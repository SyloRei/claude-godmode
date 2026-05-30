#!/usr/bin/env bash
# Stop hook: block the agent from stopping while a unit's verify found gaps.
#
# Contract (Claude Code Stop hook):
#   - stdin is the event JSON. Fields used here:
#       { cwd, stop_hook_active }
#   - To allow stop: exit 0 with no decision output.
#   - To block stop: emit {"decision":"block","reason":<text>} on stdout.
#
# This gate reads .planning/STATE.md (relative to the event's cwd, never pwd)
# and blocks only when status is exactly "verify found gaps", nudging the user
# toward the recorded next_command (or /verify <active_unit> as a fallback).
#
# Fail-open everywhere: any missing input, tool, dir, or file => exit 0 so the
# agent is never wedged by this hook. All output JSON is built with `jq -n`
# --arg so STATE.md content (quotes, newlines, backslashes) cannot corrupt it.
#
# bash 3.2 compatible: no bash-4 constructs (case-fold expansion, name-ref
# tests, bulk-read builtins, associative arrays) and no GNU-only flags. Reads
# cwd from stdin JSON, never pwd.

set -euo pipefail

# Consume all stdin so the producer never blocks. Guard EOF under pipefail.
INPUT="$(cat 2>/dev/null || true)"

# Nothing to do without input or jq.
if [ -z "$INPUT" ] || ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

# Loop safety (AC-6): never block when we are already inside a stop-hook pass.
STOP_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || true)"
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

# Override (AC-5): GODMODE_AC_GATE=off|0|false|no disables the gate. Trim and
# lowercase via tr (not bash-4 case-folding) so this stays bash 3.2 / BSD safe.
OVERRIDE="${GODMODE_AC_GATE:-}"
OVERRIDE="$(printf '%s' "$OVERRIDE" \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
  | tr '[:upper:]' '[:lower:]')"
case "$OVERRIDE" in
  off|0|false|no) exit 0 ;;
esac

# Read cwd from the event JSON (never from process pwd). Fail-open if absent.
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
if [ -z "$CWD" ]; then
  exit 0
fi

# Canonicalize BSD-safe (no realpath/readlink -f). Fail-open if cwd is gone.
CANON_CWD="$( cd "$CWD" 2>/dev/null && pwd -P )" || exit 0
if [ -z "$CANON_CWD" ]; then
  exit 0
fi

# Guards (AC-7): require an existing .planning/STATE.md. Never create it.
if [ ! -d "$CANON_CWD/.planning" ]; then
  exit 0
fi
STATE="$CANON_CWD/.planning/STATE.md"
if [ ! -f "$STATE" ]; then
  exit 0
fi

# Parse a "key: value" line from STATE.md, trimming surrounding whitespace.
# Mirrors bin/godmode-state cmd_get so the two never drift.
state_get() {
  key="$1"
  line="$(grep "^${key}:" "$STATE" | head -1 || true)"
  if [ -z "$line" ]; then
    return 0
  fi
  printf '%s\n' "${line#"${key}":}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

STATUS="$(state_get status)"
if [ -z "$STATUS" ]; then
  exit 0
fi

# Trigger (AC-4): only the literal "verify found gaps" status blocks. Anything
# else exits silently with no output.
if [ "$STATUS" != "verify found gaps" ]; then
  exit 0
fi

ACTIVE_UNIT="$(state_get active_unit)"
NEXT_COMMAND="$(state_get next_command)"

# Block (AC-3, AC-8): name the unit and echo the recorded next_command; fall
# back to /verify <active_unit> when next_command is empty.
if [ -n "$NEXT_COMMAND" ]; then
  REASON="Verify found gaps in unit ${ACTIVE_UNIT}. Run: ${NEXT_COMMAND}"
elif [ -n "$ACTIVE_UNIT" ]; then
  REASON="Verify found gaps in unit ${ACTIVE_UNIT}. Run: /verify ${ACTIVE_UNIT}"
else
  REASON="Verify found gaps. Run /verify before stopping."
fi

jq -n --arg reason "$REASON" '{decision:"block", reason:$reason}'

exit 0
