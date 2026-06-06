#!/usr/bin/env bats
# ---------------------------------------------------------------------------
# Pins the contracts unit 3 §4b adversarial-confirmation stage stands on.
#
# Drives the SHIPPED bin/godmode-findings + bin/godmode-model and inspects
# agents/finding-skeptic.md. Does NOT execute SKILL.md prose.
#
# AC-7 (downgrade persist-integration): over-rated re-reconcile at lower
#        sev/conf leaves --blocking but the row persists in plain list.
# AC-7 (helper untouched): bin/godmode-findings is frozen (git-diff clean).
# AC-8 (agent shape): finding-skeptic.md has required frontmatter + ## Handoffs.
# AC-9 (resolver): godmode-model resolves under all 3 profiles.
#
# Bash 3.2 / bats-core v1.13.0 compatible. shellcheck-clean.
# ---------------------------------------------------------------------------

load test_helper

FINDINGS="$PLUGIN_ROOT/bin/godmode-findings"
MODEL="$PLUGIN_ROOT/bin/godmode-model"

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

setup() {
  BRIEF_DIR="$(mktemp -d "${TMPDIR:-/tmp}/verify-skeptic.XXXXXX")"
}

teardown() {
  if [ -n "${BRIEF_DIR:-}" ] && [ -d "$BRIEF_DIR" ]; then
    rm -rf "$BRIEF_DIR"
  fi
}

# ---------------------------------------------------------------------------
# Helper: write a batch file and run reconcile with stdin redirect.
#
# reconcile_batch <batchfile>
#   Runs: godmode-findings reconcile "$BRIEF_DIR" < batchfile
#   Uses "run bash -c" so bats captures exit status + stdout.
# ---------------------------------------------------------------------------
reconcile_batch() {
  local batchfile="$1"
  run bash -c '"$1" reconcile "$2" < "$3"' _ "$FINDINGS" "$BRIEF_DIR" "$batchfile"
}

# ---------------------------------------------------------------------------
# AC-7 (downgrade persist-integration): over-rated → downgrade via re-reconcile
#
# §4b contract: a finding judged REFUTED-over-rated is re-reconciled at lower
# sev/conf (not dropped). Branch 2 of reconcile refreshes sev+conf for a
# recurring identity. This test drives that full sequence on the frozen helper.
# ---------------------------------------------------------------------------

@test "AC-7 (downgrade step 1): CRITICAL/HIGH finding appears in --blocking, count=1" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch1.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "auth.ts:42" "sql injection risk" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # The finding must be new.
  printf '%s\n' "$output" | grep -qF "F1 new"

  # Must appear in --blocking.
  run "$FINDINGS" list "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "F1"

  # count --blocking must be 1.
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "AC-7 (downgrade step 2): re-reconcile same identity at WARNING/MEDIUM drops from --blocking but row persists open with refreshed sev/conf" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Step 1 — seed the CRITICAL/HIGH finding.
  local batchfile
  batchfile="$BRIEF_DIR/batch1.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "auth.ts:42" "sql injection risk" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Step 2 — re-reconcile with the SAME identity (same lens + basename + note)
  # but lower sev/conf (the over-rated downgrade action).
  local batchfile2
  batchfile2="$BRIEF_DIR/batch2.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "WARNING" "MEDIUM" "auth.ts:42" "sql injection risk" \
    > "$batchfile2"

  reconcile_batch "$batchfile2"
  [ "$status" -eq 0 ]

  # The reconcile must report 'recurring' (same identity, not a new finding).
  printf '%s\n' "$output" | grep -qF "F1 recurring"

  # count --blocking must now be 0 (no longer blocks).
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  # list --blocking must NOT show F1.
  run "$FINDINGS" list "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  if printf '%s\n' "$output" | grep -qF "F1"; then
    echo "FAIL: F1 still appears in --blocking after downgrade to WARNING/MEDIUM" >&2
    return 1
  fi

  # Plain list MUST still show the row — finding is NOT dropped, NOT closed.
  run "$FINDINGS" list "$BRIEF_DIR"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "F1"

  # Extract the F1 row and assert sev=WARNING, conf=MEDIUM (refreshed values).
  local f1_row
  f1_row=$(printf '%s\n' "$output" | grep "^| F1 ")
  [ -n "$f1_row" ]

  local f1_sev f1_conf f1_status
  f1_sev=$(printf '%s\n' "$f1_row" | cut -d'|' -f4 | tr -d ' ')
  f1_conf=$(printf '%s\n' "$f1_row" | cut -d'|' -f5 | tr -d ' ')
  f1_status=$(printf '%s\n' "$f1_row" | cut -d'|' -f6 | tr -d ' ')

  [ "$f1_sev" = "WARNING" ]
  [ "$f1_conf" = "MEDIUM" ]
  [ "$f1_status" = "open" ]
}

