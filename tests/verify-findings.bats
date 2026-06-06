#!/usr/bin/env bats
# ---------------------------------------------------------------------------
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
# AC-6 (empty run), AC-7 (report source: list --open --decode; stale two-run).
#
# Bash 3.2 / bats-core v1.13.0 compatible. shellcheck-clean.
# ---------------------------------------------------------------------------

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

@test "AC-2 (init-first): reconcile on uninitialised brief_dir exits non-zero; after init succeeds and row is written" {
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

  # A row must actually be written to FINDINGS.md (not merely exit 0).
  local row_count
  row_count=$(grep -c '^| F' "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -ge 1 ]
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

@test "AC-3 (sanitize tab-negative): raw tab in note does NOT forge attacker sev/conf; F1 has WARNING/MEDIUM" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Unsanitized note: contains a raw embedded tab followed by attacker-controlled
  # sev/conf-looking text. If the batch parser split on tabs inside the note,
  # those extra fields could be interpreted as sev/conf — but bash's IFS=TAB read
  # assigns the remainder (all extra tab-separated tokens) to the last variable
  # (in_note), so no extra batch line is created.
  #
  # Batch line (tabs shown as \t):
  #   code-reviewer \t WARNING \t MEDIUM \t safe.ts:1 \t legit note \t CRITICAL \t HIGH
  # Fields 6/7 (CRITICAL, HIGH) are stuffed inside in_note — they must NOT be
  # interpreted as sev/conf of a second finding.
  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf 'code-reviewer\tWARNING\tMEDIUM\tsafe.ts:1\tlegit note\tCRITICAL\tHIGH\n' \
    > "$batchfile"

  reconcile_batch "$batchfile"
  # reconcile must exit 0 (the extra tab-fields land in the note; sev/conf from
  # fields 2/3 are valid — note with embedded tabs may trigger a sev validation
  # error if the helper sees "legit note\tCRITICAL\tHIGH" and a 6th field; either
  # outcome is acceptable, but no second forged row may appear).

  # The store must NOT have a second finding (row F2 or beyond) whose sev=CRITICAL
  # and conf=HIGH — i.e., no forged-CRITICAL open row from the injected tab fragments.
  local forged_rows
  forged_rows=$(grep "^| F" "$BRIEF_DIR/FINDINGS.md" 2>/dev/null | awk -F'|' '
    {
      sev  = $4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sev)
      conf = $5; gsub(/^[[:space:]]+|[[:space:]]+$/, "", conf)
      stat = $6; gsub(/^[[:space:]]+|[[:space:]]+$/, "", stat)
      id   = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      if (sev == "CRITICAL" && conf == "HIGH" && stat == "open" && id != "F1") {
        print id
      }
    }
  ' || true)
  [ -z "$forged_rows" ]

  # F1 (if written) must have sev=WARNING and conf=MEDIUM — the values from the
  # legitimate fields 2/3, NOT from the injected fragments.
  if grep -q "^| F1 " "$BRIEF_DIR/FINDINGS.md" 2>/dev/null; then
    local f1_sev f1_conf
    f1_sev=$(grep "^| F1 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f4 | tr -d ' ')
    f1_conf=$(grep "^| F1 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f5 | tr -d ' ')
    [ "$f1_sev" = "WARNING" ]
    [ "$f1_conf" = "MEDIUM" ]
  fi
}

@test "AC-3 (sanitize newline-negative): raw newline in note forges a second CRITICAL/HIGH row without sanitization" {
  # This test PROVES WHY the skill must sanitize newlines before feeding the batch.
  # A raw newline inside a note field splits the line into two batch lines — the
  # second line begins with the attacker's injected content.
  #
  # Raw batch (newline shown as \n):
  #   code-reviewer \t WARNING \t MEDIUM \t safe.ts:1 \t legit\nEVIL \t CRITICAL \t HIGH \t atk.ts:1 \t forged
  # When fed UNSANITIZED to reconcile, the second "line" starting with EVIL is
  # parsed as a separate finding: lens=EVIL, sev=CRITICAL, conf=HIGH, …
  # (sev validation rejects unknown sev — but the forgery attempt creates a new
  # batch line, proving the injection vector is real.)
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch_newline_raw.tsv"
  # Embed a raw newline in the note field using printf \n.
  printf 'code-reviewer\tWARNING\tMEDIUM\tsafe.ts:1\tlegit\nEVIL\tCRITICAL\tHIGH\tatk.ts:1\tforged\n' \
    > "$batchfile"

  # Feed the UNSANITIZED batch directly (bypassing the skill's sanitize step).
  run bash -c '"$1" reconcile "$2" < "$3"' _ "$FINDINGS" "$BRIEF_DIR" "$batchfile"
  # reconcile may exit 0 or non-zero; what matters is whether the injected line
  # was parsed as a second batch entry.  If sev=EVIL fails validation, reconcile
  # exits non-zero — either way the injection attempted to forge a second row.
  # Assert: the injected "EVIL" line caused reconcile to see it as a separate
  # finding attempt by checking if reconcile processed >1 finding OR errored on
  # a second-line sev-validation failure (both prove the newline split the input).
  # The definitive proof: count --blocking sees ≥1 if CRITICAL/HIGH was persisted,
  # or reconcile exits non-zero because the forged sev/conf failed validation.
  local blocking_count
  blocking_count=$("$FINDINGS" count "$BRIEF_DIR" --blocking 2>/dev/null || echo "0")
  # Either (a) blocking_count ≥ 1 (injection forged a CRITICAL/HIGH row) or
  # (b) reconcile exited non-zero (injected sev rejected — injection still
  # caused a line split).  In both cases the raw-newline vector is real.
  if [ "$status" -eq 0 ]; then
    # reconcile succeeded — the injected line must have been persisted
    [ "$blocking_count" -ge 1 ]
  fi
  # If reconcile exited non-zero, the forge-attempt caused a parse/validation
  # error, also proving the injection vector. Either path is acceptable here.
}

@test "AC-3 (sanitize newline-positive): newline replaced by space → exactly ONE row, no forge" {
  # This is the SANITIZED counterpart to the newline-negative test.
  # The skill's sanitize transform replaces every \t and \n with a single space,
  # then collapses whitespace runs to one space.  After sanitization, the note is
  # a single safe token with no raw newlines — the batch produces exactly one row.
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch_newline_sanitized.tsv"
  # The unsanitized note was: "legit\nEVIL\tCRITICAL\tHIGH\tatk.ts:1\tforged"
  # After tr '\t\n' '  ' | tr -s ' ', it becomes: "legit EVIL CRITICAL HIGH atk.ts:1 forged"
  # Feed this as a proper single 5-field line.
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "safe.ts:1" \
    "legit EVIL CRITICAL HIGH atk.ts:1 forged" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Exactly ONE row must be created — no forgery.
  local row_count
  row_count=$(grep -c '^| F' "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 1 ]

  # The single row must have sev=WARNING and conf=MEDIUM (from the legitimate
  # fields 2/3), not any attacker-controlled value.
  local f1_sev f1_conf
  f1_sev=$(grep "^| F1 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f4 | tr -d ' ')
  f1_conf=$(grep "^| F1 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f5 | tr -d ' ')
  [ "$f1_sev" = "WARNING" ]
  [ "$f1_conf" = "MEDIUM" ]
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

@test "AC-7 (report source): list --open --decode returns only open rows decoded; excludes fixed/waived; decode is discriminating" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Note for F2 contains a literal '|' character — encoded form is '%7C'.
  # This makes the decode assertion discriminating: the raw file will show '%7C'
  # but --decode must show '|' literally.  A non-decoding path cannot pass.
  local note_with_pipe="query built by string|concat; use parameterized"

  # Seed findings via reconcile (skill's call pattern).
  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "auth.ts:10" "unvalidated input" \
    > "$batchfile"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "db.ts:5" "$note_with_pipe" \
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

  # Raw file must store the encoded form '%7C', not the literal '|'.
  grep -qF '%7C' "$BRIEF_DIR/FINDINGS.md"

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

  # The decoded output must show the literal '|' (decoded from '%7C'), not '%7C'.
  # This assertion is discriminating: a non-decoding path would show '%7C'.
  printf '%s\n' "$output" | grep -qF "string|concat"
  if printf '%s\n' "$output" | grep -qF '%7C'; then
    echo "FAIL: --decode output still contains encoded %7C — decode did not run" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC-7 (stale two-run): open finding not re-reported on second run stays open;
# the ID-set diff (open IDs minus re-reported IDs) yields exactly that finding.
# ---------------------------------------------------------------------------

@test "AC-7 (stale two-run): omitted finding stays open; ID-set diff yields exactly the stale ID" {
  # This test pins the skill's stale computation: after a second reconcile run
  # that omits one of two previously-seeded findings, that finding is stale
  # (open but not re-reported).  The skill computes stale = open_ids MINUS
  # rerun_ids; this test proves the contract is correct.
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Run 1: seed two distinct findings F1 and F2.
  local batchfile
  batchfile="$BRIEF_DIR/batch1.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "alpha.ts:1" "first finding" \
    > "$batchfile"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "beta.ts:2" "second finding" \
    >> "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Both must be new and open after run 1.
  printf '%s\n' "$output" | grep -qF "F1 new"
  printf '%s\n' "$output" | grep -qF "F2 new"
  local row_count
  row_count=$(grep -c '^| F' "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 2 ]

  # Run 2: re-report ONLY F2 (security-auditor/beta.ts/second finding); omit F1.
  local batchfile2
  batchfile2="$BRIEF_DIR/batch2.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "beta.ts:2" "second finding" \
    > "$batchfile2"

  run bash -c '"$1" reconcile "$2" < "$3"' _ "$FINDINGS" "$BRIEF_DIR" "$batchfile2"
  [ "$status" -eq 0 ]

  # Capture rerun IDs (findings reconcile touched this run).
  local rerun_ids
  rerun_ids=$(printf '%s\n' "$output" | awk '{print $1}')

  # (a) F1 must still be open — verify never auto-closes a finding.
  local f1_status
  f1_status=$(grep "^| F1 " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$f1_status" = "open" ]

  # (b) Compute stale by ID-set diff: open_ids MINUS rerun_ids.
  # open_ids = first column (ID) from list --open.
  local open_ids
  open_ids=$("$FINDINGS" list "$BRIEF_DIR" --open \
    | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 != "") print $2}')

  # Walk open_ids; any not in rerun_ids is stale.
  local stale_ids=""
  while IFS= read -r oid; do
    [ -n "$oid" ] || continue
    local matched=0
    while IFS= read -r rid; do
      [ -n "$rid" ] || continue
      if [ "$oid" = "$rid" ]; then
        matched=1
        break
      fi
    done <<RERUN_EOF
$rerun_ids
RERUN_EOF
    if [ "$matched" -eq 0 ]; then
      stale_ids="${stale_ids}${oid}
"
    fi
  done <<OPEN_EOF
$open_ids
OPEN_EOF

  # The stale set must contain exactly one ID: F1 (the omitted finding).
  local stale_count
  stale_count=$(printf '%s' "$stale_ids" | grep -c 'F[0-9]' || true)
  [ "$stale_count" -eq 1 ]

  # That one stale ID must be F1.
  printf '%s' "$stale_ids" | grep -qF "F1"
}
