#!/usr/bin/env bats
#
# Recommendation-convention gate (unit 4, S12 — advances AC-9, AC-10).
#
# Exercises scripts/check-recommend.sh, which enforces that every in-scope
# question-asking surface carries the literal marker `godmode:recommend-convention`.
# Scope is no longer spine-only: the gate ships an explicit 14-entry
# RECOMMEND_SURFACES allow-list (13 skills/<name>/SKILL.md + commands/adr.md) and
# a 4-entry NA_SURFACES list, then runs a partition-completeness check over the
# repo's skills/*/SKILL.md + commands/*.md glob. Contract under test:
#   - all present in-scope surfaces carry the marker  -> exit 0, names each (AC-9)
#   - a present in-scope surface missing the marker   -> exit 1, names it  (AC-9)
#   - a near-miss / suffix-superset marker            -> exit 1, names it  (AC-9)
#   - an absent in-scope surface                       -> skipped, not failed (AC-9)
#   - a surface in NEITHER list (skill or command)    -> exit 1, names it  (AC-8)
#
# The gate resolves its own REPO_ROOT from BASH_SOURCE and cd's there, then globs
# THAT tree for the partition check. So the failure/fixture cases build a TEMP
# repo: the script is copied into a temp dir alongside a minimal surface tree and
# the COPY is run. The real repo files are never mutated. The allow-lists live in
# the script itself, so a fixture surface is classified purely by its path.

load test_helper

SCRIPT="$PLUGIN_ROOT/scripts/check-recommend.sh"
MARKER='godmode:recommend-convention'

setup() {
  FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/godmode-recommend.XXXXXX")"
}

teardown() {
  if [ -n "${FIXTURE:-}" ] && [ -d "$FIXTURE" ]; then
    rm -rf "$FIXTURE"
  fi
}

