#!/usr/bin/env bats
# tests/install.bats
# Smoke tests: install -> uninstall -> reinstall round-trip + adversarial-input hook fixtures
# + settings-merge regression (QUAL-07).
# Each test runs in a mktemp -d $HOME — never touches the real ~/.claude/.
# Bash 3.2 portable. Plain bats-core v1.13.0 matchers only — no external helper libs.
# CI gate (Phase 5 — QUAL-02 + QUAL-07).
# See: .planning/phases/05-quality-ci-tests-docs-parity/05-CONTEXT.md D-05..D-08, D-30, D-31.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT
  TEMP_HOME="$(mktemp -d)"
  export HOME="$TEMP_HOME"
  mkdir -p "$HOME/.claude"
}

teardown() {
  if [ -n "${TEMP_HOME:-}" ] && [ -d "$TEMP_HOME" ]; then
    rm -rf "$TEMP_HOME"
  fi
}

# ---- Test 1: fresh install ----
@test "install over fresh ~/.claude/" {
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/.claude-godmode-version" ]
  [ -d "$HOME/.claude/rules" ]
  [ -d "$HOME/.claude/agents" ]
  [ -d "$HOME/.claude/skills" ]
  [ -d "$HOME/.claude/hooks" ]
}

# ---- Test 2: install over hand-edited customizations (non-TTY default = keep) ----
@test "install over ~/.claude/ with hand-edited rules" {
  # First install
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  # Hand-edit a rule file
  RULE_FILE="$HOME/.claude/rules/godmode-routing.md"
  [ -f "$RULE_FILE" ]
  echo "# USER CUSTOMIZATION" >> "$RULE_FILE"
  CUSTOMIZED_HASH=$(grep -c "USER CUSTOMIZATION" "$RULE_FILE")
  [ "$CUSTOMIZED_HASH" -eq 1 ]
  # Reinstall — non-TTY default keeps customization (FOUND-01)
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  # Customization preserved
  CUSTOMIZED_AFTER=$(grep -c "USER CUSTOMIZATION" "$RULE_FILE")
  [ "$CUSTOMIZED_AFTER" -eq 1 ]
}

# ---- Test 3: uninstall happy path ----
@test "uninstall on installed plugin" {
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/.claude-godmode-version" ]
}

# ---- Test 4: uninstall refuses on version mismatch (no --force) ----
@test "uninstall refuses on version mismatch (no --force)" {
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  # Corrupt the version marker
  echo "0.0.1" > "$HOME/.claude/.claude-godmode-version"
  run bash "$REPO_ROOT/uninstall.sh"
  # FOUND-03: refuses to operate, exits non-zero
  [ "$status" -ne 0 ]
  # Marker preserved (refusal is non-destructive)
  [ -f "$HOME/.claude/.claude-godmode-version" ]
  # --force bypasses
  run bash "$REPO_ROOT/uninstall.sh" --force
  [ "$status" -eq 0 ]
}

# ---- Test 5: reinstall preserves customizations ----
@test "reinstall preserves customizations" {
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  AGENT_FILE="$HOME/.claude/agents/architect.md"
  [ -f "$AGENT_FILE" ]
  printf '\n## USER NOTE\nLocal addition.\n' >> "$AGENT_FILE"
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  grep -q "USER NOTE" "$AGENT_FILE"
}

# ---- Test 6: settings merge regression (QUAL-07 / D-30) ----
@test "settings merge: top-level keys not in template survive reinstall" {
  # Fresh install first
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  # Add a custom top-level key NOT in settings.template.json
  jq '. + {"customKey":"customValue","theme":"dark"}' "$HOME/.claude/settings.json" > "$HOME/.claude/settings.json.tmp"
  mv "$HOME/.claude/settings.json.tmp" "$HOME/.claude/settings.json"
  # Reinstall
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  # customKey survives (D-30)
  run jq -r '.customKey' "$HOME/.claude/settings.json"
  [ "$output" = "customValue" ]
  # theme survives
  run jq -r '.theme' "$HOME/.claude/settings.json"
  [ "$output" = "dark" ]
  # Template-injected keys also present (e.g., permissions.allow non-empty)
  run jq -r '.permissions.allow | length' "$HOME/.claude/settings.json"
  [ "$output" -gt 0 ]
  # And hooks keys present
  run jq -e '.hooks.SessionStart' "$HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
}

# ---- Tests 7-10: adversarial-branch hook fixtures ----
@test "hook fixture: branch name contains \"" {
  FIXTURE="$REPO_ROOT/tests/fixtures/branches/quote.json"
  [ -f "$FIXTURE" ]
  run bash -c "cat '$FIXTURE' | bash '$REPO_ROOT/hooks/post-compact.sh'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.' >/dev/null
}

@test "hook fixture: branch name contains \\" {
  FIXTURE="$REPO_ROOT/tests/fixtures/branches/backslash.json"
  [ -f "$FIXTURE" ]
  run bash -c "cat '$FIXTURE' | bash '$REPO_ROOT/hooks/post-compact.sh'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.' >/dev/null
}

@test "hook fixture: branch name contains \\n" {
  FIXTURE="$REPO_ROOT/tests/fixtures/branches/newline.json"
  [ -f "$FIXTURE" ]
  run bash -c "cat '$FIXTURE' | bash '$REPO_ROOT/hooks/post-compact.sh'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.' >/dev/null
}

@test "hook fixture: branch name contains '" {
  FIXTURE="$REPO_ROOT/tests/fixtures/branches/apostrophe.json"
  [ -f "$FIXTURE" ]
  run bash -c "cat '$FIXTURE' | bash '$REPO_ROOT/hooks/post-compact.sh'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '.' >/dev/null
}
