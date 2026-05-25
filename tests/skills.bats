#!/usr/bin/env bats
#
# Surface/skills tests (unit 7): verify the post-consolidation skill surface.
# The triage/profile/onboard skills must exist, explore-repo must be gone
# (folded into /onboard), and the total command surface must stay within the
# cap enforced by check-surface-count.sh. Covers AC-8.

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
