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

# Extract the tool name and the proposed command in a SINGLE jq call. jq emits
# the tool name on the first line and the command (which may legitimately span
# multiple lines, contain backslashes, or carry control bytes) as everything
# after the first newline — `@tsv`/`@csv` would escape those control bytes and
# defeat the carriage-return and line-continuation handling below, so a raw
# newline-joined format string is used instead. // empty keeps absent fields as
# empty strings; a jq failure (garbage stdin) leaves both empty, so the guards
# below fall through to a fail-open exit 0. jq always emits exactly one newline
# between the two fields, so the first line is the tool name and the remainder
# is the command.
_RAW_FIELDS="$(printf '%s' "$INPUT" \
  | jq -r '"\(.tool_name // empty)\n\(.tool_input.command // empty)"' 2>/dev/null || true)"
TOOL_NAME="${_RAW_FIELDS%%$'\n'*}"
COMMAND="${_RAW_FIELDS#*$'\n'}"

# Only inspect Bash tool calls; pass everything else through untouched.
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# Fast pre-filter: a real `git commit` invocation always contains BOTH the
# substrings `git` and `commit` somewhere in the command (even the grouping,
# redirect, and line-continuation forms handled below keep both). A command
# missing either cannot be a commit, so short-circuit it here and spare the
# common non-commit path the sed/tr/mktemp/segment-split work below. This is a
# pure performance gate: it introduces NO false negative (every blockable form
# still contains both substrings) and NO false positive (it only lets commands
# THROUGH; the real classification happens per segment afterward).
case "$COMMAND" in
  *git*commit*) : ;;
  *) exit 0 ;;
esac

# Detect a --no-verify / -n bypass attempt using per-segment, commit-scoped
# detection.
#
# Strategy (each numbered step is implemented in order below):
#   1. Fold backslash-newline line continuations, then strip quoted strings and
#      normalize stray control whitespace.
#   2. Split the command into pipeline/compound segments on shell separators.
#   3. For each quote-stripped segment, classify whether it is a `git commit`
#      invocation (drop leading env assignments / grouping / redirect tokens;
#      first command word must be `git`; first non-global token must be
#      `commit`).
#   4. Only within a commit segment, scan for bypass flags (--no-verify / -n /
#      short clusters containing n / an attached -c…hooksPath that survived the
#      quote strip).
#   5. The QUOTED -c hooksPath bypass (git -c 'core.hooksPath=…' commit) cannot
#      be seen in step 4 — the quote strip erases the value. So a separate RAW
#      pass splits the unmodified command on the same separators and, for each
#      raw segment that is itself a git-commit invocation, checks its
#      pre-subcommand global-flag region for a -c/-C carrying hooksPath
#      (case-insensitive). Scoping to genuine commit segments keeps non-commit
#      commands (git -c core.hooksPath=x log/status/fetch, and a
#      `git -c … diff | grep commit` pipeline) allowed, and scoping to the
#      global region keeps a commit MESSAGE that merely mentions the word
#      hooksPath allowed.
#   6. If no segment triggers a bypass, exit 0.

# Step 1a: fold backslash-newline continuations. `git \<newline>commit …` is ONE
# command to bash, but the bare newline would otherwise be read as a segment
# separator in Step 2. A backslash immediately followed by a newline is the
# continuation; collapse the pair to a single space so the command rejoins. A
# bare newline (no preceding backslash) is left intact — it stays a real
# separator. awk joins a line ending in an odd-positioned trailing backslash to
# the next (BSD/macOS awk safe: no GNU extensions).
JOINED="$(printf '%s' "$COMMAND" | awk '
  { line = $0
    # Strip a single trailing backslash that continues onto the next line.
    if (substr(line, length(line), 1) == "\\") {
      printf "%s ", substr(line, 1, length(line) - 1)
    } else {
      printf "%s\n", line
    }
  }')"

# Step 1b: strip every single- and double-quoted segment, then normalize stray
# control whitespace to spaces. [^"]* / [^']* are BSD-compatible (no PCRE); the
# quote strip removes bypass-shaped text inside a quoted message (AC-4). The
# `tr` maps carriage return (\015), vertical tab (\013) and form feed (\014) to
# spaces so a control char adjacent to `git`/`commit` cannot split the
# subcommand token and dodge the equality check. Newline (\n) is deliberately
# NOT mapped — it is a real segment separator (Step 2). Normalization only ever
# errs toward blocking: a segment must still classify as a genuine `git commit`
# invocation to be scanned, so it cannot create a false positive.
SCAN="$(printf '%s' "$JOINED" \
  | sed -e 's/"[^"]*"//g' -e "s/'[^']*'//g" \
  | tr '\015\013\014' '   ')"

