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

# reconcile_batch <batchfile>
#   Runs: godmode-findings reconcile "$BRIEF_DIR" < batchfile
#   Uses "run bash -c" so bats captures exit status + stdout (verify-findings shape).
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

# ===========================================================================
# Class A — prose / frontmatter grep (S1 must be present on disk)
# ===========================================================================

@test "AC-9 (frontmatter): allowed-tools grants Bash(*godmode-findings*)" {
  # The fix flow's orchestrator must be allowed to call the findings helper.
  run grep -nE '^allowed-tools:.*godmode-findings' "$SKILL"
  [ "$status" -eq 0 ]
}

@test "AC-2/AC-5 (§8 cites the helper predicate): transition + fixed + list --open + --blocking" {
  local s8
  s8=$(section8)
  printf '%s\n' "$s8" | grep -qF "transition"
  printf '%s\n' "$s8" | grep -qF "fixed"
  printf '%s\n' "$s8" | grep -qF "list"
  printf '%s\n' "$s8" | grep -qF -- "--open"
  printf '%s\n' "$s8" | grep -qF -- "--blocking"
}

@test "AC-3 (§8 group-by-file): basename + :NNN line-suffix stripped" {
  local s8
  s8=$(section8)
  printf '%s\n' "$s8" | grep -qF "basename"
  printf '%s\n' "$s8" | grep -qF ":NNN"
  # The grouping language itself ("one per file" / bucket).
  printf '%s\n' "$s8" | grep -qiE "one per file|per file|bucket"
}

@test "AC-1 (§8 forbids --no-verify)" {
  local s8
  s8=$(section8)
  printf '%s\n' "$s8" | grep -qF -- "--no-verify"
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

@test "AC-8 (§8 must-not write the plan-flow completion marker)" {
  # 'build complete' appears in §8 ONLY inside the MUST-NOT prohibition (it
  # legitimately appears for real in Step 7, which the §8 slice excludes).
  # Pin the prohibition wording — the load-bearing AC-8 fact for the fix flow.
  local s8
  s8=$(section8)
  printf '%s\n' "$s8" | grep -qiF "MUST NOT"
  printf '%s\n' "$s8" | grep -qF "build complete"
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

# ===========================================================================
# Class B — helper-contract (drive the shipped bin/godmode-findings)
# ===========================================================================

@test "AC-8 (fixed excludes open / no done-set): transition F? fixed → list --open drops it" {
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
  local first_id
  first_id=$(printf '%s\n' "$output" \
    | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 ~ /^F[0-9]+$/) {print $2; exit}}')
  [ -n "$first_id" ]

  # Transition the first finding to fixed (the only writer of open -> fixed).
  run "$FINDINGS" transition "$BRIEF_DIR" "$first_id" fixed
  [ "$status" -eq 0 ]

  # list --open must no longer include the fixed finding — resumability comes
  # from the fixed status itself, not a done-set.
  run "$FINDINGS" list "$BRIEF_DIR" --open --decode
  [ "$status" -eq 0 ]
  if printf '%s\n' "$output" | grep -qE "\| ${first_id} \|"; then
    echo "FAIL: fixed finding ${first_id} still appears in list --open" >&2
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
  printf '%s\n' "$output" | grep -qE "\| ${fid} \|"
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

  # The non-blocking NIT/LOW finding's ID.
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
  printf '%s\n' "$output" | grep -qE "\| ${nit_id} \|"

  # The blocking subset (gates /ship, default fix target) does NOT.
  run "$FINDINGS" list "$BRIEF_DIR" --open --blocking --decode
  [ "$status" -eq 0 ]
  if printf '%s\n' "$output" | grep -qE "\| ${nit_id} \|"; then
    echo "FAIL: non-blocking ${nit_id} appeared in --open --blocking" >&2
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

@test "AC-10/AC-11 (helper frozen): bin/godmode-findings NOT in the unit-4 git diff" {
  # Unit 4 began at S1 (commit 46d7dd4 — the first unit-4 commit); its parent is
  # the unit base. The helper must be unchanged across the whole unit-4 range.
  run bash -c 'cd "$1" && git diff --name-only 46d7dd43c7a791987126978387396d86d3963a9d~1..HEAD' _ "$PLUGIN_ROOT"
  [ "$status" -eq 0 ]
  if printf '%s\n' "$output" | grep -qx "bin/godmode-findings"; then
    echo "FAIL: bin/godmode-findings appears in the unit-4 diff — helper not frozen" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
}
