#!/usr/bin/env bats
#
# Install lifecycle smoke suite (US-017b).
#
# Covers the install -> uninstall -> reinstall round trip in an isolated
# mktemp -d $HOME (via the US-017a test_helper harness — never touches the
# real ~/.claude). Asserts manual-mode install completeness (the Wave-C fix:
# bin/ + commands/ + all 7 hooks + config/quality-gates.txt) and that the
# settings.json hook merge is idempotent across reinstalls (no duplicate
# entries).
#
# install.sh preflight requires $HOME/.claude to exist, so setup creates it.
# uninstall.sh prompts "Restore settings.json from backup? [y/N]" when a
# backup exists; install.sh always makes one, so the round-trip pipes "n".

load test_helper

setup() {
  make_temp_home
  # install.sh preflight: $HOME/.claude must already exist.
  mkdir -p "$TEST_HOME/.claude"
}

teardown() {
  teardown_temp_home
}

# --- First install: completeness ------------------------------------------

@test "install.sh exits 0 on a fresh \$HOME/.claude" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
}

@test "install installs godmode rules" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -d "$TEST_HOME/.claude/rules" ]
  # At least one godmode-*.md rule landed.
  run sh -c 'ls "$TEST_HOME"/.claude/rules/godmode-*.md'
  [ "$status" -eq 0 ]
}

@test "install installs agents and skills" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -d "$TEST_HOME/.claude/agents" ]
  [ -d "$TEST_HOME/.claude/skills" ]
  run sh -c 'ls "$TEST_HOME"/.claude/agents/*.md'
  [ "$status" -eq 0 ]
}

@test "install installs all 7 hook scripts" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude/hooks/session-start.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/post-compact.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/pre-tool-use.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/pre-tool-use-secrets.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/post-tool-use.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/user-prompt-submit.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/session-end.sh" ]
  # statusline ships alongside the hooks in manual mode.
  [ -f "$TEST_HOME/.claude/hooks/statusline.sh" ]
}

@test "install installs config/quality-gates.txt (Wave-C completeness)" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude/config/quality-gates.txt" ]
}

@test "install installs bin helpers godmode-state and godmode-hash-rules (Wave-C completeness)" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude/bin/godmode-state" ]
  [ -f "$TEST_HOME/.claude/bin/godmode-hash-rules" ]
  # bin helpers must be executable.
  [ -x "$TEST_HOME/.claude/bin/godmode-state" ]
  [ -x "$TEST_HOME/.claude/bin/godmode-hash-rules" ]
}

@test "install installs commands/godmode.md (Wave-C completeness)" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude/commands/godmode.md" ]
}

@test "install writes a valid settings.json with a hooks block" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude/settings.json" ]
  run jq -e '.hooks' "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
}

# --- Idempotency: reinstall must not duplicate hook entries ---------------

@test "reinstall is idempotent: hook entry counts do not grow" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]

  # Capture per-event hook entry counts after the first install.
  before="$(jq -S '.hooks | map_values(length)' "$TEST_HOME/.claude/settings.json")"

  # Reinstall on top of the existing settings.json.
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]

  after="$(jq -S '.hooks | map_values(length)' "$TEST_HOME/.claude/settings.json")"

  # The `unique` in install.sh's merge must keep counts identical.
  [ "$before" = "$after" ]
}

@test "reinstall is idempotent: permissions.allow does not duplicate" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  before="$(jq '.permissions.allow | length' "$TEST_HOME/.claude/settings.json")"

  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  after="$(jq '.permissions.allow | length' "$TEST_HOME/.claude/settings.json")"

  [ "$before" = "$after" ]
  # And every entry remains unique.
  run jq -e '.permissions.allow | (length == (unique | length))' \
    "$TEST_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
}

# --- Full round trip: install -> uninstall -> reinstall -------------------

@test "install -> uninstall -> reinstall round trip all exit 0" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]

  # uninstall.sh prompts to restore settings.json from backup; answer "n".
  run bash -c 'printf "n\n" | "$1"' _ "$PLUGIN_ROOT/uninstall.sh"
  [ "$status" -eq 0 ]

  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
}

@test "uninstall removes godmode rules; reinstall restores them" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  run sh -c 'ls "$TEST_HOME"/.claude/rules/godmode-*.md'
  [ "$status" -eq 0 ]

  run bash -c 'printf "n\n" | "$1"' _ "$PLUGIN_ROOT/uninstall.sh"
  [ "$status" -eq 0 ]
  # Rules are the uninstaller's documented removal target.
  run sh -c 'ls "$TEST_HOME"/.claude/rules/godmode-*.md 2>/dev/null'
  [ "$status" -ne 0 ]

  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  run sh -c 'ls "$TEST_HOME"/.claude/rules/godmode-*.md'
  [ "$status" -eq 0 ]
}

@test "tests never touch the real \$HOME/.claude" {
  # HOME is the temp dir for the whole test, so install.sh's CLAUDE_DIR
  # resolves under TEST_HOME, not the developer's real home.
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  case "$TEST_HOME" in
    "${TMPDIR:-/tmp}"*|/tmp/*|/var/folders/*) : ;;
    *) printf 'TEST_HOME is not under a temp root: %s\n' "$TEST_HOME" >&2; return 1 ;;
  esac
}