# Step 2: split on shell separators into segments.
# Translate &&, ||, |, ;, &, and literal newlines to newline — LONGEST/compound
# separators first (&& before a lone &; || before |) so the compound operator is
# consumed before its single-char form matches and only a genuine background &
# remains. Two temp files: the quote-stripped SCAN segments (classification +
# -n scan, Steps 3-4) and the RAW segments split on the SAME separators (the
# quoted-hooksPath pass, Step 5). Writing to files lets the while loops read via
# a redirect so variable assignments (BYPASS) stay in this shell, not a subshell
# (bash 3.2 / BSD: no mapfile/readarray, no process substitution).
_SEGTMP="$(mktemp)"
_RAWTMP="$(mktemp)"
# Double-quoted so the captured paths are expanded at trap-definition time (the
# values we just created), not re-evaluated at trap-firing time.
# shellcheck disable=SC2064
trap "rm -f '$_SEGTMP' '$_RAWTMP'" EXIT INT TERM

# Shared separator-splitting sed program.
_split_segments() {
  sed \
    -e 's/&&/\
/g' \
    -e 's/&/\
/g' \
    -e 's/||/\
/g' \
    -e 's/|/\
/g' \
    -e 's/;/\
/g'
}

printf '%s\n' "$SCAN" | _split_segments > "$_SEGTMP"
# RAW segments come from the line-continuation-folded command so the same
# `git \<newline>commit` form rejoins here too; quotes are intact so the
# hooksPath value is visible.
printf '%s\n' "$JOINED" | _split_segments > "$_RAWTMP"

BYPASS=0

# strip_leading_noise: given a segment, drop leading tokens that are not the
# command word — environment assignments (VAR=val), shell-grouping / subshell
# openers ( { $( ` and redirection tokens (>f, >>f, <f, 2>f, &>f, …) — and echo
# the first real command word. Used by both passes so `( git commit … )`,
# `$(git commit …)`, `` `git commit …` ``, and `>f git commit …` are still
# recognized as git invocations.
first_command_word() {
  _fcw_out=""
  for _fcw_tok in $1; do
    # Strip any leading run of shell-grouping / subshell-opener characters
    # ( { $ ` ) glued to the front of the token, e.g. `$(git` -> `git`,
    # `(git` -> `git`. The bracket set is a literal character class — no
    # expansion happens inside it — so a glued opener is removed regardless of
    # how the openers stack.
    while :; do
      case "$_fcw_tok" in
        ['({$`']*) _fcw_tok="${_fcw_tok#?}" ;;
        *) break ;;
      esac
    done
    case "$_fcw_tok" in
      # Empty after stripping (a bare opener like `(` or `$(`), or an
      # environment assignment (FOO=bar) — skip to the next token.
      "" | *=*) continue ;;
      # Redirection token, e.g. >f, >>f, <f, 2>f, &>f — skip; the value is part
      # of the same token (>file) so nothing else needs consuming.
      [\>\<]* | [0-9][\>\<]* | "&"[\>\<]*) continue ;;
      *) _fcw_out="$_fcw_tok"; break ;;
    esac
  done
  printf '%s' "$_fcw_out"
}

# ---------------------------------------------------------------------------
# Pass A (Steps 3-4): classify each quote-stripped segment and, inside a commit
# segment, scan for --no-verify / -n / short-cluster / attached-hooksPath.
# ---------------------------------------------------------------------------
while IFS= read -r seg || [ -n "$seg" ]; do
  [ "$BYPASS" -eq 0 ] || break
  # Skip blank segments (arise from adjacent separators or leading/trailing).
  [ -n "$seg" ] || continue

  # Step 3: the first real command word must be `git`.
  FIRST_CMD="$(first_command_word "$seg")"
  [ "$FIRST_CMD" = "git" ] || continue

  # Walk the remaining tokens to find git's subcommand. Skip git global flags
  # that take a value as a SEPARATE token (-c <key=val>, -C <dir>, and the long
  # globals --git-dir, --work-tree, --namespace, --super-prefix) so the value is
  # not misread as the subcommand. Without this,
  # `git --git-dir /tmp commit --no-verify` would read `/tmp` as the subcommand,
  # misclassify the segment, and skip the bypass scan. Bare `--exec-path` is
  # deliberately NOT listed — `git --exec-path` (no value) just prints the path,
  # so consuming the next token would wrongly swallow a following `commit`. Its
  # attached `--exec-path=...` form (and every other attached `--flag=val`
  # global) already falls through the `-*` arm below without consuming a token.
  SUBCOMMAND=""
  PAST_GIT=0
  SKIP_GIT_VAL=0
  for tok in $seg; do
    if [ "$PAST_GIT" -eq 0 ]; then
      # Skip everything up to and including the `git` word (grouping/redirect
      # noise was already accounted for by first_command_word).
      case "$tok" in
        *git) PAST_GIT=1 ;;
      esac
      continue
    fi
    if [ "$SKIP_GIT_VAL" -eq 1 ]; then
      SKIP_GIT_VAL=0
      continue
    fi
    case "$tok" in
      -c|-C|--git-dir|--work-tree|--namespace|--super-prefix)
        SKIP_GIT_VAL=1
        ;;
      -c*|-C*)
        : # attached-value form (-ccore.hooksPath=…); no next token consumed
        ;;
      -*)
        : # other git global flag (-p, -v, --version, --git-dir=…) — skip
        ;;
      *)
        SUBCOMMAND="$tok"
        break
        ;;
    esac
  done

  # If the subcommand is not `commit`, this segment is not a commit invocation.
  [ "$SUBCOMMAND" = "commit" ] || continue

  # Step 4: this segment IS a git commit invocation — scan it for bypass flags.
  SKIP_NEXT=0
  for tok in $seg; do
    if [ "$SKIP_NEXT" -eq 1 ]; then
      SKIP_NEXT=0
      continue
    fi
    case "$tok" in
      -m|--message|-F|--file|-c|-C|--reedit-message|--reuse-message)
        # Value is the next separate token — skip it so an unquoted value that
        # looks like a flag (e.g. -m wip_-n) is not misread as a bypass.
        SKIP_NEXT=1
        ;;
      -c*|-C*)
        # Attached-value global (-ccore.hooksPath=… or -c'…' after quote strip).
        # Only a -c/-C carrying hooksPath disables git hooks; scope the check to
        # this token (case-insensitive — git config keys are case-insensitive)
        # so a plain message word never trips it.
        case "$tok" in
          *[hH][oO][oO][kK][sS][pP][aA][tT][hH]*) BYPASS=1; break ;;
        esac
        ;;
      -m*|--message=*|-F*|--file=*)
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
done < "$_SEGTMP"

