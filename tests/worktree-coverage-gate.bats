#!/usr/bin/env bats
#
# Regression suite for scripts/check-worktree-coverage.sh (roadmap unit 6, S5).
#
# The coverage gate locks the worktree-hardening test suite: it asserts that
# each audit reproduction token ([repro:stale-base], [repro:merge-hazard],
# [repro:cleanup-leak], [repro:dash-n]) tags a `@test` line and that the five
# tracked lifecycle helpers (godmode-worktree create/mergeback/cleanup, the
# done-set helper, the skip-set helper) each keep a covering test. Backs AC-8:
# the gate exits 0 on a complete fixture and exits non-zero NAMING the missing
# lock when a token or subcommand reference is removed.
#
# We drive the gate against a temp fixture tests dir (its optional first
# argument) so these assertions never touch the real suite. Each test builds a
# minimal-but-sufficient fixture from scratch, then unlocks exactly one thing.
#
# Bash 3.2 / BSD-safe: no bash 4 constructs, no GNU-only flags.

load test_helper

# The gate under test, resolved via the repo's PLUGIN_ROOT convention.
GATE="$PLUGIN_ROOT/scripts/check-worktree-coverage.sh"

setup() {
  FIX="$(mktemp -d "${TMPDIR:-/tmp}/godmode-covgate.XXXXXX")"
}

teardown() {
  if [ -n "${FIX:-}" ] && [ -d "$FIX" ]; then
    rm -rf "$FIX"
  fi
}

# Write a complete fixture into $FIX that satisfies every gate assertion.
#
# Layout mirrors how the real suite presents the locks:
#   - repro.bats     -> one `@test` line per reproduction token
#   - helpers.bats   -> one reference per tracked subcommand, matching the
#                       gate's ERE patterns (WT" create, done" (add|has|list),
#                       godmode-skipset, ...)
#
# IMPORTANT: bats 1.13.0 preprocesses the ENTIRE .bats source — every literal
# `@test "..."` line is rewritten to `bats_test_function`, even inside a
# heredoc in a test body. So a heredoc carrying `@test` would never reach the
# fixture as a real `@test` line. We assemble each `@test` line at runtime via
# the $T variable so the token is built after preprocessing, landing verbatim
# in the fixture file the gate then greps.
write_complete_fixture() {
  local T='@test'
  {
    echo '#!/usr/bin/env bats'
    printf '%s "stale base regression [repro:stale-base]" { true; }\n' "$T"
    printf '%s "merge hazard regression [repro:merge-hazard]" { true; }\n' "$T"
    printf '%s "cleanup leak regression [repro:cleanup-leak]" { true; }\n' "$T"
    printf '%s "dash-n false positive [repro:dash-n]" { true; }\n' "$T"
  } > "$FIX/repro.bats"

  {
    echo '#!/usr/bin/env bats'
    echo 'WT="$PLUGIN_ROOT/bin/godmode-worktree"'
    echo 'STATE="$PLUGIN_ROOT/bin/godmode-state"'
    printf '%s "create helper" { run "$WT" create build/x; true; }\n' "$T"
    printf '%s "mergeback helper" { run "$WT" mergeback build/x; true; }\n' "$T"
    printf '%s "cleanup helper" { run "$WT" cleanup; true; }\n' "$T"
    printf '%s "done-set helper" { run "$STATE" "done" add 1; true; }\n' "$T"
    printf '%s "skip-set helper" { run godmode-skipset 1; true; }\n' "$T"
  } > "$FIX/helpers.bats"
}

