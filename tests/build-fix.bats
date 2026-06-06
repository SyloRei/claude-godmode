#!/usr/bin/env bats
# ---------------------------------------------------------------------------
# Pins the unit-4 fix flow: skills/build/SKILL.md §8 (--fix) prose contract
# AND the bin/godmode-findings helper behaviour the fix flow consumes.
#
# Two classes, one file:
#   Class A — prose/frontmatter grep against the edited skills/build/SKILL.md
#             on disk (these fail unless S1's §8 + frontmatter grant are present).
#   Class B — helper-contract: drive the shipped bin/godmode-findings, mirroring
#             tests/verify-findings.bats's reconcile-batch stdin pattern.
#
# Class A NEVER executes the /build prose skill (it is disable-model-invocation);
# it only greps the prose text. Class B only drives the helper binary.
#
# AC-2 (blocking-subset target + --all widening), AC-7 (reopened round-trip),
# AC-8 (fixed excludes open; no done-set; §8 must-not-write completion marker),
# AC-10 (empty-stop + helper frozen), AC-11 (helper-contract pins).
# Prose-grep backing for AC-1/AC-3/AC-5/AC-9.
#
# Bash 3.2 / bats-core compatible. shellcheck-clean.
# ---------------------------------------------------------------------------

load test_helper

FINDINGS="$PLUGIN_ROOT/bin/godmode-findings"
SKILL="$PLUGIN_ROOT/skills/build/SKILL.md"

# ---------------------------------------------------------------------------
# Harness — mirrors tests/verify-findings.bats exactly.
# ---------------------------------------------------------------------------