# ---------------------------------------------------------------------------
# Pass B (Step 5): the QUOTED -c hooksPath bypass. The quote strip in Step 1b
# erased the quoted value, so Pass A cannot see it. Walk the RAW segments (split
# on the SAME separators) and, for each raw segment that is itself a git-commit
# invocation, inspect ONLY its pre-subcommand global-flag region for a -c/-C
# global carrying hooksPath (case-insensitive). Scoping to a genuine commit
# segment keeps non-commit forms allowed (git -c core.hooksPath=x log/status/
# fetch and a `git -c … diff | grep commit` pipeline); scoping to the global
# region keeps a commit message mentioning hooksPath allowed (the word comes
# AFTER `commit`).
# ---------------------------------------------------------------------------
while IFS= read -r rawseg || [ -n "$rawseg" ]; do
  [ "$BYPASS" -eq 0 ] || break
  [ -n "$rawseg" ] || continue

  RAW_FIRST="$(first_command_word "$rawseg")"
  [ "$RAW_FIRST" = "git" ] || continue

  # Collect the global-flag region (tokens after `git`, up to and excluding the
  # first non-global token = the subcommand). A -c/-C global there (separate- or
  # attached-value) whose value carries hooksPath is the bypass. Track whether
  # the immediately preceding global was a separate-value -c/-C so its value
  # token is checked too.
  RAW_PAST_GIT=0
  RAW_SUB=""
  RAW_C_PENDING=0
  RAW_REGION=""
  for tok in $rawseg; do
    if [ "$RAW_PAST_GIT" -eq 0 ]; then
      case "$tok" in
        *git) RAW_PAST_GIT=1 ;;
      esac
      continue
    fi
    if [ "$RAW_C_PENDING" -eq 1 ]; then
      # This token is the separate value of a preceding -c/-C global.
      RAW_C_PENDING=0
      RAW_REGION="$RAW_REGION $tok"
      continue
    fi
    case "$tok" in
      -c|-C)
        RAW_C_PENDING=1
        RAW_REGION="$RAW_REGION $tok"
        ;;
      -c*|-C*)
        RAW_REGION="$RAW_REGION $tok"
        ;;
      --git-dir|--work-tree|--namespace|--super-prefix)
        # Separate-value global, not -c/-C; consume its value so it is not read
        # as the subcommand. Reuse RAW_C_PENDING as a generic "skip next value"
        # flag (the value can never carry a -c hooksPath, so adding it to the
        # region is harmless to the match below).
        RAW_C_PENDING=1
        RAW_REGION="$RAW_REGION $tok"
        ;;
      -*)
        RAW_REGION="$RAW_REGION $tok"
        ;;
      *)
        RAW_SUB="$tok"
        break
        ;;
    esac
  done

  # Only a genuine `git commit` segment is in scope.
  [ "$RAW_SUB" = "commit" ] || continue

  # A -c/-C global in the region carrying hooksPath (case-insensitive) is the
  # bypass. The region only ever contains global flags and their values, so a
  # commit message word can never reach here.
  case "$RAW_REGION" in
    *-c*[hH][oO][oO][kK][sS][pP][aA][tT][hH]*|*-C*[hH][oO][oO][kK][sS][pP][aA][tT][hH]*)
      BYPASS=1
      ;;
  esac
done < "$_RAWTMP"

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

# Allowed: emit an empty JSON object (matching pre-tool-use-secrets.sh) and pass.
jq -n '{}' 2>/dev/null || printf '{}\n'
exit 0
