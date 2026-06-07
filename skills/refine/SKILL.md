---
name: refine
description: "Mid-mission gap analysis: read the active mission's roadmap and briefs, surface what's missing or underspecified, converge on one gap, and append a NEW numbered work unit plus its full brief — strictly additive. Use when: refine, what are we missing, find gaps in the current mission, add the next unit. Never edits an existing brief or roadmap unit in place — that is /brief N's job."
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(gm=*), Bash(*godmode-state*)
---

# Refine

The **mid-mission gap-analysis** step of the planning spine. Where `/ideate` is pre-mission and generative — exploring directions for the *next* mission before any charter exists — `/refine` is mid-mission and analytical: it works *inside* the active mission, reads what has already been planned, finds what's missing or underspecified, converges on one gap, and turns it into a buildable unit. It is the sibling of `/ideate`, one step later in the lifecycle.

`/refine` is **strictly additive**. It reads the active mission's roadmap and briefs, surfaces candidate gaps and improvements, converges on the one most worth doing next, and **appends** a new numbered work unit to the roadmap plus that unit's complete brief. It never edits or rewrites an existing brief or roadmap unit in place — in-place updates are delegated to `/brief N`. This is the spine's gap-analysis seam: `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`, with `/refine` feeding a new appended unit back to `/brief`/`/plan` whenever a gap is found.

The artifacts live in the **consumer's** repo, never in the plugin source, scoped to the **active mission**:

- `.planning/missions/<mission_id>/ROADMAP.md` — the new unit is appended here (existing entries untouched).
- `.planning/missions/<mission_id>/briefs/NN-name/BRIEF.md` — the new unit's complete brief, in the same format `/brief` produces.

`<mission_id>` is the active mission's `NN-slug`, resolved from workflow state (`"$gm/godmode-state" get mission_id`; see the helper-resolution note in Process), so `/refine` always operates on whatever mission is currently active. `.planning/PROJECT.md` and `.planning/STATE.md` stay at the `.planning/` root (project-global).

---

## Mission-scoped contract

`/refine` is a mission-scoped skill. Unlike `/ideate`, it does not run on a bare repo:

- **Requires an active mission.** It resolves `mission_id` from workflow state and operates entirely within that mission. With no active mission it stops and points the user at `/mission` — it never scaffolds or invents a mission.
- **Reads the whole mission before converging.** It surveys the active mission's roadmap and existing briefs to find gaps — not just the unit the user happens to be on.
- **Strictly additive — never edits in place.** It appends a new unit and its brief. It never rewrites, renumbers, or edits an existing roadmap entry or brief. A gap *inside* an already-specified unit becomes either a new appended unit or is deferred to `/brief N` (see below). Allocating a `mission_id` and resetting the work-unit counter remain `/mission`'s job alone — `/refine` does neither.

---

## Auto Mode

Auto Mode suppresses **confirmation prompts** ("proceed? / shall I append the unit?") — never the **gap-analysis questions** that decide *which* gap is worth doing next. Converging on the wrong gap appends a unit nobody needs, and `/brief`/`/plan`/`/build` then spend real effort on it. So in **either** mode:

