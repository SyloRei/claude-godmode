#!/usr/bin/env bats
#
# LSP bundle tests (unit 3): verify the bundled .lsp.json is valid, declares
# exactly the expected language servers with their correct commands and
# extension mappings, and that the plugin manifest references it. Covers AC-7.

load test_helper

@test ".lsp.json is valid JSON" {
  run jq -e . "$PLUGIN_ROOT/.lsp.json"
  [ "$status" -eq 0 ]
}

@test ".lsp.json declares exactly pyright and typescript servers" {
  run jq -r 'keys | sort | join(",")' "$PLUGIN_ROOT/.lsp.json"
  [ "$status" -eq 0 ]
  [ "$output" = "pyright,typescript" ]
}

@test ".lsp.json typescript command is typescript-language-server" {
  run jq -r '.typescript.command' "$PLUGIN_ROOT/.lsp.json"
  [ "$status" -eq 0 ]
  [ "$output" = "typescript-language-server" ]
}

@test ".lsp.json pyright command is pyright-langserver" {
  run jq -r '.pyright.command' "$PLUGIN_ROOT/.lsp.json"
  [ "$status" -eq 0 ]
  [ "$output" = "pyright-langserver" ]
}

@test ".lsp.json typescript has a non-empty extensionToLanguage map" {
  run jq -e '.typescript.extensionToLanguage | length > 0' "$PLUGIN_ROOT/.lsp.json"
  [ "$status" -eq 0 ]
}

@test ".lsp.json pyright has a non-empty extensionToLanguage map" {
  run jq -e '.pyright.extensionToLanguage | length > 0' "$PLUGIN_ROOT/.lsp.json"
  [ "$status" -eq 0 ]
}

@test "plugin manifest references ./.lsp.json" {
  run jq -r '.lspServers' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [ "$output" = "./.lsp.json" ]
}
