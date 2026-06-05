#!/usr/bin/env bats
#
# Test suite for bin/godmode-findings (unit 1 S3–S6).
#
# Covers: AC-2 (init/idempotent), AC-3 (monotonic IDs + waive-then-add),
#         AC-4 (note round-trip), AC-5 (transition + unknown-ID error),
#         AC-6 (waive + empty-reason error),
#         AC-7 (reconcile identity stable across line drift),
#         AC-8 (four-way reconcile branch + absent-key untouched),
#         AC-9 (--blocking predicate + bare count), AC-10 (atomic writes / no residue),
#         AC-12 (location encoding — pipe/newline injection; reconcile positive + rejection),
#         AC-13 (identity-by-construction: mkey stored, note immutable, reason column;
#                 Edge A / Edge B correctness),
#         AC-14 (sev enum {CRITICAL,WARNING,NIT} + conf enum {HIGH,MEDIUM,LOW};
#                 out-of-enum values rejected on add AND reconcile).
#
# Schema: 9 data columns (ID|lens|sev|conf|status|location|note|mkey|reason),
# so raw rows split into 11 awk -F'|' fields (leading + trailing empty fields).
# Default list output remains 7 display columns (mkey/reason are internal).
#
# Ordered riskiest first: AC-4, AC-7, AC-8 before the simpler structural tests.
#
# Each test is hermetic: a fresh BRIEF_DIR is created in setup() and removed in
# teardown().  Tests never share state.
#
# Bash 3.2 / bats-core v1.13.0 compatible.

load test_helper

FINDINGS="$PLUGIN_ROOT/bin/godmode-findings"

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

setup() {
  BRIEF_DIR="$(mktemp -d "${TMPDIR:-/tmp}/godmode-findings.XXXXXX")"
}

teardown() {
  if [ -n "${BRIEF_DIR:-}" ] && [ -d "$BRIEF_DIR" ]; then
    rm -rf "$BRIEF_DIR"
  fi
}

# ---------------------------------------------------------------------------
# AC-4: note round-trip — literal %, |, and embedded newline
# This is the riskiest case: if encoding/decoding is wrong all table logic
# breaks.  Run it first so a failure localises immediately.
# ---------------------------------------------------------------------------

@test "AC-4: note containing %, |, and embedded newline survives add/list --decode byte-for-byte" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Note contains: literal %, literal |, embedded newline.
  local tricky_note
  tricky_note=$'a%b|c\nsecond line'

  run "$FINDINGS" add "$BRIEF_DIR" "security" "CRITICAL" "HIGH" "foo.ts:10" "$tricky_note"
  [ "$status" -eq 0 ]
  local fid="$output"

  # Raw FINDINGS.md must NOT contain a literal | inside the note cell
  # (the only | chars should be the column delimiters) and must not contain
  # a raw newline inside the note field.
  # Strategy: extract the data row and check the note field (field 8).
  local raw_note_field
  raw_note_field=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f8)

  # The raw note field must not contain a bare pipe or a bare newline.
  # We check that %7C is present (encoding happened) and no raw | is inside.
  printf '%s' "$raw_note_field" | grep -qF '%7C'
  printf '%s' "$raw_note_field" | grep -qF '%25'
  printf '%s' "$raw_note_field" | grep -qF '%0A'
  # No raw pipe inside the encoded field.
  if printf '%s' "$raw_note_field" | grep -qF '|'; then
    echo "FAIL: raw pipe found inside encoded note field" >&2
    return 1
  fi
  # No raw newline inside the encoded field (it is a single-line grep match so
  # if %0A is present and no literal newline, the following will succeed).
  local nl_count
  nl_count=$(printf '%s' "$raw_note_field" | wc -l | tr -d ' ')
  [ "$nl_count" -eq 0 ]

  # The row must split into the right number of fields: schema has 9 columns
  # (ID|lens|sev|conf|status|location|note|mkey|reason), meaning 11
  # pipe-delimited fields when counting the leading/trailing empty fields.
  local field_count
  field_count=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | awk -F'|' '{print NF}')
  [ "$field_count" -eq 11 ]

  # list --decode must reproduce the original note byte-for-byte.
  # Default list output is 7 display columns (mkey/reason not shown).
  run "$FINDINGS" list "$BRIEF_DIR" --decode
  [ "$status" -eq 0 ]
  # The decoded note is in field 8 of the output row (may span multiple output
  # lines when the note itself contains newlines).  We reconstruct it by
  # extracting the part after "| ${fid} | security | CRITICAL | HIGH | open | foo.ts:10 | "
  # and before the trailing " |".  Instead of fragile field parsing on multi-line
  # output, use the helper to round-trip through a file.
  local decoded
  decoded=$(printf '%s\n' "$output" | sed "s/^| ${fid} | security | CRITICAL | HIGH | open | foo.ts:10 | //" | sed 's/ |$//')

  [ "$decoded" = "$tricky_note" ]
}

# ---------------------------------------------------------------------------
# AC-7: reconcile identity stable across line-number drift; new note → new ID
# ---------------------------------------------------------------------------