- **Ask the consequential questions** — the ones whose answer materially changes which gap gets appended or how its scope is drawn (which gap matters most now, where the new unit's scope edges sit, hard constraints) AND that the roadmap / existing briefs / `.planning/PROJECT.md` / repo cannot answer. Auto Mode does not waive these; it just batches them.
- **Assume the trivial** — for low-stakes gaps the context reasonably implies, pick a sensible default and record it under an **Assumptions** heading in the brief instead of asking.
- Never ask what the roadmap or existing briefs already answer. Treat user course-corrections as normal input.

Ask following the shared recommendation convention (`godmode:recommend-convention`) defined in `rules/godmode-recommend.md`: **lead with a Recommended option** carrying a visible one-line rationale, then let the user override. A flat menu of equal gaps offloads the decision back onto the user — `/refine` is exactly where you owe the user your analysis, so say which gap you'd append and why:

```
Which gap should the next unit close?

  a) Add the missing error-path brief for the importer (Recommended — every
     built unit covers the happy path, but unit 3's brief left malformed-input
     handling unspecified, so /verify has nothing to check against)
  b) A metrics surface — useful later, but no roadmap unit or brief calls for
     it and it widens scope the mission deliberately kept narrow
  c) Something else — name the gap you want the next unit to close

Pick a letter, or describe a different gap.
```

The rationale is one line, concrete, and tied to the actual context (a specific roadmap entry, an underspecified brief, a stated constraint) — never a generic "this is common."

---

## Process

**Resolving the godmode helpers.** The `godmode-*` helpers live in the plugin install dir — **not** the consumer repo you're working in — so a bare `bin/godmode-*` path fails from another project's working directory. Every `bash` block below resolves their location into `$gm` first (plugin mode → `$CLAUDE_PLUGIN_ROOT/bin`, manual install → `~/.claude/bin`, in-repo → `./bin`) and calls `"$gm/godmode-<name>"`. Keep the resolver line; never call a helper by a bare relative path.

### 1. Resolve the active mission

First resolve which mission is active — every path below is scoped to it:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
mission_id=$("$gm/godmode-state" get mission_id)
```

If `mission_id` is unset or empty, **stop**. Tell the user to run `/mission <name>` first — `/refine` analyzes an *existing* mission and never scaffolds or invents one.

### 2. Read the mission and surface candidate gaps

Read, for the active mission:

- `.planning/missions/${mission_id}/ROADMAP.md` — the full numbered work-unit list and each entry's status.
- `.planning/missions/${mission_id}/briefs/` — every existing `NN-name/BRIEF.md`. These are the specs already captured.
- `.planning/PROJECT.md` — the project-global purpose and constraints the mission must satisfy.
- The current workflow state, so you know where the user is:
  ```bash
  gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
  "$gm/godmode-state" get mission_id
  "$gm/godmode-state" get active_unit
  "$gm/godmode-state" get status
  ```

With the whole mission in view, surface the **candidate gaps and improvements**: outcomes the roadmap implies but no unit covers, briefs missing an error path or an edge case, constraints in `PROJECT.md` that nothing yet satisfies. Use the recommendation convention (above) to converge on the **one** gap most worth closing next. The rest stay noted but unbuilt.

### 3. Derive the next unit number and directory name

The new unit takes the **next free number**: the maximum existing roadmap unit number **plus one**, zero-padded to two digits via `printf '%02d'` (the project convention: unit `3` → `03`, unit `12` → `12`). Derive a kebab-case `name` from the new unit's title — the same rule `/brief` uses: lowercase, spaces and punctuation → single hyphens, trim leading/trailing hyphens.

```bash
# mission_id from state (step 1).
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
mission_id=$("$gm/godmode-state" get mission_id)
roadmap=".planning/missions/${mission_id}/ROADMAP.md"

# MAX_UNIT = highest existing roadmap unit number (0 if the roadmap is empty).
# Roadmap units are numbered table rows ("| 23 | ... |") or "## N" headings;
# pull every leading unit number, take the largest. Default 0 when none exist.
max_unit=$(grep -Eo '^(\| *|#+ *)[0-9]+' "$roadmap" 2>/dev/null \
  | grep -Eo '[0-9]+' | sort -rn | head -1)
max_unit=${max_unit:-0}

N=$((max_unit + 1))
NN=$(printf '%02d' "$N")
name=$(printf '%s' "$UNIT_TITLE" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -cs 'a-z0-9' '-' \
  | sed -e 's/^-//' -e 's/-$//')
brief_dir=".planning/missions/${mission_id}/briefs/${NN}-${name}"
```

The brief path is `${brief_dir}/BRIEF.md`.

### 4. Append the new unit to the roadmap

**Append** the new numbered entry to `.planning/missions/${mission_id}/ROADMAP.md` — title plus its one-line outcome — at the end of the unit list. Every existing entry keeps its number, title, and status untouched. This is an Edit that adds a line; it is never a rewrite of the file's existing units.

### 5. Write the new unit's complete brief

Write the full brief at `${brief_dir}/BRIEF.md`, in the **same format `/brief` produces** (see Artifact format below): **why** (the gap and the value closing it adds), **what** (explicit in-scope and out-of-scope lists), a **spec** of verifiable `AC-N` acceptance criteria, and **assumptions**. Because this is a brand-new unit, this is always a first-time Write — `/refine` never opens an existing brief to edit it.

### 6. Record workflow state

Point the workflow at the new unit so `/godmode` knows the next command:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-state" set active_unit "$N"
"$gm/godmode-state" set status "unit appended — brief captured"
"$gm/godmode-state" set next_command "/plan $N"
```

`/refine` does **not** allocate a `mission_id` and does **not** reset the work-unit counter — only `/mission` does that. It sets the three pointers above and nothing more.

---

## Strictly additive — what /refine never does

`/refine` is append-only. To keep the boundary unambiguous:

- It **never edits or rewrites** an existing brief or an existing roadmap unit in place. Existing entries keep their numbers, titles, statuses, and AC IDs.
- A gap that lives *inside* an already-specified unit is **not** fixed by editing that unit. Either it becomes a **new appended unit** (when it is genuinely separable work), or it is **deferred to `/brief N`** (when it is a refinement of unit `N`'s own spec). In-place brief updates are `/brief N`'s job, never `/refine`'s.
- It allocates no `mission_id` and resets no counter — those belong to `/mission`.

---

## Artifact format

### `.planning/missions/<mission_id>/briefs/NN-name/BRIEF.md`

The appended unit's brief uses the exact format `/brief` produces:

```markdown
# Brief NN: [unit title]

**Updated:** [YYYY-MM-DD]
**Roadmap unit:** N — [one-line outcome from ROADMAP.md]

## Why
[The gap this unit closes — what's missing or underspecified in the mission,
the value closing it adds, and who benefits.]

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

<!-- Output follows the in-skill output convention: godmode:output-convention — see rules/godmode-output.md -->

After writing, report:

- The gap that was selected, and a one-line summary of why it won over the other candidate gaps surfaced.
- The new unit's number `N` and the path of its appended brief `.planning/missions/<mission_id>/briefs/NN-name/BRIEF.md`, confirming it was *appended* (the roadmap's existing units untouched).
- The acceptance criteria, confirming each is verifiable.
- In Auto Mode, the **Assumptions** that were made.
- The workflow state set and the next step:

> "Unit N appended to the active mission and its brief captured. Run `/plan N` to break it into a tactical plan."

---

## Related

- **/ideate** — pre-mission sibling: explores directions for the *next* mission before any charter exists. `/refine` is its mid-mission counterpart, working inside the active mission.
- **/brief N** — owns in-place brief updates. A refinement of an existing unit's spec is delegated here; `/refine` only ever appends new units.
- **/plan N** — next step: turns the appended unit's brief into a tactical plan plus verification.
- **/godmode** — reads the workflow state this skill records and tells the user the next command.

**Spine:** `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. `/refine` is the mid-mission gap-analysis step: it reads the current mission, finds what's missing, and appends a buildable unit plus its brief that re-enters the spine at `/brief`/`/plan`.
