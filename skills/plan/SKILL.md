---
name: plan
description: "Turn a brief into an ordered, dependency-aware tactical plan plus a per-criterion verification plan, so building is mechanical. Use when: plan N, break down the brief for N, produce the build plan for roadmap unit N."
user-invocable: true
argument-hint: [N]
arguments: [N]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(gm=*), Bash(*godmode-state*)
---

# Plan

Break the brief for roadmap unit **$N** into a tactical plan that makes building mechanical: ordered steps, an explicit dependency relationship per step (so `/build` can group steps into parallel waves), and a verification plan that covers every acceptance criterion from the brief.

Run after `/brief N` has captured the why + what + spec. The plan is the contract `/build N` executes against and `/verify N` checks. This is the third step of the spine: `/mission` → `/brief N` → **`/plan N`** → `/build N` → `/verify N` → `/ship`.

The artifact lives in the **consumer's** repo, alongside the brief it reads:

- Reads `.planning/missions/<mission_id>/briefs/NN-name/BRIEF.md` — the brief for roadmap unit `$N` (`mission_id=$("$gm/godmode-state" get mission_id)`; see the helper-resolution note in Process).
- Writes `.planning/missions/<mission_id>/briefs/NN-name/PLAN.md` — the single tactical plan for that unit.

**Exactly two artifact files per work unit: `BRIEF.md` + `PLAN.md`.** Do NOT introduce a third file — no `EXECUTE.md`, no separate execution-log file. The git log is the execution log. Write `PLAN.md` and nothing else.

---

## Auto Mode

Auto Mode suppresses **confirmation prompts**, not the **clarifying questions** that decide the shape of the plan. In **either** mode:

- **Ask the consequential questions** — a genuinely ambiguous step ordering, an unstated constraint, a design fork where the options diverge materially — when the brief, `.planning/PROJECT.md`, and the repo can't settle it. Guessing here produces a plan that builds the wrong thing efficiently.
- **Assume the trivial** — for low-stakes judgment calls, pick a sensible default and record it under an **Assumptions** heading rather than asking.
- Don't re-ask what the brief already decided. Treat user course-corrections as normal input. A plan is a breakdown, not an interview — but the few questions that change the breakdown are worth asking in either mode.

**Recommendation convention** (`godmode:recommend-convention`). When you do ask, follow the shared convention in `rules/godmode-recommend.md`: **lead with a Recommended option** carrying a visible one-line rationale, then let the user override — never a flat menu of equal choices:

```
How should the migration step be ordered relative to the API step?

  a) Migration first, then API (Recommended — the API handler reads the new
     column, so it can't compile until the migration lands)
  b) API first — only viable if you stub the column, which adds throwaway work
  c) Something else — tell me

Pick a letter, or describe a different option.
```

---

## Process

**Resolving the godmode helpers.** The `godmode-*` helpers live in the plugin install dir — **not** the consumer repo you're working in — so a bare `bin/godmode-*` path fails from another project's working directory. Every `bash` block below resolves their location into `$gm` first (plugin mode → `$CLAUDE_PLUGIN_ROOT/bin`, manual install → `~/.claude/bin`, in-repo → `./bin`) and calls `"$gm/godmode-<name>"`. Keep the resolver line; never call a helper by a bare relative path.

### 1. Read the brief

Find the brief directory for unit **$N** and read its `BRIEF.md`. `NN` is `$N` zero-padded to two digits (unit `3` → `03`), matching the directory `/brief N` created.

```bash
NN=$(printf '%02d' "$N")
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
mission_id=$("$gm/godmode-state" get mission_id)
brief_dir=$(ls -d .planning/missions/${mission_id}/briefs/${NN}-* 2>/dev/null | head -1)
```

If no brief directory for `$N` exists, stop and tell the user to run `/brief $N` first — do not invent a brief. Read the brief's **Spec — acceptance criteria** carefully: each criterion is what the plan must make buildable and verifiable. Note each criterion's ID (its order/identifier in the brief).

Also read for context:

- `.planning/PROJECT.md` — constraints and decisions the plan must respect.
- The current workflow state, so you know where the user is:
  ```bash
  gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
  "$gm/godmode-state" get active_unit
  "$gm/godmode-state" get status
  ```
- Any existing `${brief_dir}/PLAN.md` — if a plan already exists, this is an **update**: read it and preserve prior decisions, editing rather than clobbering.

### 2. Run the architect design pass (when Design Risk = `yes`)

This step **acts** on the Design Risk **Verdict** that `/brief` recorded into the brief's `## Design Risk` section, and it runs **before** "Order the steps" (step 3) so its output can **ground** the step ordering and `dependsOn`. The ordering is fixed: **read the verdict → architect pass on `yes` (this step) → order the steps and declare dependencies (steps 3–4)**.

This is the plan-focused counterpart to `/brief`'s step 5. Where `/brief`'s pass is **spec-focused** (Context / Recommended Approach / Tradeoffs), this pass is **plan-focused**: it asks the architect for **implementation order, sequencing, and risks** — the architect's `## Implementation Order` and `## Risks & Mitigations` — so the steps you order next are grounded in a real sequencing design rather than guessed.

**Verdict-gated spawn.** Read the **Verdict** field from the brief's `## Design Risk` section (recorded by `/brief`):

