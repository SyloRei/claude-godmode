#!/usr/bin/env bash
# PostToolUse hook: telemetry-light, per-session token totals.
#
# Contract (Claude Code hooks):
#   - stdin is the event JSON; we read session_id, cwd, and tool_response.usage.
#   - When usage tokens are present and ${cwd}/.planning/ already exists, we
#     upsert a single row keyed by session_id into ${cwd}/.planning/COSTS.md.
#   - No-op (exit 0) on any missing precondition: empty stdin, no jq, no usage
#     object, no/invalid cwd, missing .planning/ dir. Never creates .planning/.
#
# Telemetry stays local: .planning/ is gitignored. Tokens only — no USD price
# table. The "usage" field is version-dependent per docs/v3-roadmap.md so its
# absence is the version guard. cwd is canonicalized (resolves `..`/symlinks)
# and a symlink at the COSTS path is refused (defense-in-depth). An mkdir
# lock + atomic tempfile + EXIT trap keep parallel hook invocations from
# losing data or leaking partial writes.
#
# bash 3.2 compatible. BSD-safe (no GNU-only flags). All values reach the
# file via jq/printf data — never interpolated into shell, awk source, or
# markdown.

set -euo pipefail

INPUT="$(cat 2>/dev/null || true)"

# AC-5a: nothing to do without input or jq.
if [ -z "$INPUT" ] || ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

# Single jq pass: validate usage + cwd, then emit one sanitized TSV row.
# Output is empty (-> no-op) when any guard fails. Folding extraction +
# sanitization here drops what was previously 9 jq forks per hook fire to 1.
TSV="$(printf '%s' "$INPUT" | jq -r '
  def san: tostring
    | gsub("[\n\r\t]"; " ")
    | gsub("\\|"; "/")
    | gsub("\\\\"; "/");
  if (.tool_response.usage // null) == null then empty
  elif (.tool_response.usage | type) != "object" then empty
  elif (.tool_response.usage | length) == 0 then empty
  elif (.cwd // "") == "" then empty
  else
    [
      ((.session_id // "" | if . == "" then "unknown" else . end) | san),
      .cwd,
      ((if (.model | type) == "object" then (.model.display_name // "")
        elif (.model | type) == "string" then .model
        else "" end)
       | (if . == "" then "—" else . end) | san),
      ((.tool_response.usage.input_tokens             // 0) | tostring),
      ((.tool_response.usage.output_tokens            // 0) | tostring),
      ((.tool_response.usage.cache_read_input_tokens  // 0) | tostring),
      ((.tool_response.usage.cache_creation_input_tokens // 0) | tostring)
    ] | @tsv
  end
' 2>/dev/null || true)"

# AC-5b: no usable usage / cwd -> silent no-op.
if [ -z "$TSV" ]; then
  exit 0
fi

# Split TSV. All fields are non-empty by construction in jq above.
IFS=$'\t' read -r SAFE_SESSION CWD SAFE_MODEL IN_TOK OUT_TOK CR_TOK CC_TOK <<< "$TSV"

# Defensive coercion: reject anything that isn't a non-negative integer.
case "$IN_TOK"  in ''|*[!0-9]*) IN_TOK=0  ;; esac
case "$OUT_TOK" in ''|*[!0-9]*) OUT_TOK=0 ;; esac
case "$CR_TOK"  in ''|*[!0-9]*) CR_TOK=0  ;; esac
case "$CC_TOK"  in ''|*[!0-9]*) CC_TOK=0  ;; esac

# Canonicalize cwd via cd+pwd -P (BSD-safe; resolves `..` and symlinks). A
# crafted .cwd carrying traversal segments cannot escape its own resolved dir.
CANON_CWD="$( cd "$CWD" 2>/dev/null && pwd -P )" || exit 0

# AC-5c: only write into an existing .planning/ — never mkdir it.
[ -d "${CANON_CWD}/.planning" ] || exit 0

COSTS="${CANON_CWD}/.planning/COSTS.md"

# Refuse a symlink at the COSTS path so we never write through one.
if [ -L "$COSTS" ]; then
  exit 0
fi

# Best-effort UTC timestamp; falls back to "—" if date fails.
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
[ -z "$TS" ] && TS="—"

HEADER_LINE='| session | timestamp | model | input | output | cache-read | cache-creation | total |'
SEP_LINE='| --- | --- | --- | --- | --- | --- | --- | --- |'

# Acquire an mkdir-based lock so two parallel hook fires don't both read the
# same stale COSTS.md and overwrite each other (last-writer-wins data loss).
# Bounded retry stays well under the 10s hook timeout; if we still can't
# acquire, we silently skip this event rather than block the agent.
LOCK_DIR="${COSTS}.lock"
attempts=0
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  attempts=$((attempts + 1))
  if [ "$attempts" -gt 5 ]; then
    exit 0
  fi
  sleep 1
done

# EXIT trap cleans up both the lock and any orphan tempfile. Set before
# mktemp so a failure between here and mv still releases the lock.
TMP=""
# shellcheck disable=SC2064
trap 'rm -f "$TMP" 2>/dev/null; rmdir "$LOCK_DIR" 2>/dev/null' EXIT

TMP="$(mktemp "${COSTS}.tmp.XXXXXX" 2>/dev/null)" || exit 0

SRC="$COSTS"
[ -f "$COSTS" ] || SRC="/dev/null"

# Single awk pass: rewrite the table, summing into the matching session row
# or appending a new row. No associative arrays (bash 3.2 / BSD-safe). All
# values arrive via -v from already-sanitized shell variables, so awk's
# backslash-escape semantics on -v have nothing left to interpret.
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
    sum_in  = in_tok  + 0
    sum_out = out_tok + 0
    sum_cr  = cr_tok  + 0
    sum_cc  = cc_tok  + 0
    n = 0
  }
  {
    line = $0
    if (line == header || line == sep) { next }
    if (substr(line, 1, 2) != "| ") { next }
    nf = split(line, parts, "|")
    if (nf < 9) { next }
    s = parts[2]; sub(/^ /, "", s); sub(/ $/, "", s)
    if (s == session) {
      sum_in  += (parts[5] + 0)
      sum_out += (parts[6] + 0)
      sum_cr  += (parts[7] + 0)
      sum_cc  += (parts[8] + 0)
      next
    }
    n++
    keep[n] = line
  }
  END {
    print header
    print sep
    for (i = 1; i <= n; i++) print keep[i]
    total = sum_in + sum_out + sum_cr + sum_cc
    printf "| %s | %s | %s | %d | %d | %d | %d | %d |\n", \
      session, ts, model, sum_in, sum_out, sum_cr, sum_cc, total
  }
' "$SRC" > "$TMP" 2>/dev/null || exit 0

mv "$TMP" "$COSTS" 2>/dev/null || exit 0
TMP=""  # Disarm the trap's rm — the file is now COSTS, not a temp.

exit 0
