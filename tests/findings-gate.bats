#!/usr/bin/env bats
# ---------------------------------------------------------------------------
# Pins unit 6 (the FINDINGS.md schema CI gate). Advances AC-6.
#
# Exercises scripts/check-findings.sh, the gate that keeps every FINDINGS.md
# row at the canonical 9 columns so the /verify, /build --fix and /ship parsers
# never read a shifted cell. The gate runs in two parts:
#   Part 1  helper-contract parity — drives $REPO_ROOT/bin/godmode-findings and
#           asserts the emitted header / encoding / enums match the schema.
#   Part 2  fixture validation — every tests/fixtures/findings/valid-*.md must
#           conform to that same schema.
#
# Coverage here:
#   - default mode (no args) exits 0 on the repo as-is (Part 1 + Part 2 pass);
#   - each committed negative fixture is rejected by `validate <file>`;
#   - the positive fixture validates;
#   - a Part-1 divergence (helper emitting a wrong header) makes the gate fail.
#
# The divergence case cannot be triggered against the real repo (the shipped
# helper is in sync with the schema by construction), so it builds a throwaway
# REPO_ROOT skeleton in $BATS_TEST_TMPDIR: a copy of check-findings.sh under
# scripts/, a STUB bin/godmode-findings that emits an 8-column header, and a
# valid fixture under tests/fixtures/findings/. The gate resolves its helper as
# "$REPO_ROOT/bin/godmode-findings" relative to its own BASH_SOURCE, so running
# the copy from the skeleton makes Part 1 drive the stub and fail header parity.
#
# Bash 3.2 / bats-core (pinned 1.13.0) compatible. shellcheck-friendly.
# ---------------------------------------------------------------------------

load test_helper

SCRIPT="$PLUGIN_ROOT/scripts/check-findings.sh"
FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/findings"

# ---------------------------------------------------------------------------
# Mode 1 — healthy repo passes (Part 1 parity + Part 2 fixtures, default mode).
# ---------------------------------------------------------------------------

@test "check-findings (default mode) exits 0 on the repo as-is" {
  run bash -c '"$0" 2>&1' "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"findings schema OK"* ]]
}

# ---------------------------------------------------------------------------
# Mode 2 — each committed negative fixture is rejected by `validate <file>`.
# One test per fixture so each is asserted individually.
# ---------------------------------------------------------------------------

@test "check-findings validate rejects invalid-bad-enum.md" {
  run bash -c '"$0" validate "$1" 2>&1' "$SCRIPT" "$FIXTURE_DIR/invalid-bad-enum.md"
  [ "$status" -ne 0 ]
}

@test "check-findings validate rejects invalid-bad-colcount.md" {
  run bash -c '"$0" validate "$1" 2>&1' "$SCRIPT" "$FIXTURE_DIR/invalid-bad-colcount.md"
  [ "$status" -ne 0 ]
}

@test "check-findings validate rejects invalid-raw-pipe.md" {
  run bash -c '"$0" validate "$1" 2>&1' "$SCRIPT" "$FIXTURE_DIR/invalid-raw-pipe.md"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Mode 3 — the positive fixture validates.
# ---------------------------------------------------------------------------

@test "check-findings validate accepts valid-basic.md" {
  run bash -c '"$0" validate "$1" 2>&1' "$SCRIPT" "$FIXTURE_DIR/valid-basic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"conforms to schema"* ]]
}

# ---------------------------------------------------------------------------
# Mode 4 — Part-1 divergence: a helper whose header drifts from the schema must
# fail the gate. Build a throwaway REPO_ROOT skeleton whose bin/godmode-findings
# is a stub emitting an 8-column header; run the gate from there.
# ---------------------------------------------------------------------------

@test "check-findings fails when the helper diverges from the documented schema" {
  local root="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$root/scripts" "$root/bin" "$root/tests/fixtures/findings"

  # The gate copy resolves REPO_ROOT one level up from scripts/, so this copy
  # picks up the skeleton's bin/ and tests/fixtures/ — not the real repo's.
  cp "$SCRIPT" "$root/scripts/check-findings.sh"

  # A valid fixture so Part 2 cannot be the reason for failure — only Part 1's
  # header-parity check against the stub should fail.
  cp "$FIXTURE_DIR/valid-basic.md" "$root/tests/fixtures/findings/valid-basic.md"

  # STUB helper: a drifted schema. It accepts init/add/list but `init` and the
  # store it writes carry an 8-column header (one column dropped vs canonical),
  # which Part 1's "first line equals canonical header" assertion rejects.
  cat > "$root/bin/godmode-findings" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
# Drifted: 8 columns (canonical is 9 — the trailing `reason` column is gone).
WRONG_HEADER="| ID | lens | sev | conf | status | location | note | mkey |"
cmd="${1:-}"
case "$cmd" in
  init)
    store="${2:-}"
    mkdir -p "$store"
    {
      echo "$WRONG_HEADER"
      echo "|---|---|---|---|---|---|---|---|"
    } > "$store/FINDINGS.md"
    ;;
  add)
    store="${2:-}"
    # Append a drifted (8-cell) row so the gate's data-row read also sees drift.
    echo "| F1 | code | CRITICAL | HIGH | open | src/foo.sh:42 | a note | deadbeef |" >> "$store/FINDINGS.md"
    ;;
  list)
    store="${2:-}"
    # Emit a body row matching the wrong header so any list-shape check sees it.
    echo "| F1 | code | CRITICAL | HIGH | open | src/foo.sh:42 | a note |"
    ;;
  *)
    exit 1
    ;;
esac
STUB
  chmod +x "$root/bin/godmode-findings"

  # Run the copied gate from the skeleton (default mode → Part 1 then Part 2).
  run bash -c '"$0" 2>&1' "$root/scripts/check-findings.sh"
  [ "$status" -ne 0 ]
  # Assert it failed for the right reason: the helper-contract parity message.
  [[ "$output" == *"parity"* ]]
}
