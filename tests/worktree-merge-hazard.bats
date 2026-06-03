#!/usr/bin/env bats
#
# End-to-end merge-hazard reproduction for bin/godmode-worktree mergeback
# (roadmap unit 6).
#
# The audit's merge-hazard: /execute (and /build) spawn wave-sibling step
# branches that are ALL rooted at the SAME pre-merge build-branch base (the
# stale-base regime). When their work is merged back one at a time, the build
# branch advances after the first mergeback, so the second sibling's `--ff-only`
# is no longer possible. If the ladder broke there, the second wave's work would
# silently drop; if two siblings touched the SAME file divergently, a naive
# merge would leave conflict markers committed into the build branch.
#
# This file locks `mergeback`'s fast-forward -> no-edit-merge -> abort ladder
# against exactly that sequence:
#   * Case A proves an `--ff-only`-impossible second sibling still lands via the
#     `--no-edit` rung (clean, non-conflicting divergence) -> exit 0.
#   * Case B (the audit reproduction, carrying the [repro:merge-hazard] token)
#     proves a shared-file divergence reports the conflicted path, aborts, leaves
#     a clean tree (no MERGE_HEAD), and exits non-zero — so a conflict can never
#     be committed onto the build branch behind the operator's back.

load test_helper

# The helper under test, resolved via the repo's PLUGIN_ROOT convention.
WT="$PLUGIN_ROOT/bin/godmode-worktree"

# Build a scratch repo with a build branch (mh/build) one commit ahead of main,
# and capture that build branch's pre-merge HEAD as BASE — the common root both
# wave-sibling step branches will be cut from, reproducing the stale-base
# regime. The main checkout is left on mh/build for the tests to drive.
#
# Globals set for the tests:
#   SCRATCH - the scratch repo root
#   BASE    - the pre-merge build-branch HEAD (the wave-siblings' common root)
setup() {
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/godmode-mergehazard.XXXXXX")"

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

  # Build branch, one commit ahead of main. Its HEAD is the pre-merge base the
  # two wave-sibling step branches both root at.
  git checkout -q -b mh/build
  echo build-seed > build.txt
  git add build.txt
  git commit -qm "build branch seed"
  BASE="$(git rev-parse mh/build)"
}

teardown() {
  if [ -n "${SCRATCH:-}" ]; then
    rm -rf "$SCRATCH"
  fi
}

@test "AC-3: ff-impossible second sibling still lands via the no-edit rung (clean divergence)" {
  # Two wave-siblings, BOTH cut from the same pre-merge BASE.
  git checkout -q -b mh/step1 "$BASE"
  echo step-one > step1.txt
  git add step1.txt
  git commit -qm "step1 adds step1.txt"

  git checkout -q -b mh/step2 "$BASE"
  echo step-two > step2.txt
  git add step2.txt
  git commit -qm "step2 adds step2.txt"
  local step2_head
  step2_head="$(git rev-parse mh/step2)"

  # First mergeback fast-forwards the build branch onto step1 (step1 is strictly
  # ahead of BASE), advancing it past the siblings' common root.
  git checkout -q mh/build
  run "$WT" mergeback mh/step1
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-forwarded"* ]]

  # Second mergeback: the build branch has moved, so step2 is no longer strictly
  # ahead — `--ff-only` is now IMPOSSIBLE. The ladder must fall through to the
  # `--no-edit` merge rung (step2 touched a different file -> clean) and land it.
  run "$WT" mergeback mh/step2
  [ "$status" -eq 0 ]
  [[ "$output" == *"merged"* ]]
  [[ "$output" == *"no-edit"* ]]
  # Both siblings' work is present on the build branch, and step2 is an ancestor.
  git merge-base --is-ancestor "$step2_head" HEAD
  [ -f step1.txt ]
  [ -f step2.txt ]
}

@test "AC-1/AC-3: shared-file divergence is reported, aborted, leaves a clean tree, exits non-zero [repro:merge-hazard]" {
  # Two wave-siblings cut from the same pre-merge BASE, BOTH editing the SAME
  # file (shared.txt) divergently — the exact merge-hazard the audit observed.
  git checkout -q -b mh/step1 "$BASE"
  printf 'step1-version\n' > shared.txt
  git add shared.txt
  git commit -qm "step1 edits shared.txt"

  git checkout -q -b mh/step2 "$BASE"
  printf 'step2-version\n' > shared.txt
  git add shared.txt
  git commit -qm "step2 edits shared.txt"

  # First mergeback advances the build branch onto step1 (clean fast-forward off
  # BASE), so shared.txt now holds step1's version on the build branch.
  git checkout -q mh/build
  run "$WT" mergeback mh/step1
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast-forwarded"* ]]
  local build_head
  build_head="$(git rev-parse HEAD)"

  # Second mergeback: `--ff-only` impossible (build moved) AND `--no-edit` now
  # conflicts on shared.txt. The ladder must fall through to the abort rung.
  run "$WT" mergeback mh/step2
  [ "$status" -ne 0 ]
  # The structured conflict report (printed to stderr, folded into $output by
  # `run`) names the conflicted path and the step branch — the operator's only
  # signal as to WHICH file diverged.
  [[ "$output" == *"conflict"* ]]
  [[ "$output" == *"conflicted paths:"* ]]
  [[ "$output" == *"shared.txt"* ]]
  [[ "$output" == *"mh/step2"* ]]
  # The abort left a clean tree: no merge in progress, no half-applied changes
  # staged or unstaged, build HEAD unmoved (step1's mergeback result intact).
  run git rev-parse --verify --quiet MERGE_HEAD
  [ "$status" -ne 0 ]
  git diff --quiet
  git diff --cached --quiet
  run git status --porcelain
  [[ "$output" != *"UU "* ]]
  [[ "$output" != *"AA "* ]]
  [ "$(git rev-parse HEAD)" = "$build_head" ]
}
