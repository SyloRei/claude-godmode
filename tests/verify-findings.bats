#!/usr/bin/env bats
# Encodes the call contract that skills/verify/SKILL.md §4 must emit (unit 2).
#
# Pins the exact sequence /verify will call on bin/godmode-findings:
#   1. godmode-findings init <brief_dir>           (idempotent, unconditional)
#   2. build a TAB-delimited batch (5-field lines:
#        lens <TAB> sev <TAB> conf <TAB> location <TAB> note)
#      write to a temp file, redirect into:
#        godmode-findings reconcile <brief_dir> < batchfile
#   3. godmode-findings list <brief_dir> --open --decode   (report source)
#
# AC-2 (init-first), AC-3 (sanitize/no-forge), AC-4 (never-auto-close),
# AC-5 (four-way identity: new/recurring/reopened/waived-kept),
# AC-6 (empty run), AC-7 (report source: list --open --decode).
#
# Bash 3.2 / bats-core 1.13.0 compatible. shellcheck-clean.

load test_helper

FINDINGS="$PLUGIN_ROOT/bin/godmode-findings"

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

setup() {
  BRIEF_DIR="$(mktemp -d "${TMPDIR:-/tmp}/verify-findings.XXXXXX")"
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
# AC-2 (init-first): reconcile without init exits non-zero; after init it succeeds.
# ---------------------------------------------------------------------------

@test "AC-2 (init-first): reconcile on uninitialised brief_dir exits non-zero; after init succeeds" {
  # BRIEF_DIR exists but has no FINDINGS.md — reconcile must refuse.
  local batchfile
  batchfile="$BRIEF_DIR/batch1.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "foo.ts:1" "missing check" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -ne 0 ]

  # After init, reconcile of the same batch must succeed.
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-2 / AC-5 (identity / four-way via the skill's batch shape)
# ---------------------------------------------------------------------------

@test "AC-2/AC-5 (new): first batch of 2 distinct findings → each outcome 'new', IDs F1/F2, 2 open rows" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "auth.ts:10" "unvalidated input" \
    > "$batchfile"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "db.ts:5" "sql injection risk" \
    >> "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Both outcomes must be 'new'.
  printf '%s\n' "$output" | grep -qF "F1 new"
  printf '%s\n' "$output" | grep -qF "F2 new"

  # FINDINGS.md must have exactly 2 open rows.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 2 ]

  local f1_status f2_status
  f1_status=$(grep "^| F1 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  f2_status=$(grep "^| F2 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$f1_status" = "open" ]
  [ "$f2_status" = "open" ]
}

@test "AC-2/AC-5 (recurring): re-run identical batch → each outcome 'recurring', same IDs, no new rows" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "auth.ts:10" "unvalidated input" \
    > "$batchfile"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "db.ts:5" "sql injection risk" \
    >> "$batchfile"

  # First run — seeds F1, F2.
  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Second run of identical batch → recurring.
  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" | grep -qF "F1 recurring"
  printf '%s\n' "$output" | grep -qF "F2 recurring"

  # No new rows — still exactly 2.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 2 ]
}

@test "AC-2/AC-5 (line-drift): same lens+file+note with different line number → 'recurring', same ID" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "auth.ts:10" "unvalidated input" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]
  local first_id
  first_id=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')

  # Re-run with SHIFTED line number only — identity (lens+basename+note) unchanged.
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "auth.ts:99" "unvalidated input" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Must be 'recurring' with the SAME id.
  printf '%s\n' "$output" | grep -qF "${first_id} recurring"

  # Still exactly 1 row.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 1 ]
}

@test "AC-2/AC-5 (changed note = new identity): same location but different note → 'new' with a different ID" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "auth.ts:10" "unvalidated input" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]
  local first_id
  first_id=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')

  # DIFFERENT note at the same location → different identity → new ID.
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "auth.ts:10" "missing null check" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" | grep -qF " new"
  local second_id
  second_id=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')
  [ "$second_id" != "$first_id" ]

  # Two rows total.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 2 ]
}