@test "AC-7: reconcile keeps same ID when only line number changes, new note → new ID" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Seed one open finding at foo.ts:10.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "WARNING" "MEDIUM" "foo.ts:10" "unused import"
  [ "$status" -eq 0 ]
  local orig_id="$output"

  # Reconcile: same lens + file basename + note, but shifted to foo.ts:99.
  run bash -c "printf '%s\t%s\t%s\t%s\t%s\n' lint WARNING MEDIUM foo.ts:99 'unused import' | \"$FINDINGS\" reconcile \"$BRIEF_DIR\""
  [ "$status" -eq 0 ]

  # Outcome line must contain the original ID (not a new F2).
  printf '%s\n' "$output" | grep -qF "${orig_id} recurring"

  # Row count must be unchanged (1 data row, same ID).
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 1 ]

  # Now reconcile a DIFFERENT note at the same location → new ID allocated.
  run bash -c "printf '%s\t%s\t%s\t%s\t%s\n' lint WARNING MEDIUM foo.ts:99 'missing semicolon' | \"$FINDINGS\" reconcile \"$BRIEF_DIR\""
  [ "$status" -eq 0 ]

  # A new "new" outcome line must appear.
  printf '%s\n' "$output" | grep -qF " new"

  # The new ID must be different from the original.
  local new_id
  new_id=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')
  [ "$new_id" != "$orig_id" ]

  # Row count must now be 2.
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# AC-8: four-way reconcile branch + absent-key untouched
# ---------------------------------------------------------------------------

