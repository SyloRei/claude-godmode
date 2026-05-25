#!/usr/bin/env bats
#
# Episodic named missions (unit 20, S8 — advances AC-10).
#
# Exercises the mission lifecycle contract across two helpers:
#   bin/godmode-state   — adds keys mission_id | mission_name (alongside the
#                         existing active_unit | status | next_command).
#   bin/godmode-mission — start <name> / current. A fresh slug scaffolds
#                         .planning/missions/NN-<slug>/ and RESETS active_unit
#                         to 1; an existing slug switches to it and leaves
#                         active_unit (and that mission's ROADMAP.md) untouched.
#
# Both helpers resolve .planning/ relative to CWD, so every test runs inside
# its own mktemp -d (cd'd into) and NEVER touches the repo's real .planning/.
# The helpers are located by absolute path from PLUGIN_ROOT (set in
# test_helper.bash), so the working-dir swap below does not lose them.

load test_helper

# `run --separate-stderr` (used below) requires the bats 1.5.0+ flag API.
bats_require_minimum_version 1.5.0

STATE="$PLUGIN_ROOT/bin/godmode-state"
MISSION="$PLUGIN_ROOT/bin/godmode-mission"

setup() {
  TEST_CWD="$(mktemp -d "${TMPDIR:-/tmp}/godmode-mission.XXXXXX")"
  cd "$TEST_CWD"
}

teardown() {
  cd /
  if [ -n "${TEST_CWD:-}" ] && [ -d "$TEST_CWD" ]; then
    rm -rf "$TEST_CWD"
  fi
}

# --- godmode-state key support -------------------------------------------

# AC-10: mission_id is a first-class state key (set then get round-trips).
@test "godmode-state should round-trip mission_id when set then get" {
  run "$STATE" set mission_id "01-some-feature"
  [ "$status" -eq 0 ]
  run "$STATE" get mission_id
  [ "$status" -eq 0 ]
  [ "$output" = "01-some-feature" ]
}

# AC-10: mission_name is a first-class state key (set then get round-trips).
@test "godmode-state should round-trip mission_name when set then get" {
  run "$STATE" set mission_name "Some Feature"
  [ "$status" -eq 0 ]
  run "$STATE" get mission_name
  [ "$status" -eq 0 ]
  [ "$output" = "Some Feature" ]
}

# Guard: an unknown key is rejected (non-zero) and prints usage to stderr.
# Uses `run --separate-stderr` (bats >= 1.5) so the usage text is asserted on
# the real stderr stream rather than relying on it being folded into $output.
@test "godmode-state should exit non-zero and print usage when key is bogus" {
  run --separate-stderr "$STATE" set not_a_real_key value
  [ "$status" -ne 0 ]
  printf '%s\n' "$stderr" | grep -q "keys:"
}

# No regression: the pre-existing active_unit key still round-trips.
@test "godmode-state should still round-trip active_unit when set then get" {
  run "$STATE" set active_unit "3"
  [ "$status" -eq 0 ]
  run "$STATE" get active_unit
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

# --- godmode-mission lifecycle -------------------------------------------

# AC-10: a fresh slug scaffolds NN-<slug>/ and RESETS active_unit to 1.
@test "godmode-mission start should create mission dir and reset active_unit to 1 when slug is new" {
  run "$MISSION" start "Some New Feature"
  [ "$status" -eq 0 ]
  [ -d ".planning/missions/01-some-new-feature" ]
  [ -d ".planning/missions/01-some-new-feature/briefs" ]
  [ -f ".planning/missions/01-some-new-feature/ROADMAP.md" ]
  run "$STATE" get active_unit
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run "$MISSION" current
  [ "$status" -eq 0 ]
  [ "$output" = "01-some-new-feature" ]
}

# AC-10: re-starting an existing slug leaves active_unit AND its ROADMAP.md
# unchanged (switch, do not reset).
@test "godmode-mission start should preserve active_unit and ROADMAP when slug already exists" {
  run "$MISSION" start "Some New Feature"
  [ "$status" -eq 0 ]
  roadmap=".planning/missions/01-some-new-feature/ROADMAP.md"
  before="$(cat "$roadmap")"

  # Advance the unit counter mid-mission.
  run "$STATE" set active_unit "7"
  [ "$status" -eq 0 ]

  # Re-start the same mission: must switch, not reset.
  run "$MISSION" start "Some New Feature"
  [ "$status" -eq 0 ]
  run "$STATE" get active_unit
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]

  after="$(cat "$roadmap")"
  [ "$before" = "$after" ]
}

# NN allocation increments for a second distinct mission.
@test "godmode-mission start should allocate 02 for a second distinct mission" {
  run "$MISSION" start "First Thing"
  [ "$status" -eq 0 ]
  [ -d ".planning/missions/01-first-thing" ]

  run "$MISSION" start "Second Thing"
  [ "$status" -eq 0 ]
  [ -d ".planning/missions/02-second-thing" ]
  run "$MISSION" current
  [ "$status" -eq 0 ]
  [ "$output" = "02-second-thing" ]
}

# FIX 1 regression: NN allocation must survive ≥100 missions. With a pre-existing
# 100-<slug>/ dir, re-starting that exact name must SWITCH to it (not allocate a
# new 01-...), and a brand-new name must then allocate 101-... (not collide to 01).
@test "godmode-mission start should switch to a 3-digit mission dir when slug already exists" {
  mkdir -p ".planning/missions/100-existing-mission/briefs"
  printf '# Roadmap: Existing Mission\n' > ".planning/missions/100-existing-mission/ROADMAP.md"
  before="$(cat ".planning/missions/100-existing-mission/ROADMAP.md")"

  run "$MISSION" start "existing mission"
  [ "$status" -eq 0 ]
  # Switched, not re-created: no spurious 01-... dir.
  [ ! -d ".planning/missions/01-existing-mission" ]
  run "$MISSION" current
  [ "$status" -eq 0 ]
  [ "$output" = "100-existing-mission" ]

  # Switch preserves mission_id (re-asserted after a re-read).
  run "$STATE" get mission_id
  [ "$status" -eq 0 ]
  [ "$output" = "100-existing-mission" ]

  # The existing ROADMAP.md was left untouched by the switch.
  after="$(cat ".planning/missions/100-existing-mission/ROADMAP.md")"
  [ "$before" = "$after" ]
}

@test "godmode-mission start should allocate 101 for a new mission past a 3-digit max" {
  mkdir -p ".planning/missions/100-existing-mission/briefs"
  printf '# Roadmap: Existing Mission\n' > ".planning/missions/100-existing-mission/ROADMAP.md"

  run "$MISSION" start "brand new thing"
  [ "$status" -eq 0 ]
  [ -d ".planning/missions/101-brand-new-thing" ]
  run "$MISSION" current
  [ "$status" -eq 0 ]
  [ "$output" = "101-brand-new-thing" ]
}

# Usage path: `start` with no feature name exits non-zero.
@test "godmode-mission start should exit non-zero when no feature name is given" {
  run "$MISSION" start
  [ "$status" -ne 0 ]
}

# Unknown subcommand falls through to usage and exits non-zero.
@test "godmode-mission should exit non-zero when subcommand is unknown" {
  run "$MISSION" bogus
  [ "$status" -ne 0 ]
}