@test "AC-2/AC-5 (reopened): transition finding to fixed, re-report it in batch → 'reopened'" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "api.ts:20" "error not handled" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]
  local fid
  fid=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')

  # Mark it fixed.
  run "$FINDINGS" transition "$BRIEF_DIR" "$fid" fixed
  [ "$status" -eq 0 ]

  # Re-report the same finding → must be 'reopened'.
  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" | grep -qF "${fid} reopened"

  # Status must now be open again.
  local row_status
  row_status=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$row_status" = "open" ]
}

@test "AC-2/AC-5 (waived-kept): waive a finding, re-report it in batch → 'waived-kept', stays waived" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "WARNING" "LOW" "config.ts:3" "debug flag enabled" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]
  local fid
  fid=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')

  # Waive it.
  run "$FINDINGS" waive "$BRIEF_DIR" "$fid" "intentional for dev only"
  [ "$status" -eq 0 ]

  # Re-report the same finding → must be 'waived-kept'.
  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" | grep -qF "${fid} waived-kept"

  # Status must remain waived.
  local row_status
  row_status=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$row_status" = "waived" ]
}

# ---------------------------------------------------------------------------
# AC-3 (sanitize / no-forge)
# POSITIVE: pre-sanitised note (no raw tabs/newlines) → exactly ONE row, correct field count.
# NEGATIVE: raw tab inside note → does NOT forge an extra finding with attacker sev/conf.
# ---------------------------------------------------------------------------

@test "AC-3 (sanitize positive): pre-sanitised note → exactly 1 row with correct 11-field count" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Note has had its tabs and newlines replaced with single spaces (pre-sanitized).
  # Whitespace collapsed. This is what the skill must produce before feeding the batch.
  local sanitised_note="sql concat detected replace with parameterized query see line 5"

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "db.ts:5" "$sanitised_note" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" | grep -qF " new"
  local fid
  fid=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')

  # Exactly ONE data row.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 1 ]

  # The row must split into exactly 11 pipe-delimited fields (9 data columns
  # + leading/trailing empty = 11 awk -F'|' fields).
  local field_count
  field_count=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | awk -F'|' '{print NF}')
  [ "$field_count" -eq 11 ]
}

@test "AC-3 (sanitize negative): raw tab in note does NOT forge extra finding with attacker sev/conf" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Unsanitized note: the note contains a raw embedded tab followed by
  # text that looks like sev/conf values. If the batch parser split on tabs
  # from within the note, these could be interpreted as new fields — but
  # bash's read assigns the remainder to the last variable, so no extra batch
  # line is created. The store must have AT MOST 1 finding and must NOT have a
  # second finding whose sev/conf match the attacker's tab-injected fragment.
  #
  # Batch line (tabs shown as \t):
  #   code-reviewer \t WARNING \t MEDIUM \t safe.ts:1 \t legit note \t CRITICAL \t HIGH
  # The 6th and 7th fields (CRITICAL, HIGH) are embedded inside the note variable.
  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  # Use printf with an explicit tab character to embed a raw tab in the note field.
  printf 'code-reviewer\tWARNING\tMEDIUM\tsafe.ts:1\tlegit note\tCRITICAL\tHIGH\n' \
    > "$batchfile"

  reconcile_batch "$batchfile"
  # reconcile may succeed or fail; what matters is the integrity assertion below.
  # (With bash read and IFS=TAB, the 5th+ fields collapse into in_note, so
  # reconcile gets note="legit note\tCRITICAL\tHIGH" which may fail or succeed
  # depending on sev/conf validation — the stored sev/conf come from fields 2/3.)

  # The store must NOT have a second finding (row F2 or beyond) whose sev=CRITICAL
  # and conf=HIGH that was created from the injected tab fragments.
  # Assert: if there IS a second row, it does not have the attacker-controlled
  # sev (CRITICAL) and conf (HIGH) together — i.e., no forged-CRITICAL open row
  # was silently created from the note's tab-split fragments.
  local forged_rows
  forged_rows=$(grep "^| F" "$BRIEF_DIR/FINDINGS.md" | awk -F'|' '
    {
      sev  = $4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sev)
      conf = $5; gsub(/^[[:space:]]+|[[:space:]]+$/, "", conf)
      stat = $6; gsub(/^[[:space:]]+|[[:space:]]+$/, "", stat)
      id   = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      # Look for rows that appear to be forged: CRITICAL+HIGH but NOT F1
      # (F1 was legitimately created for the real batch line, though its
      # sev=WARNING/MEDIUM since those came from fields 2/3, not the note)
      if (sev == "CRITICAL" && conf == "HIGH" && stat == "open" && id != "F1") {
        print id
      }
    }
  ')
  [ -z "$forged_rows" ]

  # Also assert: F1 (if it exists) has sev=WARNING and conf=MEDIUM — the
  # values from the legitimate fields 2/3, NOT from the injected fragments.
  if grep -q "^| F1 " "$BRIEF_DIR/FINDINGS.md"; then
    local f1_sev f1_conf
    f1_sev=$(grep "^| F1 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f4 | tr -d ' ')
    f1_conf=$(grep "^| F1 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f5 | tr -d ' ')
    [ "$f1_sev" = "WARNING" ]
    [ "$f1_conf" = "MEDIUM" ]
  fi
}

# ---------------------------------------------------------------------------
# AC-4 / AC-6 (never-auto-close / empty run)
# Persist 2 findings; reconcile with EMPTY stdin → exit 0, store intact.
# ---------------------------------------------------------------------------

@test "AC-4/AC-6 (never-auto-close): empty batch leaves prior open findings untouched" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Seed 2 open findings via the skill's batch pattern.
  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "a.ts:1" "first finding" \
    > "$batchfile"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "b.ts:2" "second finding" \
    >> "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Verify 2 open rows exist.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 2 ]

  # Now reconcile an EMPTY batch (zero lines).
  local empty_batch
  empty_batch="$BRIEF_DIR/empty.tsv"
  : > "$empty_batch"

  run bash -c '"$1" reconcile "$2" < "$3"' _ "$FINDINGS" "$BRIEF_DIR" "$empty_batch"
  [ "$status" -eq 0 ]

  # Store must not be wiped — still 2 rows.
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 2 ]

  # Both rows must still be open.
  local f1_status f2_status
  f1_status=$(grep "^| F1 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  f2_status=$(grep "^| F2 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$f1_status" = "open" ]
  [ "$f2_status" = "open" ]
}