setup() {
  BRIEF_DIR="$(mktemp -d "${TMPDIR:-/tmp}/build-fix.XXXXXX")"
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

# Slice the §8 region: from the `## Step 8` heading up to the next `## ` heading
# (`## Output`). `build complete` legitimately appears in Step 7, so every §8
# prose assertion scopes to this slice only.
section8() {
  awk '/^## Step 8/{f=1} /^## Output/{f=0} f' "$SKILL"
}

# ---------------------------------------------------------------------------
# Class A — prose / frontmatter grep (S1 must be present on disk)
# ---------------------------------------------------------------------------

@test "AC-9 (frontmatter): allowed-tools grants Bash(*godmode-findings*)" {
  # The fix flow's orchestrator must be allowed to call the findings helper.
  run grep -nE '^allowed-tools:.*godmode-findings' "$SKILL"
  [ "$status" -eq 0 ]
}

@test "AC-2/AC-5 (§8 cites the helper predicate): list --open --blocking --decode contiguous call + transition … fixed" {
  local s8
  s8=$(section8)
  # The normative default-target call must appear as a contiguous string — a
  # token-scatter across unrelated sentences cannot satisfy this.
  # SC2016 intentional: single quotes used so the shell does NOT expand
  # $brief_dir / $finding_id — we are grepping for the literal prose text.
  # shellcheck disable=SC2016
  printf '%s\n' "$s8" | grep -qF 'list "$brief_dir" --open --blocking --decode'
  # shellcheck disable=SC2016
  printf '%s\n' "$s8" | grep -qF 'transition "$brief_dir" "$finding_id" fixed'
}

@test "AC-3 (§8 group-by-file): basename + :NNN line-suffix stripped" {
  local s8
  s8=$(section8)
  printf '%s\n' "$s8" | grep -qF "basename"
  printf '%s\n' "$s8" | grep -qF ":NNN"
  # The grouping language itself ("one per file" / bucket).
  printf '%s\n' "$s8" | grep -qiE "one per file|per file|bucket"
}

@test "AC-1 (§8 forbids --no-verify): prohibition sentence is present" {
  local s8
  s8=$(section8)
  # Pin the actual prohibition phrase from §8d — a drift to "use --no-verify
  # when gates are slow" would no longer match this pattern.
  printf '%s\n' "$s8" | grep -qiE "Never \`--no-verify\`|never bypass"
}

@test "AC-5 (§8 orchestrator-only): agent NEVER calls godmode-findings; orchestrator transitions" {
  local s8
  s8=$(section8)
  # The agent-never-calls-helper wording (8e).
  printf '%s\n' "$s8" | grep -qF "NEVER calls"
  printf '%s\n' "$s8" | grep -qF "godmode-findings"
  # The orchestrator is named as the marker-writer.
  printf '%s\n' "$s8" | grep -qiF "orchestrator"
}

@test "AC-8 (§8 must-not write the plan-flow completion marker): conjoined prohibition sentence" {
  # 'build complete' appears in §8 ONLY inside the MUST-NOT prohibition (it
  # legitimately appears for real in Step 7, which the §8 slice excludes).
  # Pin the conjoined prohibition phrase — matching the three words in isolation
  # across unrelated sentences is NOT sufficient.
  local s8
  s8=$(section8)
  printf '%s\n' "$s8" | grep -qF 'MUST NOT'
  # The actual prohibition sentence from §8h — contiguous phrase ensures
  # deleting the prohibition while keeping the three words elsewhere still fails.
  printf '%s\n' "$s8" | grep -qE "MUST NOT.*write.*build complete"
  # And it must be tied to NOT corrupting plan-flow resumability.
  printf '%s\n' "$s8" | grep -qiF "resumability"
}

@test "AC-2 (§8 --all widens the target): names --all and --open-without-blocking widening" {
  local s8
  s8=$(section8)
  printf '%s\n' "$s8" | grep -qF -- "--all"
  # The widening narrative: every open finding, blocking or not.
  printf '%s\n' "$s8" | grep -qiE "every open finding|widen"
}

# ---------------------------------------------------------------------------
# Class B — helper-contract (drive the shipped bin/godmode-findings)
# ---------------------------------------------------------------------------

@test "AC-8 (fixed excludes open / no done-set): transition F? fixed → list --open drops it, other finding still present" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "CRITICAL" "HIGH" "db.ts:5" "sql injection risk" \
    > "$batchfile"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "WARNING" "HIGH" "auth.ts:10" "unvalidated input" \
    >> "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Discover the assigned IDs from the decoded open list (col 2).
  run "$FINDINGS" list "$BRIEF_DIR" --open --decode
  [ "$status" -eq 0 ]
  local first_id second_id
  first_id=$(printf '%s\n' "$output" \
    | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 ~ /^F[0-9]+$/) {print $2; exit}}')
  second_id=$(printf '%s\n' "$output" \
    | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 ~ /^F[0-9]+$/) ids[++n]=$2} END{if (n>=2) print ids[2]}')
  [ -n "$first_id" ]
  [ -n "$second_id" ]

  # Transition the first finding to fixed (the only writer of open -> fixed).
  run "$FINDINGS" transition "$BRIEF_DIR" "$first_id" fixed
  [ "$status" -eq 0 ]

  # list --open must no longer include the fixed finding — resumability comes
  # from the fixed status itself, not a done-set.
  run "$FINDINGS" list "$BRIEF_DIR" --open --decode
  [ "$status" -eq 0 ]
  if printf '%s\n' "$output" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "'"$first_id"'") found=1} END{exit !found}' 2>/dev/null; then
    echo "FAIL: fixed finding ${first_id} still appears in list --open" >&2
    return 1
  fi

  # POSITIVE: the OTHER open finding must still be present — guards against a
  # whole-store-clear regression that would drop both rows.
  if ! printf '%s\n' "$output" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "'"$second_id"'") found=1} END{exit !found}'; then
    echo "FAIL: open finding ${second_id} missing from list --open after transitioning ${first_id}" >&2
    return 1
  fi
}

@test "AC-7 (reopened round-trip): fixed finding re-reconciled while present → reopened, status open" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "HIGH" "api.ts:20" "error not handled" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]
  local fid
  fid=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')
  [ -n "$fid" ]

  # /build transitions it to fixed.
  run "$FINDINGS" transition "$BRIEF_DIR" "$fid" fixed
  [ "$status" -eq 0 ]

  # /verify re-reconciles the SAME finding (it recurred) → must be 'reopened'.
  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "${fid} reopened"

  # And it is open again — back in the target set.
  run "$FINDINGS" list "$BRIEF_DIR" --open --decode
  [ "$status" -eq 0 ]
  if ! printf '%s\n' "$output" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "'"$fid"'") found=1} END{exit !found}'; then
    echo "FAIL: reopened finding ${fid} not found in list --open" >&2
    return 1
  fi
}