@test "AC-8: reconcile four-way branch (recurring, reopened, waived-kept, new) + absent untouched" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # F1: open finding.
  run "$FINDINGS" add "$BRIEF_DIR" "sec" "CRITICAL" "HIGH" "a.ts:1" "note-f1"
  [ "$status" -eq 0 ]
  local f1="$output"

  # F2: fixed finding.
  run "$FINDINGS" add "$BRIEF_DIR" "sec" "WARNING" "MEDIUM" "b.ts:1" "note-f2"
  [ "$status" -eq 0 ]
  local f2="$output"
  run "$FINDINGS" transition "$BRIEF_DIR" "$f2" fixed
  [ "$status" -eq 0 ]

  # F3: waived finding.
  run "$FINDINGS" add "$BRIEF_DIR" "sec" "WARNING" "LOW" "c.ts:1" "note-f3"
  [ "$status" -eq 0 ]
  local f3="$output"
  run "$FINDINGS" waive "$BRIEF_DIR" "$f3" "intentional"
  [ "$status" -eq 0 ]

  # F_absent: an extra open finding whose key is NOT in the reconcile batch.
  run "$FINDINGS" add "$BRIEF_DIR" "sec" "WARNING" "MEDIUM" "d.ts:1" "note-fabsent"
  [ "$status" -eq 0 ]
  local f_absent="$output"

  # Build the reconcile batch: F1 key, F2 key, F3 key, brand-new key.
  # Use a heredoc so each printf runs in the same command substitution context.
  local batch
  batch=$(
    printf '%s\t%s\t%s\t%s\t%s\n' "sec" "CRITICAL" "HIGH" "a.ts:1" "note-f1"
    printf '%s\t%s\t%s\t%s\t%s\n' "sec" "WARNING" "MEDIUM" "b.ts:1" "note-f2"
    printf '%s\t%s\t%s\t%s\t%s\n' "sec" "WARNING" "LOW" "c.ts:1" "note-f3"
    printf '%s\t%s\t%s\t%s\t%s\n' "sec" "WARNING" "LOW" "e.ts:1" "note-brand-new"
  )

  run bash -c "printf '%s' \"\$1\" | \"$FINDINGS\" reconcile \"$BRIEF_DIR\"" -- "$batch"
  [ "$status" -eq 0 ]

  # F1: stays open, same ID — "recurring".
  printf '%s\n' "$output" | grep -qF "${f1} recurring"

  # F2: fixed → reopened — "reopened".
  printf '%s\n' "$output" | grep -qF "${f2} reopened"

  # F3: waived → waived-kept — "waived-kept".
  printf '%s\n' "$output" | grep -qF "${f3} waived-kept"

  # Brand-new: allocated as the next ID (F5, since F1–F4 are seeded above).
  printf '%s\n' "$output" | grep -qF " new"

  # Extract the new ID and assert it is F5.
  local f5
  f5=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')
  [ "$f5" = "F5" ]

  # Assert resulting statuses by re-reading the file.
  local f1_status f2_status f3_status f5_status f_absent_status
  f1_status=$(grep "^| ${f1} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  f2_status=$(grep "^| ${f2} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  f3_status=$(grep "^| ${f3} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  f5_status=$(grep "^| ${f5} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  f_absent_status=$(grep "^| ${f_absent} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')

  [ "$f1_status" = "open" ]
  [ "$f2_status" = "open" ]
  [ "$f3_status" = "waived" ]
  [ "$f5_status" = "open" ]
  # Absent key untouched (still open, same ID).
  [ "$f_absent_status" = "open" ]

  # Total row count: F1+F2+F3+F4(absent)+F5(new) = 5.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 5 ]
}

# ---------------------------------------------------------------------------
# AC-2: init creates header, idempotency — no duplicate header, rows preserved
# ---------------------------------------------------------------------------

@test "AC-2: init creates FINDINGS.md with header; second init is idempotent" {
  # File must not exist before init.
  [ ! -f "$BRIEF_DIR/FINDINGS.md" ]

  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]
  [ -f "$BRIEF_DIR/FINDINGS.md" ]

  # Header row must be present.
  run grep -c '| ID |' "$BRIEF_DIR/FINDINGS.md"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # Separator row must be present.
  run grep -c '^|---|' "$BRIEF_DIR/FINDINGS.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  # Add a data row so we can verify it survives the second init.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "WARNING" "MEDIUM" "f.ts:1" "pre-existing"
  [ "$status" -eq 0 ]

  # Second init must succeed without duplicating header or dropping data.
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Still exactly one header row.
  run grep -c '| ID |' "$BRIEF_DIR/FINDINGS.md"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # The pre-existing data row must still be there.
  run grep -c '^| F' "$BRIEF_DIR/FINDINGS.md"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

# ---------------------------------------------------------------------------
# AC-3: monotonic IDs — two adds produce F1 then F2 (or Fn then Fn+1)
# ---------------------------------------------------------------------------

@test "AC-3: add produces monotonically increasing IDs" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  run "$FINDINGS" add "$BRIEF_DIR" "lint" "WARNING" "MEDIUM" "x.ts:1" "first finding"
  [ "$status" -eq 0 ]
  local id1="$output"

  run "$FINDINGS" add "$BRIEF_DIR" "lint" "WARNING" "MEDIUM" "x.ts:2" "second finding"
  [ "$status" -eq 0 ]
  local id2="$output"

  # IDs must be distinct.
  [ "$id1" != "$id2" ]

  # Both must match F<number> pattern.
  printf '%s' "$id1" | grep -qE '^F[0-9]+$'
  printf '%s' "$id2" | grep -qE '^F[0-9]+$'

  # The numeric part of id2 must be greater than id1.
  local n1 n2
  n1=${id1#F}
  n2=${id2#F}
  [ "$n2" -gt "$n1" ]
}

# ---------------------------------------------------------------------------
# AC-3 (waive-then-add): waive F1, add a new finding → next ID, not reused
# ---------------------------------------------------------------------------

@test "AC-3 (waive-then-add): waive F1, add a new finding → next monotonic ID" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Add F1.
  run "$FINDINGS" add "$BRIEF_DIR" "sec" "CRITICAL" "HIGH" "a.ts:1" "first finding"
  [ "$status" -eq 0 ]
  local f1="$output"

  # Waive F1.
  run "$FINDINGS" waive "$BRIEF_DIR" "$f1" "accepted risk"
  [ "$status" -eq 0 ]

  # Add a completely different finding → must get the NEXT ID, not reuse F1.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "NIT" "LOW" "b.ts:2" "second finding"
  [ "$status" -eq 0 ]
  local f2="$output"

  [ "$f2" != "$f1" ]
  local n1 n2
  n1=${f1#F}
  n2=${f2#F}
  [ "$n2" -gt "$n1" ]

  # Two rows total.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# AC-5: transition status + unknown-ID exits non-zero with stderr
# ---------------------------------------------------------------------------

@test "AC-5: transition open/fixed round-trip; unknown ID exits non-zero" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  run "$FINDINGS" add "$BRIEF_DIR" "sec" "CRITICAL" "HIGH" "z.ts:5" "some vuln"
  [ "$status" -eq 0 ]
  local fid="$output"

  # Transition to fixed.
  run "$FINDINGS" transition "$BRIEF_DIR" "$fid" fixed
  [ "$status" -eq 0 ]
  local new_status
  new_status=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$new_status" = "fixed" ]

  # Transition back to open.
  run "$FINDINGS" transition "$BRIEF_DIR" "$fid" open
  [ "$status" -eq 0 ]
  new_status=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$new_status" = "open" ]

  # Transition a non-existent ID must fail.
  run "$FINDINGS" transition "$BRIEF_DIR" "F99" fixed
  [ "$status" -ne 0 ]
  # Error message must name the missing ID.
  printf '%s' "$output" | grep -qF "F99"
  # Error message must say "not found".
  printf '%s' "$output" | grep -qi "not found"
}

# ---------------------------------------------------------------------------
# AC-6: waive requires non-empty reason; empty reason exits non-zero + no change
# ---------------------------------------------------------------------------

@test "AC-6: waive with reason sets status waived; empty reason exits non-zero and is a no-op" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  run "$FINDINGS" add "$BRIEF_DIR" "perf" "WARNING" "MEDIUM" "w.ts:3" "slow loop"
  [ "$status" -eq 0 ]
  local fid="$output"

  # Valid waive.
  run "$FINDINGS" waive "$BRIEF_DIR" "$fid" "accepted risk — non-critical path"
  [ "$status" -eq 0 ]
  local new_status
  new_status=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$new_status" = "waived" ]

  # Now try waive with empty reason — must fail.
  # First, add a fresh open finding to waive (the previous one is already waived).
  run "$FINDINGS" add "$BRIEF_DIR" "perf" "WARNING" "LOW" "w.ts:9" "another loop"
  [ "$status" -eq 0 ]
  local fid2="$output"

  run "$FINDINGS" waive "$BRIEF_DIR" "$fid2" ""
  [ "$status" -ne 0 ]
  # Record must remain open (unchanged).
  local unchanged_status
  unchanged_status=$(grep "^| ${fid2} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$unchanged_status" = "open" ]
}

# ---------------------------------------------------------------------------
# AC-9: --blocking predicate and bare-integer count
# ---------------------------------------------------------------------------

@test "AC-9: list --blocking returns only open CRITICAL and open HIGH-conf; count --blocking is exact" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Seed findings:
  # A: open CRITICAL/MEDIUM  → blocking (CRITICAL)
  run "$FINDINGS" add "$BRIEF_DIR" "sec" "CRITICAL" "MEDIUM" "a.ts:1" "crit finding"
  [ "$status" -eq 0 ]
  local fa="$output"

  # B: open WARNING/MEDIUM   → NOT blocking
  run "$FINDINGS" add "$BRIEF_DIR" "sec" "WARNING" "MEDIUM" "b.ts:1" "warn medium"
  [ "$status" -eq 0 ]
  local fb="$output"

  # C: open WARNING/HIGH     → blocking (HIGH conf)
  run "$FINDINGS" add "$BRIEF_DIR" "sec" "WARNING" "HIGH" "c.ts:1" "warn high-conf"
  [ "$status" -eq 0 ]
  local fc="$output"

  # D: fixed CRITICAL/HIGH   → NOT blocking (not open)
  run "$FINDINGS" add "$BRIEF_DIR" "sec" "CRITICAL" "HIGH" "d.ts:1" "fixed crit"
  [ "$status" -eq 0 ]
  local fd="$output"
  run "$FINDINGS" transition "$BRIEF_DIR" "$fd" fixed
  [ "$status" -eq 0 ]

  # E: waived CRITICAL/HIGH  → NOT blocking (waived)
  run "$FINDINGS" add "$BRIEF_DIR" "sec" "CRITICAL" "HIGH" "e.ts:1" "waived crit"
  [ "$status" -eq 0 ]
  local fe="$output"
  run "$FINDINGS" waive "$BRIEF_DIR" "$fe" "acceptable"
  [ "$status" -eq 0 ]

  # list --blocking must contain A and C; must NOT contain B, D, E.
  run "$FINDINGS" list "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "| ${fa} |"
  printf '%s\n' "$output" | grep -qF "| ${fc} |"
  if printf '%s\n' "$output" | grep -qF "| ${fb} |"; then
    echo "FAIL: WARNING/MEDIUM should not be blocking" >&2
    return 1
  fi
  if printf '%s\n' "$output" | grep -qF "| ${fd} |"; then
    echo "FAIL: fixed finding should not be blocking" >&2
    return 1
  fi
  if printf '%s\n' "$output" | grep -qF "| ${fe} |"; then
    echo "FAIL: waived finding should not be blocking" >&2
    return 1
  fi

  # count --blocking must print exactly "2".
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  # Transition A to fixed — count must now be 1.
  run "$FINDINGS" transition "$BRIEF_DIR" "$fa" fixed
  [ "$status" -eq 0 ]
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  # Transition C to fixed too — count must now be 0.
  run "$FINDINGS" transition "$BRIEF_DIR" "$fc" fixed
  [ "$status" -eq 0 ]
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# AC-10: atomic writes — no temp residue after a successful mutation
# ---------------------------------------------------------------------------

@test "AC-10: no .FINDINGS.tmp.* or .bak files remain after a successful add" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  run "$FINDINGS" add "$BRIEF_DIR" "lint" "WARNING" "MEDIUM" "tmp.ts:1" "check residue"
  [ "$status" -eq 0 ]

  # No .FINDINGS.tmp.* files.
  local tmp_files
  tmp_files=$(find "$BRIEF_DIR" -name '.FINDINGS.tmp.*' 2>/dev/null)
  [ -z "$tmp_files" ]

  # No .bak files.
  local bak_files
  bak_files=$(find "$BRIEF_DIR" -name '*.bak' 2>/dev/null)
  [ -z "$bak_files" ]
}

# ---------------------------------------------------------------------------
# Edge: empty / header-only store — list and count succeed with 0
# ---------------------------------------------------------------------------

@test "Edge: list and count --blocking on header-only store exit 0 and count returns 0" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # list on empty store must exit 0 and produce no data rows.
  run "$FINDINGS" list "$BRIEF_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # list --blocking on empty store must exit 0 and produce no output.
  run "$FINDINGS" list "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # count --blocking on empty store must print "0".
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# AC-12: location injection — crafted location cannot forge extra table rows
# ---------------------------------------------------------------------------

@test "AC-12: location containing pipe+newline does not forge extra rows; count --blocking is 0" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Crafted location containing a pipe, extra table-like content, and a newline.
  # This is the exact reproduction case from the S4 bug report.
  local loc
  loc=$'good.ts:1 | x | x | open | y | z |\n| F77 | evil | CRITICAL | HIGH | open | hacked.ts:1 | forged'

  run "$FINDINGS" add "$BRIEF_DIR" "code-reviewer" "NIT" "LOW" "$loc" "harmless nit"
  [ "$status" -eq 0 ]
  local fid="$output"

  # count --blocking must be 0 (NIT/LOW is not blocking, and the forged row must
  # not exist as a real row).
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  # There must be exactly ONE data row in the file.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 1 ]

  # The single data row must have exactly 11 pipe-delimited fields (leading and
  # trailing empty fields from awk -F'|' on "| ... |") — schema has 9 data columns.
  local field_count
  field_count=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | awk -F'|' '{print NF}')
  [ "$field_count" -eq 11 ]

  # Raw FINDINGS.md must contain %7C in the location cell (encoding happened).
  local raw_loc_field
  raw_loc_field=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f7)
  printf '%s' "$raw_loc_field" | grep -qF '%7C'

  # Decode the raw location field directly from FINDINGS.md to verify byte-for-byte
  # round-trip.  We decode from the raw file (not from list --decode output) because
  # list --decode renders the decoded location inline, which may produce multi-line
  # output when the location itself contains a newline — making field extraction from
  # the rendered table unreliable.
  local decoded_loc
  decoded_loc=$(printf '%s' "$raw_loc_field" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | awk '{gsub(/%0A/,"\n"); printf "%s",$0}' \
    | sed 's/%7C/|/g' \
    | sed 's/%25/%/g')
  [ "$decoded_loc" = "$loc" ]

  # The forged ID must NOT appear as a table row in the raw file.
  # Note: "F77" may appear as an encoded substring within the location cell — that
  # is fine.  We check that no row STARTS with "| F77 " (which would mean it was
  # forged as a real data row with its own ID column).
  if grep -qF "| F77 " "$BRIEF_DIR/FINDINGS.md"; then
    echo "FAIL: forged F77 row appeared as a real data row in FINDINGS.md" >&2
    return 1
  fi
}

