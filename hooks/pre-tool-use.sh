#!/usr/bin/env bash
# PreToolUse hook: enforce quality-gate discipline on git commits.
#
# Contract (Claude Code hooks):
#   - stdin is the event JSON: { tool_name, tool_input: { command, ... }, cwd, ... }
#   - exit 2  => BLOCK the tool call; stderr is fed back to Claude.
#   - exit 0  => allow; stdout (if valid JSON) is parsed, else added as context.
#
# This hook DISCOURAGES the common ways to skip commit verification: it blocks
# `--no-verify` / `-n` / `--no-verify=...` and the `-c core.hooksPath=...`
# trick. It is a discipline nudge, NOT a security boundary: a determined caller
# can still skip git hooks via a git alias or other config, which a stdin
# string-scanner cannot fully enumerate. The real safety net is the secret-scan
# hook (pre-tool-use-secrets.sh), which runs as a Claude Code PreToolUse hook
# and is unaffected by git's own hook-path settings. This is the first link in
# the PreToolUse chain; additional safety checks append after it.
#
# bash 3.2 compatible. JSON read via jq only — never from pwd, never via
# string interpolation.

set -euo pipefail

# Read the full event from stdin. Guard against early EOF under pipefail.
INPUT="$(cat 2>/dev/null || true)"

# If we did not get JSON, or jq is unavailable, fail open (allow).
if [ -z "$INPUT" ] || ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

# Extract the tool name and the proposed command. // empty => absent omitted.
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

# Only inspect Bash tool calls; pass everything else through untouched.
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# Detect a --no-verify / -n bypass attempt using per-segment, commit-scoped
# detection.
#
# Strategy:
#   1. Strip quoted strings from the command so that bypass-shaped tokens
#      inside quoted messages are never mistaken for real flags (AC-4).
#      E.g. git commit -m "mention -n flag" -> the -n inside quotes is gone.
#
#   2. Split the quote-stripped command into pipeline/compound segments on
#      shell separators (&&, ||, |, ;, newline). Longest separators are
#      translated first (&&, || before |) to avoid partial matches.
#      Output is written to a temp file; the while loop reads the file so
#      variable assignments inside the loop propagate to the outer scope
#      (bash 3.2 / BSD compatible: no mapfile/readarray, no process
#      substitution).
#
#   3. For each segment, determine whether it is a `git commit` invocation:
#      - Drop leading VAR=val environment assignments.
#      - The first command word must be `git`.
#      - Scan the remaining tokens, skipping -c <value> pairs, until the
#        first token that is not a git global flag; it must be `commit`.
#      Commands like `git log | grep -n commit`, `git status`, and a bare
#      `grep -n` are not commit invocations and are never scanned (AC-5,
#      AC-6, AC-7).
#
#   4. Only within a commit segment, scan for bypass flags:
#      - Value-carrying options (-m, --message, -F, --file, -c, -C,
#        --reedit-message, --reuse-message) consume their next token.
#      - --no-verify / --no-verify=* and -n / -n=* are blocked (AC-1).
#      - Short-flag clusters containing 'n' are blocked, e.g. -nv (AC-2).
#      - hooksPath anywhere in the segment is blocked (AC-3).
#      Because each segment is classified independently, a bypass in a later
#      segment (make build && git commit --no-verify -m x) is still caught
#      (AC-8), while a non-commit segment's -n is never flagged (AC-6).
#
#   5. If no segment triggers a bypass, exit 0.

