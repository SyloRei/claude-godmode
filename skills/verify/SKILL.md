---
name: verify
description: "Check a built unit goal-backward: classify every brief acceptance criterion COVERED / PARTIAL / MISSING with concrete evidence, so you know what is truly done. Use when: verify N, check whether unit N is done, confirm the goals for roadmap unit N are met."
user-invocable: true
argument-hint: [N]
arguments: [N]
allowed-tools: Read, Grep, Glob, Bash(bin/godmode-model*), Bash(*/bin/godmode-model*), Bash(git diff*), Bash(git log*), Bash(git show*), Bash(bin/godmode-state*), Bash(*/.claude/bin/godmode-state*), Bash(*/bin/godmode-state*), Bash(npm test*), Bash(npm run test*), Bash(pnpm test*), Bash(yarn test*), Bash(bats*), Bash(go test*), Bash(cargo test*), Bash(pytest*), Bash(./scripts/*test*), Bash(shellcheck*), Bash(./scripts/lint*), Bash(*/skills/verify/scripts/coverage-diff.sh*), Bash(skills/verify/scripts/coverage-diff.sh*)
---

# Verify

Decide what is **truly done** for roadmap unit **$N** by working **goal-backward**: start from the brief's acceptance criteria, not from the diff. For **each** criterion, return a verdict — **COVERED / PARTIAL / MISSING** — backed by concrete evidence (a `file:line`, a passing test name, or command output). A diff can look big and still miss a goal; only the goals decide the verdict.

Run after `/build N` has produced commits. Verify is the gate before shipping: if every criterion is COVERED, the unit is ready for `/ship`. This is the fifth step of the spine: `/mission` → `/brief N` → `/plan N` → `/build N` → **`/verify N`** → `/ship`.

This is a **read-only** operation. You inspect files, search the codebase, read the unit's diff, run the project's test command, and dispatch review lenses that themselves only read. You do **not** write or edit source — your only writes are workflow-state updates via `bin/godmode-state`.

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

### 1. Read the goals

Find the brief directory for unit **$N** and read its acceptance criteria. `NN` is `$N` zero-padded to two digits (unit `3` → `03`), matching the directory `/brief N` created.

```bash
NN=$(printf '%02d' "$N")
mission_id=$(bin/godmode-state get mission_id)
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

**Model profile.** Before spawning any review/verifier agent, resolve the active model profile from `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-balanced}`, then call the resolver `bin/godmode-model <agent>` to obtain the model for that agent under the active profile. Pass that model to the Agent tool's `model` override at spawn time. The resolver also reports the agent's effort, but **`effort` is frontmatter-only and is NOT set at spawn** (platform limitation — effort cannot be overridden when spawning an agent), so override **only** `model`; effort stays whatever the agent's frontmatter declares.

### 3. Fan out the review lenses

Verifying "done" has two halves. **`@verifier` owns AC-coverage** — does the unit meet the brief's goals? **Five code-quality lenses own the findings** — is the code that meets those goals sound? Run both halves **in parallel**: in a single message, dispatch **all six** agents concurrently (one Agent call per lens plus `@verifier`), each resolving its model via `bin/godmode-model <agent>` as the **Model profile** note above requires.

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

### 5. Classify

Assign COVERED / PARTIAL / MISSING to each criterion under the strictness rule above, using `@verifier`'s goal-backward analysis. Attach the evidence inline: `file:line`, the test name, or a short slice of command output. For PARTIAL and MISSING, state precisely what is unmet.

### 6. Record workflow state

If — and only if — **every** criterion is COVERED, point the workflow at shipping:

```bash
bin/godmode-state set active_unit "$N"
bin/godmode-state set status "verified"
bin/godmode-state set next_command "/ship"
```

If any criterion is PARTIAL or MISSING, leave the next command pointed back at building:

```bash
bin/godmode-state set active_unit "$N"
bin/godmode-state set status "verify found gaps"
bin/godmode-state set next_command "/build $N"
```

---

## Output format

The report has **two sections**: (a) the goal-backward AC-coverage verdict, then (b) the merged review findings.

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

The merged findings from the five code-quality lenses (§4), grouped by lens and ordered CRITICAL → WARNING → NIT, after dedup and dropping LOW-confidence NITs.

```markdown
## Review findings — unit N

**code-reviewer**
- CRITICAL (HIGH) — api.ts:88 — 404 branch returns 200, masking the error.

**security-auditor**
- WARNING (MEDIUM) — db.ts:14 — query built by string concat; use a parameterized query.

**test-reviewer**
- NIT (HIGH) — foo.test.ts:30 — happy path only; add the empty-input case.
```

If the merged set is empty, say so: "No review findings after merge."

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
