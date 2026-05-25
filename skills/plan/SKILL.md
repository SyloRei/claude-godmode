---
name: plan
description: "Turn a brief into an ordered, dependency-aware tactical plan plus a per-criterion verification plan, so building is mechanical. Use when: plan N, break down the brief for N, produce the build plan for roadmap unit N."
user-invocable: true
argument-hint: [N]
arguments: [N]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bin/godmode-state*), Bash(*/.claude/bin/godmode-state*), Bash(*/bin/godmode-state*)
---

# Plan

Break the brief for roadmap unit **$N** into a tactical plan that makes building mechanical: ordered steps, an explicit dependency relationship per step (so `/build` can group steps into parallel waves), and a verification plan that covers every acceptance criterion from the brief.

Run after `/brief N` has captured the why + what + spec. The plan is the contract `/build N` executes against and `/verify N` checks. This is the third step of the spine: `/mission` → `/brief N` → **`/plan N`** → `/build N` → `/verify N` → `/ship`.

The artifact lives in the **consumer's** repo, alongside the brief it reads:

- Reads `.planning/briefs/NN-name/BRIEF.md` — the brief for roadmap unit `$N`.
- Writes `.planning/briefs/NN-name/PLAN.md` — the single tactical plan for that unit.

**Exactly two artifact files per work unit: `BRIEF.md` + `PLAN.md`.** Do NOT introduce a third file — no `EXECUTE.md`, no separate execution-log file. The git log is the execution log. Write `PLAN.md` and nothing else.

---

## Auto Mode

Auto Mode suppresses **confirmation prompts**, not the **clarifying questions** that decide the shape of the plan. In **either** mode:

- **Ask the consequential questions** — a genuinely ambiguous step ordering, an unstated constraint, a design fork where the options diverge materially — when the brief, `.planning/PROJECT.md`, and the repo can't settle it. Guessing here produces a plan that builds the wrong thing efficiently.
- **Assume the trivial** — for low-stakes judgment calls, pick a sensible default and record it under an **Assumptions** heading rather than asking.
- Don't re-ask what the brief already decided. Treat user course-corrections as normal input. A plan is a breakdown, not an interview — but the few questions that change the breakdown are worth asking in either mode.

---

## Process

### 1. Read the brief

Find the brief directory for unit **$N** and read its `BRIEF.md`. `NN` is `$N` zero-padded to two digits (unit `3` → `03`), matching the directory `/brief N` created.

```bash
NN=$(printf '%02d' "$N")
brief_dir=$(ls -d .planning/briefs/${NN}-* 2>/dev/null | head -1)
```

If no brief directory for `$N` exists, stop and tell the user to run `/brief $N` first — do not invent a brief. Read the brief's **Spec — acceptance criteria** carefully: each criterion is what the plan must make buildable and verifiable. Note each criterion's ID (its order/identifier in the brief).

Also read for context:

- `.planning/PROJECT.md` — constraints and decisions the plan must respect.
- The current workflow state, so you know where the user is:
  ```bash
  bin/godmode-state get active_unit
  bin/godmode-state get status
  ```
- Any existing `${brief_dir}/PLAN.md` — if a plan already exists, this is an **update**: read it and preserve prior decisions, editing rather than clobbering.

### 2. Order the steps

Decompose the brief into small, mechanical steps — one concern each. Each step:

- has a stable **ID** (`S1`, `S2`, …),
- names the **files it touches** and the change it makes,
- references the brief **acceptance criteria it advances, by ID**.

A step should be unambiguous enough that an executor needs no extra judgment.

### 3. Declare dependencies (`dependsOn`)

Every step declares `dependsOn` — the list of step IDs it requires, or `none`. Multiple prerequisites are **comma-separated** in exactly this form: `dependsOn: S1, S2` — so `/build` parses waves unambiguously. Declare a dependency only where a **real** ordering constraint exists; spurious dependencies serialize work that could run in parallel. `/build` reads `dependsOn` to group independent steps into **waves**: every step whose dependencies are already satisfied runs in the same wave.

> Wave 1 = all steps with `dependsOn: none`. Wave 2 = all steps whose dependencies are all in Wave 1. And so on.

### 4. Write the verification plan

For **every** acceptance criterion in the brief, write a verification entry that references the criterion **by ID** and states exactly how it will be checked — the command to run, the output to observe, or the file to inspect. This is the bar `/verify N` checks against.

No brief criterion may be left without a verification entry. If a criterion cannot be made verifiable, flag it back to the user rather than inventing a check.

### 5. Write the plan artifact

Write `${brief_dir}/PLAN.md` using the format below. Use Write for a first-time create; use Edit for a surgical update to an existing plan (preserve prior decisions and assumptions).

### 6. Record workflow state

Point the workflow at building this unit so `/godmode` knows the next command:

```bash
bin/godmode-state set active_unit "$N"
bin/godmode-state set status "plan ready"
bin/godmode-state set next_command "/build $N"
```

---

## Artifact format

### `.planning/briefs/NN-name/PLAN.md`

```markdown
# Plan NN: [unit title]

**Updated:** [YYYY-MM-DD]
**Brief:** .planning/briefs/NN-name/BRIEF.md

## Steps
Each step is mechanical, names the files it touches, and references the brief
acceptance criteria it advances by ID.

### S1 — [what this step does]
- **dependsOn:** none
- **Files:** [paths touched]
- **Criteria:** [AC-IDs this step advances]
- **Change:** [the concrete edit/addition]

### S2 — [...]
- **dependsOn:** S1
- **Files:** [...]
- **Criteria:** [...]
- **Change:** [...]

## Waves (derived from dependsOn)
- **Wave 1:** S1 (dependsOn: none)
- **Wave 2:** S2 (dependsOn: S1)

## Verification plan
Every brief acceptance criterion, by ID, with how it is checked.

- **[AC-1]** — [command to run / output to observe / file to inspect → expected result]
- **[AC-2]** — [...]

## Assumptions
[Auto Mode: judgment calls surfaced here. Otherwise omit or note open questions.]
```

---

## Output

After writing, report:

- Whether the plan was created or updated, and its path `.planning/briefs/NN-name/PLAN.md`.
- The ordered steps and the wave grouping implied by `dependsOn`.
- Confirmation that **every** brief acceptance criterion has a verification entry (by ID).
- In Auto Mode, the **Assumptions** that were made.
- The workflow state set and the next step:

> "Plan ready for unit N. Run `/build N` to execute it."

---

## Related

- **/brief N** — preceding step: produces the `BRIEF.md` this plan reads its acceptance criteria from.
- **/build N** — next step: executes the steps wave by wave (reading `dependsOn`), one atomic commit per step.
- **/verify N** — checks the change against the verification plan written here.
- **/godmode** — reads the workflow state this skill records and tells the user the next command.

**Spine:** `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. The plan turns the brief's spec into ordered, dependency-aware steps with a verification plan, so building is mechanical.
