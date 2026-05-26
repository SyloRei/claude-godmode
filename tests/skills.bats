#!/usr/bin/env bats
#
# Surface/skills tests (units 7–8, 22): verify the consolidated command surface.
# Unit 7: the triage/profile/onboard skills must exist and explore-repo must be
# gone (folded into /onboard). Unit 8 adds three flat command files — /adr,
# /changelog, /pr-describe. Unit 22 adds the /ideate spine skill, bringing the
# surface to 17 (cap 18). The total must stay within the cap enforced by
# check-surface-count.sh. Guards AC-1–AC-4 (new skills exist, explore-repo
# gone), the unit 8 command additions, /ideate's presence, and AC-8 (surface
# within cap, exact count pinned).

load test_helper

@test "skills/triage/SKILL.md exists when surface is consolidated" {
  [ -f "$PLUGIN_ROOT/skills/triage/SKILL.md" ]
}

@test "skills/profile/SKILL.md exists when surface is consolidated" {
  [ -f "$PLUGIN_ROOT/skills/profile/SKILL.md" ]
}

@test "skills/onboard/SKILL.md exists when surface is consolidated" {
  [ -f "$PLUGIN_ROOT/skills/onboard/SKILL.md" ]
}

@test "skills/ideate/SKILL.md exists when surface is consolidated" {
  [ -f "$PLUGIN_ROOT/skills/ideate/SKILL.md" ]
}

@test "skills/explore-repo does not exist when folded into onboard" {
  [ ! -e "$PLUGIN_ROOT/skills/explore-repo" ]
}

@test "check-surface-count.sh exits 0 when surface is within cap" {
  run bash "$PLUGIN_ROOT/scripts/check-surface-count.sh"
  [ "$status" -eq 0 ]
}

# Pin the exact surface count so a single accidental skill/command addition
# (which would still be <= cap, exit 0) trips this test instead of slipping
# through the gate's `-gt` check. Bump deliberately when the surface changes.
@test "surface count is exactly 18 when the surface is consolidated" {
  run bash "$PLUGIN_ROOT/scripts/check-surface-count.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"= 18 user-facing command(s)"* ]]
}

# Pin the cap value itself: the count test above stays green if someone raises
# the cap to fit a new command, so assert the boundary separately.
@test "surface cap is pinned at 19 when the surface is consolidated" {
  run grep -Eq '^CAP=19$' "$PLUGIN_ROOT/scripts/check-surface-count.sh"
  [ "$status" -eq 0 ]
}

@test "commands/adr.md exists when off-spine commands are added" {
  [ -f "$PLUGIN_ROOT/commands/adr.md" ]
}

@test "commands/changelog.md exists when off-spine commands are added" {
  [ -f "$PLUGIN_ROOT/commands/changelog.md" ]
}

@test "commands/pr-describe.md exists when off-spine commands are added" {
  [ -f "$PLUGIN_ROOT/commands/pr-describe.md" ]
}

@test "lint-frontmatter.sh exits 0 when command frontmatter is valid" {
  run bash "$PLUGIN_ROOT/scripts/lint-frontmatter.sh"
  [ "$status" -eq 0 ]
}
