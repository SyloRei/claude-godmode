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
# noglob: the unquoted `for tok in $seg` loops rely on word-splitting only.
# Without -f, a trailing `*` (e.g. `git commit -m wip *`) would pathname-expand,
# and a file literally named `-n` in the cwd would surface as a bogus bypass
# token. -f disables globbing but NOT word-splitting; `case` patterns are
# unaffected — the hook only ever pattern-matches, it never relies on a glob.
set -f

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
#      Then normalize stray control whitespace (carriage return \r, vertical
#      tab \v, form feed \f) to spaces so a CR adjacent to git/commit cannot
#      defeat the `subcommand = commit` equality check (e.g. `git \rcommit
#      --no-verify` must still classify as a commit and block). Newline \n is
#      left intact — it is a meaningful segment separator handled in Step 2.
#
#   2. Split the quote-stripped command into pipeline/compound segments on
#      shell separators (&&, ||, |, ;, &, newline). Longest/compound separators
#      are translated first (&& before a lone & ; || before |) so the compound
#      operator is consumed before its single-char form is matched. The lone &
#      is the background operator, so `x & git commit --no-verify` splits into
#      `x` and a real commit segment that is then scanned (AC-8).
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
#      - An UNQUOTED hooksPath surviving the quote strip is blocked (AC-3).
#      Because each segment is classified independently, a bypass in a later
#      segment (make build && git commit --no-verify -m x) is still caught
#      (AC-8), while a non-commit segment's -n is never flagged (AC-6).
#
#   4b. The QUOTED hooksPath bypass (git -c 'core.hooksPath=/dev/null' commit)
#      cannot be seen in Step 4: the global quote strip removes the quoted -c
#      value before segments are scanned. So a separate RAW-text pre-check
#      (below, before the segment loop) flags a -c/-C global whose hooksPath
#      value sits BEFORE the commit subcommand. It is scoped to the pre-
#      subcommand global-flag region so a commit MESSAGE that merely mentions
#      the word hooksPath (git commit -m "fix hooksPath bug") stays allowed —
#      there `commit` precedes the word, so it is outside the checked region.
#
#   5. If no segment triggers a bypass, exit 0.

# Step 1: strip every single- and double-quoted segment from the command,
# then normalize stray control whitespace to spaces. [^"]* / [^']* are
# BSD-compatible (no PCRE); the quote strip removes bypass-shaped text inside a
# quoted message. The `tr` maps carriage return (\r = \015), vertical tab
# (\v = \013) and form feed (\f = \014) to spaces so a control char adjacent to
# `git`/`commit` (e.g. `git \rcommit --no-verify`) cannot split the subcommand
# token and dodge the equality check. Newline (\n) is deliberately NOT mapped —
# it is a real segment separator (Step 2). This only ever errs toward blocking:
# a segment must still be a genuine `git commit` invocation to be scanned, so
# normalization cannot create a false positive on a non-commit command.
SCAN="$(printf '%s' "$COMMAND" \
  | sed -e 's/"[^"]*"//g' -e "s/'[^']*'//g" \
  | tr '\015\013\014' '   ')"

# Step 2: split on shell separators into segments.
# Translate &&, ||, |, ;, &, and literal newlines to newline — LONGEST/compound
# separators first (&& before a lone &; || before |) so the compound operator is
# consumed before its single-char form matches and only a genuine background &
# remains.
# Output to a temp file so the while loop can read from a file redirect;
# this keeps variable assignments (BYPASS) in the same shell, not a subshell.
_SEGTMP="$(mktemp)"
# Double-quoted so the captured path is expanded at trap-definition time (the
# value of $_SEGTMP we just created), not re-evaluated at trap-firing time.
# shellcheck disable=SC2064
trap "rm -f '$_SEGTMP'" EXIT INT TERM
printf '%s\n' "$SCAN" | sed \
  -e 's/&&/\
/g' \
  -e 's/&/\
/g' \
  -e 's/||/\
/g' \
  -e 's/|/\
/g' \
  -e 's/;/\
/g' > "$_SEGTMP"

BYPASS=0

