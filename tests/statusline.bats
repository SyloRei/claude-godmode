#!/usr/bin/env bats
#
# Statusline smoke suite (US-017b).
#
# Asserts config/statusline.sh renders without error on a representative
# payload (and on a degenerate empty one), and that it uses exactly one `jq`
# invocation — the single-pass @tsv contract that keeps the statusline cheap
# to render on every assistant message.

load test_helper

STATUSLINE="$PLUGIN_ROOT/config/statusline.sh"

setup() {
  make_temp_home
}

teardown() {
  teardown_temp_home
}

@test "statusline renders without error on a representative payload" {
  run bash "$STATUSLINE" <<<'{"model":{"display_name":"Opus"},"cost":{"total_cost_usd":1.23},"context_window":{"used_percentage":42},"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # Cost is formatted to two decimals; model name is surfaced.
  [[ "$output" == *"1.23"* ]]
  [[ "$output" == *"Opus"* ]]
}

@test "statusline renders without error on an empty payload" {
  run bash "$STATUSLINE" <<<'{}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "statusline renders without error on a high-context payload" {
  run bash "$STATUSLINE" <<<'{"model":{"display_name":"Sonnet"},"cost":{"total_cost_usd":0},"context_window":{"used_percentage":85},"cwd":"/tmp"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"85%"* ]]
}

@test "statusline uses exactly one jq invocation (single-pass @tsv contract)" {
  # One `jq ` call only — multiple invocations per render are wasteful and
  # this guards the single-pass design from regressing.
  run grep -c 'jq ' "$STATUSLINE"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}