@test "AC-7 (drop-vs-downgrade contrast): downgraded finding persists in list; omitted finding is absent" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Seed finding A (CRITICAL/HIGH) and finding B is simply never submitted.
  local batchfile1
  batchfile1="$BRIEF_DIR/batch1.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "auth.ts:42" "sql injection risk" \
    > "$batchfile1"

  reconcile_batch "$batchfile1"
  [ "$status" -eq 0 ]

  # Re-reconcile finding A at lower sev/conf (downgrade action) — B is omitted entirely.
  local batchfile2
  batchfile2="$BRIEF_DIR/batch2.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "WARNING" "MEDIUM" "auth.ts:42" "sql injection risk" \
    > "$batchfile2"

  reconcile_batch "$batchfile2"
  [ "$status" -eq 0 ]

  # Finding A (downgraded) must still be present in plain list — persisted, not dropped.
  run "$FINDINGS" list "$BRIEF_DIR"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "auth.ts"

  # Finding B (omitted — the "drop" case) must be ABSENT from the store.
  # B's identity: code-reviewer / never submitted note.
  if printf '%s\n' "$output" | grep -qF "xss in output"; then
    echo "FAIL: omitted finding B 'xss in output' appeared in list" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC-5 (non-CRITICAL downgrade): REFUTED-over-rated on a non-CRITICAL finding
# sets conf→MEDIUM only; severity is UNCHANGED (distinct from CRITICAL branch).
#
# §4b Step 3 contract: non-CRITICAL over-rated → conf→MEDIUM, sev unchanged.
# ---------------------------------------------------------------------------

@test "AC-5 (non-CRITICAL downgrade step 1): WARNING/HIGH finding appears in --blocking, count=1" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch1.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "HIGH" "api.ts:17" "xss in output" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" | grep -qF "F1 new"

  run "$FINDINGS" list "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "F1"

  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "AC-5 (non-CRITICAL downgrade step 2): re-reconcile at WARNING/MEDIUM drops from --blocking, sev stays WARNING, conf now MEDIUM" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Seed the WARNING/HIGH finding (blocking via HIGH confidence).
  local batchfile1
  batchfile1="$BRIEF_DIR/batch1.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "HIGH" "api.ts:17" "xss in output" \
    > "$batchfile1"

  reconcile_batch "$batchfile1"
  [ "$status" -eq 0 ]

  # Re-reconcile same identity (same lens + basename + note) at WARNING/MEDIUM.
  # This is the non-CRITICAL over-rated downgrade: conf→MEDIUM, sev UNCHANGED.
  local batchfile2
  batchfile2="$BRIEF_DIR/batch2.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "api.ts:17" "xss in output" \
    > "$batchfile2"

  reconcile_batch "$batchfile2"
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" | grep -qF "F1 recurring"

  # Must no longer be blocking.
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run "$FINDINGS" list "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  if printf '%s\n' "$output" | grep -qF "F1"; then
    echo "FAIL: F1 still in --blocking after non-CRITICAL downgrade to MEDIUM conf" >&2
    return 1
  fi

  # Plain list must show F1 still present with sev=WARNING (NOT demoted to NIT).
  run "$FINDINGS" list "$BRIEF_DIR"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "F1"

  local f1_row
  f1_row=$(printf '%s\n' "$output" | grep "^| F1 ")
  [ -n "$f1_row" ]

  local f1_sev f1_conf f1_status
  f1_sev=$(printf '%s\n' "$f1_row" | cut -d'|' -f4 | tr -d ' ')
  f1_conf=$(printf '%s\n' "$f1_row" | cut -d'|' -f5 | tr -d ' ')
  f1_status=$(printf '%s\n' "$f1_row" | cut -d'|' -f6 | tr -d ' ')

  # Severity must remain WARNING — non-CRITICAL branch only touches conf.
  [ "$f1_sev" = "WARNING" ]
  # Confidence must be refreshed to MEDIUM.
  [ "$f1_conf" = "MEDIUM" ]
  [ "$f1_status" = "open" ]
}

# ---------------------------------------------------------------------------
# AC-7 (predicate boundary): a WARNING/MEDIUM finding is NOT blocking-eligible
# (neither CRITICAL nor HIGH-conf) so it must be absent from --blocking but
# present in plain list.  Pins that the --blocking predicate excludes it.
# ---------------------------------------------------------------------------

