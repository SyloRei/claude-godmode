#!/usr/bin/env bats
#
# Cost-tracking hook tests (unit 4, S4 — AC-10).
#
# Drives hooks/post-tool-use-cost.sh with synthesized PostToolUse JSON events
# and asserts the COSTS.md table contract from BRIEF AC-2..AC-7:
#   - AC-2  create:  first event writes ${cwd}/.planning/COSTS.md with header.
#   - AC-3  upsert:  two events with the same session_id sum into one row.
#   - AC-4  multi:   distinct session_ids produce distinct rows.
#   - AC-5  no-op:   (a) empty stdin, (b) absent usage, (c) no .planning/ dir.
#   - AC-6  adversarial: quotes/newlines/backslashes/pipes do not break table.
#   - AC-7  header + integer cells (incl. partial-usage defaults-to-zero).
#
# Each test builds its own isolated cwd dir under $TEST_HOME and feeds the
# hook an event via stdin. Event JSON is built with `jq -n --arg` to keep
# adversarial values out of shell quoting.

load test_helper

COST="$PLUGIN_ROOT/hooks/post-tool-use-cost.sh"

setup() {
  make_temp_home
}

teardown() {
  teardown_temp_home
}

# Make a fresh cwd dir under $TEST_HOME. With $1 == "with-planning",
# also create the .planning/ subdir. Echoes the cwd path.
make_cwd() {
  local d
  d="$(mktemp -d "$TEST_HOME/cwd-XXXXXX")"
  if [ "${1:-}" = "with-planning" ]; then
    mkdir "$d/.planning"
  fi
  printf '%s' "$d"
}

# Build a full PostToolUse event JSON via jq -n.
# Usage: make_event <session_id> <cwd> <model> <in> <out> <cr> <cc>
make_event() {
  jq -n \
    --arg session "$1" \
    --arg cwd "$2" \
    --arg model "$3" \
    --argjson in_t "$4" \
    --argjson out_t "$5" \
    --argjson cr_t "$6" \
    --argjson cc_t "$7" \
    '{
       session_id: $session,
       cwd: $cwd,
       model: $model,
       tool_response: {
         usage: {
           input_tokens: $in_t,
           output_tokens: $out_t,
           cache_read_input_tokens: $cr_t,
           cache_creation_input_tokens: $cc_t
         }
       }
     }'
}

# Count data rows for a given session_id (first cell match).
count_session_rows() {
  local file="$1" sid="$2"
  # Leading pipe + space + session_id + space + pipe. Sanitization may convert
  # the raw session into a single-line form, but for plain ASCII IDs this is
  # a faithful match.
  grep -c "^| ${sid} |" "$file" || true
}

# --- AC-2: create COSTS.md on first event --------------------------------

@test "create: writes COSTS.md with header on first event (AC-2)" {
  local cwd; cwd="$(make_cwd with-planning)"
  local event; event="$(make_event "sess-a" "$cwd" "claude-opus" 100 50 20 10)"

  run bash "$COST" <<<"$event"
  [ "$status" -eq 0 ]
  [ -f "$cwd/.planning/COSTS.md" ]

  local header
  header="$(head -n 1 "$cwd/.planning/COSTS.md")"
  [ "$header" = '| session | timestamp | model | input | output | cache-read | cache-creation | total |' ]
}

# --- AC-3: upsert + accumulate per session_id ----------------------------

@test "upsert: same session_id accumulates tokens into one row (AC-3)" {
  local cwd; cwd="$(make_cwd with-planning)"
  local e1 e2
  e1="$(make_event "sess-acc" "$cwd" "claude-opus" 100 50 20 10)"
  e2="$(make_event "sess-acc" "$cwd" "claude-opus"   7  3  1  4)"

  run bash "$COST" <<<"$e1"; [ "$status" -eq 0 ]
  run bash "$COST" <<<"$e2"; [ "$status" -eq 0 ]

  local file="$cwd/.planning/COSTS.md"
  [ -f "$file" ]

  local rows
  rows="$(count_session_rows "$file" "sess-acc")"
  [ "$rows" -eq 1 ] || { echo "rows=$rows"; cat "$file"; false; }

  # Parse the data row's numeric columns. Layout per hook:
  #   | session | ts | model | input | output | cache-read | cache-creation | total |
  # awk splits on "|", fields 5..9 are the five integers (with surrounding spaces).
  local row
  row="$(grep "^| sess-acc |" "$file")"
  # shellcheck disable=SC2016
  local nums
  nums="$(printf '%s\n' "$row" | awk -F'|' '{
    for (i = 5; i <= 9; i++) { gsub(/ /, "", $i); printf "%s ", $i }
    print ""
  }')"
  # Expected sums: in=107, out=53, cr=21, cc=14, total=195.
  echo "row: $row"
  echo "nums: $nums"
  [ "$nums" = "107 53 21 14 195 " ]
}