@test "AC-2 (blocking subset is narrower): non-blocking finding in --open but NOT --open --blocking" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  # One blocking (CRITICAL) and one non-blocking (NIT/LOW).
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "HIGH" "db.ts:5" "sql injection risk" \
    > "$batchfile"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "perf-reviewer" "NIT" "LOW" "loop.ts:77" "minor allocation" \
    >> "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # The non-blocking NIT/LOW finding's ID — extracted by field, not space-grep.
  run "$FINDINGS" list "$BRIEF_DIR" --open --decode
  [ "$status" -eq 0 ]
  local nit_id
  nit_id=$(printf '%s\n' "$output" \
    | awk -F'|' '{
        id=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
        sev=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sev)
        if (sev == "NIT") {print id; exit}
      }')
  [ -n "$nit_id" ]

  # The full open (--all) set DOES include the non-blocking finding.
  if ! printf '%s\n' "$output" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "'"$nit_id"'") found=1} END{exit !found}'; then
    echo "FAIL: non-blocking ${nit_id} not found in list --open (--all set)" >&2
    return 1
  fi

  # The blocking subset (gates /ship, default fix target) does NOT.
  run "$FINDINGS" list "$BRIEF_DIR" --open --blocking --decode
  [ "$status" -eq 0 ]
  if printf '%s\n' "$output" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "'"$nit_id"'") found=1} END{exit !found}' 2>/dev/null; then
    echo "FAIL: non-blocking ${nit_id} appeared in --open --blocking" >&2
    return 1
  fi
}

@test "AC-2 (--all widening): WARNING/HIGH blocking + NIT/LOW non-blocking — --open --blocking returns fewer rows than --open" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  # WARNING/HIGH is blocking via the conf-only arm (*:HIGH).
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "WARNING" "HIGH" "login.ts:5" "weak session token" \
    > "$batchfile"
  # NIT/LOW is non-blocking (neither arm matches).
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "perf-reviewer" "NIT" "LOW" "loop.ts:3" "trivial alloc" \
    >> "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Capture the non-blocking (NIT/LOW) id.
  run "$FINDINGS" list "$BRIEF_DIR" --open --decode
  [ "$status" -eq 0 ]
  local open_output nit_id open_count
  open_output="$output"
  open_count=$(printf '%s\n' "$open_output" | awk -F'|' 'NF>3{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 ~ /^F[0-9]+$/) c++} END{print c+0}')
  nit_id=$(printf '%s\n' "$open_output" \
    | awk -F'|' '{
        id=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
        sev=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sev)
        if (sev == "NIT") {print id; exit}
      }')
  [ -n "$nit_id" ]

  # --open --blocking must return FEWER rows (1 vs 2).
  run "$FINDINGS" list "$BRIEF_DIR" --open --blocking --decode
  [ "$status" -eq 0 ]
  local blocking_count
  blocking_count=$(printf '%s\n' "$output" | awk -F'|' 'NF>3{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 ~ /^F[0-9]+$/) c++} END{print c+0}')
  [ "$blocking_count" -lt "$open_count" ]

  # NIT/LOW appears in --open but NOT in --open --blocking.
  if ! printf '%s\n' "$open_output" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "'"$nit_id"'") found=1} END{exit !found}'; then
    echo "FAIL: NIT/LOW ${nit_id} not found in --open (all set)" >&2
    return 1
  fi
  if printf '%s\n' "$output" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "'"$nit_id"'") found=1} END{exit !found}' 2>/dev/null; then
    echo "FAIL: NIT/LOW ${nit_id} appeared in --open --blocking" >&2
    return 1
  fi
}

