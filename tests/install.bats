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

# ---- Tests 7-10: adversarial-branch hook fixtures (CR-03 closure) ----
# These tests exercise the FOUND-04 / CONCERNS #6 regression class: hook JSON
# construction must not corrupt under adversarial branch names. We drive the
# canonical branch-emission path (hooks/session-start.sh:53 — `git branch
# --show-current`) via a PATH-shimmed fake git that prints the adversarial
# literal from each fixture. Then we assert the literal survives the JSON
# round-trip in `.hookSpecificOutput.additionalContext`.

# Helper: build a fake-git stub that responds to the two subcommands
# session-start.sh invokes. Returns the path to the temp dir holding the stub.
# The stub reads BRANCH_LITERAL from its environment so per-test fixtures pass
# adversarial bytes without re-creating the script.
_make_fake_git() {
  local FAKE_DIR
  FAKE_DIR="$(mktemp -d)"
  cat > "$FAKE_DIR/git" <<'STUB'
#!/usr/bin/env bash
# Minimal fake-git stub: respond only to the calls hooks/session-start.sh issues.
case "$1" in
  rev-parse)
    # session-start.sh: `git rev-parse --is-inside-work-tree > /dev/null 2>&1`
    [ "$2" = "--is-inside-work-tree" ] && exit 0
    exit 1
    ;;
  branch)
    # session-start.sh: `git branch --show-current 2>/dev/null`
    if [ "$2" = "--show-current" ]; then
      # Print the adversarial literal supplied via env. Use printf %s to avoid
      # any shell-metachar interpretation; literal newlines from $BRANCH_LITERAL
      # ARE part of the test (newline fixture decodes to a 2-line value).
      printf '%s' "${BRANCH_LITERAL:-unknown}"
      exit 0
    fi
    exit 1
    ;;
  log)
    # session-start.sh: `git log --oneline -3 2>/dev/null` — keep it empty.
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
STUB
  chmod +x "$FAKE_DIR/git"
  printf '%s' "$FAKE_DIR"
}

# Helper: run session-start.sh against an adversarial fixture and assert the
# literal survives the JSON round-trip. The fixture's `.branch_hint` field
# supplies BRANCH_LITERAL. Stdin to the hook is `{"cwd": "<TEST_CWD>"}` so the
# hook cd's into a stub project dir (with package.json, ensuring CONTEXT is
# non-empty and the jq emission path is exercised).
_run_adversarial_branch_test() {
  local FIXTURE_PATH="$1"
  [ -f "$FIXTURE_PATH" ]

  # Extract the adversarial literal from the fixture
  local BRANCH_LITERAL
  BRANCH_LITERAL=$(jq -r '.branch_hint' "$FIXTURE_PATH")
  [ -n "$BRANCH_LITERAL" ]

  # Stub project dir that triggers session-start.sh PROJECT_INFO detection
  local STUB_PROJECT
  STUB_PROJECT="$(mktemp -d)"
  echo '{}' > "$STUB_PROJECT/package.json"

  # Fake git on PATH
  local FAKE_GIT_DIR
  FAKE_GIT_DIR=$(_make_fake_git)

  # Invoke session-start.sh: stdin = {"cwd": "<STUB>"}, PATH prepends fake-git,
  # BRANCH_LITERAL exported so the stub returns the adversarial bytes.
  local INPUT_JSON
  INPUT_JSON=$(jq -n --arg cwd "$STUB_PROJECT" '{cwd: $cwd}')

  run env "PATH=$FAKE_GIT_DIR:$PATH" "BRANCH_LITERAL=$BRANCH_LITERAL" \
    bash -c "bash '$REPO_ROOT/hooks/session-start.sh'" <<< "$INPUT_JSON"

  # Cleanup before assertions (so a failed assertion still cleans up)
  rm -rf "$FAKE_GIT_DIR" "$STUB_PROJECT"

  # Hook exited cleanly
  [ "$status" -eq 0 ]

  # Output is valid JSON
  printf '%s\n' "$output" | jq -e '.' >/dev/null

  # CR-03 closure: the adversarial literal MUST round-trip into additionalContext.
  # `jq -e --arg lit "..." '.hookSpecificOutput.additionalContext | contains($lit)'`
  # exits 0 iff the JSON-decoded additionalContext value contains the literal.
  printf '%s\n' "$output" | \
    jq -e --arg lit "$BRANCH_LITERAL" \
      '.hookSpecificOutput.additionalContext | contains($lit)' >/dev/null
}

@test "hook fixture: branch name contains \" (CR-03 round-trip)" {
  _run_adversarial_branch_test "$REPO_ROOT/tests/fixtures/branches/quote.json"
}

@test "hook fixture: branch name contains \\ (CR-03 round-trip)" {
  _run_adversarial_branch_test "$REPO_ROOT/tests/fixtures/branches/backslash.json"
}

@test "hook fixture: branch name contains \\n (CR-03 round-trip)" {
  _run_adversarial_branch_test "$REPO_ROOT/tests/fixtures/branches/newline.json"
}

@test "hook fixture: branch name contains ' (CR-03 round-trip)" {
  _run_adversarial_branch_test "$REPO_ROOT/tests/fixtures/branches/apostrophe.json"
}
