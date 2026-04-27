#!/usr/bin/env bash
# skills/_shared/state.sh
# Atomic STATE.md mutator. Sourced by skills that update workflow state.
#
# Mutation discipline (D-17):
#   1. awk extracts existing audit-log body verbatim (everything after second `---`)
#   2. jq -n --arg builds the new YAML front matter (CR-02 — never heredoc)
#   3. printf composes new file: front matter + body + new audit line
#   4. mv from mktemp to STATE.md (POSIX atomic rename)
#
# Audit log is APPEND-ONLY (D-16). We never edit prior lines.

set -euo pipefail

# Source _lib.sh sibling (optional dependency — defines info/warn/error if needed).
_GODMODE_STATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
[ -f "$_GODMODE_STATE_DIR/_lib.sh" ] && . "$_GODMODE_STATE_DIR/_lib.sh"

# godmode_state_update: rewrite .planning/STATE.md atomically.
# Args:
#   $1 = active_brief (integer, e.g., 4)
#   $2 = active_brief_slug (kebab-case, e.g., "skill-layer")
#   $3 = status (free-form, e.g., "Ready to plan")
#   $4 = next_command (e.g., "/plan 4")
#   $5 = audit_line (one-line description appended to audit log)
# Exit: 0 on success, 1 on failure.
godmode_state_update() {
  local active_brief="$1"
  local active_brief_slug="$2"
  local status="$3"
  local next_cmd="$4"
  local audit_line="$5"
  local state_file=".planning/STATE.md"

  if [ ! -f "$state_file" ]; then
    echo "[x] $state_file not found — run /mission first" 1>&2
    return 1
  fi

  local now_iso today
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  today=$(date -u +%Y-%m-%d)

  # 1. Build new YAML front matter via jq (CR-02 discipline; never heredoc).
  #    jq -nr emits raw output; the literal string is built inside jq so
  #    quotes/backslashes/newlines in any --arg are escaped correctly.
  local new_fm
  new_fm=$(jq -nr \
    --argjson v 1 \
    --argjson n "$active_brief" \
    --arg slug "$active_brief_slug" \
    --arg s "$status" \
    --arg c "$next_cmd" \
    --arg la "${now_iso} — ${audit_line}" \
    '"---\ngodmode_state_version: \($v)\nactive_brief: \($n)\nactive_brief_slug: \($slug)\nstatus: \($s)\nnext_command: \($c)\nlast_activity: \"\($la)\"\n---"')

  # 2. Preserve audit-log body (everything after the second `---`).
  #    awk: count `---` markers; print only after we've seen two.
  local body
  body=$(awk '/^---$/{c++; next} c>=2 {print}' "$state_file" 2>/dev/null || echo "")

  # 3. Compose new file: front matter + blank line + body + new audit line.
  local tmp
  tmp=$(mktemp -t godmode-state.XXXXXX) || return 1
  {
    printf '%s\n' "$new_fm"
    printf '\n'
    if [ -n "$body" ]; then
      printf '%s\n' "$body"
      # Ensure trailing newline before appended audit line if body didn't end with one.
    else
      printf '# Audit Log\n\n'
    fi
    printf -- '- %s — %s\n' "$today" "$audit_line"
  } > "$tmp"

  # 4. Atomic replace (POSIX rename = atomic on same filesystem).
  mv "$tmp" "$state_file"
}