@test "AC-12 (reconcile positive): pipe-in-location is stored encoded; count is 0; location round-trips" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # POSITIVE case: a valid finding whose location contains a literal "|".
  # The reconcile batch must store it encoded (%7C) and list --decode must
  # return the original byte-for-byte.  Using NIT/LOW so count --blocking=0
  # AND no forged CRITICAL row can exist.
  local expected_loc="good.ts:1 | F99 | CRITICAL | HIGH | open | x | y"

  run bash -c "printf '%s\t%s\t%s\t%s\t%s\n' 'code-reviewer' 'NIT' 'LOW' \"\$1\" 'harmless nit' | \"$FINDINGS\" reconcile \"$BRIEF_DIR\"" -- "$expected_loc"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF " new"

  # Exactly ONE data row — no forged extra columns.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 1 ]

  # Extract the new finding ID from the reconcile output.
  local fid
  fid=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')

  # The single data row must split into exactly 11 pipe-fields — no forged extra cols.
  # (9 data columns + leading/trailing empty = 11 awk -F'|' fields)
  local field_count
  field_count=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | awk -F'|' '{print NF}')
  [ "$field_count" -eq 11 ]

  # Raw FINDINGS.md must contain %7C in the location cell (encoding happened).
  local raw_loc_field
  raw_loc_field=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f7)
  printf '%s' "$raw_loc_field" | grep -qF '%7C'

  # No literal "|" inside the raw location cell (would forge extra columns).
  if printf '%s' "$raw_loc_field" | grep -qF '|'; then
    echo "FAIL: raw pipe found inside encoded location field" >&2
    return 1
  fi

  # count --blocking must be 0 (NIT/LOW, and no forged CRITICAL row exists).
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  # F99 must NOT appear as a real data-row ID (it is encoded inside the location).
  if grep -qF "| F99 " "$BRIEF_DIR/FINDINGS.md"; then
    echo "FAIL: F99 appeared as a real data row — location encoding failed" >&2
    return 1
  fi

  # Decode the raw location field directly from FINDINGS.md to verify byte-for-byte
  # round-trip.  Decoding from the raw file avoids the multi-field-split ambiguity
  # that arises when list --decode renders a decoded pipe-containing location inline.
  local raw_loc_field decoded_loc
  raw_loc_field=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f7)
  decoded_loc=$(printf '%s' "$raw_loc_field" \
    | awk '{gsub(/%0A/,"\n"); printf "%s",$0}' \
    | sed 's/%7C/|/g' \
    | sed 's/%25/%/g' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ "$decoded_loc" = "$expected_loc" ]
}

