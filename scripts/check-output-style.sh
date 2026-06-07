#!/usr/bin/env bash
#
# check-output-style.sh — enforce the in-skill output-block convention on every
# surface that prints a result.
#
# The convention (rules/godmode-output.md): every run ends with a legible result
# block, and every in-scope surface signals adherence two ways that this gate can
# check mechanically:
#   1. an Output section heading — `## Output` or `## Output Format`; and
#   2. the exact, fixed marker token `godmode:output-convention` in its body.
# The heading + marker pair is the single greppable contract between a surface
# and the rule.
#
# Scope — two tiers (mirroring the ledger in rules/godmode-output.md, 21 total):
#   Tier 1 — universal glob: every skills/*/SKILL.md (14) and every commands/*.md
#     (4). All skills and all commands print a result, so the whole glob is
#     in-scope; there is NO N/A subset and therefore NO partition-completeness
#     check here (unlike check-recommend.sh, which has an N/A list to partition).
#   Tier 2 — additive allow-list of exactly 3 agents (verifier, planner,
#     doc-writer). Only the agents the unit-1 audit flagged opt in; the other ~15
#     agents are out of scope by design, so this is an explicit array, NOT a glob
#     over agents/*.md.
#
# Per in-scope surface:
#   - present + carries BOTH heading and marker -> ok (AC-7, AC-9)
#   - present but missing the heading OR the marker -> exit 1, names the file and
#     which element is missing (AC-9), under per-category failure headers
#   - absent -> skipped, not failed (resilience, mirroring check-recommend.sh)
# A suffix-extended superset such as ...-convention-v2 does NOT satisfy the marker
# (grep -E 'godmode:output-convention([^[:alnum:]-]|$)').
#
# Delegation boundary (AC-8): this gate asserts heading + marker PRESENCE ONLY.
# The four content elements of a good result block — a status header, a
# what-changed summary, an explicit next-step line, and pretty formatting — are
# delegated to /verify's Lens-4 judgment, exactly as check-cohesion.sh and
# check-recommend.sh delegate prose quality to the same lens. The gate greps two
# tokens; it cannot judge prose. In particular there is deliberately NO
# next-step-line regex: a runtime-computed surface like commands/godmode.md emits
# its next step at run time, so a static regex would false-fail it.
#
# Pure bash 3.2 + grep. No Node, no Python, no associative arrays, no mapfile.
# Exit 0 clean, 1 on any violation.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
cd -- "${REPO_ROOT}"

# Tier-2 in-scope agents — additive allow-list, NOT a glob over agents/*.md.
OUTPUT_AGENTS=(
  agents/verifier.md
  agents/planner.md
  agents/doc-writer.md
)

# Output section heading: `## Output` or `## Output Format` (two or more `#`).
HEADING_RE='^#{2,} *Output( Format)? *$'

# The literal marker token each in-scope surface must contain. Matched with a
# trailing non-[alnum-] boundary (or EOL) so a suffix-extended superset such as
# godmode:output-convention-v2 does NOT satisfy it.
MARKER='godmode:output-convention'

# Short display label for the human-readable "ok"/"skipped" line. Presentation
# only — the heading/marker checks grep the full path verbatim.
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
    agents/*.md)
      label=${1#agents/}
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
# Per-category failure headers: each category prints its header exactly once, the
# first time it fires, so entries always appear under their own header even when
# both categories occur in one run (mirrors check-cohesion.sh).
missing_heading_shown=0
missing_marker_shown=0

# Check a single in-scope surface: skip if absent, else assert heading + marker.
check_surface() {
  local f label
  f=$1
  label=$(surface_label "$f")

  if [ ! -f "$f" ]; then
    echo "output: - ${label} (not present, skipped)"
    return 0
  fi

  checked=$((checked + 1))

  local ok=1
  if ! grep -E "${HEADING_RE}" "$f" >/dev/null 2>&1; then
    if [ "$missing_heading_shown" -eq 0 ]; then
      echo "output FAILURE: surface(s) missing an Output section heading (## Output or ## Output Format):" >&2
      missing_heading_shown=1
    fi
    printf '  [missing heading] %s\n' "$f" >&2
    failures=$((failures + 1))
    ok=0
  fi

  if ! grep -E "${MARKER}([^[:alnum:]-]|$)" "$f" >/dev/null 2>&1; then
    if [ "$missing_marker_shown" -eq 0 ]; then
      echo "output FAILURE: surface(s) missing the marker '${MARKER}':" >&2
      missing_marker_shown=1
    fi
    printf '  [missing marker] %s\n' "$f" >&2
    failures=$((failures + 1))
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    echo "output: ok ${label}"
  fi
}

# --- Tier 1: universal glob over all skills and commands -------------------
for f in skills/*/SKILL.md commands/*.md; do
  # Guard against a glob that matched nothing (literal pattern left intact).
  [ -e "$f" ] || continue
  check_surface "$f"
done

# A tier-1 glob that matched zero surfaces is a misconfiguration (wrong working
# dir, or a renamed surface tree), not a clean pass — fail loudly.
if [ "$checked" -eq 0 ]; then
  echo "output ERROR: no surfaces found under skills/ or commands/." >&2
  exit 1
fi

# --- Tier 2: additive allow-list of in-scope agents -----------------------
for f in "${OUTPUT_AGENTS[@]}"; do
  check_surface "$f"
done

if [ "$failures" -ne 0 ]; then
  echo "output: ${failures} output-convention violation(s) (missing heading or marker)." >&2
  exit 1
fi

echo "output: heading + marker present on all ${checked} in-scope surface(s)."
exit 0
