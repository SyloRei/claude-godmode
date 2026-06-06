#!/usr/bin/env bats
#
# Install lifecycle smoke suite (US-017b).
#
# Covers the install -> uninstall -> reinstall round trip in an isolated
# mktemp -d $HOME (via the US-017a test_helper harness — never touches the
# real ~/.claude). Asserts manual-mode install completeness (the Wave-C fix:
# bin/ + commands/ + all 8 hooks + config/quality-gates.txt) and that the
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

@test "install installs rules to the private path, not the auto-loaded global path" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]

  # Unit 3: rules must NOT land in the auto-loaded $HOME/.claude/rules/ — the
  # SessionStart hook injects them, so a global copy would double-inject.
  run sh -c 'ls "$TEST_HOME"/.claude/rules/godmode-*.md 2>/dev/null'
  [ "$status" -ne 0 ]

  # They DO land in the pinned private path the hook reads, and all 9 ship.
  [ -d "$TEST_HOME/.claude/godmode/rules" ]
  run sh -c 'ls "$TEST_HOME"/.claude/godmode/rules/godmode-*.md | wc -l | tr -d " "'
  [ "$status" -eq 0 ]
  [ "$output" = "9" ]
}

@test "install removes stale legacy godmode rules from the auto-loaded path and backs them up" {
  # Simulate a pre-unit-3 install that copied rules into the auto-loaded dir.
  mkdir -p "$TEST_HOME/.claude/rules"
  printf 'stale /plan-stories /execute\n' > "$TEST_HOME/.claude/rules/godmode-routing.md"

  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]

  # The stale auto-loaded copy is gone (it would override the hook copy).
  run sh -c 'ls "$TEST_HOME"/.claude/rules/godmode-*.md 2>/dev/null'
  [ "$status" -ne 0 ]

  # It was backed up under the install backup dir before removal.
  run sh -c 'ls "$TEST_HOME"/.claude/backups/godmode-*/rules/godmode-routing.md'
  [ "$status" -eq 0 ]

  # The now-empty legacy rules/ dir is removed.
  [ ! -d "$TEST_HOME/.claude/rules" ]
}

@test "install preserves non-godmode files in the auto-loaded rules dir" {
  # A user's own rule must survive; only godmode-*.md is reclaimed.
  mkdir -p "$TEST_HOME/.claude/rules"
  printf 'stale\n' > "$TEST_HOME/.claude/rules/godmode-routing.md"
  printf 'mine\n' > "$TEST_HOME/.claude/rules/my-own-rule.md"

  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]

  # godmode file removed, user file kept, dir retained (not empty).
  [ ! -f "$TEST_HOME/.claude/rules/godmode-routing.md" ]
  [ -f "$TEST_HOME/.claude/rules/my-own-rule.md" ]
  [ -d "$TEST_HOME/.claude/rules" ]
}

@test "install installs agents and skills" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -d "$TEST_HOME/.claude/agents" ]
  [ -d "$TEST_HOME/.claude/skills" ]
  run sh -c 'ls "$TEST_HOME"/.claude/agents/*.md'
  [ "$status" -eq 0 ]
}

@test "install installs the 19-agent roster: 3 review lenses present, retired reviewer absent" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  # The generalist reviewer was split into three single-lens reviewers.
  [ -f "$TEST_HOME/.claude/agents/perf-reviewer.md" ]
  [ -f "$TEST_HOME/.claude/agents/convention-reviewer.md" ]
  [ -f "$TEST_HOME/.claude/agents/test-reviewer.md" ]
  # Unit 6 (P2.1) added four agents to the roster.
  [ -f "$TEST_HOME/.claude/agents/debugger.md" ]
  [ -f "$TEST_HOME/.claude/agents/migration-engineer.md" ]
  [ -f "$TEST_HOME/.claude/agents/perf-engineer.md" ]
  [ -f "$TEST_HOME/.claude/agents/incident-responder.md" ]
  # Unit 3 (adversarial confirmation) added the finding-skeptic agent.
  [ -f "$TEST_HOME/.claude/agents/finding-skeptic.md" ]
  # The retired generalist agent must not ship.
  [ ! -f "$TEST_HOME/.claude/agents/reviewer.md" ]
  # Roster size is exactly 19 agents.
  run sh -c 'ls "$TEST_HOME"/.claude/agents/*.md | wc -l | tr -d " "'
  [ "$status" -eq 0 ]
  [ "$output" = "19" ]
}

@test "install installs all 8 hook scripts" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude/hooks/session-start.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/post-compact.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/pre-tool-use.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/pre-tool-use-secrets.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/post-tool-use.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/user-prompt-submit.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/session-end.sh" ]
  [ -f "$TEST_HOME/.claude/hooks/stop-ac-gate.sh" ]
  # statusline ships alongside the hooks in manual mode.
  [ -f "$TEST_HOME/.claude/hooks/statusline.sh" ]
}

