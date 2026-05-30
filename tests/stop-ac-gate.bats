#!/usr/bin/env bats
#
# Stop-hook AC-N coverage gate tests (unit 6, S6 — AC-9).
#
# Drives hooks/stop-ac-gate.sh with synthesized Stop event JSON and asserts the
# block/pass contract from BRIEF AC-3..AC-8:
#   - AC-3  block:   status "verify found gaps" emits {"decision":"block",...}
#                    whose reason names the unit and the recorded next_command.
#   - AC-4  pass:    any other status (e.g. "verified") emits no block.
#   - AC-5  override: GODMODE_AC_GATE=off|0|false|no|OFF disables the gate.
#   - AC-6  loop:    stop_hook_active=true never blocks (no re-entrancy wedge).
#   - AC-7  fail-open: empty stdin / no jq / missing-or-empty cwd / no .planning
#                     / no STATE.md / no status line all exit 0 with no block,
#                     and never create .planning/ where it began absent.
#   - AC-8  valid-JSON: any non-empty stdout is parseable JSON.
#
# Each test builds an isolated cwd dir under $TEST_HOME holding .planning/STATE.md
# and feeds the hook an event via stdin. Event JSON is built with `jq -n --arg`
# so STATE content cannot leak through shell quoting. Bats runs from outside the
# event cwd, so any reliance on process pwd (instead of the event .cwd) would be
# caught: the hook must read .cwd, never pwd.
#
# bash 3.2 / BSD-safe: no GNU-only flags, no bash-4 constructs (CI runs macOS).

load test_helper

STOP_GATE="$PLUGIN_ROOT/hooks/stop-ac-gate.sh"

setup() {
  make_temp_home
}

teardown() {
  teardown_temp_home
}

# Make a fresh repo dir under $TEST_HOME. With $1 == "with-planning", create
# .planning/STATE.md from the supplied fields. Echoes the repo path.
# Usage: make_cwd with-planning <status> [active_unit] [next_command]
#        make_cwd                              # bare dir, no .planning/
make_cwd() {
  local d
  d="$(mktemp -d "$TEST_HOME/cwd-XXXXXX")"
  if [ "${1:-}" = "with-planning" ]; then
    mkdir "$d/.planning"
    {
      [ -n "${2:-}" ] && printf 'status: %s\n' "$2"
      [ -n "${3:-}" ] && printf 'active_unit: %s\n' "$3"
      [ -n "${4:-}" ] && printf 'next_command: %s\n' "$4"
    } > "$d/.planning/STATE.md"
  fi
  printf '%s' "$d"
}

# Build a Stop event JSON via jq -n. cwd is passed as a raw --arg; stop_hook_active
# is injected as a JSON bool only when $2 is non-empty.
# Usage: make_event <cwd> [stop_hook_active]
make_event() {
  if [ -n "${2:-}" ]; then
    jq -n --arg cwd "$1" --argjson active "$2" \
      '{cwd: $cwd, stop_hook_active: $active}'
  else
    jq -n --arg cwd "$1" '{cwd: $cwd}'
  fi
}

# Assert a captured $output is empty or, if non-empty, valid JSON (AC-8).
assert_json_or_empty() {
  if [ -n "$1" ]; then
    printf '%s' "$1" | jq -e . > /dev/null
  fi
}

# Build a stub PATH bindir under $TEST_HOME containing symlinks to every external
# the hook needs EXCEPT jq, so `command -v jq` fails. Echoes the bindir path.
# Used only by the no-jq fail-open case (AC-7).
make_nojq_bindir() {
  local bindir tool src
  bindir="$(mktemp -d "$TEST_HOME/nojq-bin-XXXXXX")"
  for tool in cat sed tr grep head bash; do
    src="$(PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" command -v "$tool")"
    [ -n "$src" ] && ln -s "$src" "$bindir/$tool"
  done
  printf '%s' "$bindir"
}

# --- AC-3: block when verify found gaps ----------------------------------

@test "block: 'verify found gaps' emits block naming unit and next_command (AC-3)" {
  local cwd; cwd="$(make_cwd with-planning "verify found gaps" "6" "/build 6")"
  local event; event="$(make_event "$cwd")"

  run bash "$STOP_GATE" <<<"$event"
  [ "$status" -eq 0 ]
  assert_json_or_empty "$output"

  printf '%s' "$output" | jq -e '.decision == "block"'

  local reason
  reason="$(printf '%s' "$output" | jq -r '.reason')"
  printf '%s' "$reason" | grep -qF '6'
  printf '%s' "$reason" | grep -qF '/build 6'
}

# --- AC-4: pass on any other status --------------------------------------

@test "pass: 'verified' status emits no block (AC-4)" {
  local cwd; cwd="$(make_cwd with-planning "verified" "6" "/build 6")"
  local event; event="$(make_event "$cwd")"

  run bash "$STOP_GATE" <<<"$event"
  [ "$status" -eq 0 ]
  assert_json_or_empty "$output"

  if [ -n "$output" ]; then
    printf '%s' "$output" | jq -e '.decision != "block"'
  fi
}

# --- AC-5: GODMODE_AC_GATE override --------------------------------------

