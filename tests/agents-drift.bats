#!/usr/bin/env bats
#
# AGENTS.md drift gate (unit 2, S4 — advances AC-8).
#
# Exercises scripts/check-agents-drift.sh, which verifies the committed
# AGENTS.md matches what bin/godmode-agents --stdout regenerates. Contract:
#   - committed tree in sync     -> exit 0, prints "AGENTS.md up to date"
#   - AGENTS.md tampered (stale) -> exit non-zero, prints a regenerate hint
#
# The gate resolves COMMITTED as $REPO_ROOT/AGENTS.md (the real tracked file)
# and cannot be redirected, so the tamper case mutates AGENTS.md in place. To
# keep the working tree clean, setup saves the original bytes to a temp file
# and teardown restores them from that copy — bats runs teardown even when an
# assertion fails, so AGENTS.md is always put back. Restore is from the saved
# copy (not `git checkout`) so the test never couples to git state.

load test_helper

SCRIPT="$PLUGIN_ROOT/scripts/check-agents-drift.sh"
AGENTS="$PLUGIN_ROOT/AGENTS.md"

setup() {
  AGENTS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/godmode-agents-md.XXXXXX")"
  cp "$AGENTS" "$AGENTS_BACKUP"
}

teardown() {
  if [ -n "${AGENTS_BACKUP:-}" ] && [ -f "$AGENTS_BACKUP" ]; then
    cp "$AGENTS_BACKUP" "$AGENTS"
    rm -f "$AGENTS_BACKUP"
  fi
}

@test "check-agents-drift.sh should exit 0 when AGENTS.md matches the generator" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "check-agents-drift.sh should exit non-zero when AGENTS.md is tampered" {
  printf '\n%s\n' "drift-sentinel: this line is not produced by the generator" >> "$AGENTS"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bin/godmode-agents"* ]]
}