@test "install installs config/quality-gates.txt (Wave-C completeness)" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude/config/quality-gates.txt" ]
}

@test "install installs bin helpers godmode-state and godmode-model (Wave-C completeness)" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude/bin/godmode-state" ]
  [ -f "$TEST_HOME/.claude/bin/godmode-model" ]
  # bin helpers must be executable.
  [ -x "$TEST_HOME/.claude/bin/godmode-state" ]
  [ -x "$TEST_HOME/.claude/bin/godmode-model" ]
}

@test "install installs commands/godmode.md (Wave-C completeness)" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude/commands/godmode.md" ]
}

@test "install installs the off-spine command files adr/changelog/pr-describe (unit 8)" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.claude/commands/adr.md" ]
  [ -f "$TEST_HOME/.claude/commands/changelog.md" ]
  [ -f "$TEST_HOME/.claude/commands/pr-describe.md" ]
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

@test "uninstall removes private godmode rules; reinstall restores them" {
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  run sh -c 'ls "$TEST_HOME"/.claude/godmode/rules/godmode-*.md'
  [ "$status" -eq 0 ]

  run bash -c 'printf "n\n" | "$1"' _ "$PLUGIN_ROOT/uninstall.sh"
  [ "$status" -eq 0 ]
  # The private rules dir is the uninstaller's removal target now.
  [ ! -d "$TEST_HOME/.claude/godmode/rules" ]

  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  run sh -c 'ls "$TEST_HOME"/.claude/godmode/rules/godmode-*.md'
  [ "$status" -eq 0 ]
}

@test "uninstall removes leftover legacy global rules and exits 0" {
  # Pre-unit-3 installs left rules in the auto-loaded $HOME/.claude/rules/.
  # uninstall must clean them up even though install no longer writes there.
  mkdir -p "$TEST_HOME/.claude/rules"
  printf 'legacy\n' > "$TEST_HOME/.claude/rules/godmode-foo.md"

  run bash -c 'printf "n\n" | "$1"' _ "$PLUGIN_ROOT/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_HOME/.claude/rules/godmode-foo.md" ]
}

@test "uninstall is idempotent: exits 0 when no godmode rules are present" {
  # Nothing installed; the guarded globs must not abort under set -euo pipefail.
  run bash -c 'printf "n\n" | "$1"' _ "$PLUGIN_ROOT/uninstall.sh"
  [ "$status" -eq 0 ]
}

@test "install targets the temp HOME, not the developer's real \$HOME/.claude" {
  # Isolation guarantee: install.sh resolves CLAUDE_DIR="$HOME/.claude", and the
  # harness points HOME at the temp dir. Prove the install actually used it and
  # could not have written to the real home.
  [ -n "$ORIG_HOME" ]                 # helper saved the real home
  [ "$HOME" = "$TEST_HOME" ]          # HOME is redirected for this test
  [ "$ORIG_HOME" != "$TEST_HOME" ]    # ...and it is genuinely different

  # Record the real ~/.claude/godmode/rules listing (if any) BEFORE install.
  before="$(ls -1 "$ORIG_HOME/.claude/godmode/rules" 2>/dev/null || true)"

  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]

  # Install populated the TEMP home (proves it honored HOME)...
  [ -d "$TEST_HOME/.claude/godmode/rules" ]
  run sh -c 'ls "$TEST_HOME"/.claude/godmode/rules/godmode-*.md'
  [ "$status" -eq 0 ]

  # ...and the real ~/.claude/godmode/rules listing is unchanged.
  after="$(ls -1 "$ORIG_HOME/.claude/godmode/rules" 2>/dev/null || true)"
  [ "$before" = "$after" ]
}

# --- M7 / FR-21: persistent install state survives a version bump -----------

@test "install marker + version under CLAUDE_PLUGIN_DATA survive a reinstall (version bump)" {
  data_dir="$TEST_HOME/.claude/plugins/data/claude-godmode"

  # First install writes the version + install marker.
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$data_dir/version" ]
  [ -f "$data_dir/installed" ]
  first_marker="$(cat "$data_dir/installed")"

  # Simulate a prior, older install by rewriting the recorded version.
  printf '0.0.1\n' > "$data_dir/version"

  # Reinstall (the "update"): the data dir persists, version is refreshed to
  # the canonical value, and the install marker is still present.
  run "$PLUGIN_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$data_dir/installed" ]
  canonical="$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  [ "$(cat "$data_dir/version")" = "$canonical" ]
  [ "$(cat "$data_dir/version")" != "0.0.1" ]
}