@test "override: GODMODE_AC_GATE off|0|false|no|OFF never blocks (AC-5)" {
  local cwd; cwd="$(make_cwd with-planning "verify found gaps" "6" "/build 6")"
  local event; event="$(make_event "$cwd")"

  local val
  for val in off 0 false no OFF; do
    GODMODE_AC_GATE="$val" run bash "$STOP_GATE" <<<"$event"
    [ "$status" -eq 0 ] || { echo "val=$val status=$status"; false; }
    assert_json_or_empty "$output"
    if [ -n "$output" ]; then
      printf '%s' "$output" | jq -e '.decision != "block"' \
        || { echo "val=$val blocked: $output"; false; }
    fi
  done
}

# --- AC-6: loop safety ---------------------------------------------------

@test "loop-safety: stop_hook_active=true never blocks even with gaps (AC-6)" {
  local cwd; cwd="$(make_cwd with-planning "verify found gaps" "6" "/build 6")"
  local event; event="$(make_event "$cwd" true)"

  run bash "$STOP_GATE" <<<"$event"
  [ "$status" -eq 0 ]
  assert_json_or_empty "$output"

  if [ -n "$output" ]; then
    printf '%s' "$output" | jq -e '.decision != "block"'
  fi
}

# --- AC-7a: empty stdin --------------------------------------------------

@test "fail-open: empty stdin exits 0, no block, no stderr (AC-7)" {
  run bash "$STOP_GATE" < /dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- AC-7b: jq unavailable -----------------------------------------------

@test "fail-open: jq unavailable exits 0, no block (AC-7)" {
  # Gaps status is present, so without the no-jq guard the hook would block.
  local cwd; cwd="$(make_cwd with-planning "verify found gaps" "6" "/build 6")"
  local event; event="$(make_event "$cwd")"

  local bindir; bindir="$(make_nojq_bindir)"
  # Sanity: jq is genuinely off this PATH.
  run env -i PATH="$bindir" bash -c 'command -v jq'
  [ "$status" -ne 0 ]

  run env -i PATH="$bindir" bash "$STOP_GATE" <<<"$event"
  [ "$status" -eq 0 ]
  assert_json_or_empty "$output"
  if [ -n "$output" ]; then
    printf '%s' "$output" | jq -e '.decision != "block"'
  fi
}

# --- AC-7c: missing / empty cwd ------------------------------------------

@test "fail-open: missing cwd key exits 0, no block (AC-7)" {
  local event; event="$(jq -n '{stop_hook_active: false}')"

  run bash "$STOP_GATE" <<<"$event"
  [ "$status" -eq 0 ]
  assert_json_or_empty "$output"
  if [ -n "$output" ]; then
    printf '%s' "$output" | jq -e '.decision != "block"'
  fi
}

@test "fail-open: empty cwd value exits 0, no block (AC-7)" {
  local event; event="$(make_event "")"

  run bash "$STOP_GATE" <<<"$event"
  [ "$status" -eq 0 ]
  assert_json_or_empty "$output"
  if [ -n "$output" ]; then
    printf '%s' "$output" | jq -e '.decision != "block"'
  fi
}

# --- AC-7d: cwd with no .planning/ — and none gets created ---------------

@test "fail-open: no .planning/ dir exits 0 and is never created (AC-7)" {
  local cwd; cwd="$(make_cwd)"   # bare dir, no .planning
  local event; event="$(make_event "$cwd")"

  run bash "$STOP_GATE" <<<"$event"
  [ "$status" -eq 0 ]
  assert_json_or_empty "$output"
  if [ -n "$output" ]; then
    printf '%s' "$output" | jq -e '.decision != "block"'
  fi
  [ ! -d "$cwd/.planning" ]
}

# --- AC-7e: .planning/ present but no STATE.md ---------------------------

@test "fail-open: .planning/ without STATE.md exits 0, no block (AC-7)" {
  local cwd; cwd="$(mktemp -d "$TEST_HOME/cwd-XXXXXX")"
  mkdir "$cwd/.planning"   # dir exists, STATE.md absent
  local event; event="$(make_event "$cwd")"

  run bash "$STOP_GATE" <<<"$event"
  [ "$status" -eq 0 ]
  assert_json_or_empty "$output"
  if [ -n "$output" ]; then
    printf '%s' "$output" | jq -e '.decision != "block"'
  fi
  [ ! -f "$cwd/.planning/STATE.md" ]
}

# --- AC-7f: STATE.md present with no status line -------------------------

@test "fail-open: STATE.md without a status line exits 0, no block (AC-7)" {
  local cwd; cwd="$(mktemp -d "$TEST_HOME/cwd-XXXXXX")"
  mkdir "$cwd/.planning"
  printf 'active_unit: 6\nnext_command: /build 6\n' > "$cwd/.planning/STATE.md"
  local event; event="$(make_event "$cwd")"

  run bash "$STOP_GATE" <<<"$event"
  [ "$status" -eq 0 ]
  assert_json_or_empty "$output"
  if [ -n "$output" ]; then
    printf '%s' "$output" | jq -e '.decision != "block"'
  fi
}
