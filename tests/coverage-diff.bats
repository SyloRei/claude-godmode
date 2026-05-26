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

@test "coverage-diff.sh exits 0 when a drop stays within positional tolerance" {
  # current (78) is above baseline (80) - tolerance (5) = 75, so no regression.
  run "$DIFF" 80 78 5
  [ "$status" -eq 0 ]
}

@test "coverage-diff.sh exits 1 when a drop exceeds positional tolerance" {
  # current (70) is below baseline (80) - tolerance (5) = 75, so a regression.
  run "$DIFF" 80 70 5
  [ "$status" -eq 1 ]
}

@test "coverage-diff.sh exits 0 at the tolerance boundary (current == baseline - tolerance)" {
  # 75 == 80 - 5: the regression test is current < baseline - tolerance, so
  # landing exactly on the boundary is NOT a regression (sensible: dropping to
  # the allowed floor is still within tolerance).
  run "$DIFF" 80 75 5
  [ "$status" -eq 0 ]
}

@test "coverage-diff.sh accepts the --tolerance flag form" {
  run "$DIFF" --baseline 80 --current 70 --tolerance 5
  [ "$status" -eq 1 ]
}

@test "coverage-diff.sh prints -2.5 and exits 1 when decimal coverage regresses" {
  run "$DIFF" 87.5 85.0
  [ "$status" -eq 1 ]
  [ "$output" = "-2.5" ]
}

@test "coverage-diff.sh prints +2.5 and exits 0 when decimal coverage improves" {
  run "$DIFF" 85.0 87.5
  [ "$status" -eq 0 ]
  [ "$output" = "+2.5" ]
}

@test "coverage-diff.sh never emits scientific notation for a tiny delta" {
  run "$DIFF" 80.00001 80
  [ "$status" -eq 1 ]
  [ "$output" = "-0.00001" ]
  [[ "$output" != *e* ]]
}

@test "coverage-diff.sh exits 2 with a stderr message when current is non-numeric" {
  run "$DIFF" 80 n/a
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a number"* ]]
}
