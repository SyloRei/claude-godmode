#!/usr/bin/env bats
#
# Surface/skills tests (units 7–8): verify the consolidated command surface.
# Unit 7: the triage/profile/onboard skills must exist and explore-repo must be
# gone (folded into /onboard). Unit 8 adds three flat command files — /adr,
# /changelog, /pr-describe — bringing the surface to 16. The total must stay
# within the cap enforced by check-surface-count.sh. Guards AC-1–AC-4 (new
# skills exist, explore-repo gone), the unit 8 command additions, and AC-8
# (surface within cap, exact count pinned).

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
@test "surface count is exactly 16 when the surface is consolidated" {
  run bash "$PLUGIN_ROOT/scripts/check-surface-count.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"= 16 user-facing command(s)"* ]]
}

@test "commands/adr.md exists (unit 8 command addition)" {
  [ -f "$PLUGIN_ROOT/commands/adr.md" ]
}

@test "commands/changelog.md exists (unit 8 command addition)" {
  [ -f "$PLUGIN_ROOT/commands/changelog.md" ]
}

@test "commands/pr-describe.md exists (unit 8 command addition)" {
  [ -f "$PLUGIN_ROOT/commands/pr-describe.md" ]
}

@test "lint-frontmatter.sh exits 0 with the new command frontmatter" {
  run bash "$PLUGIN_ROOT/scripts/lint-frontmatter.sh"
  [ "$status" -eq 0 ]
}
