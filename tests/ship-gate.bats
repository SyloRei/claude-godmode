#!/usr/bin/env bats
# ---------------------------------------------------------------------------
# Pins unit 5 (load-bearing ship gate + waive mechanism):
#   - skills/ship/SKILL.md Step 1b findings gate + conversational waive, and
#   - skills/verify/SKILL.md Step 6 open_blocking record + three-branch handoff,
#   PLUS the bin/godmode-findings behaviour the gate consumes (waive clears it).
#
# Two classes, one file (mirrors tests/build-fix.bats):
#   Class A — prose/frontmatter grep against the edited SKILL.md files on disk
#             (these fail unless S1's Step 1b + S2's Step 6 are present).
#   Class B — helper-contract: drive the shipped bin/godmode-findings, proving
#             the waive clears the gate end-to-end + the helper is frozen.
#
# Class A NEVER executes the /ship or /verify prose skills (/ship is
# disable-model-invocation); it only greps the prose text. Class B only drives
# the helper binary.
#
# AC-1..AC-9 backed by prose-grep; AC-7 also has a helper-contract case;
# AC-10 (helper frozen) + AC-11 (waive clears gate; empty reason rejected) are
# helper-contract.
#
# Bash 3.2 / bats-core compatible. shellcheck-clean.
# ---------------------------------------------------------------------------

load test_helper

FINDINGS="$PLUGIN_ROOT/bin/godmode-findings"
SHIP_SKILL="$PLUGIN_ROOT/skills/ship/SKILL.md"
VERIFY_SKILL="$PLUGIN_ROOT/skills/verify/SKILL.md"

# ---------------------------------------------------------------------------
# Harness — mirrors tests/build-fix.bats exactly.
# ---------------------------------------------------------------------------

setup() {
  BRIEF_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ship-gate.XXXXXX")"
}

teardown() {
  if [ -n "${BRIEF_DIR:-}" ] && [ -d "$BRIEF_DIR" ]; then
    rm -rf "$BRIEF_DIR"
  fi
}

# Slice the /ship Step 1b region: from the `## Step 1b` heading up to the next
# `## ` heading (`## Step 2`). Every Step-1b prose assertion scopes to this slice
# so a stray "no commit" / "BLOCK" elsewhere in /ship cannot satisfy the gate's
# contract.
step1b() {
  awk '/^## Step 1b/{f=1} /^## Step 2/{f=0} f' "$SHIP_SKILL"
}

# Slice the /verify Step 6 region: from the `### 6.` heading up to the next
# `---` rule (Step 6 is the last numbered step before `## Output format`).
verify_step6() {
  awk '/^### 6\./{f=1} f && /^---$/{print; f=0; next} f' "$VERIFY_SKILL"
}

# ---------------------------------------------------------------------------
# Class A — /ship prose / frontmatter grep (S1 must be present on disk)
# ---------------------------------------------------------------------------

@test "AC-6 (frontmatter): /ship allowed-tools grants Bash(*godmode-findings*)" {
  # The gate + waive loop must be allowed to call the findings helper.
  run grep -nE '^allowed-tools:.*Bash\(\*godmode-findings\*\)' "$SHIP_SKILL"
  [ "$status" -eq 0 ]
}

