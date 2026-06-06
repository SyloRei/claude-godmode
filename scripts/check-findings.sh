#!/usr/bin/env bash
#
# check-findings.sh — CI gate for the per-brief findings store (FINDINGS.md).
#
# Why this gate exists: bin/godmode-findings writes a FINDINGS.md markdown
# table that the whole verification spine (/verify, /build --fix, /ship) parses
# by column position. That parser is only safe if EVERY row has exactly the
# 9 documented columns and never carries a raw, unencoded `|` (which would
# forge an extra column and silently shift every downstream field). This gate
# makes any schema drift — in the helper itself or in a committed fixture — a
# hard CI failure instead of a parser that quietly reads the wrong cell.
#
# It runs in two parts:
#   Part 1  helper-contract parity — drive bin/godmode-findings in a temp store
#           and assert it emits the canonical header, percent-encodes raw pipes
#           and newlines, enforces the sev/conf enums, and hides the internal
#           mkey/reason columns from default `list` output.
#   Part 2  fixture validation — every tests/fixtures/findings/valid-*.md must
#           conform to the same schema the helper produces.
#
# Modes:
#   check-findings.sh                 run Part 1 then Part 2 (exit 0 iff both pass)
#   check-findings.sh validate <file> validate a single file (the bats hook)
#   check-findings.sh <anything-else> usage to stderr, exit 1
#
# Bash 3.2 compatible (macOS ships 3.2): no mapfile/readarray, no [[ -v ]],
# no ${var,,}/${var^^}, no associative arrays, no GNU-only flags, BSD-safe sed.
# Pure bash + grep/awk/sed plus the helper under test — no Node/Python/bats/jq.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO_ROOT/bin/godmode-findings"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/findings"

# The canonical 9-column header, exactly as bin/godmode-findings emits it.
CANONICAL_HEADER="| ID | lens | sev | conf | status | location | note | mkey | reason |"

# Temp dir used by Part 1; the EXIT trap cleans it up. Empty on the validate
# path (single-file mode never creates one) so the trap is then a no-op.
_FINDINGS_CHECK_TMP=""
# shellcheck disable=SC2064
trap 'rm -rf "$_FINDINGS_CHECK_TMP"' EXIT

usage() {
  echo "usage: check-findings.sh                 # parity + fixture validation" >&2
  echo "       check-findings.sh validate <file> # validate a single FINDINGS.md" >&2
}

# ---------------------------------------------------------------------------
# validate_file <file>
# The single-file schema validator. Returns 0 when <file> conforms to the
# canonical 9-column FINDINGS.md schema, non-zero (with a stderr message
# naming the file + offending row + reason) on the FIRST violation.
# Shared verbatim between Part 2 and `validate <file>` mode.
# ---------------------------------------------------------------------------
validate_file() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo "findings: file not found: $file" >&2
    return 1
  fi

  # Header line (line 1) must equal the canonical 9-column header exactly.
  local header
  header=$(sed -n '1p' "$file")
  if [ "$header" != "$CANONICAL_HEADER" ]; then
    echo "findings: $file: line 1 header does not match canonical schema" >&2
    echo "  expected: $CANONICAL_HEADER" >&2
    echo "  actual:   $header" >&2
    return 1
  fi

  # Separator line (line 2) must be a markdown separator row with 9 groups.
  local sep
  sep=$(sed -n '2p' "$file")
  case "$sep" in
    "|---|---|---|---|---|---|---|---|---|") ;;
    *)
      echo "findings: $file: line 2 is not the canonical 9-column separator row" >&2
      echo "  actual: $sep" >&2
      return 1
      ;;
  esac

  # Every data row (line 3 onward, non-blank) must split into EXACTLY 9
  # content cells. A well-formed row "| a | ... | i |" has a leading and a
  # trailing empty field around the 9 content cells, so awk -F'|' reports
  # NF == 11. A raw, unencoded `|` inside a cell pushes NF past 11; a missing
  # column drops it below 11 — either way the row is rejected.
  local lineno=0
  local line nf
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [ "$lineno" -le 2 ]; then
      continue
    fi
    # Skip blank lines (trailing newline, deliberate spacing).
    if [ -z "$line" ]; then
      continue
    fi

    nf=$(printf '%s' "$line" | awk -F'|' '{print NF}')
    if [ "$nf" -ne 11 ]; then
      echo "findings: $file: line $lineno does not have exactly 9 cells (found $((nf - 2)))" >&2
      echo "  a raw unencoded '|' (should be %7C) or a missing column is the usual cause" >&2
      echo "  row: $line" >&2
      return 1
    fi

    # Enum checks on the positional columns: sev (4), conf (5), status (6).
    local sev conf status
    sev=$(printf '%s' "$line" | awk -F'|' '{print $4}' \
      | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    conf=$(printf '%s' "$line" | awk -F'|' '{print $5}' \
      | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    status=$(printf '%s' "$line" | awk -F'|' '{print $6}' \
      | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    case "$sev" in
      CRITICAL|WARNING|NIT) ;;
      *)
        echo "findings: $file: line $lineno sev '$sev' not in {CRITICAL,WARNING,NIT}" >&2
        return 1
        ;;
    esac
    case "$conf" in
      HIGH|MEDIUM|LOW) ;;
      *)
        echo "findings: $file: line $lineno conf '$conf' not in {HIGH,MEDIUM,LOW}" >&2
        return 1
        ;;
    esac
    case "$status" in
      open|fixed|waived) ;;
      *)
        echo "findings: $file: line $lineno status '$status' not in {open,fixed,waived}" >&2
        return 1
        ;;
    esac
  done < "$file"

  return 0
}