# Step 1: strip every single- and double-quoted segment from the command.
# [^"]* / [^']* are BSD-compatible (no PCRE). This removes the quoted values
# so that bypass-shaped text inside a quoted message is gone.
SCAN="$(printf '%s' "$COMMAND" | sed -e 's/"[^"]*"//g' -e "s/'[^']*'//g")"

# Step 2: split on shell separators into segments.
# Translate &&, ||, |, ;, and literal newlines to newline — LONGEST separators
# first (&&, || before |) to avoid partial matches.
# Output to a temp file so the while loop can read from a file redirect;
# this keeps variable assignments (BYPASS) in the same shell, not a subshell.
_SEGTMP="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$_SEGTMP'" EXIT INT TERM
printf '%s\n' "$SCAN" | sed \
  -e 's/&&/\
/g' \
  -e 's/||/\
/g' \
  -e 's/|/\
/g' \
  -e 's/;/\
/g' > "$_SEGTMP"

BYPASS=0
while IFS= read -r seg || [ -n "$seg" ]; do
  # Skip blank segments (arise from adjacent separators or leading/trailing).
  [ -n "$seg" ] || continue

  # Step 3: classify the segment as a git commit invocation.
  #
  # First drop leading VAR=val assignments; iterate tokens until we find the
  # first word that is not of the form NAME=value.
  first_cmd=""
  for tok in $seg; do
    case "$tok" in
      *=*) continue ;;  # env assignment, skip
      *)   first_cmd="$tok"; break ;;
    esac
  done

  # If the first real command word is not `git`, this segment is not a git
  # commit — skip it entirely (catches `grep -n commit`, `sed -n ...`, etc.).
  [ "$first_cmd" = "git" ] || continue

  # Now walk the remaining tokens to find git's subcommand.
  # Skip git global flags that take a value: -c <value> and -C <value>
  # (directory). Other single-char git global flags (-p, -v, ...) do not
  # take values and are skipped without consuming a token.
  subcommand=""
  past_git=0
  skip_git_val=0
  for tok in $seg; do
    # Skip the `git` word itself on the first encounter.
    if [ "$past_git" -eq 0 ]; then
      if [ "$tok" = "git" ]; then
        past_git=1
      fi
      continue
    fi
    # If the previous token was -c or -C (global git flag), consume value.
    if [ "$skip_git_val" -eq 1 ]; then
      skip_git_val=0
      continue
    fi
    case "$tok" in
      -c|-C)
        # Global -c key=val or -C dir; next token is the value.
        skip_git_val=1
        ;;
      -c*|-C*)
        # Attached-value form: -ccore.hooksPath=... — no next token consumed.
        ;;
      -*)
        # Other git global flags (-p, -v, --version, etc.) — skip.
        ;;
      *)
        # First non-flag token after `git` is the subcommand.
        subcommand="$tok"
        break
        ;;
    esac
  done

  # If the subcommand is not `commit`, this segment is not a commit invocation.
  [ "$subcommand" = "commit" ] || continue

  # Step 4: this segment IS a git commit invocation — scan it for bypass flags.
  #
  # The hooksPath check applies to the whole segment (AC-3): the -c token's
  # value may be consumed by the loop above, but the raw text is still in $seg.
  case "$seg" in
    *hooksPath*) BYPASS=1; break ;;
  esac

  # Scan tokens for --no-verify / -n / short-flag clusters containing n.
  # Value-carrying options consume their next token so that an unquoted value
  # that looks like a flag (e.g. -m wip_-n) is not misread as a bypass.
  SKIP_NEXT=0
  for tok in $seg; do
    if [ "$SKIP_NEXT" -eq 1 ]; then
      SKIP_NEXT=0
      continue
    fi
    case "$tok" in
      -m|--message|-F|--file|-c|-C|--reedit-message|--reuse-message)
        # Value is the next separate token — skip it.
        SKIP_NEXT=1
        ;;
      -m*|--message=*|-F*|--file=*|-c*|-C*)
        : # attached-value form; value is part of this token, nothing to skip
        ;;
      --no-verify|--no-verify=*)
        BYPASS=1; break
        ;;
      -n|-n=*)
        BYPASS=1; break
        ;;
      --*)
        : # other long option, ignore
        ;;
      -[a-zA-Z]*)
        # short-flag cluster, e.g. -nv ; an embedded 'n' is --no-verify's short.
        case "$tok" in
          *n*) BYPASS=1; break ;;
        esac
        ;;
    esac
  done

  # If a bypass was found in this segment, stop examining further segments.
  [ "$BYPASS" -eq 0 ] || break
done < "$_SEGTMP"

if [ "$BYPASS" -eq 1 ]; then
  # Exit 2 blocks the call; stderr is surfaced back to Claude.
  printf '%s\n' "BLOCKED: 'git commit' with --no-verify / -n bypasses the quality gates." >&2
  printf '%s\n' "claude-godmode requires all six quality gates to run on every commit:" >&2
  if [ -f "${CLAUDE_PLUGIN_ROOT:-.}/config/quality-gates.txt" ]; then
    while IFS= read -r gate || [ -n "$gate" ]; do
      [ -n "$gate" ] && printf '  - %s\n' "$gate" >&2
    done < "${CLAUDE_PLUGIN_ROOT:-.}/config/quality-gates.txt"
  fi
  printf '%s\n' "Re-run the commit without --no-verify, after the gates pass." >&2
  exit 2
fi

# Allowed: emit nothing, exit 0.
exit 0