# Build a fixture from the REAL repro/coverage test files, INCLUDING a copy of
# this gate-regression file itself. This reproduces the exact real-tree layout
# in which the gate file's own AC-8 `@test` descriptions (e.g. `removing
# [repro:stale-base] ...`) and its fixture-writer `printf` lines carry the very
# tokens/patterns the gate scans for. The loophole closed in S8 was that those
# self-satisfying mentions kept the gate green even after a REAL reproduction
# test lost its tag. We copy the live tests/ tree so this regression tracks the
# real files, not synthetic stand-ins.
write_real_tree_fixture() {
  cp "$PLUGIN_ROOT"/tests/*.bats "$FIX/"
}

@test "AC-1: real repro-tag deletion trips the gate despite gate-file copy [repro:stale-base]" {
  # Real-tree layout: every real .bats, including this gate file's own copy
  # whose AC-8 descriptions mention [repro:stale-base]. Intact => exit 0.
  write_real_tree_fixture
  run "$GATE" "$FIX"
  [ "$status" -eq 0 ]

  # Strip the [repro:stale-base] tag from the REAL reproduction file copy,
  # leaving the gate-file copy's `AC-8: removing [repro:stale-base]` description
  # in place. Before S8 this false-greened (the gate-file description satisfied
  # the grep); after S8 the gate file is excluded from the scan, so the lock
  # must now go red and name stale-base.
  grep -v 'repro:stale-base' "$FIX/worktree-stale-base.bats" > "$FIX/wsb.new"
  mv "$FIX/wsb.new" "$FIX/worktree-stale-base.bats"
  run "$GATE" "$FIX"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "stale-base"
}

@test "AC-1: a tests dir holding only the gate's own file fails loudly" {
  # After excluding worktree-coverage-gate.bats, no real .bats remains to scan.
  # An empty scan must fail loudly (non-zero) rather than silently pass.
  cp "$PLUGIN_ROOT/tests/worktree-coverage-gate.bats" "$FIX/"
  run "$GATE" "$FIX"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "no real .bats files to scan"
}

@test "AC-8: clean fixture (all 4 tokens + 5 refs present) exits 0" {
  write_complete_fixture
  run "$GATE" "$FIX"
  [ "$status" -eq 0 ]
  # Sanity: the gate reports the full lock set as present.
  echo "$output" | grep -q "all .* reproduction/subcommand lock(s) present"
}

@test "AC-8: removing [repro:stale-base] fails non-zero and names it" {
  write_complete_fixture
  # Drop the stale-base @test line only.
  grep -v 'repro:stale-base' "$FIX/repro.bats" > "$FIX/repro.bats.new"
  mv "$FIX/repro.bats.new" "$FIX/repro.bats"
  run "$GATE" "$FIX"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "repro:stale-base"
}

@test "AC-8: removing [repro:merge-hazard] fails non-zero and names it" {
  write_complete_fixture
  grep -v 'repro:merge-hazard' "$FIX/repro.bats" > "$FIX/repro.bats.new"
  mv "$FIX/repro.bats.new" "$FIX/repro.bats"
  run "$GATE" "$FIX"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "merge-hazard"
}

@test "AC-8: removing [repro:cleanup-leak] fails non-zero and names it" {
  write_complete_fixture
  grep -v 'repro:cleanup-leak' "$FIX/repro.bats" > "$FIX/repro.bats.new"
  mv "$FIX/repro.bats.new" "$FIX/repro.bats"
  run "$GATE" "$FIX"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "cleanup-leak"
}

@test "AC-8: removing [repro:dash-n] fails non-zero and names it" {
  write_complete_fixture
  grep -v 'repro:dash-n' "$FIX/repro.bats" > "$FIX/repro.bats.new"
  mv "$FIX/repro.bats.new" "$FIX/repro.bats"
  run "$GATE" "$FIX"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "dash-n"
}

@test "AC-8: removing the mergeback subcommand ref fails non-zero and names it" {
  write_complete_fixture
  # Drop the mergeback line; the other four helper refs remain.
  grep -v 'mergeback' "$FIX/helpers.bats" > "$FIX/helpers.bats.new"
  mv "$FIX/helpers.bats.new" "$FIX/helpers.bats"
  run "$GATE" "$FIX"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "mergeback"
}

@test "AC-8: removing the skip-set helper ref fails non-zero and names it" {
  write_complete_fixture
  grep -v 'godmode-skipset' "$FIX/helpers.bats" > "$FIX/helpers.bats.new"
  mv "$FIX/helpers.bats.new" "$FIX/helpers.bats"
  run "$GATE" "$FIX"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "godmode-skipset"
}

@test "AC-8: a non-existent tests dir fails loudly non-zero" {
  run "$GATE" "$FIX/does-not-exist"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "tests dir not found"
}
