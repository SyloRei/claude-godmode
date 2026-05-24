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

# Only concerned with git commit commands. Match both the plain `git commit`
# and the `git -c <opt> commit` form (so the -c core.hooksPath bypass below is
# actually reached). The `git ` + `commit` pattern won't false-BLOCK unrelated
# commands like `git add x_commit.txt` — those simply carry no bypass token, so
# the detection loop leaves BYPASS=0 and we exit 0 anyway.
case "$COMMAND" in
  *"git "*"commit"*) ;;
  *) exit 0 ;;
esac

# Detect a --no-verify / -n bypass attempt.
#
# Strategy: a real bypass flag is always an UNQUOTED bare argument; the same
# text inside a commit message is always QUOTED. So we first strip every
# single- and double-quoted segment from the command, then scan the remaining
# whitespace-split tokens. This makes "git commit --message=\"add -n flag\""
# safe (the quoted value, including the -n, is removed) while still catching a
# genuine "git commit -m wip --no-verify".
#
# Stripping uses sed with non-greedy-equivalent character classes (BSD/macOS
# compatible: no PCRE). [^"]* / [^']* stop at the closing quote.
SCAN="$(printf '%s' "$COMMAND" | sed -e 's/"[^"]*"//g' -e "s/'[^']*'//g")"

# After stripping quotes, value-carrying options that take their value as a
# SEPARATE *unquoted* token still consume one following token (e.g. "-m wip").
# Skip that one token so an unquoted value like "-n" used as a message word is
# not misread as a flag.
BYPASS=0
SKIP_NEXT=0
for tok in $SCAN; do
  if [ "$SKIP_NEXT" -eq 1 ]; then
    SKIP_NEXT=0
    continue
  fi
  case "$tok" in
    -m|--message|-F|--file|-c|-C|--reedit-message|--reuse-message)
      # Value is the next token — skip it.
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

# Also catch `-c core.hooksPath=...`, which disables git hooks without ever
# typing --no-verify. The `-c` token's value may be skipped by the loop above,
# so scan the quote-stripped command as a whole.
case "$SCAN" in
  *hooksPath*) BYPASS=1 ;;
esac

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
