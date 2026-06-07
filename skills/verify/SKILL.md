---
name: verify
description: "Check a built unit goal-backward: classify every brief acceptance criterion COVERED / PARTIAL / MISSING with concrete evidence, so you know what is truly done. Use when: verify N, check whether unit N is done, confirm the goals for roadmap unit N are met."
user-invocable: true
argument-hint: [N]
arguments: [N]
allowed-tools: Read, Grep, Glob, Bash(gm=*), Bash(*godmode-model*), Bash(git diff*), Bash(git log*), Bash(git show*), Bash(*godmode-state*), Bash(*godmode-findings*), Bash(npm test*), Bash(npm run test*), Bash(pnpm test*), Bash(yarn test*), Bash(bats*), Bash(go test*), Bash(cargo test*), Bash(pytest*), Bash(./scripts/*test*), Bash(shellcheck*), Bash(./scripts/lint*), Bash(*/skills/verify/scripts/coverage-diff.sh*), Bash(skills/verify/scripts/coverage-diff.sh*)
---

# Verify

Decide what is **truly done** for roadmap unit **$N** by working **goal-backward**: start from the brief's acceptance criteria, not from the diff. For **each** criterion, return a verdict — **COVERED / PARTIAL / MISSING** — backed by concrete evidence (a `file:line`, a passing test name, or command output). A diff can look big and still miss a goal; only the goals decide the verdict.

Run after `/build N` has produced commits. Verify is the gate before shipping: if every criterion is COVERED, the unit is ready for `/ship`. This is the fifth step of the spine: `/mission` → `/brief N` → `/plan N` → `/build N` → **`/verify N`** → `/ship`.

This is a **read-only** operation. You inspect files, search the codebase, read the unit's diff, run the project's test command, and dispatch review lenses that themselves only read. You do **not** write or edit source — your only writes are workflow-state updates via `bin/godmode-state` and findings persistence via `bin/godmode-findings`. `/verify` only ever calls `godmode-findings init`, `reconcile`, and `list` — it **never** calls `transition` or `waive` and **never** auto-closes a finding. The `open→fixed` transition is `/build`'s job; a finding that no lens re-reports this run stays `open` and is reported as stale.

---

## Auto Mode

When `## Auto Mode Active` is present in context: do not ask clarifying questions. Locate the brief and plan for unit `$N`, run the project's test command yourself to gather evidence, classify every criterion, and report. Treat user course-corrections as normal input.

When Auto Mode is absent, still avoid an interview — verification is mechanical. Ask only if you genuinely cannot find the brief or determine the project's test command.

---

## Strictness — the core rule

**Never report PARTIAL as COVERED. "Claimed" is not "verified".**

- **COVERED** — you have **concrete evidence** the criterion is met: a `file:line` that implements it, a named test that exercises it and passes, or command output that demonstrates the observable result the brief asked for. No evidence → not COVERED.
- **PARTIAL** — the criterion is partly met: some of the behavior exists, or it exists but a sub-condition or edge case from the criterion is unmet or unproven. Say exactly what is missing.
- **MISSING** — no evidence the criterion is met, or evidence that it is not.

When in doubt between COVERED and PARTIAL, choose **PARTIAL**. A code comment, a TODO, a stub, or a step that merely *claims* to do the work is **not** evidence. A test that exists but does not run (or is skipped) is **not** evidence — nor is one that trivially passes without exercising the criterion (e.g. asserts `true`, or never calls the code under test).

---

## Process

**Resolving the godmode helpers.** The `godmode-*` helpers live in the plugin install dir — **not** the consumer repo you're working in — so a bare `bin/godmode-*` path fails from another project's working directory. Every `bash` block below resolves their location into `$gm` first (plugin mode → `$CLAUDE_PLUGIN_ROOT/bin`, manual install → `~/.claude/bin`, in-repo → `./bin`) and calls `"$gm/godmode-<name>"`. Keep the resolver line; never call a helper by a bare relative path.

### 1. Read the goals

Find the brief directory for unit **$N** and read its acceptance criteria. `NN` is `$N` zero-padded to two digits (unit `3` → `03`), matching the directory `/brief N` created.

```bash
NN=$(printf '%02d' "$N")
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
mission_id=$("$gm/godmode-state" get mission_id)
brief_dir=$(ls -d .planning/missions/${mission_id}/briefs/${NN}-* 2>/dev/null | head -1)
```

If no brief directory for `$N` exists, stop and tell the user to run `/brief $N` first — there are no goals to verify against.

Read, in order:

- `${brief_dir}/BRIEF.md` — the **Spec — acceptance criteria**. These are the goals you verify against, each by its ID.
- `${brief_dir}/PLAN.md` if present — its **Verification plan** tells you, per criterion, how it was meant to be checked (the command to run, output to observe, or file to inspect). Use it as a guide, but it does not replace gathering your own evidence.
- `.planning/PROJECT.md` — constraints the unit had to respect.

### 2. Gather evidence per criterion

For **each** acceptance criterion, go and find the proof — goal-backward:

- **Read / Grep / Glob** the codebase for the `file:line` that implements the criterion.
- **Run the project's test command** when a criterion is behavioral, and capture the passing (or failing) output. Use the command the PLAN.md verification entry names, or the project's detected runner (`bats`, `npm test`, `pytest`, `go test`, …).
- Inspect command output for the exact observable result the brief asked for (the status code, the file written, the placeholder rendered, the zero-warning lint run).

A criterion is only COVERED if the evidence you gathered demonstrates the brief's observable result — not merely that related code exists.

When `.planning/STANDARDS.md` is present, judge the change against it as authoritative project context over the generic defaults where it has spoken (see "Project Standards Precedence" in `rules/godmode-coding.md`).

**Model profile.** Before spawning any review/verifier agent, resolve the active model profile from `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-balanced}`, then call the resolver `"$gm/godmode-model" <agent>` (resolve `$gm` as the **Resolving the godmode helpers** note above shows) to obtain the model for that agent under the active profile. Pass that model to the Agent tool's `model` override at spawn time. The resolver also reports the agent's effort, but **`effort` is frontmatter-only and is NOT set at spawn** (platform limitation — effort cannot be overridden when spawning an agent), so override **only** `model`; effort stays whatever the agent's frontmatter declares.

### 3. Fan out the review lenses

Verifying "done" has two halves. **`@verifier` owns AC-coverage** — does the unit meet the brief's goals? **Five code-quality lenses own the findings** — is the code that meets those goals sound? Run both halves **in parallel**: in a single message, dispatch **all six** agents concurrently (one Agent call per lens plus `@verifier`), each resolving its model via `"$gm/godmode-model" <agent>` as the **Model profile** note above requires.

Scope every lens to **unit $N's changes only** — the diff the unit produced, e.g. `git diff` for the unit's commits — not the whole codebase. The six agents:

- `@verifier` — goal-backward AC-coverage (drives §4 below; owns COVERED / PARTIAL / MISSING).
- `code-reviewer` — correctness, structure, error handling, readability.
- `security-auditor` — injection, secrets, unsafe input, path/command traversal.
- `perf-reviewer` — hot paths, needless work, allocations, N+1 / blocking calls.
- `convention-reviewer` — adherence to the repo's detected patterns and naming.
- `test-reviewer` — test coverage, meaningful assertions, missing edge/error cases.

