#!/usr/bin/env bats
#
# Full-lifecycle smoke test for bin/godmode-worktree (roadmap unit 6, AC-6).
#
# The per-subcommand suites in worktree-stale-base.bats each prove one verb in
# isolation. This file locks the COMPOSITION no single-verb test covers: the
# end-to-end happy path an agent wave actually walks —
#
#   create (wave 1) -> agent commit -> mergeback -> create (wave 2, off the
#   UPDATED build HEAD) -> targeted cleanup
#
# The load-bearing assertion is at the second `create`: the new worktree's base
# must have the *advanced* build HEAD as an ancestor AND carry wave 1's file.
# If `create` ever stopped merging the build branch in, wave 2 would build on a
# stale base — exactly the audit's original symptom — and this test turns red.
#
# Bash 3.2 / BSD-safe only: no mapfile/readarray, no [[ -v ]], no ${var,,},
# no associative arrays, no GNU-only flags.

load test_helper

# The helper under test, resolved via the repo's PLUGIN_ROOT convention.
WT="$PLUGIN_ROOT/bin/godmode-worktree"

# Build a fresh scratch repo with a base commit and a build branch one commit
# ahead of main. The build branch is checked out in the main tree; wave
# worktrees are added under .claude/worktrees/ so targeted `cleanup <id>` can
# resolve them under the repo's worktrees root.
#
# Globals set for the tests:
#   SCRATCH    - the scratch repo root (the main checkout, on the build branch)
#   BUILD      - the build branch name
setup() {
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/godmode-lifecycle.XXXXXX")"
  BUILD="lc/build"

  cd "$SCRATCH" || return 1
  git init -q
  # Local identity only — never touch the user's global git config.
  git config user.email "test@example.com"
  git config user.name "godmode test"

  # Base commit on main.
  echo base > base.txt
  git add base.txt
  git commit -qm "base"
  git branch -M main

  # Build branch, one commit ahead of main.
  git checkout -q -b "$BUILD"
  printf 'build-branch-only content\n' > build_only.txt
  git add build_only.txt
  git commit -qm "build branch seeds build_only.txt"

  mkdir -p .claude/worktrees
}

teardown() {
  if [ -n "${SCRATCH:-}" ]; then
    # Force-remove any wave worktrees, ignoring ones already reaped, then drop
    # the whole scratch repo. Guard each so teardown never fails the suite.
    git -C "$SCRATCH" worktree remove --force "$SCRATCH/.claude/worktrees/wave1" >/dev/null 2>&1 || true
    git -C "$SCRATCH" worktree remove --force "$SCRATCH/.claude/worktrees/wave2" >/dev/null 2>&1 || true
    rm -rf "$SCRATCH"
  fi
}

@test "AC-6: full create -> commit -> mergeback -> second create -> cleanup lifecycle" {
  # --- 1. WAVE 1 CREATE -----------------------------------------------------
  # The SDK would auto-create the agent's tree off main (behind the build
  # branch). Reproduce that, then run `create` from inside it to bring the
  # build HEAD in. After create, the build HEAD must be an ancestor of the
  # worktree's HEAD and the build-only file must be materialized.
  local build_head_initial
  build_head_initial="$(git -C "$SCRATCH" rev-parse "$BUILD")"

  git -C "$SCRATCH" worktree add -q -b lc/wave1 .claude/worktrees/wave1 main
  cd "$SCRATCH/.claude/worktrees/wave1" || return 1
  [ ! -f build_only.txt ]

  run "$WT" create "$BUILD"
  [ "$status" -eq 0 ]
  git merge-base --is-ancestor "$build_head_initial" HEAD
  [ -s build_only.txt ]

  # --- 2. AGENT COMMIT ------------------------------------------------------
  # Simulate the agent doing its step's work and committing on the wave's own
  # step branch (lc/wave1).
  echo wave-one-output > wave1.txt
  git add wave1.txt
  git commit -qm "wave 1 agent adds wave1.txt"
  local wave1_head
  wave1_head="$(git rev-parse HEAD)"

  # --- 3. MERGEBACK ---------------------------------------------------------
  # From a checkout of the build branch, mergeback the wave 1 step branch. The
  # build branch advances (clean ff/merge, exit 0) and now carries wave1.txt.
  cd "$SCRATCH" || return 1
  run "$WT" mergeback lc/wave1
  [ "$status" -eq 0 ]
  git merge-base --is-ancestor "$wave1_head" HEAD
  [ -f wave1.txt ]
  local build_head_updated
  build_head_updated="$(git rev-parse "$BUILD")"
  # The build branch genuinely moved forward from where wave 1 started.
  [ "$build_head_updated" != "$build_head_initial" ]

  # --- 4. WAVE 2 CREATE OFF THE UPDATED HEAD --------------------------------
  # A second agent tree is again auto-created off main (stale). `create` must
  # bring in the *advanced* build HEAD: the new worktree's HEAD has the updated
  # build HEAD as an ancestor AND contains wave 1's file — proving no stale base
  # and that wave 2 builds on wave 1's work.
  git worktree add -q -b lc/wave2 .claude/worktrees/wave2 main
  cd "$SCRATCH/.claude/worktrees/wave2" || return 1
  [ ! -f wave1.txt ]

  run "$WT" create "$BUILD"
  [ "$status" -eq 0 ]
  git merge-base --is-ancestor "$build_head_updated" HEAD
  [ -f wave1.txt ]

  # --- 5. TARGETED CLEANUP --------------------------------------------------
  # Reap the wave 1 worktree by id from the main checkout. Only that tree is
  # removed; the live wave 2 tree must survive. Move out of any reaped tree
  # first so cleanup can remove it.
  cd "$SCRATCH" || return 1
  run "$WT" cleanup wave1
  [ "$status" -eq 0 ]
  [[ "$output" == *"reaped"* ]]
  run git worktree list --porcelain
  [[ "$output" != *".claude/worktrees/wave1"* ]]
  [[ "$output" == *".claude/worktrees/wave2"* ]]
  [ -d .claude/worktrees/wave2 ]
}
