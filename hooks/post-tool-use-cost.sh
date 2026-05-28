#!/usr/bin/env bash
# PostToolUse hook: telemetry-light, per-session token totals.
#
# Contract (Claude Code hooks):
#   - stdin is the event JSON; we read session_id, cwd, and tool_response.usage.
#   - When usage tokens are present and ${cwd}/.planning/ already exists, we
#     upsert a single row keyed by session_id into ${cwd}/.planning/COSTS.md.
#   - The hook is no-op on any missing precondition (empty stdin, no jq, no
#     usage object, no .planning/ dir) and never creates the .planning/ dir.
#
# Telemetry stays local: .planning/ is gitignored. Tokens only — no USD price
# table. The "usage" field is version-dependent per docs/v3-roadmap.md, so its
# absence is the version guard (silently exit 0).
#
# All values reach the file via jq --arg / printf data — never interpolated
# into shell, JSON, or markdown. Adversarial quotes/newlines/backslashes in
# model/session_id are sanitized to single-line strings before they hit the
# table so the markdown layout cannot be broken by content.
#
# bash 3.2 compatible. BSD-safe (no GNU-only awk/sed flags). No associative
# arrays. Reads cwd from stdin JSON, never from pwd.

set -euo pipefail

# Read the full event from stdin. Guard against early EOF under pipefail.
INPUT="$(cat 2>/dev/null || true)"

# AC-5a: nothing to do without input or jq.
if [ -z "$INPUT" ] || ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

# AC-5b: no usage object → version guard, silent no-op.
HAS_USAGE="$(printf '%s' "$INPUT" \
  | jq -r 'if (.tool_response.usage // null) == null
           then "0"
           elif (.tool_response.usage | type) == "object"
                and (.tool_response.usage | length) > 0
           then "1"
           else "0" end' 2>/dev/null || printf '0')"
if [ "$HAS_USAGE" != "1" ]; then
  exit 0
fi

# Extract per-event fields. // empty lets shell defaults handle absence.
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
MODEL="$(printf '%s' "$INPUT" \
  | jq -r '
      (.model // null) as $m
      | if ($m | type) == "object" then ($m.display_name // empty)
        elif ($m | type) == "string" then $m
        else empty end
    ' 2>/dev/null || true)"

# Token sub-fields each default to 0 (AC-7 — missing sub-fields → 0).
IN_TOK="$(printf '%s' "$INPUT" \
  | jq -r '.tool_response.usage.input_tokens // 0' 2>/dev/null || printf '0')"
OUT_TOK="$(printf '%s' "$INPUT" \
  | jq -r '.tool_response.usage.output_tokens // 0' 2>/dev/null || printf '0')"
CR_TOK="$(printf '%s' "$INPUT" \
  | jq -r '.tool_response.usage.cache_read_input_tokens // 0' 2>/dev/null || printf '0')"
CC_TOK="$(printf '%s' "$INPUT" \
  | jq -r '.tool_response.usage.cache_creation_input_tokens // 0' 2>/dev/null || printf '0')"

# Coerce to integers; reject anything not a non-negative integer.
case "$IN_TOK" in ''|*[!0-9]*) IN_TOK=0 ;; esac
case "$OUT_TOK" in ''|*[!0-9]*) OUT_TOK=0 ;; esac
case "$CR_TOK" in ''|*[!0-9]*) CR_TOK=0 ;; esac
case "$CC_TOK" in ''|*[!0-9]*) CC_TOK=0 ;; esac

# Default session_id / model when absent.
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"
[ -z "$MODEL" ] && MODEL="—"

# AC-5c: only write into an existing .planning/ — never mkdir it.
if [ -z "$CWD" ] || [ ! -d "${CWD}/.planning" ]; then
  exit 0
fi

COSTS="${CWD}/.planning/COSTS.md"

# Best-effort UTC timestamp; empty on failure (acceptable per brief).
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
[ -z "$TS" ] && TS="—"

# Sanitize markdown-table-hostile characters to single-line, pipe-free text.
# Done in jq so we never interpolate raw user data into shell or awk source.
# Backslashes are also normalized to "/" because BSD awk's -v assignment
# interprets backslash escapes — stripping them here keeps the round-trip
# faithful and the table parseable.
SAFE_SESSION="$(printf '%s' "$SESSION_ID" \
  | jq -Rrs 'gsub("\r"; " ") | gsub("\n"; " ") | gsub("\\|"; "/") | gsub("\\\\"; "/")')"
SAFE_MODEL="$(printf '%s' "$MODEL" \
  | jq -Rrs 'gsub("\r"; " ") | gsub("\n"; " ") | gsub("\\|"; "/") | gsub("\\\\"; "/")')"

# Stable header — AC-7 column order.
HEADER_LINE='| session | timestamp | model | input | output | cache-read | cache-creation | total |'
SEP_LINE='| --- | --- | --- | --- | --- | --- | --- | --- |'

TMP="${COSTS}.tmp.$$"

# Upsert via a single awk pass over the prior file. No associative arrays:
# we scan rows, sum tokens on the matching session_id, and rewrite the file.
# If the prior file is missing/empty, awk reads /dev/null and just emits the
# new row under a fresh header. session_id is the first cell; we extract it
# exactly the way printf wrote it ("| <session> | ..."), so the round-trip is
# deterministic for sanitized values.
SRC="$COSTS"
[ -f "$COSTS" ] || SRC="/dev/null"

awk \
  -v session="$SAFE_SESSION" \
  -v ts="$TS" \
  -v model="$SAFE_MODEL" \
  -v in_tok="$IN_TOK" \
  -v out_tok="$OUT_TOK" \
  -v cr_tok="$CR_TOK" \
  -v cc_tok="$CC_TOK" \
  -v header="$HEADER_LINE" \
  -v sep="$SEP_LINE" '
  BEGIN {
    sum_in = in_tok + 0
    sum_out = out_tok + 0
    sum_cr = cr_tok + 0
    sum_cc = cc_tok + 0
    row_ts = ts
    row_model = model
    n = 0
  }
  # Capture pre-existing data rows. A data row starts with "| " and is not the
  # header or separator. Field 2 (between the 1st and 2nd "|") is session.
  {
    line = $0
    if (line == header || line == sep) { next }
    if (substr(line, 1, 2) != "| ") { next }
    # Split on "|" — leading/trailing fields are empty due to outer pipes.
    nf = split(line, parts, "|")
    if (nf < 9) { next }
    s = parts[2]; sub(/^ /, "", s); sub(/ $/, "", s)
    if (s == session) {
      # Accumulate this session into the new row, refresh timestamp & model
      # to the latest event so the row reflects last activity.
      sum_in  += (parts[5] + 0)
      sum_out += (parts[6] + 0)
      sum_cr  += (parts[7] + 0)
      sum_cc  += (parts[8] + 0)
      next
    }
    # Preserve other sessions in first-seen order.
    n++
    keep[n] = line
  }
  END {
    print header
    print sep
    for (i = 1; i <= n; i++) print keep[i]
    total = sum_in + sum_out + sum_cr + sum_cc
    printf "| %s | %s | %s | %d | %d | %d | %d | %d |\n", \
      session, row_ts, row_model, sum_in, sum_out, sum_cr, sum_cc, total
  }
' "$SRC" > "$TMP" 2>/dev/null || { rm -f "$TMP"; exit 0; }

mv "$TMP" "$COSTS" 2>/dev/null || { rm -f "$TMP"; exit 0; }

exit 0