@test "AC-12 (reconcile rejection): batch line with newline-in-field is rejected non-zero" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # A batch field containing a raw newline splits into two lines.  The second
  # fragment fails sev/conf validation so reconcile must exit non-zero.  We
  # assert the non-zero status explicitly — do NOT swallow with || true.
  local loc
  loc=$'good.ts:1\n| F77 | evil | NIT | LOW | open | hacked.ts:1 | forged'

  run bash -c "printf '%s\t%s\t%s\t%s\t%s\n' 'code-reviewer' 'NIT' 'LOW' \"\$1\" 'harmless nit' | \"$FINDINGS\" reconcile \"$BRIEF_DIR\"" -- "$loc"
  # Must exit non-zero (the second fragment fails sev/conf validation).
  [ "$status" -ne 0 ]

  # Regardless of the error, no forged F77 row must appear.
  if grep -qF "| F77 " "$BRIEF_DIR/FINDINGS.md"; then
    echo "FAIL: forged F77 row appeared as a real data row in FINDINGS.md" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC-13: identity-by-construction
# mkey is stored at creation time, note is immutable, reason is in its own column.
# Verifies Edge A and Edge B.
# ---------------------------------------------------------------------------

@test "AC-13 (Edge A): OPEN note containing ' [waived: old]' text — reconcile finds same ID (no duplicate)" {
  # AC-13: Edge A — note literally contains ' [waived: old]' as text.
  # The old suffix-strip logic would strip from the FIRST occurrence in the encoded
  # note, producing a diverged mkey and causing reconcile to create a NEW row
  # instead of matching the existing waived row.  With stored mkey this cannot happen.
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local tricky_note="fix the [waived: old] handler"

  run "$FINDINGS" add "$BRIEF_DIR" "sec" "WARNING" "HIGH" "app.ts:5" "$tricky_note"
  [ "$status" -eq 0 ]
  local fid="$output"

  # Waive it.
  run "$FINDINGS" waive "$BRIEF_DIR" "$fid" "deliberate override"
  [ "$status" -eq 0 ]

  # The note cell must be unchanged by waive (immutable after creation).
  local raw_note_field
  raw_note_field=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f8 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ "$raw_note_field" = "$tricky_note" ]

  # The reason must be in the reason column (field 10), not appended to note.
  local reason_field
  reason_field=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f10 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ "$reason_field" = "deliberate override" ]

  # mkey before waive — capture before reconcile for immutability check.
  local mkey_before
  mkey_before=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f9 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  # Reconcile the ORIGINAL finding (same lens/location/note, no waive suffix).
  run bash -c "printf '%s\t%s\t%s\t%s\t%s\n' 'sec' 'WARNING' 'HIGH' 'app.ts:5' \"\$1\" | \"$FINDINGS\" reconcile \"$BRIEF_DIR\"" -- "$tricky_note"
  [ "$status" -eq 0 ]

  # Must be waived-kept — not new (no duplicate).
  printf '%s\n' "$output" | grep -qF "${fid} waived-kept"

  # Status must remain waived.
  local status_col
  status_col=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$status_col" = "waived" ]

  # mkey must be unchanged by reconcile.
  local mkey_after
  mkey_after=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f9 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ "$mkey_after" = "$mkey_before" ]

  # Still exactly one data row.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 1 ]
}

