#!/usr/bin/env bash
# hooks/post-tool-use.sh
# Surfaces failed quality-gate exits via additionalContext injection so the next turn sees them.
# Fast-path returns {} for non-Bash tools, non-gate commands, and successful exits.
# Bash 3.2 portable.
set -euo pipefail

INPUT=$(cat || true)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ "$TOOL_NAME" = "Bash" ] || { echo '{}'; exit 0; }

EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_exit_code // 0' 2>/dev/null || echo 0)
[ "$EXIT_CODE" = "0" ] && { echo '{}'; exit 0; }

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -n "$CMD" ] || { echo '{}'; exit 0; }

# Match against the quality-gate pattern set via a single regex (avoids case-pattern
# subsumption warnings — e.g. `npm test` matches `pnpm test` substring-wise).
is_gate=0
if printf '%s' "$CMD" | grep -qE '(\btsc\b|\beslint\b|\bshellcheck\b|\b(npm|yarn|pnpm|bun)[[:space:]]+test\b|\bpytest\b|\bcargo[[:space:]]+(test|check|clippy)\b|\bgo[[:space:]]+(test|vet)\b|\bbats\b)'; then
  is_gate=1
fi

[ "$is_gate" = "1" ] || { echo '{}'; exit 0; }

# Truncate command for display (first 120 chars)
CMD_SHORT=$(printf '%s' "$CMD" | cut -c1-120)
[ "${#CMD}" -gt 120 ] && CMD_SHORT="${CMD_SHORT}..."

jq -n --arg cmd "$CMD_SHORT" --arg code "$EXIT_CODE" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: ("[godmode-post-tool-use] Last quality-gate command exited non-zero: `" + $cmd + "` -> exit " + $code + ". Address before continuing.")}}'
