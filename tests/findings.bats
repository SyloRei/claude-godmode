#!/usr/bin/env bats
#
# Test suite for bin/godmode-findings (unit 1 S3).
#
# Covers: AC-2 (init/idempotent), AC-3 (monotonic IDs), AC-4 (note round-trip),
#         AC-5 (transition + unknown-ID error), AC-6 (waive + empty-reason error),
#         AC-7 (reconcile identity stable across line drift),
#         AC-8 (four-way reconcile branch + absent-key untouched),
#         AC-9 (--blocking predicate + bare count), AC-10 (atomic writes / no residue).
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
  BRIEF_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/godmode-findings.XXXXXX")"
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

  # The row must split into the right number of fields: header has 7 columns
  # (ID|lens|sev|conf|status|location|note), meaning 9 pipe-delimited fields
  # when counting the leading/trailing empty fields.
  local field_count
  field_count=$(grep "^| ${fid} " "$BRIEF_DIR/FINDINGS.md" | awk -F'|' '{print NF}')
  [ "$field_count" -eq 9 ]

  # list --decode must reproduce the original note byte-for-byte.
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
  local batch
  batch=$(printf '%s\t%s\t%s\t%s\t%s\n' "sec" "CRITICAL" "HIGH" "a.ts:1" "note-f1"
          printf '%s\t%s\t%s\t%s\t%s\n' "sec" "WARNING" "MEDIUM" "b.ts:1" "note-f2"
          printf '%s\t%s\t%s\t%s\t%s\n' "sec" "WARNING" "LOW" "c.ts:1" "note-f3"
          printf '%s\t%s\t%s\t%s\t%s\n' "sec" "INFO" "LOW" "e.ts:1" "note-brand-new")

  run bash -c "printf '%s' \"\$1\" | \"$FINDINGS\" reconcile \"$BRIEF_DIR\"" -- "$batch"
  [ "$status" -eq 0 ]

  # F1: stays open, same ID — "recurring".
  printf '%s\n' "$output" | grep -qF "${f1} recurring"

  # F2: fixed → reopened — "reopened".
  printf '%s\n' "$output" | grep -qF "${f2} reopened"

  # F3: waived → waived-kept — "waived-kept".
  printf '%s\n' "$output" | grep -qF "${f3} waived-kept"

  # Brand-new: allocated as next ID.
  printf '%s\n' "$output" | grep -qF " new"

  # Extract F4 (the new one).
  local f4
  f4=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')

  # Assert resulting statuses by re-reading the file.
  local f1_status f2_status f3_status f4_status f_absent_status
  f1_status=$(grep "^| ${f1} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  f2_status=$(grep "^| ${f2} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  f3_status=$(grep "^| ${f3} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  f4_status=$(grep "^| ${f4} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')
  f_absent_status=$(grep "^| ${f_absent} " "$BRIEF_DIR/FINDINGS.md" | cut -d'|' -f6 | tr -d ' ')

  [ "$f1_status" = "open" ]
  [ "$f2_status" = "open" ]
  [ "$f3_status" = "waived" ]
  [ "$f4_status" = "open" ]
  # Absent key untouched (still open, same ID).
  [ "$f_absent_status" = "open" ]

  # Total row count: F1+F2+F3+F4+F_absent = 5.
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
  # Error must appear on stderr (captured in $output by bats when combined with run).
  printf '%s' "$output" | grep -qi "F99"
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