@test "AC-4 (frontmatter): /ship adds no --waive flag" {
  # Pin the user's choice of a conversational waive (no new flag surface): the
  # frontmatter (between the first two `---` fences) must not mention --waive.
  local frontmatter
  frontmatter=$(awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{exit} f' "$SHIP_SKILL")
  if printf '%s\n' "$frontmatter" | grep -qF -- "--waive"; then
    echo "FAIL: /ship frontmatter mentions --waive (must be conversational, no flag)" >&2
    return 1
  fi
}

@test "AC-1 (Step 1b exists, placed after quality gates / before git readiness)" {
  # The heading exists...
  run grep -nE '^## Step 1b' "$SHIP_SKILL"
  [ "$status" -eq 0 ]
  # ...and is positioned strictly between Step 1 (quality gates) and Step 2
  # (git readiness): the line number of Step 1b must fall between the two.
  local l1 l1b l2
  l1=$(grep -nE '^## Step 1:' "$SHIP_SKILL"  | head -1 | cut -d: -f1)
  l1b=$(grep -nE '^## Step 1b' "$SHIP_SKILL" | head -1 | cut -d: -f1)
  l2=$(grep -nE '^## Step 2:' "$SHIP_SKILL"  | head -1 | cut -d: -f1)
  [ -n "$l1" ] && [ -n "$l1b" ] && [ -n "$l2" ]
  [ "$l1" -lt "$l1b" ]
  [ "$l1b" -lt "$l2" ]
}

@test "AC-1 (Step 1b reads the live count via godmode-findings count --blocking)" {
  local s1b
  s1b=$(step1b)
  # The gate's read — contiguous call so a token-scatter cannot satisfy it.
  # SC2016 intentional: single quotes keep $gm / $brief_dir literal (prose grep).
  # shellcheck disable=SC2016
  printf '%s\n' "$s1b" | grep -qF 'godmode-findings" count "$brief_dir" --blocking'
}

@test "AC-9 (gate trusts the live count, NOT the recorded open_blocking key)" {
  local s1b
  s1b=$(step1b)
  # The gate must say it does NOT trust the verify-recorded open_blocking state
  # key for the block decision — assert the conjoined disavowal, not a bare word.
  printf '%s\n' "$s1b" | grep -qiE "does \*\*not\*\* read|never trusts|does not read"
  printf '%s\n' "$s1b" | grep -qF "open_blocking"
  # And the positive wording that the gate uses the LIVE count it just read.
  printf '%s\n' "$s1b" | grep -qiE "live count|live[[:space:]]+\*\*count\*\*|its own count"
}

@test "AC-2 (count > 0 → hard BLOCK: no commit / push / PR / shipped, no --no-verify)" {
  local s1b
  s1b=$(step1b)
  # The BLOCK verdict is tied to the > 0 case.
  printf '%s\n' "$s1b" | grep -qiE 'open_blocking > 0|count.*> 0'
  printf '%s\n' "$s1b" | grep -qF "BLOCK"
  # The four hard prohibitions of the block (same semantics as a failing gate).
  printf '%s\n' "$s1b" | grep -qiF "do **not** commit"
  printf '%s\n' "$s1b" | grep -qiF "git push"
  printf '%s\n' "$s1b" | grep -qiF "gh pr create"
  printf '%s\n' "$s1b" | grep -qiF "status=shipped"
  printf '%s\n' "$s1b" | grep -qiF -- "--no-verify"
}

@test "AC-2 (--no-push does not exempt the findings gate: BLOCK applies in both modes)" {
  local s1b
  s1b=$(step1b)
  # The conjoined contract: the BLOCK applies in BOTH normal and --no-push mode,
  # and --no-push does NOT exempt the gate. Matching '--no-push' alone is not
  # enough — pin the both-modes / does-not-exempt phrasing.
  printf '%s\n' "$s1b" | grep -qiE "both normal and \`?--no-push|both modes"
  printf '%s\n' "$s1b" | grep -qiE "does not exempt|not exempt the findings gate"
}

@test "AC-2 (BLOCK reports the rows via list --open --blocking --decode)" {
  local s1b
  s1b=$(step1b)
  # SC2016 intentional: literal prose, no expansion.
  # shellcheck disable=SC2016
  printf '%s\n' "$s1b" | grep -qF 'godmode-findings" list "$brief_dir" --open --blocking --decode'
}

@test "AC-3 (two escapes: /build N --fix and a conversational waive)" {
  local s1b
  s1b=$(step1b)
  # Both escapes are named.
  printf '%s\n' "$s1b" | grep -qF -- "/build N --fix"
  printf '%s\n' "$s1b" | grep -qiF "waive"
  # The waive is conversational and runs only on a user-named ID + reason.
  # SC2016 intentional: literal prose, no expansion.
  # shellcheck disable=SC2016
  printf '%s\n' "$s1b" | grep -qF 'godmode-findings" waive "$brief_dir"'
  # The never-auto-waive prohibition (conjoined phrase, not a bare token).
  printf '%s\n' "$s1b" | grep -qiE "never auto-waives|does \*\*not\*\* waive|never invents"
}

@test "AC-3 (waive re-reads the live count in the same invocation)" {
  local s1b
  s1b=$(step1b)
  # After a waive the gate re-reads count --blocking and proceeds once it hits 0.
  printf '%s\n' "$s1b" | grep -qiE "re-read.*count|re-read the live count"
  printf '%s\n' "$s1b" | grep -qiE "reaches 0|reach(es)? 0|until then"
}

@test "AC-5 (fail-closed: non-zero count → BLOCK + report the error)" {
  local s1b
  s1b=$(step1b)
  # The fail-closed contract: a store the gate cannot read BLOCKS — assert the
  # conjoined phrasing, not the bare word "fail-closed".
  printf '%s\n' "$s1b" | grep -qiF "fail-closed"
  printf '%s\n' "$s1b" | grep -qiE "exits non-zero|count failed|store unreadable|cannot read"
  printf '%s\n' "$s1b" | grep -qiE "treat.*as \*\*BLOCKED\*\*|treat the gate as \*\*BLOCKED\*\*|never ship past"
}

@test "AC-5 (not-applicable skip branch: no brief_dir / no FINDINGS.md → skip)" {
  local s1b
  s1b=$(step1b)
  # The skip branch — a standalone change with no findings to gate on.
  printf '%s\n' "$s1b" | grep -qiE "skip Step 1b|skip.*proceed to Step 2|gate is not applicable|Not applicable"
  printf '%s\n' "$s1b" | grep -qF "FINDINGS.md"
}

# ---------------------------------------------------------------------------
# Class A — /verify prose grep (S2 must be present on disk)
# ---------------------------------------------------------------------------

@test "AC-7 (/verify Step 6 records open_blocking via godmode-state set on every run)" {
  local s6
  s6=$(verify_step6)
  # Computes the live count...
  # SC2016 intentional: literal prose, no expansion.
  # shellcheck disable=SC2016
  printf '%s\n' "$s6" | grep -qF 'godmode-findings" count "$brief_dir" --blocking'
  # ...and records it with godmode-state set open_blocking.
  # shellcheck disable=SC2016
  printf '%s\n' "$s6" | grep -qF 'godmode-state" set open_blocking'
  # On EVERY run (conjoined phrase, not a bare token).
  printf '%s\n' "$s6" | grep -qiE "on \*\*every\*\* run|every run, regardless"
}

@test "AC-7 (/verify Step 6 keeps the ownership invariant: never transition/waive)" {
  local s6
  s6=$(verify_step6)
  # The count call is read-only and within verify's ownership: never transition/waive.
  printf '%s\n' "$s6" | grep -qiE "read-only|ownership invariant"
  printf '%s\n' "$s6" | grep -qiF "never"
  printf '%s\n' "$s6" | grep -qF "transition"
  printf '%s\n' "$s6" | grep -qF "waive"
}

@test "AC-8 (/verify Step 6 has three next_command branches incl. /build N --fix)" {
  local s6
  s6=$(verify_step6)
  # (a) both axes clear → /ship happy path.
  printf '%s\n' "$s6" | grep -qF '"/ship"'
  # (b) ACs COVERED but open_blocking > 0 → the fix-loop handoff.
  # SC2016 intentional: literal prose ($N is a SKILL placeholder, not expanded).
  # shellcheck disable=SC2016
  printf '%s\n' "$s6" | grep -qF 'set next_command "/build $N --fix"'
  # (c) any AC PARTIAL/MISSING → /build $N (unchanged).
  # shellcheck disable=SC2016
  printf '%s\n' "$s6" | grep -qF 'set next_command "/build $N"'
}

@test "AC-8 (/verify Step 6 keys the branches on open_blocking == 0 vs > 0)" {
  local s6
  s6=$(verify_step6)
  # The two-axis decision: both branches reference the open_blocking comparison,
  # so a single-axis handoff cannot satisfy this.
  printf '%s\n' "$s6" | grep -qiE 'open_blocking == 0|open_blocking==0'
  printf '%s\n' "$s6" | grep -qiE 'open_blocking > 0|open_blocking>0'
}

# ---------------------------------------------------------------------------
# Class B — helper-contract (drive the shipped bin/godmode-findings)
# ---------------------------------------------------------------------------

@test "AC-11 (waive clears the gate): add blocking → count 1 → waive → count 0" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # A blocking finding (CRITICAL/HIGH — both arms fire). `add` prints its ID.
  run "$FINDINGS" add "$BRIEF_DIR" "security-auditor" "CRITICAL" "HIGH" "db.ts:5" "sql injection risk"
  [ "$status" -eq 0 ]
  local fid
  fid="$output"
  [ -n "$fid" ]

  # The gate's source of truth reports exactly one blocking finding.
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # The user names the ID + a real reason → /ship runs the waive.
  run "$FINDINGS" waive "$BRIEF_DIR" "$fid" "confirmed false positive — parameterized query"
  [ "$status" -eq 0 ]

  # The waived finding has left the blocking set, so /ship's gate clears.
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "AC-11 (waive clears the gate, conf arm): WARNING/HIGH blocking → waive → count 0" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  # WARNING/HIGH is blocking via the conf-only arm (*:HIGH), not CRITICAL.
  run "$FINDINGS" add "$BRIEF_DIR" "code-reviewer" "WARNING" "HIGH" "auth.ts:10" "unvalidated input"
  [ "$status" -eq 0 ]
  local fid
  fid="$output"
  [ -n "$fid" ]

  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run "$FINDINGS" waive "$BRIEF_DIR" "$fid" "input is validated upstream by the router"
  [ "$status" -eq 0 ]

  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "AC-11 (empty reason rejected): waive with '' exits non-zero, count unchanged" {
  run "$FINDINGS" init "$BRIEF_DIR"
  [ "$status" -eq 0 ]

  run "$FINDINGS" add "$BRIEF_DIR" "security-auditor" "CRITICAL" "HIGH" "db.ts:5" "sql injection risk"
  [ "$status" -eq 0 ]
  local fid
  fid="$output"
  [ -n "$fid" ]

  # An empty reason must be rejected — a reason is required, so /ship cannot waive
  # without a user-supplied reason.
  run "$FINDINGS" waive "$BRIEF_DIR" "$fid" ""
  [ "$status" -ne 0 ]

  # The blocking count is unchanged — the finding still gates the ship.
  run "$FINDINGS" count "$BRIEF_DIR" --blocking
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "AC-10 (helper frozen): bin/godmode-findings NOT in the unit-5 git diff" {
  # Derive unit 5's base dynamically — the parent of the EARLIEST unit-5 commit
  # that edited skills/ship or skills/verify (this mission's S1/S2). Anchoring on
  # the /ship Step 1b subject avoids colliding with the unrelated mission-05
  # "unit 5 S1" commits (architect/done-set) that touch neither SKILL.
  local unit5_sha
  unit5_sha=$(cd "$PLUGIN_ROOT" && git log --reverse --format='%H %s' \
    -- skills/ship/SKILL.md skills/verify/SKILL.md \
    | awk '/unit 5 S1 — \/ship|unit 5 S2 — \/verify/{print $1; exit}')

  if [ -z "$unit5_sha" ]; then
    skip "unit-5 ship/verify commit not found in history — cannot pin frozen-helper range"
  fi

  run bash -c 'cd "$1" && git diff --name-only "$2~1..HEAD" -- bin/godmode-findings' \
    _ "$PLUGIN_ROOT" "$unit5_sha"
  [ "$status" -eq 0 ]
  if [ -n "$output" ]; then
    echo "FAIL: bin/godmode-findings appears in the unit-5 diff — helper not frozen" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
}

@test "AC-10 (helper frozen): working copy of bin/godmode-findings matches unit-5 base" {
  # Byte-for-byte: the working-tree helper must be identical to its content at the
  # unit-5 base commit (complements the name-only diff above — catches an in-place
  # edit that some later commit might have reverted in name-only terms).
  local unit5_sha
  unit5_sha=$(cd "$PLUGIN_ROOT" && git log --reverse --format='%H %s' \
    -- skills/ship/SKILL.md skills/verify/SKILL.md \
    | awk '/unit 5 S1 — \/ship|unit 5 S2 — \/verify/{print $1; exit}')

  if [ -z "$unit5_sha" ]; then
    skip "unit-5 ship/verify commit not found in history — cannot pin frozen-helper base"
  fi

  run bash -c 'cd "$1" && git diff --quiet "$2~1" HEAD -- bin/godmode-findings' \
    _ "$PLUGIN_ROOT" "$unit5_sha"
  [ "$status" -eq 0 ]
}