@test "AC-7 (predicate boundary): WARNING/MEDIUM finding is outside --blocking but present in plain list" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch1.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "convention-reviewer" "WARNING" "MEDIUM" "util.ts:5" "inconsistent naming" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" | grep -qF "F1 new"

  # Must NOT appear in --blocking (neither CRITICAL nor HIGH-conf).
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run "$FINDINGS" list "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  if printf '%s\n' "$output" | grep -qF "F1"; then
    echo "FAIL: WARNING/MEDIUM finding F1 incorrectly appears in --blocking" >&2
    return 1
  fi

  # Must appear in plain list — the finding was persisted.
  run "$FINDINGS" list "$BRIEF_DIR"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "F1"
}

# ---------------------------------------------------------------------------
# AC-7 (helper untouched): bin/godmode-findings must not be modified by unit 3.
# The unit-3 base is 1a8cafe; the helper is frozen — no new subcommands added.
# ---------------------------------------------------------------------------

@test "AC-7 (helper untouched): bin/godmode-findings diff against unit-3 base is empty" {
  # git diff exits non-zero when there are changes; empty diff means no changes.
  run git -C "$PLUGIN_ROOT" diff "1a8cafe26e1e85b4b541d3317bca539105342be2..HEAD" -- "bin/godmode-findings"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# AC-8 (agent shape): agents/finding-skeptic.md frontmatter and body contracts.
# ---------------------------------------------------------------------------

@test "AC-8 (agent shape): finding-skeptic.md exists and has required frontmatter fields" {
  local agent_file="$PLUGIN_ROOT/agents/finding-skeptic.md"
  [ -f "$agent_file" ]

  # Must have a non-empty model: field.
  local model_val
  model_val=$(grep -m1 '^model:' "$agent_file" | sed 's/^model:[[:space:]]*//')
  [ -n "$model_val" ]

  # Must have a non-empty effort: field.
  local effort_val
  effort_val=$(grep -m1 '^effort:' "$agent_file" | sed 's/^effort:[[:space:]]*//')
  [ -n "$effort_val" ]
}

@test "AC-8 (agent shape): disallowedTools includes both Write and Edit (read-only agent)" {
  local agent_file="$PLUGIN_ROOT/agents/finding-skeptic.md"
  [ -f "$agent_file" ]

  # The disallowedTools line must include Write.
  grep -q 'disallowedTools:' "$agent_file"
  local disallowed_line
  disallowed_line=$(grep 'disallowedTools:' "$agent_file")

  printf '%s\n' "$disallowed_line" | grep -q 'Write'
  printf '%s\n' "$disallowed_line" | grep -q 'Edit'
}

@test "AC-8 (agent shape): body contains a ## Handoffs heading" {
  local agent_file="$PLUGIN_ROOT/agents/finding-skeptic.md"
  [ -f "$agent_file" ]

  grep -q '^## Handoffs' "$agent_file"
}

# ---------------------------------------------------------------------------
# AC-9 (resolver): godmode-model resolves finding-skeptic under all 3 profiles.
# Expected values confirmed in S1:
#   quality  → "opus xhigh"
#   balanced → "sonnet high"
#   budget   → "haiku default"
# ---------------------------------------------------------------------------

@test "AC-9 (resolver quality): godmode-model finding-skeptic quality → contains opus" {
  run "$MODEL" finding-skeptic quality
  [ "$status" -eq 0 ]

  # Exactly one non-empty line.
  local line_count
  line_count=$(printf '%s\n' "$output" | grep -c '.')
  [ "$line_count" -eq 1 ]

  # Must contain "opus".
  printf '%s\n' "$output" | grep -q 'opus'

  # Exact value check: quality non-writer agent maps to "opus xhigh".
  [ "$output" = "opus xhigh" ]
}

@test "AC-9 (resolver balanced): godmode-model finding-skeptic balanced → contains sonnet" {
  run "$MODEL" finding-skeptic balanced
  [ "$status" -eq 0 ]

  # Exactly one non-empty line.
  local line_count
  line_count=$(printf '%s\n' "$output" | grep -c '.')
  [ "$line_count" -eq 1 ]

  # Must contain "sonnet".
  printf '%s\n' "$output" | grep -q 'sonnet'

  # Exact value: balanced reads frontmatter; finding-skeptic has model=sonnet, effort=high.
  [ "$output" = "sonnet high" ]
}

@test "AC-9 (resolver budget): godmode-model finding-skeptic budget → contains haiku" {
  run "$MODEL" finding-skeptic budget
  [ "$status" -eq 0 ]

  # Exactly one non-empty line.
  local line_count
  line_count=$(printf '%s\n' "$output" | grep -c '.')
  [ "$line_count" -eq 1 ]

  # Must contain "haiku".
  printf '%s\n' "$output" | grep -q 'haiku'

  # Exact value: budget always maps to "haiku default".
  [ "$output" = "haiku default" ]
}
