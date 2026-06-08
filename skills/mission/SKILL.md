---
name: mission
description: "Start or switch to a named feature mission and capture its purpose, constraints, and numbered roadmap, so every later step shares the same context. Use this to begin a new feature cycle or update its direction — it drives bin/godmode-mission, maintains the project-global .planning/PROJECT.md, and writes the mission's .planning/missions/<mission_id>/ROADMAP.md."
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Bash(gm=*), Bash(*godmode-state*), Bash(*godmode-mission*)
---

# Mission

Establish the durable foundation for a **named feature cycle** — a *mission*: **why** it exists, the **constraints** it must respect, what **success** looks like, and a **numbered roadmap** of work units. Run `/mission <feature name>` to create-or-switch a mission; re-run any time to update its direction. Every later step (`/brief N`, `/plan N`, `/build N`, `/verify N`, `/ship`) reads this shared context for the active mission. If `/ideate` already proposed this feature, `/mission` picks up that proposal as seed context (see step 2).

A **mission** is a named feature cycle stored at `.planning/missions/<mission_id>/`, where `<mission_id>` is `NN-slug` (allocated by `bin/godmode-mission`). Each mission owns its own roadmap and briefs, and its work units number from 1 *within the mission*.

Artifacts live in the **consumer's** repo (the project you are helping build), never in the plugin source. Two are **project-global** at the `.planning/` root and span every mission; one is **mission-scoped**:

- `.planning/PROJECT.md` *(root, global)* — purpose, constraints, success criteria. The persistent project charter, shared by all missions.
- `.planning/STATE.md` *(root, global)* — workflow state, including the active `mission_id`.
- `.planning/missions/<mission_id>/ROADMAP.md` *(per-mission)* — this mission's numbered list of work units. Each entry is referenceable by number: `/brief N` plans entry N **of the active mission**.

---

## Auto Mode

Auto Mode suppresses **confirmation prompts** ("proceed? / shall I write it?") — never the **clarifying questions** that decide what the project actually is. A charter built on silent guesses is confidently wrong, and every later step inherits the error. So even in Auto Mode:

- **Still ask the consequential questions** — the ones whose answer materially changes the charter or this mission's scope (who it's for, what "success" concretely means, hard constraints, scope edges) AND that the repo/README/manifests/recent commits cannot answer. Batch them up front, lettered/option style, so they're answered fast.
- **Assume the trivial** — for low-stakes gaps the repo can reasonably imply, pick a sensible default and record it under an **Assumptions** heading rather than asking.
- Don't interrogate: if the repo already answers something, don't ask it. Treat user course-corrections as normal input.

When Auto Mode is absent, same principle — ask the essential questions, keep it brief. This is a charter, not an interview, but the few questions that set direction are worth asking in either mode.

**Recommendation convention** (`godmode:recommend-convention`). Every question you ask follows the shared convention in `rules/godmode-recommend.md`: lead with a **Recommended** option that carries a visible one-line rationale, then let the user override. Don't hand back a flat menu of equal choices — you did the analysis, so say what you'd pick and why:

```
What does "success" concretely mean for this project?

  a) Ships a working CLI a new user can install and run (Recommended — the
     repo is a tool, and the README frames adoption as the goal)
  b) Reaches feature parity with the prior version — broader, slower to verify
  c) Something else — tell me

Pick a letter, or describe a different option.
```

---

## Process

### 1. Start or switch the mission

**Resolving the godmode helpers.** The `godmode-*` helpers live in the plugin install dir — **not** the consumer repo you're working in — so a bare `bin/godmode-*` path fails from another project's working directory. Every `bash` block below resolves their location into `$gm` first (plugin mode → `$CLAUDE_PLUGIN_ROOT/bin`, manual install → `~/.claude/bin`, in-repo → `./bin`) and calls `"$gm/godmode-<name>"`. The helpers still operate on the consumer repo's `.planning/` (your current working directory) — only the binary is resolved from the install dir. Keep the resolver line; never call a helper by a bare relative path.

