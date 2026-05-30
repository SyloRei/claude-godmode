#!/usr/bin/env bats
#
# Adversarial hook-fixture suite (US-017b).
#
# Feeds pre-tool-use.sh, pre-tool-use-secrets.sh, and post-tool-use.sh stdin
# containing quotes, newlines, backslashes, and missing fields, then asserts:
#   - the documented exit code (commit bypass -> 2, clean -> 0), and
#   - stdout is valid JSON when non-empty (piped through `jq -e .`).
#
# Each test runs in an isolated mktemp -d $HOME (US-017a harness). The secret
# hook needs a real git repo to scan a staged diff, so those tests create one
# under TEST_HOME and pass its path as the event .cwd — never relying on pwd.

load test_helper

PRE="$PLUGIN_ROOT/hooks/pre-tool-use.sh"
SECRETS="$PLUGIN_ROOT/hooks/pre-tool-use-secrets.sh"
POST="$PLUGIN_ROOT/hooks/post-tool-use.sh"
SESSION_START="$PLUGIN_ROOT/hooks/session-start.sh"

setup() {
  make_temp_home
}

teardown() {
  teardown_temp_home
}

# assert_json_or_empty lives in test_helper.bash (shared across hook suites).

# Build a temp git repo under TEST_HOME with one staged file; echo its path.
# Usage: REPO="$(make_repo_with_staged 'file contents')"
make_repo_with_staged() {
  local repo
  repo="$(mktemp -d "$TEST_HOME/repo.XXXXXX")"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name tester
  printf '%s\n' "$1" > "$repo/staged.txt"
  git -C "$repo" add staged.txt
  printf '%s' "$repo"
}

# --- pre-tool-use.sh: commit-bypass discipline ----------------------------

@test "pre-tool-use: clean git commit exits 0, JSON-or-empty" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m \"ok\""}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: --no-verify is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: short -n bypass is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -n -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: -c core.hooksPath bypass is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git -c core.hooksPath=/dev/null commit -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: -n inside a quoted commit message is NOT a bypass (exit 0)" {
  # The flag-shaped text lives inside the quoted message, so it must pass.
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m \"mention -n and --no-verify in the body\""}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: adversarial quotes/backslashes in message exit 0" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m \"has \\\"nested\\\" and \\\\ backslash\""}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: missing fields ({}) fail open (exit 0)" {
  run bash "$PRE" <<<'{}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: empty stdin fails open (exit 0)" {
  run bash "$PRE" <<<''
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: non-Bash tool passes through (exit 0)" {
  run bash "$PRE" <<<'{"tool_name":"Edit","tool_input":{}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

# --- pre-tool-use-secrets.sh: staged-diff secret scan ---------------------

@test "secrets: clean staged diff exits 0 with valid JSON" {
  local repo; repo="$(make_repo_with_staged 'just ordinary text here')"
  run bash "$SECRETS" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"$repo"}
EOF
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "secrets: staged AWS key is blocked (exit 2)" {
  local repo; repo="$(make_repo_with_staged 'aws = AKIAIOSFODNN7EXAMPLE')"
  run bash "$SECRETS" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"$repo"}
EOF
  [ "$status" -eq 2 ]
}

@test "secrets: line marker # godmode:allow-secret lets the commit pass (exit 0)" {
  local repo; repo="$(make_repo_with_staged 'aws = AKIAIOSFODNN7EXAMPLE # godmode:allow-secret')"
  run bash "$SECRETS" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"$repo"}
EOF
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "secrets: adversarial quotes/backslashes with no cwd fail open (exit 0)" {
  run bash "$SECRETS" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m \"a \\\"b\\\" \\\\ c\"}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "secrets: non-Bash tool passes through (exit 0)" {
  run bash "$SECRETS" <<<'{"tool_name":"Read"}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "secrets: missing fields ({}) pass through (exit 0)" {
  run bash "$SECRETS" <<<'{}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

# --- post-tool-use.sh: surface failed quality-gate commands ---------------

@test "post-tool-use: non-zero tracked command emits valid JSON (exit 0)" {
  # stderr carries quotes, a backslash, and a newline — must not corrupt JSON.
  run bash "$POST" <<<'{"tool_name":"Bash","tool_input":{"command":"git push"},"tool_response":{"exit_code":1,"stderr":"boom \"quoted\" \\back\nline2"}}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s' "$output" | jq -e '.systemMessage' > /dev/null
}

@test "post-tool-use: zero exit emits nothing (exit 0)" {
  run bash "$POST" <<<'{"tool_name":"Bash","tool_input":{"command":"git push"},"tool_response":{"exit_code":0}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "post-tool-use: untracked command non-zero stays quiet (exit 0)" {
  run bash "$POST" <<<'{"tool_name":"Bash","tool_input":{"command":"ls /nope"},"tool_response":{"exit_code":2}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "post-tool-use: missing fields ({}) exit 0 with no output" {
  run bash "$POST" <<<'{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "post-tool-use: non-Bash tool passes through (exit 0)" {
  run bash "$POST" <<<'{"tool_name":"Edit","tool_response":{"exit_code":1}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- session-start.sh: inject godmode rules (AC-10) -----------------------
# The hook resolves bin/godmode-rules and rules/ relative to CWD, so run from
# PLUGIN_ROOT (the repo root). make_temp_home only relocates $HOME, leaving the
# repo-relative resolution intact.

@test "session-start: emits SessionStart additionalContext with all 8 rules" {
  run bash -c "cd '$PLUGIN_ROOT' && echo '{\"hook_event_name\":\"SessionStart\"}' | bash hooks/session-start.sh"
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  # Valid JSON with the expected hook event name.
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' > /dev/null

  # Pull the injected context and assert every rule marker is present.
  local ctx
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -qF '## Identity'                                   # godmode-identity
  printf '%s' "$ctx" | grep -qF '## Quality Gates (Canonical'                   # godmode-quality
  printf '%s' "$ctx" | grep -qF '## Git Discipline'                             # godmode-git
  printf '%s' "$ctx" | grep -qF '## Lifecycle Routing'                          # godmode-routing
  printf '%s' "$ctx" | grep -qF '## Context Management'                         # godmode-context
  printf '%s' "$ctx" | grep -qF '## Auto-Detection'                            # godmode-coding
  printf '%s' "$ctx" | grep -qF '## Debugging Protocol'                         # godmode-testing
  printf '%s' "$ctx" | grep -qF '## Workflow cycle'                             # godmode-workflow
}

@test "session-start: preserves the existing workflow-spine context" {
  run bash -c "cd '$PLUGIN_ROOT' && echo '{\"hook_event_name\":\"SessionStart\"}' | bash hooks/session-start.sh"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' \
    | grep -qF 'Workflow spine:'
}
