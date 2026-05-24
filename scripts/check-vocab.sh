#!/usr/bin/env bash
#
# check-vocab.sh — enforce the v2 vocabulary across everything that ships.
#
# v2 locks the surface to its own naming (Project -> Mission -> Brief -> Plan
# -> Build -> Verify -> Ship). The old v1.x "pipeline / phase / stories"
# vocabulary and the removed commands (/prd, /plan-stories, /execute) must NOT
# leak into anything the plugin installs — not just the command/skill surface,
# but the rules and agents loaded into every session and the hooks that inject
# context at runtime. (A per-wave reviewer missed v1 leaks in hooks/rules
# precisely because an earlier version of this gate only scanned commands/ +
# skills/. It now scans the full installed surface, discovered dynamically so a
# newly added skill/agent/rule is covered automatically.)
#
# Forbidden:
#   - phase / pipeline / stories   (v1 workflow vocabulary)
#   - task(s) ONLY as a workflow noun (ordinary English "task" is allowed)
#   - the removed command names /prd, /plan-stories, /execute, and the
#     stories.json / .claude-pipeline runtime artifacts (regression guard)
#
# Pure bash 3.2 + find + grep. No Node, no Python. Exit 0 clean, 1 on any hit.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
cd -- "${REPO_ROOT}"

# Build the scan set DYNAMICALLY so new files are covered without edits:
#   - commands/*.md         (slash-command files)
#   - skills/*/SKILL.md      (skills; _-prefixed internal dirs excluded)
#   - rules/godmode-*.md     (rules loaded every session)
#   - agents/*.md            (subagent contracts)
#   - hooks/*.sh             (runtime context injectors)
files=()
while IFS= read -r f; do files+=("$f"); done < <(
  {
    find commands -maxdepth 1 -name '*.md' 2>/dev/null
    find skills -mindepth 2 -maxdepth 2 -name 'SKILL.md' -not -path 'skills/_*' 2>/dev/null
    find rules -maxdepth 1 -name 'godmode-*.md' 2>/dev/null
    find agents -maxdepth 1 -name '*.md' 2>/dev/null
    find hooks -maxdepth 1 -name '*.sh' 2>/dev/null
  } | sort
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "vocab: nothing to scan." >&2
  exit 1
fi

# Forbidden patterns (extended regex, case-insensitive).
FORBIDDEN=(
  '\bphase\b'
  '\bpipeline\b'
  '\bstories\b'
  '\btasks?\.json\b'
  '\btask (list|queue|runner|file|spec|id)\b'
  '/prd\b'
  '/plan-stories\b'
  '/execute\b'
  'stories\.json'
  '\.claude-pipeline'
)

hits=0
for pat in "${FORBIDDEN[@]}"; do
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$hits" -eq 0 ]; then
      echo "vocab FAILURE: forbidden v1/removed vocabulary found:" >&2
    fi
    printf '  [%s] %s\n' "$pat" "$line" >&2
    hits=$((hits + 1))
  done < <(grep -rniE "$pat" "${files[@]}" 2>/dev/null || true)
done

if [ "$hits" -ne 0 ]; then
  echo "vocab: ${hits} forbidden usage(s) in the installed surface." >&2
  exit 1
fi

echo "vocab: installed surface clean (${#files[@]} file(s) scanned)."
exit 0