# ---------------------------------------------------------------------------
# part1_parity — drive the helper and assert it honors the documented schema.
# ---------------------------------------------------------------------------
part1_parity() {
  if [ ! -x "$HELPER" ]; then
    echo "findings: helper not found or not executable: $HELPER" >&2
    return 1
  fi

  _FINDINGS_CHECK_TMP="$(mktemp -d)"
  local store="$_FINDINGS_CHECK_TMP"

  # init the store.
  if ! "$HELPER" init "$store" >/dev/null 2>&1; then
    echo "findings: parity: 'init' failed" >&2
    return 1
  fi

  # add a finding whose note contains a raw '|' and a newline.
  local raw_note
  raw_note="raw | pipe and
newline in note"
  if ! "$HELPER" add "$store" code CRITICAL HIGH "src/foo.sh:42" "$raw_note" >/dev/null 2>&1; then
    echo "findings: parity: 'add' (valid finding) failed" >&2
    return 1
  fi

  local ffile="$store/FINDINGS.md"

  # (a) first line equals the canonical 9-column header.
  local header
  header=$(sed -n '1p' "$ffile")
  if [ "$header" != "$CANONICAL_HEADER" ]; then
    echo "findings: parity: helper header diverged from canonical schema" >&2
    echo "  expected: $CANONICAL_HEADER" >&2
    echo "  actual:   $header" >&2
    return 1
  fi

  # (b) the data row percent-encodes the raw '|' (%7C) and newline (%0A), so
  # it splits into exactly 9 content cells (NF == 11) with no forged column.
  local data_row nf
  data_row=$(sed -n '3p' "$ffile")
  nf=$(printf '%s' "$data_row" | awk -F'|' '{print NF}')
  if [ "$nf" -ne 11 ]; then
    echo "findings: parity: helper data row did not encode to 9 cells (found $((nf - 2)))" >&2
    echo "  row: $data_row" >&2
    return 1
  fi
  case "$data_row" in
    *"%7C"*) ;;
    *)
      echo "findings: parity: raw '|' in note was not encoded to %7C" >&2
      echo "  row: $data_row" >&2
      return 1
      ;;
  esac
  case "$data_row" in
    *"%0A"*) ;;
    *)
      echo "findings: parity: newline in note was not encoded to %0A" >&2
      echo "  row: $data_row" >&2
      return 1
      ;;
  esac

  # Enum validation: a bad sev and a bad conf must both be rejected (exit != 0).
  if "$HELPER" add "$store" code BOGUS HIGH "src/x.sh:1" "bad sev" >/dev/null 2>&1; then
    echo "findings: parity: 'add' accepted an out-of-range sev (BOGUS)" >&2
    return 1
  fi
  if "$HELPER" add "$store" code WARNING BOGUS "src/x.sh:1" "bad conf" >/dev/null 2>&1; then
    echo "findings: parity: 'add' accepted an out-of-range conf (BOGUS)" >&2
    return 1
  fi

  # Default `list` emits exactly the 7 public display columns: the internal
  # mkey (a 40-hex sha1) and reason columns must be hidden. We assert the
  # first listed row has NF == 9 (leading + 7 content + trailing empty fields).
  local list_row list_nf
  list_row=$("$HELPER" list "$store" | sed -n '1p')
  if [ -z "$list_row" ]; then
    echo "findings: parity: 'list' produced no rows" >&2
    return 1
  fi
  list_nf=$(printf '%s' "$list_row" | awk -F'|' '{print NF}')
  if [ "$list_nf" -ne 9 ]; then
    echo "findings: parity: default 'list' did not emit exactly 7 display columns (found $((list_nf - 2)))" >&2
    echo "  row: $list_row" >&2
    return 1
  fi

  # Clean up this temp store now; reset so the EXIT trap stays a no-op.
  rm -rf "$_FINDINGS_CHECK_TMP"
  _FINDINGS_CHECK_TMP=""
  return 0
}

# ---------------------------------------------------------------------------
# part2_fixtures — validate every valid-*.md fixture (positive glob ONLY).
# ---------------------------------------------------------------------------
part2_fixtures() {
  local matched=0
  local f
  # Nullglob is not portable to bash 3.2; guard each candidate with [ -f ].
  for f in "$FIXTURE_DIR"/valid-*.md; do
    [ -f "$f" ] || continue
    matched=1
    if ! validate_file "$f"; then
      return 1
    fi
  done

  if [ "$matched" -eq 0 ]; then
    echo "findings: no valid-*.md fixtures found under $FIXTURE_DIR" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  if [ "$#" -eq 0 ]; then
    if ! part1_parity; then
      echo "findings: helper-contract parity FAILED" >&2
      exit 1
    fi
    if ! part2_fixtures; then
      echo "findings: fixture validation FAILED" >&2
      exit 1
    fi
    echo "findings schema OK (helper parity + fixtures)"
    exit 0
  fi

  case "$1" in
    validate)
      if [ "$#" -ne 2 ]; then
        usage
        exit 1
      fi
      if ! validate_file "$2"; then
        exit 1
      fi
      echo "findings: $2 conforms to schema"
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