@test "AC-13 (Edge B): waive with reason containing ' [waived: ...]' — reconcile yields waived-kept, count --blocking=0" {
  # AC-13: Edge B — waive reason itself contains literal ' [waived: F3] per triage'.
  # The old suffix-strip logic (last-occurrence awk) would incorrectly strip from
  # the appended suffix but could still misfire in corner cases.  With the reason
  # in a separate column and mkey stored at creation, the reconcile must always
  # find the waived row by its immutable mkey — regardless of what is in the reason.
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  run "$FINDINGS" add "$BRIEF_DIR" "sec" "CRITICAL" "HIGH" "app.ts:10" "risky call"
  [ "$status" -eq 0 ]
  local fid="$output"

  # Waive with a reason that contains literal [waived: ...] text.
  run "$FINDINGS" waive "$BRIEF_DIR" "$fid" "dup of [waived: F3] per triage"
  [ "$status" -eq 0 ]

  # count --blocking must be 0 immediately after waive.
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  # The note must be unchanged (immutable after creation).
  local raw_note_field
  raw_note_field=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f8 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ "$raw_note_field" = "risky call" ]

  # The reason must be in the reason column (field 10), non-empty.
  # The reason "dup of [waived: F3] per triage" does not contain | or newline,
  # so it is stored as-is (no percent-encoding needed for these chars).
  local reason_field
  reason_field=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f10 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  # Must be non-empty (reason was stored).
  [ -n "$reason_field" ]
  # Must not be blank — the note cell must not contain the reason text.
  local note_field
  note_field=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f8 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ "$note_field" = "risky call" ]

  # Reconcile the ORIGINAL finding (same lens/location/note).
  run bash -c "printf '%s\t%s\t%s\t%s\t%s\n' 'sec' 'CRITICAL' 'HIGH' 'app.ts:10' 'risky call' | \"$FINDINGS\" reconcile \"$BRIEF_DIR\""
  [ "$status" -eq 0 ]

  # Must be waived-kept — the CRITICAL is NOT resurrected as a new open row.
  printf '%s\n' "$output" | grep -qF "${fid} waived-kept"

  # Status must still be waived — NOT open.
  local status_col
  status_col=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$status_col" = "waived" ]

  # count --blocking after reconcile must still be 0.
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  # Exactly one row (no resurrected open duplicate).
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 1 ]
}

