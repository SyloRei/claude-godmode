#!/usr/bin/env bats
#
# Done-set operations for bin/godmode-state (roadmap unit 5, S4).
#
# The done-set (steps completed for the active unit) is encoded INSIDE the
# `status` value after a " | done: " marker, e.g. "building 5 | done: S1,S2".
# This preserves the three-key state invariant — there is NO fourth top-level
# workflow key. These tests lock that contract:
#   - membership is EXACT (S2 must not match the S20 prefix),
#   - `done add` is idempotent (no S2,S2 duplicates),
#   - `done list` returns insertion order, comma-joined,
#   - the done-set lives in the single `status:` line, not a new key,
#   - the status label prefix survives a `done add`.
#
# godmode-state reads/writes .planning/STATE.md relative to cwd, so every test
# runs in a fresh temp dir and cd's there before driving the helper.

load test_helper

STATE="$PLUGIN_ROOT/bin/godmode-state"

# Fresh isolated scratch dir per test; the helper writes .planning/STATE.md here.
setup() {
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/godmode-doneset.XXXXXX")"
  cd "$SCRATCH" || return 1
}

teardown() {
  if [ -n "${SCRATCH:-}" ] && [ -d "$SCRATCH" ]; then
    rm -rf "$SCRATCH"
  fi
}

@test "AC-1: done has matches exactly — S2 is a member, S20 is not (no prefix collision)" {
  run "$STATE" set status "building 5"
  [ "$status" -eq 0 ]
  run "$STATE" "done" add S2
  [ "$status" -eq 0 ]

  # The exact step is a member.
  run "$STATE" "done" has S2
  [ "$status" -eq 0 ]

  # A step sharing the "S2" prefix must NOT match — membership is exact.
  run "$STATE" "done" has S20
  [ "$status" -ne 0 ]
}

@test "AC-1: done add is idempotent — a repeated step yields a single list entry" {
  run "$STATE" set status "building 5"
  [ "$status" -eq 0 ]
  run "$STATE" "done" add S2
  [ "$status" -eq 0 ]
  run "$STATE" "done" add S2
  [ "$status" -eq 0 ]

  # Exactly one entry, never "S2,S2".
  run "$STATE" "done" list
  [ "$status" -eq 0 ]
  [ "$output" = "S2" ]
}

@test "AC-2: done list returns insertion order and both steps are members" {
  run "$STATE" set status "building 5"
  [ "$status" -eq 0 ]
  run "$STATE" "done" add S1
  [ "$status" -eq 0 ]
  run "$STATE" "done" add S2
  [ "$status" -eq 0 ]

  run "$STATE" "done" list
  [ "$status" -eq 0 ]
  [ "$output" = "S1,S2" ]

  run "$STATE" "done" has S1
  [ "$status" -eq 0 ]
  run "$STATE" "done" has S2
  [ "$status" -eq 0 ]
}

@test "AC-1: the done-set stays inside the single status: line (no fourth key)" {
  run "$STATE" set status "building 5"
  [ "$status" -eq 0 ]
  run "$STATE" "done" add S1
  [ "$status" -eq 0 ]
  run "$STATE" "done" add S2
  [ "$status" -eq 0 ]
  run "$STATE" "done" add S3
  [ "$status" -eq 0 ]

  # Exactly one status: line — the done-set did not spawn a sibling top-level key.
  run grep -c '^status:' .planning/STATE.md
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  # That one status: line carries the encoded done-set (match the full marker,
  # not a bare "done:", so an accidentally-malformed marker would be caught).
  run grep '^status:' .planning/STATE.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"| done:"* ]]
  [[ "$output" == *"S1,S2,S3"* ]]
}

@test "AC-1: done add on an uninitialized status round-trips (no silent corruption)" {
  # No prior `set status` — status is empty. `done add` must still produce a
  # well-formed marker that survives the get/read trim, so a later `done has`
  # finds the step. (Guards the empty-label edge that would otherwise write a
  # leading-space " | done: ..." value whose marker is lost to whitespace trim.)
  run "$STATE" "done" add S1
  [ "$status" -eq 0 ]

  run "$STATE" "done" has S1
  [ "$status" -eq 0 ]

  run "$STATE" "done" list
  [ "$status" -eq 0 ]
  [ "$output" = "S1" ]

  # Still a single status: line carrying the marker — no fourth key, no breakage.
  run grep -c '^status:' .planning/STATE.md
  [ "$output" = "1" ]
  run grep '^status:' .planning/STATE.md
  [[ "$output" == *"| done:"* ]]
}

@test "AC-1: done add preserves the status label prefix" {
  run "$STATE" set status "building 5"
  [ "$status" -eq 0 ]
  run "$STATE" "done" add S1
  [ "$status" -eq 0 ]

  # The done-set is just S1...
  run "$STATE" "done" list
  [ "$status" -eq 0 ]
  [ "$output" = "S1" ]

  # ...and the human-readable status value still begins with its label.
  run "$STATE" get status
  [ "$status" -eq 0 ]
  [[ "$output" == "building 5"* ]]
}
