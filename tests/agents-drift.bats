#!/usr/bin/env bats
#
# AGENTS.md drift gate (unit 2, S4 — advances AC-8).
#
# Exercises scripts/check-agents-drift.sh, which verifies the committed
# AGENTS.md matches what bin/godmode-agents --stdout regenerates. Contract:
#   - committed tree in sync     -> exit 0, prints "AGENTS.md up to date"
#   - AGENTS.md tampered (stale) -> exit non-zero, prints a regenerate hint
#
# The gate resolves COMMITTED as $REPO_ROOT/AGENTS.md (the real tracked file)
# and cannot be redirected, so the tamper case mutates AGENTS.md in place. To
# keep the working tree clean, setup saves the original bytes to a temp file
# and teardown restores them from that copy — bats runs teardown even when an
# assertion fails, so AGENTS.md is always put back. Restore is from the saved
# copy (not `git checkout`) so the test never couples to git state.

load test_helper

SCRIPT="$PLUGIN_ROOT/scripts/check-agents-drift.sh"
GENERATOR="$PLUGIN_ROOT/bin/godmode-agents"
AGENTS="$PLUGIN_ROOT/AGENTS.md"

setup() {
  AGENTS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/godmode-agents-md.XXXXXX")"
  cp "$AGENTS" "$AGENTS_BACKUP"
}

teardown() {
  if [ -n "${AGENTS_BACKUP:-}" ] && [ -f "$AGENTS_BACKUP" ]; then
    cp "$AGENTS_BACKUP" "$AGENTS"
    rm -f "$AGENTS_BACKUP"
  fi
}

@test "check-agents-drift should exit 0 when AGENTS.md matches the generator" {
  run bash -c '"$0" 2>&1' "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AGENTS.md up to date"* ]]
}

@test "check-agents-drift should exit non-zero with a drift message when AGENTS.md is tampered" {
  printf '\n%s\n' "drift-sentinel: this line is not produced by the generator" >> "$AGENTS"
  # Capture stderr too: the drift diagnostic is emitted on stderr. Assert on the
  # "drift:" prefix, which appears only in the gate's failure message and never
  # in AGENTS.md body — so this passes for the right reason, not on diff context.
  run bash -c '"$0" 2>&1' "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"drift:"* ]]
}

# --- generator correctness (AC-2 / AC-3 / AC-4) -----------------------------
# These exercise bin/godmode-agents directly via --stdout (no file mutation),
# guarding the generator's defined acceptance criteria against silent
# regressions — the drift gate alone would not catch e.g. a dropped
# description field or a non-deterministic ordering, only a stale committed
# file. They need no AGENTS.md backup since --stdout touches nothing.

@test "godmode-agents --stdout should be byte-identical across two runs (idempotent, AC-2)" {
  first="$(mktemp "${TMPDIR:-/tmp}/godmode-agents-1.XXXXXX")"
  second="$(mktemp "${TMPDIR:-/tmp}/godmode-agents-2.XXXXXX")"
  "$GENERATOR" --stdout > "$first"
  "$GENERATOR" --stdout > "$second"
  run diff "$first" "$second"
  rm -f "$first" "$second"
  [ "$status" -eq 0 ]
}

@test "godmode-agents export should carry one roster entry per agent file (AC-3)" {
  generated="$("$GENERATOR" --stdout)"
  agent_count=0
  for f in "$PLUGIN_ROOT"/agents/*.md; do
    [ -f "$f" ] || continue
    agent_count=$((agent_count + 1))
    name=$(grep -m1 '^name:' "$f" | sed -e 's/^name:[[:space:]]*//' -e 's/["'\'']//g')
    [[ "$generated" == *"$name"* ]] || { echo "roster missing agent: $name"; return 1; }
  done
  # The roster heading count must equal the number of agent files — no extras,
  # none dropped — and the count is glob-driven, not hardcoded.
  roster_headings=$(printf '%s\n' "$generated" \
    | awk '/^## Agent roster/{f=1; next} /^## Engineering rules/{f=0} f && /^### /{c++} END{print c+0}')
  [ "$roster_headings" -eq "$agent_count" ]
}

@test "godmode-agents export should embed every rule body verbatim (AC-4)" {
  generated="$("$GENERATOR" --stdout)"
  rule_count=0
  for f in "$PLUGIN_ROOT"/rules/godmode-*.md; do
    [ -f "$f" ] || continue
    rule_count=$((rule_count + 1))
    body="$(cat "$f")"
    [[ "$generated" == *"$body"* ]] || { echo "rule body not embedded verbatim: $f"; return 1; }
  done
  [ "$rule_count" -gt 0 ]
}
