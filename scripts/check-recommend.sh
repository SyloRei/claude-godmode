#!/usr/bin/env bash
#
# check-recommend.sh — enforce the recommendation-backed-question convention
# on the planning-spine skills.
#
# The convention (AC-4): every planning-spine skill must carry the literal
# marker token `godmode:recommend-convention`, signalling that the skill follows
# the convention of pairing each question it asks the user with a concrete
# recommendation. The marker is a machine-checkable anchor so this gate can
# verify the convention is present without parsing prose.
#
# Spine skills are hardcoded: mission brief plan ideate refine. Not every spine
# skill is built yet (ideate/refine arrive later), so an ABSENT SKILL.md is
# SKIPPED, not failed (AC-7) — this lets the gate pass before those skills land.
# A PRESENT spine skill that lacks the marker is a failure naming the file
# (AC-6). When all present spine skills carry the marker, the gate exits 0 and
# reports each spine skill it checked (AC-5).
#
# Pure bash 3.2 + grep. No Node, no Python. Exit 0 clean, 1 on any violation.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
cd -- "${REPO_ROOT}"

# The planning-spine skill set (hardcoded by design).
SPINE=(mission brief plan ideate refine)

# The literal marker token each present spine skill must contain.
MARKER='godmode:recommend-convention'

failures=0
checked=0

for name in "${SPINE[@]}"; do
  f="skills/${name}/SKILL.md"

  if [ ! -f "$f" ]; then
    echo "recommend: - ${name} (not built yet, skipped)"
    continue
  fi

  checked=$((checked + 1))

  if grep -F "$MARKER" "$f" >/dev/null 2>&1; then
    echo "recommend: ✓ ${name}"
  else
    if [ "$failures" -eq 0 ]; then
      echo "recommend FAILURE: spine skill(s) missing the marker '${MARKER}':" >&2
    fi
    printf '  [missing marker] %s\n' "$f" >&2
    failures=$((failures + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "recommend: ${failures} spine skill(s) missing the convention marker." >&2
  exit 1
fi

echo "recommend: convention marker present on all ${checked} built spine skill(s)."
exit 0