@test "AC-13: waive stores reason in reason column; note is unchanged; mkey identical before/after waive" {
  # AC-13: reason column + note immutability contract.
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  run "$FINDINGS" add "$BRIEF_DIR" "sec" "WARNING" "HIGH" "auth.ts:42" "risky call"
  [ "$status" -eq 0 ]
  local fid="$output"

  # Capture note and mkey before waive.
  local note_before mkey_before
  note_before=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f8 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  mkey_before=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f9 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  # Waive with a reason containing |, ], and an embedded newline.
  local reason
  reason=$'accepted | risk [see ticket]\nfollowup in Q3'

  run "$FINDINGS" waive "$BRIEF_DIR" "$fid" "$reason"
  [ "$status" -eq 0 ]

  # note must be identical to before waive — immutable.
  local note_after
  note_after=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f8 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ "$note_after" = "$note_before" ]

  # mkey must be identical to before waive — immutable.
  local mkey_after
  mkey_after=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f9 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ "$mkey_after" = "$mkey_before" ]

  # reason must be in the reason column (field 10), percent-encoded.
  local raw_reason_field
  raw_reason_field=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f10 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  # Should contain %7C (for the |) and %0A (for the newline).
  printf '%s' "$raw_reason_field" | grep -qF '%7C'
  printf '%s' "$raw_reason_field" | grep -qF '%0A'

  # status must be waived.
  local status_col
  status_col=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$status_col" = "waived" ]

  # Reconcile the ORIGINAL finding — must be waived-kept.
  run bash -c "printf '%s\t%s\t%s\t%s\t%s\n' 'sec' 'WARNING' 'HIGH' 'auth.ts:42' 'risky call' | \"$FINDINGS\" reconcile \"$BRIEF_DIR\""
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "${fid} waived-kept"

  # Status must remain waived.
  status_col=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  [ "$status_col" = "waived" ]

  # Still exactly one data row.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# AC-10 (extended): no residue after transition, waive, and reconcile
# ---------------------------------------------------------------------------

@test "AC-10 (extended): no temp residue after transition, waive, and reconcile" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  run "$FINDINGS" add "$BRIEF_DIR" "lint" "WARNING" "MEDIUM" "r.ts:1" "residue check"
  [ "$status" -eq 0 ]
  local fid="$output"

  # After transition.
  run "$FINDINGS" transition "$BRIEF_DIR" "$fid" fixed
  [ "$status" -eq 0 ]
  [ -z "$(find "$BRIEF_DIR" -name '.FINDINGS.tmp.*' 2>/dev/null)" ]
  [ -z "$(find "$BRIEF_DIR" -name '*.bak' 2>/dev/null)" ]

  # After waive (re-open first so waive can target an open finding).
  run "$FINDINGS" transition "$BRIEF_DIR" "$fid" open
  [ "$status" -eq 0 ]
  run "$FINDINGS" waive "$BRIEF_DIR" "$fid" "deliberate"
  [ "$status" -eq 0 ]
  [ -z "$(find "$BRIEF_DIR" -name '.FINDINGS.tmp.*' 2>/dev/null)" ]
  [ -z "$(find "$BRIEF_DIR" -name '*.bak' 2>/dev/null)" ]

  # Add another finding then reconcile.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "NIT" "LOW" "r.ts:2" "second"
  [ "$status" -eq 0 ]
  run bash -c "printf '%s\t%s\t%s\t%s\t%s\n' lint NIT LOW r.ts:2 second | \"$FINDINGS\" reconcile \"$BRIEF_DIR\""
  [ "$status" -eq 0 ]
  [ -z "$(find "$BRIEF_DIR" -name '.FINDINGS.tmp.*' 2>/dev/null)" ]
  [ -z "$(find "$BRIEF_DIR" -name '*.bak' 2>/dev/null)" ]
}

# ---------------------------------------------------------------------------
# AC-3 (extended): ID not reused after transition to fixed
# ---------------------------------------------------------------------------

@test "AC-3 (extended): ID not reused after F1 is fixed and a new finding is added" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Add F1.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "NIT" "LOW" "a.ts:1" "first"
  [ "$status" -eq 0 ]
  local f1="$output"

  # Transition F1 to fixed.
  run "$FINDINGS" transition "$BRIEF_DIR" "$f1" fixed
  [ "$status" -eq 0 ]

  # Add a new, different finding.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "NIT" "LOW" "b.ts:1" "second"
  [ "$status" -eq 0 ]
  local f2="$output"

  # f2 must be a NEW ID distinct from f1 — not a reused F1.
  [ "$f2" != "$f1" ]

  # f2 must be F-next (numerically greater).
  local n1 n2
  n1=${f1#F}
  n2=${f2#F}
  [ "$n2" -gt "$n1" ]

  # Two rows total.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# AC-14: severity enum is exactly {CRITICAL,WARNING,NIT}; out-of-enum value rejected
#         confidence enum is exactly {HIGH,MEDIUM,LOW}; out-of-enum value rejected
#         Both are checked on add AND reconcile.
# ---------------------------------------------------------------------------

@test "AC-14: add with out-of-enum severity exits non-zero; error names {CRITICAL,WARNING,NIT}" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Construct the bad sev dynamically so the literal does not appear in source.
  local bad_sev
  bad_sev="IN""FO"
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "$bad_sev" "LOW" "x.ts:1" "info finding"
  [ "$status" -ne 0 ]
  # Error message must name the three valid severities.
  printf '%s' "$output" | grep -qF "CRITICAL"
  printf '%s' "$output" | grep -qF "WARNING"
  printf '%s' "$output" | grep -qF "NIT"
  # Error message must echo back the rejected value.
  printf '%s' "$output" | grep -qF "$bad_sev"
}

@test "AC-14 (conf enum on add): add with out-of-enum conf exits non-zero; error names {HIGH,MEDIUM,LOW}" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Use a conf value that is not in {HIGH,MEDIUM,LOW}.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "WARNING" "VERY_HIGH" "x.ts:1" "bad conf"
  [ "$status" -ne 0 ]
  # Error message must name the three valid conf values.
  printf '%s' "$output" | grep -qF "HIGH"
  printf '%s' "$output" | grep -qF "MEDIUM"
  printf '%s' "$output" | grep -qF "LOW"
  # Error message must echo back the rejected value.
  printf '%s' "$output" | grep -qF "VERY_HIGH"
}