**Coverage-delta check.** When the project produces a coverage value (the consumer's coverage tooling yields a baseline and a current figure), feed both to the bundled `coverage-diff.sh` to report the signed delta and flag a regression — deterministic evidence for the `test-reviewer` lens rather than an eyeballed guess. The script prints the signed delta (`+5` / `0` / `-5`) on stdout and exits non-zero when current coverage regressed beyond the tolerance. Resolve it across install modes:

```bash
diff_sh=""
for cand in \
  "${CLAUDE_PLUGIN_ROOT:-}/skills/verify/scripts/coverage-diff.sh" \
  "$HOME/.claude/skills/verify/scripts/coverage-diff.sh" \
  "skills/verify/scripts/coverage-diff.sh"; do
  [ -n "$cand" ] && [ -x "$cand" ] && { diff_sh="$cand"; break; }
done
if [ -n "$diff_sh" ]; then
  "$diff_sh" "$baseline" "$current"
else
  # Make the skip visible — a missing script must not silently no-op the check.
  >&2 echo "warning: coverage-diff.sh not found — skipping coverage-delta check"
fi
```

A non-zero exit means coverage regressed — a finding for `test-reviewer`, not a hard stop here (`/verify` is read-only).

**Shared finding schema.** Each lens reports every finding as a structured record so findings merge cleanly:

```
{ lens, severity, confidence, location, note }
```

- `lens` — which reviewer produced it (`code-reviewer`, `security-auditor`, …).
- `severity` — one of **CRITICAL | WARNING | NIT**.
- `confidence` — one of **HIGH | MEDIUM | LOW** (the lens's certainty the finding is real and actionable).
- `location` — a `file:line` anchor in the unit's diff.
- `note` — one concrete sentence: what is wrong and why.

### 4. Merge the findings

After all lenses return, merge their findings into one set:

- **Dedup** — collapse findings that multiple lenses raise about the same `file:line` / issue into a single record; keep the highest severity and note the contributing lenses.
- **Drop LOW-confidence NITs** — discard any finding that is both `NIT` and `LOW` confidence; it is noise.
- **Group by lens**, and within the report **order severity CRITICAL → WARNING → NIT** so the most important findings surface first.

The `@verifier` lens does not feed this findings set — its output drives the AC-coverage verdict in §5 (Classify) instead.

### 4b. Confirm the blocking findings

Before persisting, subject the blocking-eligible findings to adversarial confirmation. A finding is **blocking-eligible** when its `severity` is `CRITICAL` OR its `confidence` is `HIGH` — exactly the predicate `godmode-findings --blocking` uses. All other findings (neither CRITICAL nor HIGH-confidence) are non-blocking and pass straight through to the persist step unchanged.

**Step 1 — Mechanical pre-filter (UNCONDITIONAL — runs in every profile including budget).**

For each blocking-eligible finding, check whether its `location`'s **file** appears anywhere in this unit's diff (the same `git diff` for the unit's commits already gathered in §3). If the finding's **file** does NOT appear in the diff at all:

- DROP the finding with reason `out-of-diff`.
- Do NOT spawn a skeptic for it.

A finding whose file IS in the diff (regardless of whether the exact line number matches) MUST pass through to the skeptic. The pre-filter removes hallucinated or wrong-file anchors — NOT drifted line numbers within a changed file. Line-level questions (e.g. an adjacent or shifted line in a file that IS in the diff) are adjudicated by the skeptic, not the pre-filter.

This pre-filter is cheap and unconditional. It removes stale wrong-file artifacts from the confirmation batch regardless of the active model profile.

**Step 2 — Per-profile skeptic spawn.**

Resolve `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-balanced}` (the same way §2 does) and apply the profile policy:

- **quality** — confirm ALL blocking-eligible findings that survived the pre-filter.
- **balanced** — confirm only findings with `severity = CRITICAL` (skip HIGH-confidence WARNINGs).
- **budget** — SKIP the skeptic spawn entirely. The pre-filter survivors pass through to the persist step **unchanged** (treated as UPHELD; no verdict step runs).

For each finding selected by the profile policy, spawn **exactly one** `@finding-skeptic` via the Agent tool (the same way §3 dispatches lenses), with its model resolved via:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-model" ] && { echo "$c/bin"; break; }; done)
skeptic_model=$("$gm/godmode-model" finding-skeptic)
```

Pass `skeptic_model` as the Agent tool's `model` parameter when spawning `@finding-skeptic` (mirroring how §3 passes per-lens models). Pass the agent: (a) the single finding record (`lens`, `severity`, `confidence`, `location`, `note`), and (b) the unit diff. The skeptic is read-only. It returns exactly one verdict and one reason sentence.

Findings NOT selected by the profile policy (e.g. HIGH-conf WARNINGs in balanced, or all survivors in budget) pass through to Step 3 unchanged.

**Step 3 — Verdict → action.**

Apply the following state machine to each skeptic verdict:

| Verdict | Action |
|---|---|
| **UPHELD** | Finding passes through UNCHANGED (original `sev`/`conf`) into the reconcile batch. |
| **REFUTED — not real** | DROP the finding — it is NOT added to the reconcile batch at all. |
| **REFUTED — over-rated** | DOWNGRADE (soft-kill): the finding is persisted but exits `--blocking`. For a **non-CRITICAL** finding, set `conf → MEDIUM`. For a **CRITICAL** finding, set `sev → WARNING` AND `conf → MEDIUM`. The downgraded finding IS added to the reconcile batch with its new `sev`/`conf` — it stays visible in `FINDINGS.md` and the report. |

**Default-UPHOLD:** Demote a finding ONLY on an affirmative, evidence-backed refutation. If the skeptic is uncertain, if evidence is ambiguous, or if the skeptic cannot locate the cited code, the verdict MUST be UPHELD. (The `@finding-skeptic` agent enforces this rule internally; the state machine here honors it: ambiguity → UPHELD → pass through unchanged.)

**Result:** the batch fed to `reconcile` below carries the POST-confirmation `sev`/`conf` for every finding. Because `reconcile` refreshes severity and confidence on a recurring match, no separate `godmode-findings` command is needed — the updated values flow through automatically.

**Persist findings.** After merging and deduplicating the five code-quality lens findings (the post-dedup filtered set — `@verifier`'s AC-coverage output is NOT included here), persist them via `godmode-findings`:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)

# Step 1: init unconditionally — idempotent; reconcile errors if FINDINGS.md is absent.
"$gm/godmode-findings" init "$brief_dir"

# Step 2: build the reconcile batch from the post-dedup merged quality-lens findings.
# SANITIZE each finding's lens, location, and note before feeding stdin:
# replace every tab and newline with a single space, then collapse runs of
# whitespace to one space. The helper's reconcile stdin parser is raw
# tab-delimited — an unsanitized tab or newline in a note would shift fields
# or split a line. The helper percent-encodes on write; sanitize is the
# source-side guard. This whitespace-collapse matches the helper's own
# match-key normalization, so it does NOT perturb cross-run identity.
batch_file=$(mktemp "${TMPDIR:-/tmp}/verify-findings.XXXXXX")
while IFS= read -r finding; do  # merged_findings = in-memory post-dedup finding set (placeholder)
  lens=$(     printf '%s' "$finding" | ... | tr '\t\n' '  ' | tr -s ' ')
  sev=$(      printf '%s' "$finding" | ...)
  conf=$(     printf '%s' "$finding" | ...)
  location=$( printf '%s' "$finding" | ... | tr '\t\n' '  ' | tr -s ' ')
  note=$(     printf '%s' "$finding" | ... | tr '\t\n' '  ' | tr -s ' ')
  printf '%s\t%s\t%s\t%s\t%s\n' "$lens" "$sev" "$conf" "$location" "$note"
done < "$merged_findings" >> "$batch_file"

# Step 3: feed the batch to reconcile; capture outcome lines (new/recurring/reopened/waived-kept).
# A non-zero reconcile exit MUST surface as an error — do NOT silently fall back
# to the in-memory merge.
reconcile_output=$("$gm/godmode-findings" reconcile "$brief_dir" < "$batch_file") || {
  echo "ERROR: godmode-findings reconcile failed — findings not persisted." >&2
  rm -f "$batch_file"
  exit 1
}
rm -f "$batch_file"
```

**Empty merged set:** still run `init` (idempotent); feed an empty batch to `reconcile` or skip it — but **never** clear or rewrite `FINDINGS.md` from scratch. A clean run must not wipe prior findings.

**Compute stale.** `reconcile` emits one outcome word per finding on stdout — exactly the four words `new`, `recurring`, `reopened`, or `waived-kept`. The word `stale` is NOT emitted by the helper; it is computed skill-side. After `reconcile` returns, compute stale by diffing the IDs reconcile re-reported this run against the IDs currently open in the store:

```bash
# Parse the IDs reconcile touched this run (one per "Fn <outcome>" line).
rerun_ids=$(printf '%s\n' "$reconcile_output" | awk '{print $1}')

# IDs of all findings still open AFTER this reconcile run.
# (reconcile never auto-closes; open findings not in this batch stay open = stale.)
open_ids=$("$gm/godmode-findings" list "$brief_dir" --open | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2}')

# stale = open IDs that reconcile did NOT touch this run.
stale_count=0
while IFS= read -r oid; do
  [ -n "$oid" ] || continue
  matched=0
  while IFS= read -r rid; do
    [ -n "$rid" ] || continue
    if [ "$oid" = "$rid" ]; then
      matched=1
      break
    fi
  done <<RERUN_EOF
$rerun_ids
RERUN_EOF
  if [ "$matched" -eq 0 ]; then
    stale_count=$((stale_count + 1))
  fi
done <<OPEN_EOF
$open_ids
OPEN_EOF
```

**Count reconcile outcomes** from `$reconcile_output` for the delta summary in §output:

```bash
new_count=$(      printf '%s\n' "$reconcile_output" | grep -c ' new$'          || true)
recurring_count=$(printf '%s\n' "$reconcile_output" | grep -c ' recurring$'    || true)
reopened_count=$( printf '%s\n' "$reconcile_output" | grep -c ' reopened$'     || true)
waivedkept_count=$(printf '%s\n' "$reconcile_output" | grep -c ' waived-kept$' || true)
```

### 5. Classify

Assign COVERED / PARTIAL / MISSING to each criterion under the strictness rule above, using `@verifier`'s goal-backward analysis. Attach the evidence inline: `file:line`, the test name, or a short slice of command output. For PARTIAL and MISSING, state precisely what is unmet.

### 6. Record workflow state

"Done" has **two independent axes**: AC-coverage (do the goals hold?) and the findings gate (are there open blocking findings?). `next_command=/ship` is correct **only when both are clear**. So this step first records the live open-blocking count, then branches the handoff three ways.

**Record `open_blocking` on every run.** After `reconcile` (above), read the live open-blocking count from the store — the same `--blocking` predicate `/ship`'s gate trusts — and record it on **every** run, regardless of which branch below is taken (reuse the `brief_dir` already resolved in §1). This recorded value is **advisory**: it lets `/godmode` surface the right next command. `/ship`'s gate never trusts it — it always reads its own live count.

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-findings" ] && { echo "$c/bin"; break; }; done)
open_blocking=$("$gm/godmode-findings" count "$brief_dir" --blocking)
"$gm/godmode-state" set open_blocking "$open_blocking"
```

This `count` call is **read-only** and within `/verify`'s ownership invariant: verify only ever calls `godmode-findings` `init` / `reconcile` / `list` / `count` — **never** `transition` or `waive`, and it never auto-closes a finding.

Then branch the handoff three ways:

**(a) Every criterion COVERED *and* `open_blocking == 0`** — both axes clear; point the workflow at shipping:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-state" set active_unit "$N"
"$gm/godmode-state" set status "verified"
"$gm/godmode-state" set next_command "/ship"
```

**(b) Every criterion COVERED *but* `open_blocking > 0`** — the unit's goals are met, but open blocking findings remain. The loop isn't done: point the user at the fix loop, **not** `/ship`:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-state" set active_unit "$N"
"$gm/godmode-state" set status "verified | blocking findings open"
"$gm/godmode-state" set next_command "/build $N --fix"
```

**(c) Any criterion PARTIAL or MISSING** — the goals are not met; leave the next command pointed back at building:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-state" set active_unit "$N"
"$gm/godmode-state" set status "verify found gaps"
"$gm/godmode-state" set next_command "/build $N"
```

---

## Output Format

<!-- Output follows the in-skill output convention: godmode:output-convention — see rules/godmode-output.md -->

The report has **two sections**: (a) the goal-backward AC-coverage verdict, then (b) the merged review findings. It leads with the verdict (the terminal state), summarizes what was found, and ends on the single next-step `/command` below.

### (a) AC-coverage verdict

A per-criterion verdict table, then a verdict line.

```markdown
## Verification — unit N

| Criterion | Verdict | Evidence |
|-----------|---------|----------|
| [AC-1] [short restatement] | COVERED | path/to/file.sh:42 — implements X; `bats tests/foo.bats` passes (3 ok) |
| [AC-2] [short restatement] | PARTIAL | handler exists at api.ts:88 but the 404 branch is unhandled — no test |
| [AC-3] [short restatement] | MISSING | no implementation found; grep for `placeholder` returns nothing |

**Verdict:** N COVERED / N PARTIAL / N MISSING.
```

### (b) Review findings

The rendered findings derive from `"$gm/godmode-findings" list "$brief_dir" --open --decode` — the persisted, decoded truth, including findings carried over from prior runs and waive reasons. This is NOT the ephemeral in-memory merge; it is the authoritative store after `reconcile` has run.

Open the output of that command and format it grouped by lens, ordered CRITICAL → WARNING → NIT.

Add a one-line delta summary immediately above the findings table:

```
Findings delta: N new · N recurring · N reopened · N waived-kept · N stale
```

Where the first four counts (`new`, `recurring`, `reopened`, `waived-kept`) come from `reconcile`'s stdout outcome lines, and `stale` is the skill-computed count from the `list --open` diff (the open findings whose identity was not in this run's batch).

```markdown
## Review findings — unit N

Findings delta: 1 new · 2 recurring · 0 reopened · 0 waived-kept · 1 stale

**code-reviewer**
- CRITICAL (HIGH) — api.ts:88 — 404 branch returns 200, masking the error.

**security-auditor**
- WARNING (MEDIUM) — db.ts:14 — query built by string concat; use a parameterized query.

**test-reviewer**
- NIT (HIGH) — foo.test.ts:30 — happy path only; add the empty-input case.
```

If `list --open --decode` returns no rows, say: "No open review findings."

Then the next step:

- **All COVERED** → "Unit N verified — every criterion is COVERED with evidence. Run `/ship`."
- **Any PARTIAL / MISSING** → "Unit N is not done: [list the PARTIAL/MISSING criteria and exactly what's unmet]. Run `/build N` to close the gaps."

Be strict and specific. A vague "looks good" is not a verification.

---

## Related

- **/brief N** — defines the acceptance criteria this skill verifies against.
- **/plan N** — its verification plan tells you how each criterion was meant to be checked.
- **/build N** — produced the commits under verification; the step to re-run when gaps remain.
- **/ship** — next step once every criterion is COVERED.
- **/godmode** — reads the workflow state this skill records and tells the user the next command.

**Spine:** `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. Verify is the goal-backward gate: every brief criterion classified COVERED / PARTIAL / MISSING with evidence, so "done" means done.