# ---------------------------------------------------------------------------
# AC-7 (report source): list --open --decode returns only open rows, decoded.
# Fixed and waived rows are excluded. This is what /verify §4 section (b) renders from.
# ---------------------------------------------------------------------------

@test "AC-7 (report source): list --open --decode returns only open rows decoded; excludes fixed/waived" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Seed findings via reconcile (skill's call pattern).
  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "auth.ts:10" "unvalidated input" \
    > "$batchfile"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "db.ts:5" "sql injection risk" \
    >> "$batchfile"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "perf-reviewer" "NIT" "LOW" "loop.ts:77" "minor allocation" \
    >> "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # F1=code-reviewer/WARNING/MEDIUM → transition to fixed.
  run "$FINDINGS" transition "$BRIEF_DIR" "F1" fixed
  [ "$status" -eq 0 ]

  # F3=perf-reviewer/NIT/LOW → waive.
  run "$FINDINGS" waive "$BRIEF_DIR" "F3" "noise threshold"
  [ "$status" -eq 0 ]

  # F2=security-auditor/CRITICAL/HIGH → remains open.

  # list --open --decode — this is the exact command /verify uses to render §4(b).
  run "$FINDINGS" list "$BRIEF_DIR" --open --decode
  [ "$status" -eq 0 ]

  # F2 (open) must appear.
  printf '%s\n' "$output" | grep -qF "| F2 |"

  # F1 (fixed) must NOT appear.
  if printf '%s\n' "$output" | grep -qF "| F1 |"; then
    echo "FAIL: fixed finding F1 appeared in --open --decode output" >&2
    return 1
  fi

  # F3 (waived) must NOT appear.
  if printf '%s\n' "$output" | grep -qF "| F3 |"; then
    echo "FAIL: waived finding F3 appeared in --open --decode output" >&2
    return 1
  fi

  # The open row must be decoded — human-readable text, not encoded.
  # 'sql injection risk' must appear literally (the note was plain ASCII, no encoding needed,
  # but the decode path must be exercised; verify the note appears verbatim).
  printf '%s\n' "$output" | grep -qF "sql injection risk"
}
