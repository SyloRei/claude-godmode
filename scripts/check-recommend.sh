#!/usr/bin/env bash
#
# check-recommend.sh — enforce the recommendation-backed-question convention
# across every question-asking surface.
#
# The convention: every surface that asks the user a consequential question must
# carry the literal marker token `godmode:recommend-convention`, signalling that
# it follows the convention of pairing each question with a concrete
# recommendation (the canonical rule lives in rules/godmode-recommend.md). The
# marker is a machine-checkable anchor so this gate can verify the convention is
# present without parsing prose.
#
# Scope is no longer spine-only. Two explicit, hand-maintained lists mirror the
# ledger in rules/godmode-recommend.md:
#
#   RECOMMEND_SURFACES — the 14 in-scope surfaces that MUST carry the marker.
#     Each entry is a full relative path encoding its own shape (13 skills as
#     skills/<name>/SKILL.md + commands/adr.md), so the marker check loop greps
#     the path verbatim and never branches on skill-vs-command shape (AC-7).
#   NA_SURFACES — the 4 surfaces that ask no consequential question: recorded
#     here so the partition check below knows they are deliberately unmarked.
#
# Per in-scope surface (semantics unchanged from the spine-only gate):
#   - present + carries the exact marker   -> ok (AC-9)
#   - absent                                -> skipped, not failed (AC-7)
#   - present but missing the marker        -> exit 1, names the file (AC-9)
#   - a suffix-extended superset such as ...-convention-v2 does NOT satisfy it.
#
# Partition completeness (AC-8): every skills/*/SKILL.md and commands/*.md that
# actually exists in the repo must be classified in EXACTLY one of the two
# lists, and the gate enforces both halves of that contract:
#   - a surface in NEITHER list fails (unclassified), so a newly added
#     question-asking surface cannot silently escape the convention; and
#   - a surface in BOTH lists fails (ambiguous), so a path cannot be in-scope and
#     N/A at once — it must be classified in exactly one of RECOMMEND_SURFACES or
#     NA_SURFACES.
#
# This gate asserts marker *presence* only. Whether a question *truly* leads
# with a recommendation — that the prose actually renders the principle — is a
# `/verify` judgment-lens concern; the gate greps a token and cannot judge prose.
#
# Pure bash 3.2 + grep. No Node, no Python, no associative arrays. Exit 0 clean,
# 1 on any violation.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
cd -- "${REPO_ROOT}"

# In-scope surfaces (14) — must carry the marker. Full relative paths so the
# marker loop never branches on skill-vs-command shape.
RECOMMEND_SURFACES=(
  skills/mission/SKILL.md skills/brief/SKILL.md skills/plan/SKILL.md
  skills/ideate/SKILL.md skills/refine/SKILL.md
  skills/build/SKILL.md skills/ship/SKILL.md skills/onboard/SKILL.md
  skills/debug/SKILL.md skills/refactor/SKILL.md skills/tdd/SKILL.md
  skills/profile/SKILL.md skills/triage/SKILL.md
  commands/adr.md
)

# N/A surfaces (4) — ask no consequential question, recorded but not marked.
# Mirrors the N/A ledger in rules/godmode-recommend.md.
NA_SURFACES=(
  skills/verify/SKILL.md commands/changelog.md
  commands/godmode.md commands/pr-describe.md
)

# The literal marker token each in-scope surface must contain.
MARKER='godmode:recommend-convention'

