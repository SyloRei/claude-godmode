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

# --- pre-tool-use.sh: regression suite — commit-bypass scoping (AC-9) -----
# Real bypasses still blocked — new flag forms and multi-segment commands.

@test "pre-tool-use: --no-verify= attached form is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify=x -m y"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: short cluster -nv is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -nv -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: short cluster -vn is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -vn -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: bypass in later compound segment is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"make build && git commit --no-verify -m x"}}'
  [ "$status" -eq 2 ]
}

# Legitimate -n on non-commit commands — false-positive regression (AC-5/6/7).

# AC-9 redness map: of the exit-0 false-positive cases below, only
# `git log --oneline | grep -n commit` reproduces the ORIGINAL false positive —
# it is RED against the pre-segment-scoping hook (which flagged the -n in a piped
# grep as a commit bypass) and GREEN now. The other exit-0 cases are
# forward-guards (they were already green) that lock the segment scoping against
# future regressions. The exit-2 cases below are RED against the pre-R1 hook
# (verified: `&` and CR-adjacency bypasses returned 0 there) and GREEN now —
# they guard the R1 hardening, not the original false positive.

@test "pre-tool-use: grep -rn is not a bypass (exit 0)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"grep -rn PATTERN ."}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: grep -n is not a bypass (exit 0)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"grep -n PATTERN file"}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: sed -n is not a bypass (exit 0)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"sed -n 1,5p file"}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: git log piped to grep -n commit is not a bypass (exit 0)" {
  # This is the ONE case that reproduces the original false positive: red against
  # the pre-segment-scoping hook, green now (see AC-9 redness map above).
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git log --oneline | grep -n commit"}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: git log piped to grep -n is not a bypass (exit 0)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git log | grep -n x"}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: git merge --no-edit followed by clean commit is allowed (exit 0)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git merge --no-edit && git commit -m \"merge\""}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: git commit --no-edit is not a bypass (exit 0)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit --no-edit"}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

# R1 intent-regression guards (AC-8): background `&` operator and carriage-return
# adjacency. These return exit 0 (allowed) against the pre-R1 hook — proven by
# extracting hooks/pre-tool-use.sh@4e67a0b and feeding it the same payloads —
# and exit 2 (blocked) now. They guard the lone-& separator and the
# tr '\015\013\014' control-char normalization added in R1.

@test "pre-tool-use: bypass after background & operator is blocked (exit 2)" {
  # `x & git commit --no-verify` — the `&` backgrounds `x`, leaving a genuine
  # commit segment that must still be scanned (red against pre-R1: returned 0).
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"x & git commit --no-verify -m m"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: short -n after background & operator is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"sleep 1 & git commit -n -m m"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: carriage-return adjacency cannot dodge the commit check (exit 2)" {
  # A real CR byte glued to `commit` (git<CR>commit) would split the subcommand
  # token before R1's tr normalization. JSON requires the CR be escaped as \r;
  # built via printf (a literal CR inside a here-string is awkward and would be
  # invalid JSON). jq decodes the \r escape to a real CR, which the hook's
  # tr '\015\013\014' maps to a space so `commit` is still recognized and the
  # --no-verify is blocked. Red against pre-R1 (returned 0).
  run bash -c 'printf %s "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git \\rcommit --no-verify -m m\"}}" | bash "'"$PRE"'"'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: hooksPath bypass in a later compound segment is blocked (exit 2)" {
  # AC-8 forward coverage: the test-reviewer noted later-segment coverage only
  # exercised --no-verify, not the -c core.hooksPath form. (Already green on
  # pre-R1; this locks the segment scoping for hooksPath specifically.)
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"make build && git -c core.hooksPath=/dev/null commit -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: quoted shell separators and bypass token in message are allowed (exit 0)" {
  # The message contains both `&&` and `--no-verify`, but quoted: the quote-strip
  # removes the message content before segment splitting, so it neither splits
  # the segment nor trips the bypass guard.
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m \"msg with && --no-verify\""}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

# R3 regression guards (AC-1, AC-2, AC-3, AC-9, AC-10): close two false-NEGATIVE
# holes found by /verify 3.
#
# Gap 1 (separate-value git globals): --git-dir / --work-tree (and --namespace,
# --super-prefix) take a SEPARATE value token. Before R3 the subcommand scan only
# consumed -c/-C values, so the global's value was read as the subcommand, the
# segment was misclassified as non-commit, and the bypass scan never ran. These
# exit-2 cases are RED against the pre-R3 hook (verified: it returns 0 there) and
# GREEN after R3.
#
# Gap 2 (quoted -c hooksPath): the global quote-strip erased the quoted -c value,
# so -c then consumed `commit` as its value and the segment was misclassified.
# R3 adds a RAW pre-check scoped to the pre-subcommand global region. The quoted
# bypass cases below are RED pre-R3 (returned 0) and GREEN after; the legit
# message-mentioning-hooksPath case proves the fix introduces no new false
# positive (it stays exit 0, since `commit` precedes the word).

@test "pre-tool-use: separate-value --git-dir then --no-verify is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git --git-dir /tmp commit --no-verify -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: separate-value --work-tree then -n is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git --work-tree /tmp commit -n -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: separate-value --git-dir with -nv cluster is blocked (exit 2)" {
  # Separate-value global + short cluster containing n.
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git --git-dir /tmp commit -nv -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: separate-value global bypass in later compound segment is blocked (exit 2)" {
  # Gap-1 regression must also hold when the commit sits in a later segment (AC-8).
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"make build && git --git-dir /tmp commit --no-verify -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: single-quoted -c hooksPath bypass is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git -c '\''core.hooksPath=/dev/null'\'' commit -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: double-quoted -c hooksPath bypass is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git -c \"core.hooksPath=/dev/null\" commit -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: the word hooksPath inside a commit message is allowed (exit 0)" {
  # No new false positive: `commit` precedes the word, so it is outside the
  # pre-subcommand global region the Gap-2 RAW check inspects (AC-4 family).
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix hooksPath bug in the message\""}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: legit separate-value --git-dir on a clean commit is allowed (exit 0)" {
  # The separate-value-global consume must not itself flag a clean commit.
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git --git-dir /tmp commit -m \"clean\""}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

# R4 regression guards (AC-1, AC-3, AC-8, AC-10): close a false-POSITIVE
# regression and four false-NEGATIVE bypass holes found by /verify 3.
#
# Regression (CRITICAL): the R3 RAW pre-check used `${COMMAND%% commit*}`, which
# returns the WHOLE command when there is no ` commit` token, so a NON-commit
# `git -c core.hooksPath=x …` was wrongly blocked. R4 replaces it with a
# per-RAW-segment global-region check scoped to genuine `git commit` segments,
# so the cases below stay exit 0. These are RED against the pre-R4 hook
# (returned 2 there) and GREEN after.

@test "pre-tool-use: -c hooksPath on a non-commit git log is allowed (exit 0)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git -c core.hooksPath=x log --oneline"}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: -c hooksPath on a non-commit git status is allowed (exit 0)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git -c core.hooksPath=x status"}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: -c hooksPath on a non-commit git fetch is allowed (exit 0)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git -c core.hooksPath=x fetch origin"}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: -c hooksPath on a non-commit pipeline ending in grep commit is allowed (exit 0)" {
  # A non-commit pipeline whose LATER segment merely contains the word `commit`
  # must not be flagged — the naive `*\" commit\"*` guard would wrongly fire here.
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git -c core.hooksPath=x diff | grep commit"}}'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

