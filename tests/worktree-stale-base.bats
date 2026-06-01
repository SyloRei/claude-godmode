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
# `create` is load-bearing: the "X absent before create, present after" pair
# inside one test body is what makes this suite turn red if the merge step is
# ever bypassed or regresses.

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

@test "AC-3/AC-7: X is absent before create and present after (regression guard)" {
  # The audit's observed outcome: the SDK's main-based worktree does not contain
  # the build branch's work. Asserting absence and presence in ONE body is the
  # load-bearing check — if `create` were a no-op, replaced with `touch X`, or
  # bypassed, this single test turns red.
  [ ! -f X ]

  run "$WT" create build/unit
  [ "$status" -eq 0 ]
  # X is now materialized with real, non-empty content from the merge.
  [ -s X ]
}

@test "AC-4: after create the build-branch HEAD is an ancestor of HEAD" {
  run "$WT" create build/unit
  [ "$status" -eq 0 ]
  git merge-base --is-ancestor "$BUILD_HEAD" HEAD
}

@test "AC-3: create is idempotent — a second run is a no-op fast path" {
  run "$WT" create build/unit
  [ "$status" -eq 0 ]
  # Second run takes the "already based on" fast path, still exit 0.
  run "$WT" create build/unit
  [ "$status" -eq 0 ]
  [[ "$output" == *"already based"* ]]
  [ -f X ]
}

@test "AC-1: no subcommand exits non-zero and the usage names create" {
  run "$WT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *create* ]]
}

@test "AC-1: an unknown subcommand exits non-zero" {
  run "$WT" bogus
  [ "$status" -ne 0 ]
}

@test "create: an unresolvable build-ref exits non-zero with a clear message" {
  run "$WT" create no/such/ref
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not resolve"* ]]
  # The stale worktree is left untouched (no merge attempted).
  [ ! -f X ]
}

@test "create: run outside any git work tree exits non-zero" {
  local notgit
  notgit="$(mktemp -d "${TMPDIR:-/tmp}/godmode-notgit.XXXXXX")"
  cd "$notgit" || return 1
  run "$WT" create build/unit
  [ "$status" -ne 0 ]
  [[ "$output" == *"git work tree"* ]]
  cd "$WT_DIR" || return 1
  rm -rf "$notgit"
}

@test "create: a merge conflict is aborted and exits non-zero, leaving a clean tree" {
  # Diverge the worktree from the build branch on the same file X so the merge
  # genuinely conflicts (worktree's X != build branch's X).
  printf 'conflicting worktree content\n' > X
  git add X
  git commit -qm "worktree adds a conflicting X"

  run "$WT" create build/unit
  [ "$status" -ne 0 ]
  [[ "$output" == *"conflict"* ]]
  # The abort must leave no merge in progress (a linked worktree's `.git` is a
  # file, so ask git rather than stat .git/MERGE_HEAD).
  run git rev-parse --verify --quiet MERGE_HEAD
  [ "$status" -ne 0 ]
  run git merge-base --is-ancestor "$BUILD_HEAD" HEAD
  [ "$status" -ne 0 ]
}

# --- mergeback (unit 4) --------------------------------------------------------
#
# mergeback operates on the currently-checked-out build branch and brings a
# committed step branch back via the fast-forward -> no-edit-merge -> abort
# ladder. These tests build the build/step topology inside the scratch repo and
# drive the helper from a checkout of the build branch.

# Put the scratch repo's main checkout onto a fresh build branch (off main) and
# cd there. The simulated stale worktree from setup() is left intact.
checkout_build() {
  cd "$SCRATCH" || return 1
  git checkout -q -B mb/build main
}

@test "AC-1: mergeback fast-forwards when the step branch is strictly ahead" {
  checkout_build
  local build_before
  build_before="$(git rev-parse HEAD)"

  # Step branch strictly ahead of the build branch.
  git checkout -q -b mb/step
  echo step-one > step.txt
  git add step.txt
  git commit -qm "step adds step.txt"
  local step_head
  step_head="$(git rev-parse mb/step)"

  # Back on the build branch, mergeback fast-forwards onto the step branch.
  git checkout -q mb/build
  run "$WT" mergeback mb/step
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-forwarded"* ]]
  # Build HEAD is now exactly the step HEAD, and the prior build HEAD is an
  # ancestor (a true fast-forward, no merge commit).
  [ "$(git rev-parse HEAD)" = "$step_head" ]
  git merge-base --is-ancestor "$build_before" HEAD
}

