#!/usr/bin/env bats
#
# coverage-diff.sh contract tests (unit 9, AC-8).
#
# coverage-diff.sh <baseline> <current> [tolerance] prints the signed delta and
# exits: 0 = no regression, 1 = regression beyond tolerance, 2 = bad/missing
# input. These tests assert the exit-code contract and the printed delta.
#
# Hermetic: the script is pure shell + awk, takes values as args, and invokes no
# project toolchain.

load test_helper

DIFF="$PLUGIN_ROOT/skills/verify/scripts/coverage-diff.sh"

@test "coverage-diff.sh exits 0 with delta 0 when coverage is unchanged" {
  run "$DIFF" 80 80
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "coverage-diff.sh exits 0 with +5 delta when coverage improves" {
  run "$DIFF" 80 85
  [ "$status" -eq 0 ]
  [ "$output" = "+5" ]
}

@test "coverage-diff.sh exits 1 with -5 delta when coverage regresses" {
  run "$DIFF" 80 75
  [ "$status" -eq 1 ]
  [ "$output" = "-5" ]
}

@test "coverage-diff.sh exits 2 when no input is given" {
  run "$DIFF"
  [ "$status" -eq 2 ]
}

@test "coverage-diff.sh exits 2 when current value is missing" {
  run "$DIFF" 80
  [ "$status" -eq 2 ]
}

@test "coverage-diff.sh accepts --baseline/--current flag form" {
  run "$DIFF" --baseline 80 --current 85
  [ "$status" -eq 0 ]
  [ "$output" = "+5" ]
}