# --- AC-4: multi-session — distinct rows ---------------------------------

@test "multi-session: distinct session_ids yield distinct rows (AC-4)" {
  local cwd; cwd="$(make_cwd with-planning)"
  local e1 e2
  e1="$(make_event "sess-aaa" "$cwd" "claude-opus" 10 20 0 0)"
  e2="$(make_event "sess-bbb" "$cwd" "claude-opus" 30 40 0 0)"

  run bash "$COST" <<<"$e1"; [ "$status" -eq 0 ]
  run bash "$COST" <<<"$e2"; [ "$status" -eq 0 ]

  local file="$cwd/.planning/COSTS.md"
  [ -f "$file" ]

  local a b
  a="$(count_session_rows "$file" "sess-aaa")"
  b="$(count_session_rows "$file" "sess-bbb")"
  [ "$a" -eq 1 ] || { echo "a=$a"; cat "$file"; false; }
  [ "$b" -eq 1 ] || { echo "b=$b"; cat "$file"; false; }

  # And the two rows are textually distinct.
  local row_a row_b
  row_a="$(grep "^| sess-aaa |" "$file")"
  row_b="$(grep "^| sess-bbb |" "$file")"
  [ "$row_a" != "$row_b" ]
}

# --- AC-5a: empty stdin is a no-op ---------------------------------------

@test "no-op: empty stdin exits 0 and creates nothing (AC-5a)" {
  local cwd; cwd="$(make_cwd with-planning)"

  run bash "$COST" < /dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$cwd/.planning/COSTS.md" ]
}

# --- AC-5b: absent / empty usage is a no-op ------------------------------

@test "no-op: empty usage object exits 0 and creates nothing (AC-5b)" {
  local cwd; cwd="$(make_cwd with-planning)"

  # Valid event shape but tool_response.usage is empty -> version-guard no-op.
  local event
  event="$(jq -n --arg session "sess-noop" --arg cwd "$cwd" \
    '{session_id: $session, cwd: $cwd, tool_response: {usage: {}}}')"

  run bash "$COST" <<<"$event"
  [ "$status" -eq 0 ]
  [ ! -f "$cwd/.planning/COSTS.md" ]

  # Also: tool_response with no usage key at all.
  local event2
  event2="$(jq -n --arg session "sess-noop2" --arg cwd "$cwd" \
    '{session_id: $session, cwd: $cwd, tool_response: {}}')"

  run bash "$COST" <<<"$event2"
  [ "$status" -eq 0 ]
  [ ! -f "$cwd/.planning/COSTS.md" ]
}

# --- AC-5c: cwd without .planning/ — no creation, no mkdir ---------------

@test "no-op: missing .planning/ dir exits 0 and is not created (AC-5c)" {
  local cwd; cwd="$(make_cwd)"   # no .planning subdir

  local event
  event="$(make_event "sess-bare" "$cwd" "claude-opus" 100 50 20 10)"

  run bash "$COST" <<<"$event"
  [ "$status" -eq 0 ]
  [ ! -d "$cwd/.planning" ]
  [ ! -f "$cwd/.planning/COSTS.md" ]
}

# --- AC-6: adversarial session_id / model -------------------------------

