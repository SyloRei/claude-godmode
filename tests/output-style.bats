#!/usr/bin/env bats
#
# Output style tests (unit 5): verify the bundled godmode-terse style file
# exists with name/description frontmatter, and that the plugin manifest
# references the outputStyles directory. Covers AC-6.

load test_helper

STYLE="$PLUGIN_ROOT/outputStyles/godmode-terse.md"

@test "godmode-terse.md style file exists" {
  [ -f "$STYLE" ]
}

@test "godmode-terse.md frontmatter has a name line" {
  run grep -E '^name:' "$STYLE"
  [ "$status" -eq 0 ]
}

@test "godmode-terse.md frontmatter has a description line" {
  run grep -E '^description:' "$STYLE"
  [ "$status" -eq 0 ]
}

@test "plugin manifest references ./outputStyles/" {
  run jq -r '.outputStyles' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [ "$output" = "./outputStyles/" ]
}