# Step 4b (RAW pre-check): catch the QUOTED `-c core.hooksPath=...` bypass that
# the quote strip would otherwise erase. Scope the check to the global-flag
# region BEFORE the first `commit` subcommand word: a -c/-C flag whose value
# carries hooksPath there disables git hooks. A commit MESSAGE that mentions the
# word hooksPath appears AFTER `commit`, so it is outside this region and stays
# allowed. Operate on the RAW $COMMAND (not the quote-stripped SCAN) so quoted
# values are visible. ${COMMAND%% commit*} keeps only the text up to the first
# ` commit` token (the whole string if absent — a non-commit command, harmless).
GLOBAL_REGION="${COMMAND%% commit*}"
case "$GLOBAL_REGION" in
  *-c*hooksPath*|*-C*hooksPath*) BYPASS=1 ;;
esac

while IFS= read -r seg || [ -n "$seg" ]; do
  # If the RAW pre-check (Step 4b) already found a bypass, stop scanning.
  [ "$BYPASS" -eq 0 ] || break
  # Skip blank segments (arise from adjacent separators or leading/trailing).
  [ -n "$seg" ] || continue

  # Step 3: classify the segment as a git commit invocation.
  #
  # First drop leading VAR=val assignments; iterate tokens until we find the
  # first word that is not of the form NAME=value.
  FIRST_CMD=""
  for tok in $seg; do
    case "$tok" in
      *=*) continue ;;  # env assignment, skip
      *)   FIRST_CMD="$tok"; break ;;
    esac
  done

  # If the first real command word is not `git`, this segment is not a git
  # commit — skip it entirely (catches `grep -n commit`, `sed -n ...`, etc.).
  [ "$FIRST_CMD" = "git" ] || continue

  # Now walk the remaining tokens to find git's subcommand.
  # Skip git global flags that take a value as a SEPARATE token, so their
  # value is not misread as the subcommand:
  #   -c <key=val>, -C <dir>, and the long globals --git-dir, --work-tree,
  #   --namespace, --super-prefix (each always consumes one following token).
  # Without this, `git --git-dir /tmp commit --no-verify` would read `/tmp` as
  # the subcommand, misclassify the segment as non-commit, and skip the bypass
  # scan. NOTE: bare `--exec-path` is deliberately NOT listed — `git --exec-path`
  # (no value) just prints the path, so consuming the next token would wrongly
  # swallow a following `commit`. Its attached `--exec-path=...` form (and every
  # other attached `--flag=val` global) already falls through the `-*` arm below
  # without consuming a token. Other single-char/value-less globals (-p, -v, ...)
  # are likewise skipped without consuming a token.
  SUBCOMMAND=""
  PAST_GIT=0
  SKIP_GIT_VAL=0
  for tok in $seg; do
    # Skip the `git` word itself on the first encounter.
    if [ "$PAST_GIT" -eq 0 ]; then
      if [ "$tok" = "git" ]; then
        PAST_GIT=1
      fi
      continue
    fi
    # If the previous token was a separate-value global flag, consume value.
    if [ "$SKIP_GIT_VAL" -eq 1 ]; then
      SKIP_GIT_VAL=0
      continue
    fi
    case "$tok" in
      -c|-C|--git-dir|--work-tree|--namespace|--super-prefix)
        # Separate-value global (e.g. -c key=val, --git-dir DIR); next token
        # is the value — consume it so it is not read as the subcommand.
        SKIP_GIT_VAL=1
        ;;
      -c*|-C*)
        # Attached-value form: -ccore.hooksPath=... — no next token consumed.
        ;;
      -*)
        # Other git global flags (-p, -v, --version, --git-dir=..., etc.) —
        # skip. Attached `--flag=val` globals carry their value inline, so no
        # token is consumed here.
        ;;
      *)
        # First non-flag token after `git` is the subcommand.
        SUBCOMMAND="$tok"
        break
        ;;
    esac
  done

  # If the subcommand is not `commit`, this segment is not a commit invocation.
  [ "$SUBCOMMAND" = "commit" ] || continue

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