# Bypass holes the R4 classifier now closes (each RED against pre-R4: returned 0).

@test "pre-tool-use: subshell ( git commit --no-verify ) is blocked (exit 2)" {
  # The segment's first token is `(`/`( git`; the classifier strips leading
  # grouping openers so the inner commit is still recognized.
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"( git commit --no-verify )"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: command-substitution \$(git commit --no-verify) is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"$(git commit --no-verify -m x)"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: redirect-prefixed >f git commit --no-verify is blocked (exit 2)" {
  # A leading redirection token is valid shell; the commit still runs, so the
  # classifier must skip the redirect token to find `git`.
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":">f git commit --no-verify -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: fd-redirect-prefixed 2>/tmp/x git commit -n is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"2>/tmp/x git commit -n -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: backslash-newline continuation joins git \\ commit --no-verify (exit 2)" {
  # `git \<newline>commit --no-verify` is ONE command to bash; the newline is a
  # CONTINUATION, not a segment separator. The \n arrives JSON-escaped, so build
  # the payload with printf (like the carriage-return test above). The hook
  # folds the backslash-newline back to a space, so `commit` is recognized.
  run bash -c 'printf %s "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git \\\\\\ncommit --no-verify -m m\"}}" | bash "'"$PRE"'"'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: a bare newline still separates segments, not a continuation (exit 0)" {
  # `git commit -m x<newline>git log` — the newline is a real separator (no
  # preceding backslash), so the segments do not join; neither carries a bypass.
  run bash -c 'printf %s "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\\ngit log\"}}" | bash "'"$PRE"'"'
  [ "$status" -eq 0 ]
  assert_json_or_empty
}

@test "pre-tool-use: mixed-case -c core.HooksPath bypass is blocked (exit 2)" {
  # Git config keys are case-insensitive, so HooksPath disables hooks identically.
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git -c core.HooksPath=/dev/null commit -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: upper-case -c core.HOOKSPATH bypass is blocked (exit 2)" {
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git -c core.HOOKSPATH=/dev/null commit -m x"}}'
  [ "$status" -eq 2 ]
}

@test "pre-tool-use: unquoted message word fix-hooksPath-bug is allowed (exit 2->0)" {
  # The over-broad R3 per-segment `*hooksPath*` test fired on a plain message
  # word; R4 scopes the hooksPath check to -c/-C global tokens, so an UNQUOTED
  # message word no longer trips it.
  run bash "$PRE" <<<'{"tool_name":"Bash","tool_input":{"command":"git commit -m fix-hooksPath-bug"}}'
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
