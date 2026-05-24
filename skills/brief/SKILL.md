---
name: brief
description: "Turn a numbered roadmap unit into a single brief — why + what + spec — so implementation is unambiguous. Use when: brief N, write the brief for N, capture requirements for roadmap unit N before building."
user-invocable: true
argument-hint: [N]
arguments: [N]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bin/godmode-state*), Bash(*/.claude/bin/godmode-state*), Bash(*/bin/godmode-state*)
---

# Brief

Capture everything implementation needs for roadmap unit **$N** in one artifact: **why** it matters (problem/goal), **what** is in and out of scope, and a **spec** of verifiable acceptance criteria. A good brief leaves no room for "I assumed you meant…".

Run after `/mission` has produced a numbered roadmap. The brief is the contract `/plan N` and `/build N` read from. This is the second step of the spine: `/mission` → **`/brief N`** → `/plan N` → `/build N` → `/verify N` → `/ship`.

The artifact lives in the **consumer's** repo, never in the plugin source:

- `.planning/briefs/NN-name/BRIEF.md` — the single brief for roadmap unit `$N`.

**One brief artifact per unit.** No second file at this step — `/plan N` adds `PLAN.md` later. Write `BRIEF.md` and nothing else.

---

## Auto Mode

When `## Auto Mode Active` is present in context: do not ask clarifying questions. Infer the why + what + spec from the roadmap entry, `.planning/PROJECT.md`, the README, and the repo. Pick reasonable defaults, surface every assumption inline under an **Assumptions** heading in the brief, and write the artifact. Treat user course-corrections as normal input.

When Auto Mode is absent, ask only the **essential** clarifying questions — the ones the roadmap and repo cannot answer (scope edges, the bar for "done", hard constraints). Use a lettered/option style so the user can answer fast:

```
Scope of unit N — which of these is in scope?
  a) ... (recommended)
  b) ...
  c) something else — tell me
```

Keep it tight. A brief is a contract, not an interview.

---

## Process

### 1. Read the roadmap unit

Read `.planning/ROADMAP.md` and find the numbered entry **$N**. That entry's title and one-line outcome are the seed for this brief. If `$N` does not exist in the roadmap, stop and tell the user to run `/mission` to add or renumber it — do not invent a unit.

Also read for context:

- `.planning/PROJECT.md` — purpose, constraints, decisions the brief must respect.
- The current workflow state, so you know where the user is:
  ```bash
  bin/godmode-state get active_unit
  bin/godmode-state get status
  ```
- Any existing `.planning/briefs/` directory — if a brief for `$N` already exists, this is an **update**: read it and preserve prior decisions, editing rather than clobbering.

### 2. Derive the directory name

`NN` is `$N` **zero-padded to two digits** (the project convention: unit `3` → `03`, unit `12` → `12`), matching `printf '%02d'` below. Derive a kebab-case `name` from the unit title: lowercase, spaces and punctuation → single hyphens, trim leading/trailing hyphens.

```bash
# N comes from the roadmap unit number ($N).
NN=$(printf '%02d' "$N")
name=$(printf '%s' "$UNIT_TITLE" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -cs 'a-z0-9' '-' \
  | sed -e 's/^-//' -e 's/-$//')
brief_dir=".planning/briefs/${NN}-${name}"
```

The brief path is `${brief_dir}/BRIEF.md`.

### 3. Capture WHY + WHAT + SPEC

Fill the three required sections:

- **WHY** — the problem or goal. What pain does this unit remove, or what value does it add? Who benefits? Tie it back to the roadmap outcome and `PROJECT.md` purpose.
- **WHAT** — scope. An explicit **in scope** list and an explicit **out of scope** list. The out-of-scope list is what prevents drift; do not skip it.
- **SPEC** — the acceptance criteria. Each one **verifiable** (see below). These become the bar `/verify N` checks against.

### 4. Write verifiable acceptance criteria

Every criterion must be **checkable** — a reader can run it or observe it and get an unambiguous yes/no. State the trigger and the expected observable result.

**Good (verifiable):**

- "Returns HTTP 404 with `{"error":"not found"}` when the id does not exist."
- "`brief N` writes exactly one file at `.planning/briefs/NN-name/BRIEF.md`."
- "Lint passes with zero shellcheck warnings on changed `.sh` files."
- "An empty input list renders the 'No items yet' placeholder."

**Bad (vague — do not write these):**

- "Works correctly."
- "Handles errors gracefully."
- "The brief is good quality."
- "User experience is improved."

If a criterion can't be made verifiable, it isn't a criterion yet — turn it into one (name the trigger + the observable outcome) or drop it.

Label each criterion sequentially: `AC-1`, `AC-2`, … These IDs are the stable contract `/plan N` (which references them in its steps and verification plan) and `/verify N` (which classifies each by ID) depend on. **When updating a brief, preserve existing AC IDs and append new ones — never renumber**, or you break verification evidence that already cited the old IDs.

### 5. Write the brief artifact

Create `${brief_dir}/` if needed and write `BRIEF.md` using the format below. Use Write for a first-time create; use Edit for a surgical update to an existing brief (preserve prior decisions and assumptions).

### 6. Record workflow state

Point the workflow at planning this unit so `/godmode` knows the next command:

```bash
bin/godmode-state set active_unit "$N"
bin/godmode-state set status "brief captured"
bin/godmode-state set next_command "/plan $N"
```

---

## Artifact format

### `.planning/briefs/NN-name/BRIEF.md`

```markdown
# Brief NN: [unit title]

**Updated:** [YYYY-MM-DD]
**Roadmap unit:** N — [one-line outcome from ROADMAP.md]

## Why
[The problem or goal. What pain this removes / value it adds, and who benefits.]

## What

### In scope
- [Concrete capability included.]

### Out of scope
- [Explicitly excluded — what this unit will NOT do.]

## Spec — acceptance criteria
Each criterion is verifiable (a clear trigger and observable result) and carries a stable **`AC-N`** label — these IDs are the references `/plan N` and `/verify N` use.

- [ ] **AC-1:** [Returns / renders / writes ... when ...]
- [ ] **AC-2:** [...]

## Assumptions
[Auto Mode: inferred defaults surfaced here. Otherwise omit or note open questions.]
```

---

## Output

After writing, report:

- Whether the brief was created or updated, and its path `.planning/briefs/NN-name/BRIEF.md`.
- A one-line summary of the why + the in/out scope split.
- The acceptance criteria, confirming each is verifiable.
- In Auto Mode, the **Assumptions** that were made.
- The workflow state set and the next step:

> "Brief captured for unit N. Run `/plan N` to break it into a tactical plan."

---

## Related

- **/mission** — preceding step: produces the numbered roadmap this brief reads unit N from.
- **/plan N** — next step: turns this brief into a tactical plan plus verification.
- **/godmode** — reads the workflow state this skill records and tells the user the next command.

**Spine:** `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. The brief is the why + what + spec contract every later step builds against.