# Build a fixture repo: copy the gate script in and create one marked surface per
# argument. Each argument is either a bare skill name (-> skills/<name>/SKILL.md)
# or a full relative path containing a slash (-> used verbatim, e.g.
# commands/adr.md), so a fixture can exercise the command path shape too — not
# just skills. Every created surface carries the convention marker.
# Usage: make_fixture mission brief commands/adr.md
make_fixture() {
  mkdir -p "$FIXTURE/scripts"
  cp "$SCRIPT" "$FIXTURE/scripts/check-recommend.sh"
  chmod +x "$FIXTURE/scripts/check-recommend.sh"
  for entry in "$@"; do
    case "$entry" in
      */*) rel="$entry" ;;
      *)   rel="skills/$entry/SKILL.md" ;;
    esac
    mkdir -p "$FIXTURE/$(dirname "$rel")"
    printf '# %s\n\n<!-- %s -->\n' "$entry" "$MARKER" > "$FIXTURE/$rel"
  done
}

# --- case 1: pass on the repo as built -----------------------------------

# AC-10: the real repo exits 0 and reports all 14 in-scope surfaces as ok,
# including the surfaces widened into scope by unit 4 (build/ship/onboard/... and
# the command-shape adr surface), plus the partition-complete success line.
@test "check-recommend should exit 0 and report all 14 in-scope surfaces as ok on the repo as built" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # original spine five
  [[ "$output" == *"ok mission"* ]]
  [[ "$output" == *"ok brief"* ]]
  [[ "$output" == *"ok plan"* ]]
  [[ "$output" == *"ok ideate"* ]]
  [[ "$output" == *"ok refine"* ]]
  # surfaces newly widened into scope by unit 4
  [[ "$output" == *"ok build"* ]]
  [[ "$output" == *"ok ship"* ]]
  [[ "$output" == *"ok onboard"* ]]
  [[ "$output" == *"ok debug"* ]]
  [[ "$output" == *"ok refactor"* ]]
  [[ "$output" == *"ok tdd"* ]]
  [[ "$output" == *"ok profile"* ]]
  [[ "$output" == *"ok triage"* ]]
  # the lone command-shape surface
  [[ "$output" == *"ok adr"* ]]
  # success / partition-complete line names the new count, not the old "5"
  [[ "$output" == *"14 of 14 in-scope surface(s); partition complete."* ]]
}

# --- case 2: fail when a present in-scope surface loses its marker (AC-9) ---

# AC-9: a present in-scope surface missing the marker -> exit 1 naming the file.
# Operates on a TEMP copy; the real repo files are never touched.
@test "check-recommend should exit 1 and name the file when a present surface lacks the marker" {
  make_fixture mission brief plan
  # Strip the marker from one present surface in the fixture only.
  printf '# brief\n\n(no marker here)\n' > "$FIXTURE/skills/brief/SKILL.md"

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/brief/SKILL.md"* ]]
}

# AC-9: the gate checks command surfaces by the same path-verbatim rule — a
# present commands/<name>.md missing the marker fails and names it.
@test "check-recommend should exit 1 and name a command surface present without the marker" {
  make_fixture mission
  mkdir -p "$FIXTURE/commands"
  printf '# adr\n\n(no marker here)\n' > "$FIXTURE/commands/adr.md"

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"commands/adr.md"* ]]
}

# AC-9: the marker check is exact — a near-miss token still fails and names it.
@test "check-recommend should exit 1 when a surface carries only a near-miss marker" {
  make_fixture mission brief plan
  printf '# plan\n\n<!-- godmode:recommend -->\n' > "$FIXTURE/skills/plan/SKILL.md"

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/plan/SKILL.md"* ]]
}

# AC-9: a suffix-extended superset (e.g. ...-convention-v2) is NOT the literal
# token the rule mandates, so it must fail and name the file — guards against
# substring matching silently accepting a versioned variant.
@test "check-recommend should exit 1 when a surface carries only a superset marker" {
  make_fixture mission brief plan
  printf '# plan\n\n<!-- %s-v2 -->\n' "$MARKER" > "$FIXTURE/skills/plan/SKILL.md"

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/plan/SKILL.md"* ]]
}

# --- case 3: command path-shape surface passes (AC-10) --------------------

# AC-10: a present command surface (the adr path shape) carrying the marker is
# reported as ok, exercising the command path, not just skills.
@test "check-recommend should report a present command surface (adr path shape) as ok" {
  make_fixture mission commands/adr.md

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok mission"* ]]
  [[ "$output" == *"ok adr"* ]]
}

# --- case 4: partition completeness (AC-8) --------------------------------

# AC-8: a skill surface present in the tree but classified in NEITHER
# RECOMMEND_SURFACES nor NA_SURFACES fails the gate and names the surface — even
# though it carries the marker, presence alone cannot let it escape the partition.
@test "check-recommend should exit 1 and name an unclassified skill surface" {
  make_fixture mission rogue

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/rogue/SKILL.md"* ]]
  [[ "$output" == *"unclassified"* ]]
}

# AC-8: the partition check covers command surfaces too — a commands/<rogue>.md
# in neither list fails the gate and names it.
@test "check-recommend should exit 1 and name an unclassified command surface" {
  make_fixture mission commands/rogue.md

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"commands/rogue.md"* ]]
  [[ "$output" == *"unclassified"* ]]
}

# --- case 5: skip absent in-scope surfaces (AC-9) -------------------------

# AC-9: a fixture with ONLY mission present (the other in-scope surfaces absent)
# still exits 0 — every present surface carries the marker, the rest are skipped,
# and the lone surface is classified so the partition stays complete.
@test "check-recommend should exit 0 when only one surface is present and it has the marker" {
  make_fixture mission

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok mission"* ]]
  [[ "$output" == *"skipped"* ]]
}

# --- case 6: both failure paths fire in one run (AC-8 + AC-9) --------------

# A single run can trip BOTH the marker check and the partition check: a present
# in-scope surface stripped of its marker (missing-marker failure) alongside an
# unclassified surface (partition failure). The gate must exit 1 and emit BOTH
# summary lines, naming the missing-marker file and the unclassified surface.
@test "check-recommend should exit 1 and fire both summary lines when a marker is missing and a surface is unclassified" {
  make_fixture mission brief rogue
  # Strip the marker from a present in-scope surface -> missing-marker failure.
  printf '# brief\n\n(no marker here)\n' > "$FIXTURE/skills/brief/SKILL.md"
  # skills/rogue/SKILL.md is in neither list -> partition failure (despite marker).

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 1 ]
  # both files are named
  [[ "$output" == *"skills/brief/SKILL.md"* ]]
  [[ "$output" == *"skills/rogue/SKILL.md"* ]]
  # both summary lines fire
  [[ "$output" == *"missing the convention marker."* ]]
  [[ "$output" == *"unclassified surface(s)"* ]]
}

# --- case 7: an N/A surface present but unmarked still passes (AC-8) -------

# An N/A surface (skills/verify/SKILL.md, in NA_SURFACES) present WITHOUT the
# marker must NOT fail the gate: the marker loop never demands a marker on
# NA_SURFACES, and the partition stays complete because the surface is classified.
@test "check-recommend should exit 0 when an N/A surface is present without the marker" {
  make_fixture mission
  mkdir -p "$FIXTURE/skills/verify"
  printf '# verify\n\n(N/A surface — asks no consequential question, no marker)\n' \
    > "$FIXTURE/skills/verify/SKILL.md"

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok mission"* ]]
  [[ "$output" != *"missing the convention marker."* ]]
  [[ "$output" != *"unclassified"* ]]
}
