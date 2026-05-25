#!/usr/bin/env bash
# PostToolUse hook: surface non-zero exit codes from tracked Bash commands.
#
# Contract (Claude Code hooks):
#   - stdin is the event JSON, including the tool result. For the Bash tool the
#     result is exposed under .tool_response with fields such as:
#       { stdout, stderr, exit_code / exitCode, interrupted, ... }
#   - exit 0 => stdout parsed as JSON if valid, else treated as context.
#   - A "systemMessage" field surfaces a warning to the user/Claude.
#
# We watch the quality-gate-relevant commands (typecheck, lint, tests, build,
# git) and, when one exits non-zero, emit a clear systemMessage so a silent
# failure cannot slip past. All JSON is built with `jq -n` — never via heredoc
# or string interpolation — so adversarial command text / stderr (quotes,
# newlines, backslashes) cannot corrupt the output.
#
# bash 3.2 compatible. Reads cwd/fields from stdin JSON, never from pwd.

set -euo pipefail

# Read the full event from stdin. Guard against early EOF under pipefail.
INPUT="$(cat 2>/dev/null || true)"

# Nothing to do without input or jq.
if [ -z "$INPUT" ] || ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

# Exit code may be reported as exit_code or exitCode depending on version.
EXIT_CODE="$(printf '%s' "$INPUT" \
  | jq -r '.tool_response.exit_code // .tool_response.exitCode // empty' \
  2>/dev/null || true)"

# No usable exit code, or it is zero => nothing to surface.
if [ -z "$EXIT_CODE" ] || [ "$EXIT_CODE" = "0" ]; then
  exit 0
fi

# Only surface for quality-gate-relevant tooling, to avoid noise on the many
# ordinary non-zero exits (grep-no-match, test probes, etc.).
TRACKED=0
case "$COMMAND" in
  *"git commit"*|*"git push"*|*tsc*|*"go vet"*|*mypy*|*pyright*) TRACKED=1 ;;
  *eslint*|*ruff*|*clippy*|*golangci-lint*|*rubocop*|*shellcheck*) TRACKED=1 ;;
  *pytest*|*vitest*|*jest*|*rspec*) TRACKED=1 ;;
  *"go test"*) TRACKED=1 ;;
  *"npm run build"*|*"pnpm build"*|*"yarn build"*|*"cargo build"*) TRACKED=1 ;;
esac

if [ "$TRACKED" -eq 0 ]; then
  exit 0
fi

# Grab a short stderr excerpt for the message (may contain quotes/newlines).
STDERR_EXCERPT="$(printf '%s' "$INPUT" \
  | jq -r '.tool_response.stderr // empty' 2>/dev/null || true)"

MSG="Quality-gate command exited non-zero (exit ${EXIT_CODE}). Do not declare the task complete until it passes."

# Build the output JSON safely with jq -n --arg. Adversarial content in
# $COMMAND / $STDERR_EXCERPT is passed as data, never interpolated.
jq -n \
  --arg msg "$MSG" \
  --arg cmd "$COMMAND" \
  --arg code "$EXIT_CODE" \
  --arg err "$STDERR_EXCERPT" \
  '{
     systemMessage: ($msg + "\nCommand: " + $cmd
       + (if ($err | length) > 0
          then "\nstderr: " + ($err[0:500])
          else "" end))
   }'

exit 0
