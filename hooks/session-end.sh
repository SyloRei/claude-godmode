#!/usr/bin/env bash
# SessionEnd hook: persist a last-session marker into the plugin data dir.
#
# Contract (Claude Code hooks):
#   - stdin is the event JSON: { reason, cwd, ... }. We consume it but never
#     act on pwd.
#   - This hook produces no context for Claude (the session is ending); it just
#     records a marker. It must never error: a failed mkdir/write exits 0.
#
# CLAUDE_PLUGIN_DATA (~/.claude/plugins/data/<id>/) persists across plugin
# updates, unlike CLAUDE_PLUGIN_ROOT which resets on every bump. The
# last-session marker (and last-version-seen, when discoverable) lives here so
# it outlives upgrades. In manual mode the env var is unset, so we derive the
# canonical per-installation path.
#
# bash 3.2 compatible. All JSON read via jq only.

set -euo pipefail

# Consume stdin so the producer never blocks; guard early EOF under pipefail.
INPUT="$(cat 2>/dev/null || true)"

PLUGIN_DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/claude-godmode}"

# Never error if the dir can't be created — just give up quietly.
mkdir -p "$PLUGIN_DATA_DIR" 2>/dev/null || exit 0

# Portable UTC timestamp; if date fails for any reason, fall back to empty.
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

# Pull the end reason from stdin when jq + input are available (best effort).
REASON=""
if [ -n "$INPUT" ] && command -v jq > /dev/null 2>&1; then
  REASON="$(printf '%s' "$INPUT" | jq -r '.reason // empty' 2>/dev/null || true)"
fi

# Record the last-version-seen if we can locate the canonical manifest. This is
# best-effort: a missing manifest simply leaves the field empty.
VERSION=""
if command -v jq > /dev/null 2>&1; then
  for manifest in \
    "${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json}" \
    "$HOME/.claude/plugins/data/claude-godmode/version"; do
    if [ -n "$manifest" ] && [ -f "$manifest" ]; then
      case "$manifest" in
        *plugin.json)
          VERSION="$(jq -r '.version // empty' "$manifest" 2>/dev/null || true)" ;;
        *)
          VERSION="$(cat "$manifest" 2>/dev/null || true)" ;;
      esac
      [ -n "$VERSION" ] && break
    fi
  done
fi

# Write the marker. Build JSON with jq -n when available so adversarial values
# (reason text with quotes/newlines) cannot corrupt the file.
MARKER="$PLUGIN_DATA_DIR/last-session"
if command -v jq > /dev/null 2>&1; then
  jq -n \
    --arg ts "$TS" \
    --arg reason "$REASON" \
    --arg version "$VERSION" \
    '{ last_session_at: $ts, reason: $reason, version: $version }' \
    > "$MARKER" 2>/dev/null || true
else
  # No jq — write a minimal timestamp marker.
  printf '%s\n' "$TS" > "$MARKER" 2>/dev/null || true
fi

exit 0