@test "AC-2: mergeback merges a clean divergence with no editor" {
  checkout_build
  # Advance the build branch on its own file.
  echo build-side > build_side.txt
  git add build_side.txt
  git commit -qm "build advances build_side.txt"

  # Step branch diverges off the original base, touching a DIFFERENT file.
  git checkout -q -b mb/step main
  echo step-side > step_side.txt
  git add step_side.txt
  git commit -qm "step advances step_side.txt"
  local step_head
  step_head="$(git rev-parse mb/step)"

  # mergeback makes a no-editor merge commit (GIT_MERGE_AUTOEDIT=no); if an
  # editor were spawned the command would hang/fail rather than return 0 here.
  git checkout -q mb/build
  run "$WT" mergeback mb/step
  [ "$status" -eq 0 ]
  [[ "$output" == *"merged"* ]]
  [[ "$output" == *"no-edit"* ]]
  git merge-base --is-ancestor "$step_head" HEAD
  # Both sides' files are present in the merged tree.
  [ -f build_side.txt ]
  [ -f step_side.txt ]
}

@test "AC-3: mergeback conflict is aborted, leaves a clean tree, exits non-zero" {
  checkout_build
  # Build branch edits a line of shared.txt.
  printf 'line\n' > shared.txt
  git add shared.txt
  git commit -qm "build seeds shared.txt"
  printf 'build-version\n' > shared.txt
  git add shared.txt
  git commit -qm "build edits shared.txt"
  local build_head
  build_head="$(git rev-parse HEAD)"

  # Step branch edits the SAME line off the seeded version -> genuine conflict.
  git checkout -q -b mb/step HEAD~1
  printf 'step-version\n' > shared.txt
  git add shared.txt
  git commit -qm "step edits shared.txt"

  git checkout -q mb/build
  run "$WT" mergeback mb/step
  [ "$status" -ne 0 ]
  # Conflict report (on stderr) names the step branch.
  [[ "$output" == *"conflict"* ]]
  [[ "$output" == *"mb/step"* ]]
  # The abort left a clean tree: no merge in progress, no conflict markers or
  # half-applied changes (staged or unstaged), build HEAD unmoved. We assert via
  # diff rather than `status --porcelain` because the scratch repo carries an
  # untracked sibling `worktree/` from setup() that is unrelated to the merge.
  run git rev-parse --verify --quiet MERGE_HEAD
  [ "$status" -ne 0 ]
  git diff --quiet
  git diff --cached --quiet
  # No unresolved-conflict entries remain in the porcelain output.
  run git status --porcelain
  [[ "$output" != *"UU "* ]]
  [[ "$output" != *"AA "* ]]
  [ "$(git rev-parse HEAD)" = "$build_head" ]
}

@test "mergeback: no argument exits non-zero with usage" {
  checkout_build
  run "$WT" mergeback
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}

@test "mergeback: an unresolvable step-branch exits non-zero with a clear message" {
  checkout_build
  run "$WT" mergeback no/such/branch
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not resolve"* ]]
}

# --- cleanup (unit 4) ----------------------------------------------------------

@test "AC-4: cleanup reaps a prunable worktree, keeps live ones, is idempotent" {
  cd "$SCRATCH" || return 1
  # Two further worktrees under .claude/worktrees: one we will make prunable,
  # one that stays live throughout. Each gets its own branch — `main` is already
  # claimed by setup()'s simulated stale worktree, and git refuses to check out
  # the same branch in two trees.
  mkdir -p .claude/worktrees
  git worktree add -q -b wt/gone .claude/worktrees/gone main
  git worktree add -q -b wt/live .claude/worktrees/live main

  # Make the first prunable: remove its working directory out from under git.
  rm -rf .claude/worktrees/gone

  run "$WT" cleanup
  [ "$status" -eq 0 ]
  [[ "$output" == *"reaped"* ]]
  # The prunable entry is gone from git's view; the live one remains.
  run git worktree list --porcelain
  [[ "$output" != *".claude/worktrees/gone"* ]]
  [[ "$output" == *".claude/worktrees/live"* ]]
  # The live working directory still exists on disk.
  [ -d .claude/worktrees/live ]

  # Idempotent: a second run with nothing to reap still exits 0.
  run "$WT" cleanup
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to reap"* ]]
  # Still untouched the live worktree.
  run git worktree list --porcelain
  [[ "$output" == *".claude/worktrees/live"* ]]

  git worktree remove --force .claude/worktrees/live >/dev/null 2>&1 || true
}

@test "cleanup: a second argument exits non-zero with usage" {
  cd "$SCRATCH" || return 1
  # cleanup takes an optional single [<id|path>]; a second positional is invalid.
  run "$WT" cleanup target-id extra-arg
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}
