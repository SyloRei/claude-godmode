---
name: ideate
description: "Pre-mission discovery: discuss and think out candidate directions for the next feature mission, converge on one concrete proposal, and capture the reasoning as a durable artifact that /mission later reads as its seed. Use when: ideate, what should the next mission be, explore options before committing to a charter. Does not start or mutate any mission — it stops at a proposal."
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Bash(gm=*), Bash(*godmode-state*)
---

# Ideate

The **pre-mission front door** of the planning spine. Before `/mission` demands a decision — a feature name, a purpose, success criteria, constraints, a numbered roadmap — `/ideate` does the messy, generative work that *precedes* that decision: discuss candidate directions for the **next** mission, think each one through out loud, and converge on one concrete proposal. The proposal is written as a durable artifact that `/mission` then reads as its seed.

A charter is a contract, not a brainstorm. `/ideate` keeps the brainstorm out of `/mission`: it gives the user a real space to explore alternatives — with the reasoning preserved — and it gives `/mission` a synthesized starting point instead of a blank prompt. This is the spine's front door: `/ideate` → `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`.

The artifact lives in the **consumer's** repo (the project you are helping build), never in the plugin source:

- `.planning/ideas/<slug>/IDEAS.md` — one durable record per candidate feature. `<slug>` is the kebab-case proposed feature name.

This location is deliberately **outside** `.planning/missions/`: the prospective mission has no `mission_id` yet — `/ideate` runs before any mission is allocated for the idea. `.planning/ideas/` is project-global scratch space at the `.planning/` root, alongside `PROJECT.md` and `STATE.md`.

---

## Pre-mission contract

`/ideate` is out-of-spine-order by design. It does not behave like the mission-scoped steps:

- **Requires no active mission.** It runs on a bare repo with no missions at all, before anything has been allocated.
- **May run mid-mission.** While a mission is active, `/ideate` shapes the *next* mission without disturbing the current one. It does not read or rely on the active mission's state.
- **Does not start, switch, or mutate any mission.** It allocates no `mission_id`, resets no counter, writes no roadmap, touches no brief. It **stops at a proposal** — the `IDEAS.md` artifact. `/mission` remains the only skill that allocates a `mission_id` and resets the work-unit counter.
- **No mission-flow state writes.** Because it is pre-mission and out-of-order, `/ideate` does **not** set `active_unit` or `next_command` into a mission flow — that would corrupt an active mission's pointer. Any state write, if ever needed, goes only through the `godmode-state` helper; none is required. At most, `/ideate` suggests `/mission <name>` as the next step in its output prose.

---

## Auto Mode

Auto Mode suppresses **confirmation prompts** ("proceed? / shall I write the artifact?") — never the **discovery questions** that decide what the next mission should even be. Ideation built on silent guesses converges on the wrong idea, and `/mission` inherits it. So even in Auto Mode:

- **Still ask the consequential discovery questions** — the ones whose answer materially changes which direction the next mission pursues (the core problem, who it's for, the rough scope, which candidate is worth committing to) AND that the repo/README/recent commits cannot answer. Batch them up front, lettered/option style, so they're answered fast.
- **Assume the trivial** — for low-stakes gaps the repo can reasonably imply, pick a sensible default and record it under an **Assumptions** heading rather than asking.
- Don't interrogate: if the repo already answers something, don't ask it. Treat user course-corrections as normal input.

When Auto Mode is absent, same principle — ask the essential discovery questions, keep it brief. This is exploration, not an interview, but the few questions that pick a direction are worth asking in either mode.

**Recommendation convention** (`godmode:recommend-convention`). Every question you ask follows the shared convention in `rules/godmode-recommend.md`: **lead with a Recommended option** that carries a visible one-line rationale, then let the user override. Don't hand back a flat menu of equal candidates — ideation is exactly where you owe the user your analysis, so say which direction you'd pursue and why:

```
Which direction should the next mission pursue?

  a) Add an episodic-memory layer (Recommended — the roadmap's biggest open
     gap is cross-session continuity, and the existing state file is the
     natural seam to extend)
  b) Build a metrics dashboard — useful, but no one has asked for it and it
     adds a runtime surface the project deliberately avoids
  c) Something else — tell me the problem you want the next mission to solve

Pick a letter, or describe a different direction.
```

The rationale is one line, concrete, and tied to the actual context (the project's purpose, a known gap, a stated constraint) — never a generic "this is common."

---

## Process

### 1. Read the context (no mission resolution)

`/ideate` does **not** resolve or read the active mission. Read only the project-global context that informs *what to build next*:

- `.planning/PROJECT.md` (if present) — purpose, constraints, decisions. The candidate direction must fit the charter's purpose and respect its constraints.
- Existing `.planning/ideas/` directory — if an `IDEAS.md` already exists for the same feature, this is an **update**: read it and carry forward prior directions and reasoning, editing rather than clobbering.
- The repo itself (README, manifests, recent commits) — to ground the discussion in what exists and what's missing.

Do not call `bin/godmode-mission` and do not read `active_unit` — neither is part of this skill's job.

### 2. Discuss and think out candidate directions

Surface several candidate directions for the next mission. For each, think it through out loud: the problem it solves, who benefits, rough scope, and the trade-offs against the others. Use the recommendation convention (above) to converge: lead with the direction you'd recommend and the one-line reason, then let the user steer. The goal is **one concrete proposed mission**, with the alternatives and their reasoning preserved.

### 3. Derive the slug

Derive a kebab-case `<slug>` from the **proposed feature name**, using the **same** rule `/mission` and `/brief` use — lowercase, spaces and punctuation → single hyphens, trim leading/trailing hyphens. This is what makes `/mission <feature name>` later resolve to the same slug and find this artifact:

```bash
# FEATURE_NAME is the proposed feature name converged on in step 2.
slug=$(printf '%s' "$FEATURE_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*$//')
ideas_dir=".planning/ideas/${slug}"
```

The artifact path is `${ideas_dir}/IDEAS.md`. Note there is **no** `NN` prefix here — unlike a brief, the prospective mission has no number yet.

### 4. Write the ideation artifact

Create `${ideas_dir}/` if needed and write `IDEAS.md` using the format below. Use Write for a first-time create; use Edit for a surgical update to an existing idea (preserve prior directions and reasoning). The artifact captures, at minimum: the proposed feature name, the problem/goal, the candidate directions considered **with their reasoning** (including the recommended one and *why*), and a **charter seed** (purpose / rough success criteria / known constraints) plus an initial **rough work-unit list**.

This is the last step. `/ideate` stops here — it does not start a mission.

---

## Artifact format

### `.planning/ideas/<slug>/IDEAS.md`

```markdown
# Idea: [proposed feature name]

**Updated:** [YYYY-MM-DD]
**Status:** proposal (pre-mission — no mission_id allocated yet)

## Problem / goal
[The problem this would solve or the value it would add, and who benefits.]

## Candidate directions considered
- **[Direction A]** (Recommended — [one-line reason it wins, tied to context]).
  [What it does, rough scope, trade-offs.]
- **[Direction B]** — [what it does; why it lost to A.]
- **[Direction C]** — [what it does; why it lost to A.]

## Proposed mission
[The one direction converged on — a concrete, namable mission.]

## Charter seed
- **Purpose:** [why this mission exists, for /mission to refine into PROJECT.md.]
- **Rough success criteria:** [the bar that would say the mission succeeded.]
- **Known constraints:** [hard limits the mission must respect.]

## Rough work-unit list
1. [First likely work unit — a seed for the mission's roadmap.]
2. [...]
3. [...]

## Assumptions
[Auto Mode: inferred defaults surfaced here. Otherwise omit or note open questions.]
```

---

## Output

After writing, report:

- Whether the artifact was created or updated, and its path `.planning/ideas/<slug>/IDEAS.md`.
- The proposed feature name and a one-line summary of the recommended direction and why it won over the alternatives.
- In Auto Mode, the **Assumptions** that were made.
- The next step, stated explicitly (in prose only — no state-pointer writes into a mission flow): run **`/mission <name>`** to commit the proposal into a mission. If unsure what to run next, **`/godmode`** is the fallback.

> "Idea captured at `.planning/ideas/<slug>/IDEAS.md`. When you're ready to commit, run `/mission <name>` — it reads this artifact as its seed. (Not sure? `/godmode` always tells you the next step.)"

**No workflow state written.** `/ideate` deliberately sets no state pointer (the pre-mission contract — see above), so `/godmode` will still report the cold-start default until `/mission` allocates the mission. This is expected, not a bug.

---

## Related

- **/mission** — next step: `/mission <name>` starts the mission and reads a matching `.planning/ideas/<slug>/IDEAS.md` as seed context for the charter and roadmap.
- **/onboard** — run first on an unfamiliar codebase; its findings ground the candidate directions discussed here.
- **/godmode** — reads workflow state and tells the user the next command. `/ideate` is pre-mission, so it sets no state pointer itself.

**Spine:** `/ideate` → `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. Ideate is the pre-mission front door that feeds a synthesized proposal into `/mission`.