@test "AC-10 (empty-stop): store with only a non-blocking finding → --open --blocking is empty" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "perf-reviewer" "NIT" "LOW" "loop.ts:77" "minor allocation" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # There IS an open finding (so the store is non-empty)...
  run "$FINDINGS" list "$BRIEF_DIR" --open --decode
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  # ...but the BLOCKING subset — the default fix target — is empty → §8 empty-stop.
  run "$FINDINGS" list "$BRIEF_DIR" --open --blocking --decode
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC-2 (blocking boundary — conf arm): WARNING/HIGH IS blocking; CRITICAL/LOW IS blocking; NIT/LOW is NOT" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  # conf-only arm: *:HIGH — WARNING/HIGH must be blocking.
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "WARNING" "HIGH" "api.ts:1" "weak token" \
    > "$batchfile"
  # sev-only arm: CRITICAL:* — CRITICAL/LOW must be blocking.
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "security-auditor" "CRITICAL" "LOW" "db.ts:2" "injection risk" \
    >> "$batchfile"
  # neither arm: NIT/LOW — must NOT be blocking.
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "perf-reviewer" "NIT" "LOW" "loop.ts:3" "minor alloc" \
    >> "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Capture IDs by sev from the full open list.
  run "$FINDINGS" list "$BRIEF_DIR" --open --decode
  [ "$status" -eq 0 ]
  local warning_high_id critical_low_id nit_low_id
  warning_high_id=$(printf '%s\n' "$output" \
    | awk -F'|' '{
        id=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
        sev=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sev)
        conf=$5; gsub(/^[[:space:]]+|[[:space:]]+$/, "", conf)
        if (sev == "WARNING" && conf == "HIGH") {print id; exit}
      }')
  critical_low_id=$(printf '%s\n' "$output" \
    | awk -F'|' '{
        id=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
        sev=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sev)
        conf=$5; gsub(/^[[:space:]]+|[[:space:]]+$/, "", conf)
        if (sev == "CRITICAL" && conf == "LOW") {print id; exit}
      }')
  nit_low_id=$(printf '%s\n' "$output" \
    | awk -F'|' '{
        id=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
        sev=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sev)
        if (sev == "NIT") {print id; exit}
      }')
  [ -n "$warning_high_id" ]
  [ -n "$critical_low_id" ]
  [ -n "$nit_low_id" ]

  # Fetch the blocking subset.
  run "$FINDINGS" list "$BRIEF_DIR" --open --blocking --decode
  [ "$status" -eq 0 ]
  local blocking_output
  blocking_output="$output"

  # WARNING/HIGH MUST be in blocking (conf arm: *:HIGH).
  if ! printf '%s\n' "$blocking_output" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "'"$warning_high_id"'") found=1} END{exit !found}'; then
    echo "FAIL: WARNING/HIGH ${warning_high_id} not in --open --blocking (conf arm broken)" >&2
    return 1
  fi

  # CRITICAL/LOW MUST be in blocking (sev arm: CRITICAL:*).
  if ! printf '%s\n' "$blocking_output" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "'"$critical_low_id"'") found=1} END{exit !found}'; then
    echo "FAIL: CRITICAL/LOW ${critical_low_id} not in --open --blocking (sev arm broken)" >&2
    return 1
  fi

  # NIT/LOW must NOT be in blocking (neither arm).
  if printf '%s\n' "$blocking_output" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "'"$nit_low_id"'") found=1} END{exit !found}' 2>/dev/null; then
    echo "FAIL: NIT/LOW ${nit_low_id} appeared in --open --blocking" >&2
    return 1
  fi
}

@test "AC-3 (bucket normalization): same basename different :NNN suffix → same match key, one stored row" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  local batchfile
  batchfile="$BRIEF_DIR/batch.tsv"
  # First finding at auth.ts:10.
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "auth.ts:10" "unvalidated input" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]
  local first_id
  first_id=$(printf '%s\n' "$output" | grep " new" | awk '{print $1}')
  [ -n "$first_id" ]

  # Second batch: same lens+basename+note, only line suffix differs (auth.ts:99).
  # The match key strips the :NNN suffix, so this must be 'recurring' — same ID.
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "code-reviewer" "WARNING" "MEDIUM" "auth.ts:99" "unvalidated input" \
    > "$batchfile"

  reconcile_batch "$batchfile"
  [ "$status" -eq 0 ]

  # Must be recurring with the SAME id — not a new row.
  printf '%s\n' "$output" | grep -qF "${first_id} recurring"

  # Still exactly 1 row in the store — basename+:NNN-strip deduplicated them.
  local row_count
  row_count=$(grep -c '^| F' "$BRIEF_DIR/FINDINGS.md")
  [ "$row_count" -eq 1 ]
}

@test "AC-10/AC-11 (helper frozen): bin/godmode-findings NOT in the unit-4 git diff" {
  # Derive the unit-4 S1 base commit dynamically from git log to avoid baking in
  # a SHA that silently checks the wrong range after a rebase or fork.
  local unit4_sha
  unit4_sha=$(cd "$PLUGIN_ROOT" && git log --format='%H %s' | \
    awk '/unit 4 S1/{print $1; exit}')

  if [ -z "$unit4_sha" ]; then
    skip "unit-4 S1 commit not found in history — cannot pin frozen-helper range"
  fi

  run bash -c 'cd "$1" && git diff --name-only "$2~1..HEAD"' _ "$PLUGIN_ROOT" "$unit4_sha"
  [ "$status" -eq 0 ]
  if printf '%s\n' "$output" | grep -qx "bin/godmode-findings"; then
    echo "FAIL: bin/godmode-findings appears in the unit-4 diff — helper not frozen" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
}