- **`yes`** — spawn `@architect` inline (via the Agent tool, the same way `/verify` spawns its review agents and `/brief`'s step 5 spawns its design pass).
- **`no`, absent, empty, or unset** — spawn **nothing**. This honors the gate default (`default to no`) and keeps trivial units cheap: no architect pass runs, it adds no cost, and it never blocks the plan. Fail-cheap.

**Always re-invoke; plan-focused framing.** When the verdict is `yes`, this pass runs **every time** — it does **not** skip the spawn by reusing whatever the brief already recorded in its `## Architecture` section. Instead it **hands** the architect that brief `## Architecture` content (when present) **as context**, alongside the unit's **Why** / **What** and the recorded **Design Risk triggers**, and asks specifically for **implementation order, sequencing, and risks**. The brief's spec-focused architecture is an input; the output you want here is the architect's `## Implementation Order` and `## Risks & Mitigations` — deliberately distinct from the Context / Approach / Tradeoffs `/brief` distilled.

**Confirmation behavior.** The pass costs opus, so in interactive mode surface a recommendation-backed confirm **before** spawning, following the shared convention in `rules/godmode-recommend.md` (`godmode:recommend-convention`) — lead with a **Recommended: yes** option, since the gate already judged this unit design-heavy:

```
Design Risk for unit N is `yes` (triggers: [recorded triggers]).
Run a plan-focused architect pass (implementation order / sequencing / risks)
before ordering the steps?
  a) Yes (Recommended — the gate flagged real design risk; one opus pass now
     grounds the step order and dependsOn instead of guessing the sequencing)
  b) No — skip the pass and order the steps from the brief as-is
```

In **Auto Mode**, spawn automatically with no prompt: Auto Mode suppresses confirmations, not the consequential sequencing work the gate has already decided is warranted.

**Model tier — resolver bypass.** The architect spawn runs at the agent's frontmatter tier (**opus**). Do **NOT** route the architect's model through `bin/godmode-model`: under a `budget` profile that resolver downgrades every agent to haiku, which would yield a worthless sequencing pass. This is a deliberate divergence from `/verify`'s resolver pattern — the Design Risk verdict is the **sole** cost control here, so `userConfig.model_profile` does not downgrade or suppress this pass. Spawn the architect at opus directly.

**Output handling.** Distill the architect's plan-focused grounding — the recommended approach plus its `## Implementation Order` and `## Risks & Mitigations` — into `PLAN.md`'s `## Design Notes` section **only**, recording how it shaped the step order and `dependsOn`. Do **NOT** rewrite the brief's `## Architecture` (the brief is read-only to `/plan`), and do **NOT** add a third artifact — the `BRIEF.md` + `PLAN.md` two-artifact rule holds. This grounding then **informs** the step ordering you do in step 3 and the dependencies you declare in step 4.

### 3. Order the steps

Decompose the brief into small, mechanical steps — one concern each. Each step:

- has a stable **ID** (`S1`, `S2`, …),
- names the **files it touches** and the change it makes,
- references the brief **acceptance criteria it advances, by ID**.

A step should be unambiguous enough that an executor needs no extra judgment.

When `.planning/STANDARDS.md` is present, treat it as authoritative project context the plan's steps should respect over the generic defaults where it has spoken (see "Project Standards Precedence" in `rules/godmode-coding.md`).

### 4. Declare dependencies (`dependsOn`)

Every step declares `dependsOn` — the list of step IDs it requires, or `none`. Multiple prerequisites are **comma-separated** in exactly this form: `dependsOn: S1, S2` — so `/build` parses waves unambiguously. Declare a dependency only where a **real** ordering constraint exists; spurious dependencies serialize work that could run in parallel. `/build` reads `dependsOn` to group independent steps into **waves**: every step whose dependencies are already satisfied runs in the same wave.

> Wave 1 = all steps with `dependsOn: none`. Wave 2 = all steps whose dependencies are all in Wave 1. And so on.

### 5. Write the verification plan

For **every** acceptance criterion in the brief, write a verification entry that references the criterion **by ID** and states exactly how it will be checked — the command to run, the output to observe, or the file to inspect. This is the bar `/verify N` checks against.

No brief criterion may be left without a verification entry. If a criterion cannot be made verifiable, flag it back to the user rather than inventing a check.

### 6. Write the plan artifact

Write `${brief_dir}/PLAN.md` using the format below. Use Write for a first-time create; use Edit for a surgical update to an existing plan (preserve prior decisions and assumptions).

### 7. Record workflow state

Point the workflow at building this unit so `/godmode` knows the next command:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-state" set active_unit "$N"
"$gm/godmode-state" set status "plan ready"
"$gm/godmode-state" set next_command "/build $N"
```

---

## Artifact format

### `.planning/missions/<mission_id>/briefs/NN-name/PLAN.md`

```markdown
# Plan NN: [unit title]

**Updated:** [YYYY-MM-DD]
**Brief:** .planning/missions/<mission_id>/briefs/NN-name/BRIEF.md

## Design Notes
<!-- Populated ONLY when the brief's Design Risk Verdict is `yes` (distilled from the plan-focused @architect pass, step 2). When the verdict is `no`/absent, this section is empty or omitted. -->

[The plan-focused architect grounding: the recommended approach plus the
implementation order / sequencing / risks (the architect's `## Implementation
Order` and `## Risks & Mitigations`), and HOW it shaped the step order and
`dependsOn` below.]

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

- Whether the plan was created or updated, and its path `.planning/missions/<mission_id>/briefs/NN-name/PLAN.md`.
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