`/mission` always takes a **feature name** as its argument. Hand it to the lifecycle helper, which slugifies the name and decides create-vs-switch:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-mission" start <feature name>
```

- **New name** (no `.planning/missions/NN-slug` for that slug yet) → the helper allocates the next `NN`, scaffolds `.planning/missions/NN-slug/` with a header-only `ROADMAP.md` and a `briefs/` directory, records `mission_id`/`mission_name` in state, and **resets `active_unit` to 1**. This is a fresh feature cycle: its roadmap and briefs number from 1.
- **Existing name** (a mission dir already exists for that slug) → the helper **switches** to it: it sets `mission_id`/`mission_name` and **leaves `active_unit` unchanged**, preserving that mission's counter.

Then resolve the active mission so every later path is mission-scoped:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
mission_id=$("$gm/godmode-state" get mission_id)
```

If `/mission` was invoked without a feature name, ask the user for one before doing anything else — a mission must be named.

### 2. Seed from a prior `/ideate` artifact (additive, best-effort)

`/ideate` (the pre-mission front door) may have written a durable proposal at `.planning/ideas/<slug>/IDEAS.md`, where `<slug>` is the kebab-case feature name. Because `bin/godmode-mission start <feature name>` derives the mission's `<slug>` from the **same** feature name with the **same** slugify rule, an `/ideate` proposal and the `/mission` of the same name share a slug — that slug match is the contract that connects them.

The active `mission_id` is `NN-slug`; the seed slug is its `slug` portion (everything after the leading `NN-`). With that slug known, check for the artifact and, **if it exists**, Read it and use it as seed context for the charter (`PROJECT.md`) and this mission's `ROADMAP.md` — the proposed purpose, rough success criteria, known constraints, candidate directions, and rough work-unit list become starting material for the steps below (still subject to the consequential questions and merge behavior; the user can override anything).

This read is **additive and best-effort**: if no matching `.planning/ideas/<slug>/IDEAS.md` exists, do nothing and continue — `/mission` behaves **exactly as it does today**, with no error and no change to any other behavior described here. The artifact only ever adds seed context; it never gates or alters the mission lifecycle.

### 3. Read before writing

Always Read existing state first — re-running `/mission` for the same mission is an **update**, not a fresh write:

- `.planning/PROJECT.md` (if present) — current purpose, constraints, decisions (project-global, at the `.planning/` root; shared by all missions).
- `.planning/missions/${mission_id}/ROADMAP.md` — this mission's numbered work units and their status. For a freshly created mission the helper has already seeded a header-only file.
- Read the current workflow state:
  ```bash
  gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
  "$gm/godmode-state" get active_unit
  "$gm/godmode-state" get status
  ```

If `PROJECT.md` does not exist, this is a first-time project initialization. If it exists, preserve what is already decided (see Merge behavior below).

### 4. Gather purpose, constraints, success criteria

Establish, from the repo and the user (or inferred defaults in Auto Mode):

- **Purpose** — what the project is for and who it serves. One or two paragraphs. This is project-global; refine it across missions, don't rewrite it per feature.
- **Constraints** — hard limits: tech stack, portability targets, license, dependency budget, anything non-negotiable.
- **Success criteria** — the concrete bar that says the project achieved its goal. Measurable where possible.

The charter (`PROJECT.md`) spans all missions. The current mission's roadmap captures only the work units that belong to *this* feature cycle.

### 5. Establish the mission's numbered roadmap

Break this mission's work into a **numbered** list of work units. Each entry:

- Has a stable integer number — the reference `/brief N` will use. Numbering starts at 1 **within the mission**.
- Has a short title and a one-line outcome statement.
- Has a status: `pending`, `active`, or `done`.

Number entries sequentially. New work units append with the next free number; **never renumber existing entries** (their numbers are referenced elsewhere).

### 6. Write the artifacts (merge, never clobber)

Write the project-global `.planning/PROJECT.md` (at the root) and the mission-scoped `.planning/missions/${mission_id}/ROADMAP.md` using the formats below.

### 7. Record workflow state

Point the workflow at the first unstarted roadmap entry so `/godmode` can tell the user what to do next:

```bash
# N = the lowest-numbered roadmap entry of this mission that is still pending
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-state" set active_unit "N"
"$gm/godmode-state" set status "mission defined"
"$gm/godmode-state" set next_command "/brief N"
```

`mission_id`/`mission_name` are already set by `bin/godmode-mission start` (step 1) — do not set them by hand here.

If every roadmap entry is already `done`, set `status` to `roadmap complete` and leave `next_command` pointing at `/mission` to add more work units to this mission (or start a new one).

---