@test "AC-14 (sev enum on reconcile): reconcile with invalid sev exits non-zero" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local bad_sev
  bad_sev="IN""FO"
  # A reconcile batch with an invalid sev must be rejected non-zero.
  run bash -c "printf '%s\t%s\t%s\t%s\t%s\n' 'lint' \"\$1\" 'LOW' 'x.ts:1' 'bad sev' | \"$FINDINGS\" reconcile \"$BRIEF_DIR\"" -- "$bad_sev"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF "CRITICAL"
  printf '%s' "$output" | grep -qF "WARNING"
  printf '%s' "$output" | grep -qF "NIT"
}

@test "AC-14 (conf enum on reconcile): reconcile with invalid conf exits non-zero; error names {HIGH,MEDIUM,LOW}" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # A reconcile batch with conf=VERY_HIGH must be rejected non-zero.
  run bash -c "printf '%s\t%s\t%s\t%s\t%s\n' 'lint' 'WARNING' 'VERY_HIGH' 'x.ts:1' 'bad conf' | \"$FINDINGS\" reconcile \"$BRIEF_DIR\""
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF "HIGH"
  printf '%s' "$output" | grep -qF "MEDIUM"
  printf '%s' "$output" | grep -qF "LOW"
  printf '%s' "$output" | grep -qF "VERY_HIGH"
}

# ---------------------------------------------------------------------------
# Fix 4: basename -- handles dash-prefixed locations without dedup collapse
# ---------------------------------------------------------------------------

@test "Fix-4 (basename --): dash-prefixed locations stay as distinct rows" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # Two findings with DIFFERENT notes at dash-prefixed locations.
  # Without "basename --", BSD basename errors, returning empty for both,
  # causing identical match keys and dedup collapsing both to one row.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "NIT" "LOW" "-a.ts:1" "note alpha"
  [ "$status" -eq 0 ]
  local fa="$output"

  run "$FINDINGS" add "$BRIEF_DIR" "lint" "NIT" "LOW" "-b.ts:2" "note beta"
  [ "$status" -eq 0 ]
  local fb="$output"

  # Must be two DISTINCT IDs.
  [ "$fa" != "$fb" ]

  # Both rows must exist in the file.
  local row_count
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 2 ]

  # Verify identity is still correct: same note, different line → recurring (AC-7).
  # This uses a normal (non-dash) location to confirm the dedup key still works.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "NIT" "LOW" "normal.ts:10" "normal note"
  [ "$status" -eq 0 ]
  local fn="$output"

  run "$FINDINGS" add "$BRIEF_DIR" "lint" "NIT" "LOW" "normal.ts:99" "normal note"
  [ "$status" -eq 0 ]
  local fn2="$output"

  # Same note + basename → same ID returned (dedup).
  [ "$fn" = "$fn2" ]

  # Row count must be 3 (the two dash-prefix rows + one normal dedup row).
  row_count=$(grep -c "^| F" "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 3 ]
}

# ---------------------------------------------------------------------------
# list --open filter (currently untested)
# ---------------------------------------------------------------------------

@test "list --open returns only open findings; closed/waived excluded" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # A: open.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "NIT" "LOW" "a.ts:1" "open finding"
  [ "$status" -eq 0 ]
  local fa="$output"

  # B: fixed.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "WARNING" "MEDIUM" "b.ts:1" "fixed finding"
  [ "$status" -eq 0 ]
  local fb="$output"
  run "$FINDINGS" transition "$BRIEF_DIR" "$fb" fixed
  [ "$status" -eq 0 ]

  # C: waived.
  run "$FINDINGS" add "$BRIEF_DIR" "lint" "NIT" "LOW" "c.ts:1" "waived finding"
  [ "$status" -eq 0 ]
  local fc="$output"
  run "$FINDINGS" waive "$BRIEF_DIR" "$fc" "deliberate"
  [ "$status" -eq 0 ]

  # list --open must contain A only.
  run "$FINDINGS" list "$BRIEF_DIR" --open
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "| ${fa} |"
  if printf '%s\n' "$output" | grep -qF "| ${fb} |"; then
    echo "FAIL: fixed finding should not appear in --open list" >&2
    return 1
  fi
  if printf '%s\n' "$output" | grep -qF "| ${fc} |"; then
    echo "FAIL: waived finding should not appear in --open list" >&2
    return 1
  fi
}
