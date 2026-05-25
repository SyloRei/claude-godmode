#!/usr/bin/env bash
# UserPromptSubmit hook: inject a one-line workflow-orientation reminder.
#
# Contract (Claude Code hooks):
#   - stdin is the event JSON: { prompt, cwd, ... }. We consume it but read
#     project state from .planning/STATE.md via bin/godmode-state, never pwd.
#   - exit 0 => stdout parsed as JSON if valid, else added as plain context.
#
# If there is no .planning/STATE.md, or godmode-state / jq are unavailable, the
# hook emits nothing and exits 0 (silent). Output is kept to one short line so
# it stays well under the 10,000-char additionalContext cap. All JSON is built
# with `jq -n` — never via heredoc or string interpolation — so a value
# containing quotes/newlines/backslashes cannot corrupt the output.
#
# bash 3.2 compatible.

set -euo pipefail

# Read the event from stdin (don't discard it — we need .cwd). Guard early EOF.
INPUT="$(cat 2>/dev/null || true)"

# jq is required to read .cwd and emit safe JSON; without it, fail silent.
command -v jq > /dev/null 2>&1 || exit 0

# Resolve the project root from the event's .cwd (NEVER pwd — the session may
# be rooted in a subdirectory). Fall back to pwd only if cwd is absent.
CWD=""
[ -n "$INPUT" ] && CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$CWD" ] || CWD="$(pwd)"

STATE_FILE="$CWD/.planning/STATE.md"

# Nothing to orient toward without project state.
[ -f "$STATE_FILE" ] || exit 0

# Run state reads from the project root so godmode-state's relative .planning
# path resolves correctly.
cd "$CWD" 2>/dev/null || exit 0

# Locate the godmode-state helper. In plugin mode CLAUDE_PLUGIN_ROOT points at
# the installed plugin dir; in manual mode it lives under ~/.claude/bin; fall
# back to a repo-relative path for in-tree use.
STATE_BIN=""
for cand in \
  "${CLAUDE_PLUGIN_ROOT:-}/bin/godmode-state" \
  "$HOME/.claude/bin/godmode-state" \
  "bin/godmode-state"; do
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    STATE_BIN="$cand"
    break
  fi
done

[ -n "$STATE_BIN" ] || exit 0

# Read the next-command pointer and active unit. Never let a helper failure
# abort this hook.
NEXT_CMD="$(bash "$STATE_BIN" get next_command 2>/dev/null || true)"
ACTIVE_UNIT="$(bash "$STATE_BIN" get active_unit 2>/dev/null || true)"

# Nothing useful to surface.
if [ -z "$NEXT_CMD" ] && [ -z "$ACTIVE_UNIT" ]; then
  exit 0
fi

# Build a single-line reminder.
REMINDER="godmode"
[ -n "$ACTIVE_UNIT" ] && REMINDER="${REMINDER} | active: ${ACTIVE_UNIT}"
[ -n "$NEXT_CMD" ] && REMINDER="${REMINDER} | next: ${NEXT_CMD}"

jq -n \
  --arg ctx "$REMINDER" \
  '{
     hookSpecificOutput: {
       hookEventName: "UserPromptSubmit",
       additionalContext: $ctx
     }
   }'

exit 0
