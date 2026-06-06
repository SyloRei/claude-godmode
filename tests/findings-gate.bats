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
#   - each committed negative fixture is rejected by `validate <file>`, and each
#     assertion pins the SPECIFIC failure message so a fixture cannot pass for
#     the wrong reason (enum / too-few / too-many / separator / status);
#   - the positive fixture validates;
#   - the shallow error paths (file-not-found, unknown subcommand) are covered;
#   - a Part-1 divergence (helper emitting a wrong header) makes the gate fail,
#     pinned to the header-parity message specifically.
#
# The divergence case cannot be triggered against the real repo (the shipped
# helper is in sync with the schema by construction), so it builds a throwaway
# REPO_ROOT skeleton: a copy of check-findings.sh under scripts/, a STUB
# bin/godmode-findings that emits an 8-column header, and a valid fixture under
# tests/fixtures/findings/. The gate resolves its helper as
# "$REPO_ROOT/bin/godmode-findings" relative to its own BASH_SOURCE, so running
# the copy from the skeleton makes Part 1 drive the stub and fail header parity.
#
# Bash 3.2 / bats-core (pinned 1.13.0) compatible. shellcheck-friendly.
# ---------------------------------------------------------------------------

load test_helper

SCRIPT="$PLUGIN_ROOT/scripts/check-findings.sh"
FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/findings"

# Per-test temp root for the divergence skeleton; teardown reaps it.
setup() {
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/findings-gate.XXXXXX")"
}

teardown() {
  if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}

# ---------------------------------------------------------------------------
# Mode 1 — healthy repo passes (Part 1 parity + Part 2 fixtures, default mode).
# bats `run` captures stdout+stderr into $output by default — no 2>&1 needed.
# ---------------------------------------------------------------------------

@test "check-findings (default mode) exits 0 on the repo as-is" {
  run bash -c '"$0"' "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"findings schema OK"* ]]
}

# ---------------------------------------------------------------------------
# Mode 2 — each committed negative fixture is rejected by `validate <file>`,
# AND each test pins the specific failure message so the fixture cannot pass
# for an unintended reason.
# ---------------------------------------------------------------------------

@test "check-findings validate rejects invalid-bad-enum.md (sev enum)" {
  run bash -c '"$0" validate "$1"' "$SCRIPT" "$FIXTURE_DIR/invalid-bad-enum.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in {CRITICAL,WARNING,NIT}"* ]]
}

@test "check-findings validate rejects invalid-bad-colcount.md (too few columns)" {
  run bash -c '"$0" validate "$1"' "$SCRIPT" "$FIXTURE_DIR/invalid-bad-colcount.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too few columns"* ]]
}

@test "check-findings validate rejects invalid-raw-pipe.md (too many columns)" {
  run bash -c '"$0" validate "$1"' "$SCRIPT" "$FIXTURE_DIR/invalid-raw-pipe.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too many columns"* ]]
}

@test "check-findings validate rejects invalid-bad-separator.md (separator row)" {
  run bash -c '"$0" validate "$1"' "$SCRIPT" "$FIXTURE_DIR/invalid-bad-separator.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"separator"* ]]
}

@test "check-findings validate rejects invalid-bad-status.md (status enum)" {
  run bash -c '"$0" validate "$1"' "$SCRIPT" "$FIXTURE_DIR/invalid-bad-status.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in {open,fixed,waived}"* ]]
}

# ---------------------------------------------------------------------------
# Mode 3 — the positive fixture validates (it carries open/waived/fixed rows,
# so the `fixed` status arm is exercised here).
# ---------------------------------------------------------------------------

@test "check-findings validate accepts valid-basic.md" {
  run bash -c '"$0" validate "$1"' "$SCRIPT" "$FIXTURE_DIR/valid-basic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"conforms to schema"* ]]
}

# ---------------------------------------------------------------------------
# Mode 3b — shallow error paths: a missing file and an unknown subcommand.
# ---------------------------------------------------------------------------

@test "check-findings validate <missing-file> fails with 'file not found'" {
  run bash -c '"$0" validate "$1"' "$SCRIPT" "$TMP_ROOT/does-not-exist.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"file not found"* ]]
}

@test "check-findings <unknown-subcommand> prints usage and exits non-zero" {
  run bash -c '"$0" bogus' "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}

# ---------------------------------------------------------------------------
# Mode 4 — Part-1 divergence: a helper whose header drifts from the schema must
# fail the gate. Build a throwaway REPO_ROOT skeleton whose bin/godmode-findings
# is a stub emitting an 8-column header; run the gate from there. The assertion
# pins the header-parity message so the test fails iff the divergence is caught
# at the header check (not incidentally at some other Part-1 assertion).
# ---------------------------------------------------------------------------

@test "check-findings fails when the helper header diverges from the schema" {
  local root="$TMP_ROOT/repo"
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
  run bash -c '"$0"' "$root/scripts/check-findings.sh"
  [ "$status" -ne 0 ]
  # Pin the exact failure point: the header-parity assertion in Part 1.
  [[ "$output" == *"helper header diverged"* ]]
}