# Membership test (bash 3.2 safe — no associative arrays). Usage:
#   in_list "$needle" "${SOME_ARRAY[@]}"  -> 0 if present, 1 otherwise.
in_list() {
  local needle item
  needle=$1
  shift
  for item in "$@"; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

# Short display label for the human-readable "ok" line. Presentation only — the
# marker check greps the full path verbatim and never relies on this.
surface_label() {
  local label
  case "$1" in
    skills/*/SKILL.md)
      label=${1#skills/}
      label=${label%/SKILL.md}
      ;;
    commands/*.md)
      label=${1#commands/}
      label=${label%.md}
      ;;
    *)
      label=$1
      ;;
  esac
  printf '%s' "$label"
}

failures=0
checked=0
marker_header_shown=0

# --- Marker presence across the in-scope set (AC-7, AC-9) -----------------
for f in "${RECOMMEND_SURFACES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "recommend: - $(surface_label "$f") (not built yet, skipped)"
    continue
  fi

  checked=$((checked + 1))

  # Match the exact token, allowing surrounding prose/backticks but rejecting
  # suffix-extended supersets (e.g. ...-convention-v2) — the rule mandates the
  # token be literal and fixed, so a versioned variant must NOT satisfy the gate.
  if grep -E "${MARKER}([^[:alnum:]-]|$)" "$f" >/dev/null 2>&1; then
    echo "recommend: ok $(surface_label "$f")"
  else
    if [ "$marker_header_shown" -eq 0 ]; then
      echo "recommend FAILURE: surface(s) missing the marker '${MARKER}':" >&2
      marker_header_shown=1
    fi
    printf '  [missing marker] %s\n' "$f" >&2
    failures=$((failures + 1))
  fi
done

# --- Partition completeness (AC-8) ----------------------------------------
# Every surface present in the repo must be classified in EXACTLY one list: in
# neither fails (unclassified), in both fails (ambiguous overlap). Together these
# two checks enforce the documented exactly-one contract.
partition_failures=0
overlap_failures=0
partition_header_shown=0
overlap_header_shown=0
for f in skills/*/SKILL.md commands/*.md; do
  # Guard against a glob that matched nothing (literal pattern left intact).
  [ -e "$f" ] || continue

  in_recommend=0
  in_na=0
  if in_list "$f" "${RECOMMEND_SURFACES[@]}"; then
    in_recommend=1
  fi
  if in_list "$f" "${NA_SURFACES[@]}"; then
    in_na=1
  fi

  # In BOTH lists -> ambiguous: violates exactly-one, fail and name it.
  if [ "$in_recommend" -eq 1 ] && [ "$in_na" -eq 1 ]; then
    if [ "$overlap_header_shown" -eq 0 ]; then
      echo "recommend FAILURE: surface(s) classified in BOTH lists (must be in exactly one):" >&2
      overlap_header_shown=1
    fi
    printf '  [both lists] %s — remove it from RECOMMEND_SURFACES or NA_SURFACES so it is in exactly one\n' "$f" >&2
    overlap_failures=$((overlap_failures + 1))
    continue
  fi

  # In exactly one list -> correctly classified.
  if [ "$in_recommend" -eq 1 ] || [ "$in_na" -eq 1 ]; then
    continue
  fi

  # In NEITHER list -> unclassified, fail and name it.
  if [ "$partition_header_shown" -eq 0 ]; then
    echo "recommend FAILURE: surface(s) classified neither in-scope nor N/A:" >&2
    partition_header_shown=1
  fi
  printf '  [unclassified] %s — classify it in RECOMMEND_SURFACES or NA_SURFACES\n' "$f" >&2
  partition_failures=$((partition_failures + 1))
done

# --- Report ----------------------------------------------------------------
total_failures=$((failures + partition_failures + overlap_failures))
if [ "$total_failures" -ne 0 ]; then
  if [ "$failures" -ne 0 ]; then
    echo "recommend: ${failures} surface(s) missing the convention marker." >&2
  fi
  if [ "$overlap_failures" -ne 0 ]; then
    echo "recommend: ${overlap_failures} surface(s) in both lists — each must be classified in exactly one of RECOMMEND_SURFACES or NA_SURFACES." >&2
  fi
  if [ "$partition_failures" -ne 0 ]; then
    echo "recommend: ${partition_failures} unclassified surface(s) — classify each in RECOMMEND_SURFACES or NA_SURFACES." >&2
  fi
  exit 1
fi

echo "recommend: convention marker present on ${checked} of ${#RECOMMEND_SURFACES[@]} in-scope surface(s); partition complete."
exit 0
