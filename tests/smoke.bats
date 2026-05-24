#!/usr/bin/env bats
#
# Smoke tests: prove the bats harness runs and a couple of real repo
# invariants hold. This is the scaffold (US-017a); US-017b adds the
# install/uninstall/adversarial-hook/statusline suites on top of
# test_helper.bash.

load test_helper

@test "harness runs" {
  true
}

@test "plugin manifest exists" {
  [ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]
}

@test "plugin manifest declares a non-empty version" {
  run jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" != "null" ]
}