@test "adversarial: quotes/newlines/backslashes/pipes preserve table shape (AC-6)" {
  local cwd; cwd="$(make_cwd with-planning)"

  # session_id and model carry every markdown-table-hostile char.
  # jq -n --arg handles the raw bytes safely; the hook sanitizes them.
  local nasty_session=$'has "quote" and\nnewline and \\back and | pipe'
  local nasty_model=$'model "x" \\ y | z\nnext'

  local event
  event="$(jq -n \
    --arg session "$nasty_session" \
    --arg cwd "$cwd" \
    --arg model "$nasty_model" \
    '{
       session_id: $session,
       cwd: $cwd,
       model: $model,
       tool_response: {usage: {input_tokens: 1, output_tokens: 2, cache_read_input_tokens: 3, cache_creation_input_tokens: 4}}
     }')"

  run bash "$COST" <<<"$event"
  [ "$status" -eq 0 ]

  local file="$cwd/.planning/COSTS.md"
  [ -f "$file" ]

  # First non-blank line is the documented header.
  local header
  header="$(awk 'NF { print; exit }' "$file")"
  [ "$header" = '| session | timestamp | model | input | output | cache-read | cache-creation | total |' ]

  # Every non-blank line has exactly 9 pipes (8 columns with outer pipes).
  # We do not assert specific sanitization output — only table shape.
  local bad
  bad="$(awk 'NF {
    n = gsub(/\|/, "|", $0)
    if (n != 9) { print NR ":" n ":" $0 }
  }' "$file")"
  [ -z "$bad" ] || { echo "malformed rows:"; echo "$bad"; echo "---"; cat "$file"; false; }
}

# --- AC-7: header column names + integer cells --------------------------

@test "header: names all eight columns and cell counts are integers (AC-7)" {
  local cwd; cwd="$(make_cwd with-planning)"
  local event; event="$(make_event "sess-hdr" "$cwd" "claude-opus" 11 22 33 44)"
  run bash "$COST" <<<"$event"
  [ "$status" -eq 0 ]

  local file="$cwd/.planning/COSTS.md"
  local header_lc
  header_lc="$(head -n 1 "$file" | tr '[:upper:]' '[:lower:]')"

  printf '%s' "$header_lc" | grep -qF 'session'
  printf '%s' "$header_lc" | grep -qF 'timestamp'
  printf '%s' "$header_lc" | grep -qF 'model'
  printf '%s' "$header_lc" | grep -qF 'input'
  printf '%s' "$header_lc" | grep -qF 'output'
  printf '%s' "$header_lc" | grep -qF 'cache-read'
  printf '%s' "$header_lc" | grep -qF 'cache-creation'
  printf '%s' "$header_lc" | grep -qF 'total'

  # The four count columns + total cell are integers.
  local row
  row="$(grep "^| sess-hdr |" "$file")"
  [ -n "$row" ] || { cat "$file"; false; }

  # Extract numeric columns 5..9 (input/output/cache-read/cache-creation/total).
  local i
  for i in 5 6 7 8 9; do
    local cell
    cell="$(printf '%s\n' "$row" | awk -F'|' -v idx="$i" '{ gsub(/ /, "", $idx); print $idx }')"
    [[ "$cell" =~ ^[0-9]+$ ]] || { echo "col $i not integer: '$cell' in row: $row"; false; }
  done
}

# --- AC-7 supporting: partial usage defaults missing sub-fields to 0 ----

@test "partial-usage: missing sub-fields default to 0; total reflects (AC-7)" {
  local cwd; cwd="$(make_cwd with-planning)"

  # Only input_tokens provided.
  local event
  event="$(jq -n --arg session "sess-part" --arg cwd "$cwd" \
    '{
       session_id: $session,
       cwd: $cwd,
       tool_response: {usage: {input_tokens: 50}}
     }')"

  run bash "$COST" <<<"$event"
  [ "$status" -eq 0 ]

  local file="$cwd/.planning/COSTS.md"
  [ -f "$file" ]

  local row
  row="$(grep "^| sess-part |" "$file")"
  [ -n "$row" ] || { cat "$file"; false; }

  # Columns 5..9: input=50, output=0, cache-read=0, cache-creation=0, total=50.
  local nums
  nums="$(printf '%s\n' "$row" | awk -F'|' '{
    for (i = 5; i <= 9; i++) { gsub(/ /, "", $i); printf "%s ", $i }
    print ""
  }')"
  [ "$nums" = "50 0 0 0 50 " ] || { echo "row: $row"; echo "nums: $nums"; cat "$file"; false; }
}