## Merge behavior (re-running updates, does not clobber)

`/mission` is safe to re-run, and the name you pass decides what happens — this is enforced by `bin/godmode-mission`:

- **New feature name → new mission, counter reset.** A name with no existing mission dir scaffolds a fresh `.planning/missions/NN-slug/` and resets `active_unit` to 1. The new mission's roadmap and briefs number from 1, independent of every other mission.
- **Existing feature name → merge in place, counter preserved.** Re-running with a name that already has a mission dir switches to it and leaves `active_unit` (its counter) untouched. You then **update** that mission's existing `ROADMAP.md` rather than starting over. Merge-never-clobber is now scoped to that mission.

On every run, regardless of create-vs-switch:

- **Preserve existing decisions.** Read the current project-global `PROJECT.md` and carry forward purpose, constraints, success criteria, and any **Decisions** section verbatim unless the user explicitly changes one. Edit individual lines or sections; do not rewrite the whole file from a blank slate. `PROJECT.md` is shared across missions — never reset it when starting a new mission.
- **Append, don't renumber, roadmap entries.** Within the active mission's `ROADMAP.md`, existing numbered entries keep their numbers and status. New work units get the next free number. If the user marks an entry done or active, change only that entry's status field.
- **Never silently drop content.** When updating a section, keep prior context; if a constraint or decision is being removed, note it explicitly (e.g. move it under a `## Superseded` heading rather than deleting it).
- **Show a diff summary.** After writing, report which sections changed and which roadmap entries were added or had their status updated.

Use Edit for surgical changes to existing files (the project-global `PROJECT.md`, and an existing mission's `ROADMAP.md`) and Write only for first-time population of a freshly seeded or absent file.

---

## Artifact formats

### `.planning/PROJECT.md` *(root, project-global)*

```markdown
# Project: [name]

**Updated:** [YYYY-MM-DD]

## Purpose
[Why this project exists and who it serves.]

## Success Criteria
- [Concrete, measurable where possible.]

## Constraints
- [Hard limits: stack, portability, license, dependency budget, non-negotiables.]

## Decisions
- [YYYY-MM-DD] [Decision] — [rationale]. (Preserved across re-runs and missions.)
```

### `.planning/missions/<mission_id>/ROADMAP.md` *(per-mission)*

`bin/godmode-mission` seeds this header-only when the mission is created; `/mission` populates and updates it. `<mission_id>` is the active mission's `NN-slug` from `"$gm/godmode-state" get mission_id` (see the helper-resolution note in step 1).

```markdown
# Roadmap: [mission name]

**Updated:** [YYYY-MM-DD]

Numbered work units for this mission. Reference an entry with `/brief N`.

| # | Work unit | Outcome | Status |
|---|-----------|---------|--------|
| 1 | [title]   | [one-line outcome] | pending |
| 2 | [title]   | [one-line outcome] | active  |
| 3 | [title]   | [one-line outcome] | done    |
```

---

## Output

<!-- Output follows the in-skill output convention: godmode:output-convention — see rules/godmode-output.md -->

After writing, report:

- The active mission (`mission_id` and `mission_name`), and whether it was created fresh or switched into.
- Which artifacts were created vs updated, with their paths (the global `.planning/PROJECT.md` and the mission-scoped `.planning/missions/<mission_id>/ROADMAP.md`).
- A short diff summary: changed sections and added/updated roadmap entries.
- In Auto Mode, an **Assumptions** list of inferred defaults.
- The workflow state set and the next step:

> "Mission '<mission_name>' defined. Run `/brief N` to plan work unit N."

---

## Related

- **/ideate** — the pre-mission front door: discusses and proposes the next mission, writing `.planning/ideas/<slug>/IDEAS.md`. `/mission <name>` auto-reads a matching artifact as seed context (step 2).
- **/brief N** — turns roadmap entry N of the active mission into a work unit with a why + what + spec.
- **/godmode** — reads the workflow state this skill records (including the active `mission_id`) and tells the user the next command.
- **/onboard** — run first on an unfamiliar codebase; its findings sharpen the purpose and constraints captured in `PROJECT.md`.
- **bin/godmode-mission** — the lifecycle helper this skill drives to create-or-switch missions and keep `mission_id`/`mission_name` in sync.

**Spine:** `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. Mission is the shared-context root every later step reads from, scoped to the active mission.
