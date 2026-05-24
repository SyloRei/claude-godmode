#!/usr/bin/env bash
#
# check-vocab.sh — enforce the v2 user-facing vocabulary.
#
# v2 locks the surface to its own naming (Project -> Mission -> Brief -> Plan
# -> Commit). The old v1.x "pipeline / phase / stories" vocabulary must NOT
# leak into the user-facing surface. This gate greps that surface for the
# forbidden workflow words and fails if any appear.
#
# Scope = the v2 user-facing surface: commands/ and the v2 skills. The legacy
# v1.x pipeline skills (prd, plan-stories, execute) and skills/_shared/ are
# slated for removal in a later story and are EXCLUDED here — they are not part
# of the locked v2 command surface and would otherwise mask real regressions.
#
# Forbidden:
#   - phase     (workflow word — v2 uses "mission"/"brief")
#   - pipeline  (workflow word — v2 has a single workflow, not a pipeline)
#   - stories   (workflow noun — v2 plans into briefs, not stories)
#   - task(s)   ONLY as a workflow noun. Ordinary English "task" is unavoidable,
#               so we target obvious workflow usages, not bare "task".
#
# Pure bash 3.2 + grep. No Node, no Python.
# Exit 0 when clean, exit 1 listing every hit.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

cd -- "${REPO_ROOT}"

# v2 user-facing surface to scan. Listed explicitly so legacy pipeline skills
# (skills/{prd,plan-stories,execute}, skills/_shared) are excluded by omission.
SCAN_PATHS=(
  "commands"
  "skills/brief"
  "skills/build"
  "skills/plan"
  "skills/verify"
  "skills/mission"
  "skills/debug"
  "skills/tdd"
  "skills/refactor"
  "skills/explore-repo"
  "skills/ship"
)

# Forbidden patterns (extended regex, case-insensitive).
#   - bare workflow words: phase, pipeline, stories
#   - task as a workflow noun: "task(s).json", "task list/queue/runner",
#     "the task pipeline" etc. — patterns unlikely to match ordinary prose.
FORBIDDEN=(
  '\bphase\b'
  '\bpipeline\b'
  '\bstories\b'
  '\btasks?\.json\b'
  '\btask (list|queue|runner|file|spec|id)\b'
)

# Keep only paths that exist (a missing v2 skill should not crash the gate).
existing=()
for p in "${SCAN_PATHS[@]}"; do
  [ -e "$p" ] && existing+=("$p")
done

if [ "${#existing[@]}" -eq 0 ]; then
  echo "vocab: nothing to scan." >&2
  exit 1
fi

hits=0
for pat in "${FORBIDDEN[@]}"; do
  # grep -r -n -i -E across the v2 surface; collect matches without aborting
  # the loop when a pattern has zero hits (grep exits 1 on no-match).
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$hits" -eq 0 ]; then
      echo "vocab FAILURE: forbidden v2-surface vocabulary found:" >&2
    fi
    printf '  [%s] %s\n' "$pat" "$line" >&2
    hits=$((hits + 1))
  done < <(grep -rniE "$pat" "${existing[@]}" 2>/dev/null || true)
done

if [ "$hits" -ne 0 ]; then
  echo "vocab: ${hits} forbidden usage(s) in the v2 user-facing surface." >&2
  exit 1
fi

echo "vocab: v2 user-facing surface clean (${#existing[@]} path(s) scanned)."
exit 0
