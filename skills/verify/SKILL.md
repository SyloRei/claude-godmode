---
name: verify
description: "Check a built unit goal-backward: classify every brief acceptance criterion COVERED / PARTIAL / MISSING with concrete evidence, so you know what is truly done. Use when: verify N, check whether unit N is done, confirm the goals for roadmap unit N are met."
user-invocable: true
argument-hint: [N]
arguments: [N]
allowed-tools: Read, Grep, Glob, Bash(bin/godmode-state*), Bash(*/.claude/bin/godmode-state*), Bash(*/bin/godmode-state*), Bash(npm test*), Bash(npm run test*), Bash(pnpm test*), Bash(yarn test*), Bash(bats*), Bash(go test*), Bash(cargo test*), Bash(pytest*), Bash(./scripts/*test*), Bash(shellcheck*), Bash(./scripts/lint*)
---

# Verify

Decide what is **truly done** for roadmap unit **$N** by working **goal-backward**: start from the brief's acceptance criteria, not from the diff. For **each** criterion, return a verdict — **COVERED / PARTIAL / MISSING** — backed by concrete evidence (a `file:line`, a passing test name, or command output). A diff can look big and still miss a goal; only the goals decide the verdict.

Run after `/build N` has produced commits. Verify is the gate before shipping: if every criterion is COVERED, the unit is ready for `/ship`. This is the fifth step of the spine: `/mission` → `/brief N` → `/plan N` → `/build N` → **`/verify N`** → `/ship`.

This is a **read-only** operation. You inspect files, search the codebase, and run the project's test command. You do **not** write or edit source — your only writes are workflow-state updates via `bin/godmode-state`.

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
brief_dir=$(ls -d .planning/briefs/${NN}-* 2>/dev/null | head -1)
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

### 3. Classify

Assign COVERED / PARTIAL / MISSING to each criterion under the strictness rule above. Attach the evidence inline: `file:line`, the test name, or a short slice of command output. For PARTIAL and MISSING, state precisely what is unmet.

### 4. Record workflow state

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

Report a per-criterion verdict table, then a verdict line.

```markdown
## Verification — unit N

| Criterion | Verdict | Evidence |
|-----------|---------|----------|
| [AC-1] [short restatement] | COVERED | path/to/file.sh:42 — implements X; `bats tests/foo.bats` passes (3 ok) |
| [AC-2] [short restatement] | PARTIAL | handler exists at api.ts:88 but the 404 branch is unhandled — no test |
| [AC-3] [short restatement] | MISSING | no implementation found; grep for `placeholder` returns nothing |

**Verdict:** N COVERED / N PARTIAL / N MISSING.
```

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
