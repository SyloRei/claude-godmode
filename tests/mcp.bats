#!/usr/bin/env bats
#
# MCP bundle tests (unit 4): verify the bundled .mcp.json is valid, declares
# exactly the expected npx-backed servers, and that the plugin manifest
# references it. Covers AC-7.

load test_helper

@test ".mcp.json is valid JSON" {
  run jq -e . "$PLUGIN_ROOT/.mcp.json"
  [ "$status" -eq 0 ]
}

@test ".mcp.json declares exactly context7, github, playwright servers" {
  run jq -r '.mcpServers | keys | sort | join(",")' "$PLUGIN_ROOT/.mcp.json"
  [ "$status" -eq 0 ]
  [ "$output" = "context7,github,playwright" ]
}

@test ".mcp.json context7 command is npx" {
  run jq -r '.mcpServers.context7.command' "$PLUGIN_ROOT/.mcp.json"
  [ "$status" -eq 0 ]
  [ "$output" = "npx" ]
}

@test ".mcp.json github command is npx" {
  run jq -r '.mcpServers.github.command' "$PLUGIN_ROOT/.mcp.json"
  [ "$status" -eq 0 ]
  [ "$output" = "npx" ]
}

@test ".mcp.json playwright command is npx" {
  run jq -r '.mcpServers.playwright.command' "$PLUGIN_ROOT/.mcp.json"
  [ "$status" -eq 0 ]
  [ "$output" = "npx" ]
}

@test "plugin manifest references ./.mcp.json" {
  run jq -r '.mcpServers' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [ "$output" = "./.mcp.json" ]
}
