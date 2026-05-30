#!/usr/bin/env bats
#
# Stale-base correctness for bin/godmode-worktree (roadmap unit 2).
#
# The SDK auto-creates an `isolation: worktree` agent's tree off `main`, but the
# active build branch is usually one or more commits ahead. The audit observed
# the symptom directly: a build-branch-only file is ABSENT from the fresh,
# main-based worktree, so the agent edits a stale base and its commit silently
# drops earlier waves' work. `godmode-worktree create <build-ref>` is the fix —
# it merges the build-branch HEAD into the worktree before the agent builds.
#
# These tests encode that reproduction in an isolated scratch repo and prove
# `create` is load-bearing: the "X absent before create" assertion is what makes
# this suite turn red if the merge step is ever bypassed or regresses.

load test_helper

# The helper under test, resolved via the repo's PLUGIN_ROOT convention.
WT="$PLUGIN_ROOT/bin/godmode-worktree"

# Build the audit's stale-base reproduction in a fresh scratch repo and cd into
# the simulated SDK worktree (checked out at `main`, behind the build branch).
#
# Globals set for the tests:
#   SCRATCH    - the scratch repo root (the "main checkout")
#   WT_DIR     - the simulated stale worktree, checked out at main
#   BUILD_HEAD - the build branch HEAD commit (build/unit), captured here
setup() {
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/godmode-stalebase.XXXXXX")"
  WT_DIR="$SCRATCH/worktree"

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

  # Build branch, one commit ahead of main, adding a build-branch-only file X.
  git checkout -q -b build/unit
  printf 'build-branch-only content\n' > X
  git add X
  git commit -qm "add X on build branch"
  BUILD_HEAD="$(git rev-parse build/unit)"

  # Free `main` for the worktree by detaching the main checkout, then simulate
  # the SDK's stale worktree: a fresh tree checked out at main (behind build).
  git checkout -q --detach main
  git worktree add "$WT_DIR" main >/dev/null 2>&1
  cd "$WT_DIR" || return 1
}

teardown() {
  if [ -n "${SCRATCH:-}" ]; then
    # Guard the worktree removal so an absent/already-removed tree does not
    # fail the suite during teardown.
    git -C "$SCRATCH" worktree remove --force "$WT_DIR" >/dev/null 2>&1 || true
    rm -rf "$SCRATCH"
  fi
}

@test "AC-7: stale worktree lacks the build-branch-only file before create" {
  # The audit's observed outcome: the SDK's main-based worktree does not contain
  # the build branch's work. This is the load-bearing assertion — if `create`
  # were a no-op or skipped, the AC-3 test below would still see X absent.
  [ "$(pwd)" = "$WT_DIR" ]
  [ ! -f X ]
}

@test "AC-3: create merges the build branch in, materializing its file" {
  run "$WT" create build/unit
  [ "$status" -eq 0 ]
  [ -f X ]
  # The file's content must be non-empty (the merge brought real work in).
  [ -s X ]
  [ -n "$(cat X)" ]
}

@test "AC-4: after create the build-branch HEAD is an ancestor of HEAD" {
  run "$WT" create build/unit
  [ "$status" -eq 0 ]
  git merge-base --is-ancestor "$BUILD_HEAD" HEAD
}

@test "AC-1: create is idempotent once the build branch is already in" {
  run "$WT" create build/unit
  [ "$status" -eq 0 ]
  # Second run is a no-op fast path, still exit 0.
  run "$WT" create build/unit
  [ "$status" -eq 0 ]
  [ -f X ]
}

@test "AC-1: no subcommand exits non-zero and the usage mentions create" {
  run "$WT"
  [ "$status" -ne 0 ]
  [[ "$output" == *create* ]]
}

@test "AC-1: an unknown subcommand exits non-zero" {
  run "$WT" bogus
  [ "$status" -ne 0 ]
}
