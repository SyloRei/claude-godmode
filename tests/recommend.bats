#!/usr/bin/env bats
#
# Recommendation-convention gate (unit 21, S5 — advances AC-9).
#
# Exercises scripts/check-recommend.sh, which enforces that every PRESENT
# planning-spine skill (mission brief plan ideate refine) carries the literal
# marker `godmode:recommend-convention`. Contract under test:
#   - all present spine skills carry the marker -> exit 0, names each (AC-5)
#   - a present spine skill missing the marker  -> exit 1, names the file (AC-6)
#   - an absent spine skill                      -> skipped, not failed (AC-7)
#
# The gate resolves its own REPO_ROOT from BASH_SOURCE and cd's there, so the
# failure/fixture cases build a TEMP repo: the script is copied into a temp dir
# alongside a minimal skills/<name>/SKILL.md tree and the COPY is run. The real
# repo files are never mutated.

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

# Build a fixture repo: copy the gate script in and create a SKILL.md per named
# spine skill, each carrying the convention marker. Usage: make_fixture m b p
make_fixture() {
  mkdir -p "$FIXTURE/scripts"
  cp "$SCRIPT" "$FIXTURE/scripts/check-recommend.sh"
  chmod +x "$FIXTURE/scripts/check-recommend.sh"
  for name in "$@"; do
    mkdir -p "$FIXTURE/skills/$name"
    printf '# %s\n\n<!-- %s -->\n' "$name" "$MARKER" > "$FIXTURE/skills/$name/SKILL.md"
  done
}

# --- case 1: pass on the repo as built -----------------------------------

# AC-5: the real repo exits 0 and names the built spine skills.
@test "check-recommend should exit 0 and name built spine skills on the repo as built" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mission"* ]]
  [[ "$output" == *"brief"* ]]
  [[ "$output" == *"plan"* ]]
  # /ideate (unit 22) and /refine (unit 23) are built, so each must be
  # reported as ok, not skipped.
  [[ "$output" == *"ok ideate"* ]]
  [[ "$output" == *"ok refine"* ]]
}

# --- case 2: fail when a present spine skill loses its marker (AC-6) -------

# AC-6: a present spine skill missing the marker -> exit 1 naming the file.
# Operates on a TEMP copy; the real repo files are never touched.
@test "check-recommend should exit 1 and name the file when a present spine skill lacks the marker" {
  make_fixture mission brief plan
  # Strip the marker from one present spine skill in the fixture only.
  printf '# brief\n\n(no marker here)\n' > "$FIXTURE/skills/brief/SKILL.md"

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/brief/SKILL.md"* ]]
}

# AC-6: the marker check is exact — a near-miss token still fails and names it.
@test "check-recommend should exit 1 when a spine skill carries only a near-miss marker" {
  make_fixture mission brief plan
  printf '# plan\n\n<!-- godmode:recommend -->\n' > "$FIXTURE/skills/plan/SKILL.md"

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/plan/SKILL.md"* ]]
}

# AC-6: a suffix-extended superset (e.g. ...-convention-v2) is NOT the literal
# token the rule mandates, so it must fail and name the file — guards against
# substring matching silently accepting a versioned variant.
@test "check-recommend should exit 1 when a spine skill carries only a superset marker" {
  make_fixture mission brief plan
  printf '# plan\n\n<!-- %s-v2 -->\n' "$MARKER" > "$FIXTURE/skills/plan/SKILL.md"

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/plan/SKILL.md"* ]]
}

# --- case 3: skip absent spine skills (AC-7) ------------------------------

# Every spine skill is now built (refine landed in unit 23), so the real repo
# reports each as ok and skips none. The genuine skip-absent behaviour (AC-7)
# is exercised against a fixture in the next test.
@test "check-recommend reports all built spine skills as ok and skips none on the repo as built" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok refine"* ]]
  [[ "$output" != *"skipped"* ]]
}

# AC-7: a fixture with ONLY mission present (brief/plan/ideate/refine absent)
# still exits 0 — every present skill carries the marker, the rest are skipped.
@test "check-recommend should exit 0 when only one spine skill is present and it has the marker" {
  make_fixture mission

  run "$FIXTURE/scripts/check-recommend.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mission"* ]]
  [[ "$output" == *"skipped"* ]]
}
