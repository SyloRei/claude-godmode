#!/usr/bin/env bats
#
# gates.sh contract tests (unit 9, AC-8).
#
# gates.sh reads the gate list from config/quality-gates.txt (resolved across
# install modes, or pinned via GATES_FILE), evaluates each gate through the
# GATES_RUNNER hook, and exits non-zero if any gate fails or the config is
# absent. These tests force the three contract cases deterministically:
#   - all gates pass     (GATES_RUNNER=true + a fixture gate file) -> exit 0
#   - one gate fails     (a runner that fails on a known gate name) -> non-zero
#   - config absent      (GATES_FILE pinned at a nonexistent path)  -> non-zero
#
# Hermetic: the gate list is written to a temp file under an isolated $HOME, so
# the real project toolchain is never invoked.

load test_helper

GATES="$PLUGIN_ROOT/skills/ship/scripts/gates.sh"

setup() {
  make_temp_home
  # A hermetic three-gate fixture written to the isolated temp $HOME.
  GATES_FIXTURE="$TEST_HOME/quality-gates.txt"
  export GATES_FIXTURE
  printf '%s\n' \
    "Typecheck passes" \
    "Lint passes" \
    "Tests pass" \
    > "$GATES_FIXTURE"
}

teardown() {
  teardown_temp_home
}

@test "gates.sh exits 0 when all gates pass" {
  GATES_FILE="$GATES_FIXTURE" GATES_RUNNER=true run "$GATES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all 3 gate(s) passed"* ]]
}

@test "gates.sh exits non-zero when a gate fails" {
  # Runner fails only for the "Lint passes" gate, passes the rest.
  fail_lint="$TEST_HOME/fail-lint.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "$1" in "Lint passes") exit 1 ;; *) exit 0 ;; esac' \
    > "$fail_lint"
  chmod +x "$fail_lint"

  GATES_FILE="$GATES_FIXTURE" GATES_RUNNER="$fail_lint" run "$GATES"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Lint passes"* ]]
}

@test "gates.sh exits 1 when quality-gates.txt is absent" {
  # Pin GATES_FILE at a path that does not exist so resolution fails.
  GATES_FILE="$TEST_HOME/does-not-exist.txt" GATES_RUNNER=true run "$GATES"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "gates.sh reports every gate unevaluated and exits 1 when GATES_RUNNER is unset" {
  # No GATES_RUNNER wired: each gate must be flagged unevaluated and the run
  # must fail, so an unwired gate can never masquerade as a silent pass.
  unset GATES_RUNNER
  GATES_FILE="$GATES_FIXTURE" run "$GATES"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unevaluated"* ]]
}
