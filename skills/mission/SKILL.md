---
name: mission
description: "Capture project purpose, constraints, and a numbered roadmap once, so every later step shares the same context. Use this to start a new project or update its direction — it initializes or updates .planning/PROJECT.md and .planning/ROADMAP.md."
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Bash(bin/godmode-state*)
---

# Mission

Establish the durable foundation for a project: **why** it exists, the **constraints** it must respect, what **success** looks like, and a **numbered roadmap** of work units. Run once to initialize; re-run any time to update direction. Every later step (`/brief N`, `/plan N`, `/build N`, `/verify N`, `/ship`) reads this shared context.

Two artifacts live in the **consumer's** repo (the project you are helping build), never in the plugin source:

- `.planning/PROJECT.md` — purpose, constraints, success criteria. The persistent project charter.
- `.planning/ROADMAP.md` — a numbered list of work units. Each entry is referenceable by number: `/brief N` plans entry N.

---

## Auto Mode

Auto Mode suppresses **confirmation prompts** ("proceed? / shall I write it?") — never the **clarifying questions** that decide what the project actually is. A charter built on silent guesses is confidently wrong, and every later step inherits the error. So even in Auto Mode:

- **Still ask the consequential questions** — the ones whose answer materially changes the charter (who it's for, what "success" concretely means, hard constraints, scope edges) AND that the repo/README/manifests/recent commits cannot answer. Batch them up front, lettered/option style, so they're answered fast.
- **Assume the trivial** — for low-stakes gaps the repo can reasonably imply, pick a sensible default and record it under an **Assumptions** heading rather than asking.
- Don't interrogate: if the repo already answers something, don't ask it. Treat user course-corrections as normal input.

When Auto Mode is absent, same principle — ask the essential questions, keep it brief. This is a charter, not an interview, but the few questions that set direction are worth asking in either mode.

---

## Process

### 1. Read before writing

Always Read existing state first — this is an **update**, not a fresh write:

- `.planning/PROJECT.md` (if present) — current purpose, constraints, decisions.
- `.planning/ROADMAP.md` (if present) — current numbered work units and their status.
- Read the current workflow state:
  ```bash
  bin/godmode-state get active_unit
  bin/godmode-state get status
  ```

If neither doc exists, this is a first-time initialization. If they exist, preserve what is already decided (see Merge behavior below).

### 2. Gather purpose, constraints, success criteria

Establish, from the repo and the user (or inferred defaults in Auto Mode):

- **Purpose** — what the project is for and who it serves. One or two paragraphs.
- **Constraints** — hard limits: tech stack, portability targets, license, dependency budget, anything non-negotiable.
- **Success criteria** — the concrete bar that says the project achieved its goal. Measurable where possible.

### 3. Establish the numbered roadmap

Break the work into a **numbered** list of work units. Each entry:

- Has a stable integer number — the reference `/brief N` will use.
- Has a short title and a one-line outcome statement.
- Has a status: `pending`, `active`, or `done`.

Number entries sequentially. New work units append with the next free number; **never renumber existing entries** (their numbers are referenced elsewhere).

### 4. Write the artifacts (merge, never clobber)

Write `.planning/PROJECT.md` and `.planning/ROADMAP.md` using the formats below.

### 5. Record workflow state

Point the workflow at the first unstarted roadmap entry so `/godmode` can tell the user what to do next:

```bash
# N = the lowest-numbered roadmap entry that is still pending
bin/godmode-state set active_unit "N"
bin/godmode-state set status "mission defined"
bin/godmode-state set next_command "/brief N"
```

If every roadmap entry is already `done`, set `status` to `roadmap complete` and leave `next_command` pointing at `/mission` to add more work units.

---

## Merge behavior (re-running updates, does not clobber)

`/mission` is safe to re-run. On every run:

- **Preserve existing decisions.** Read the current `PROJECT.md` and carry forward purpose, constraints, success criteria, and any **Decisions** section verbatim unless the user explicitly changes one. Edit individual lines or sections; do not rewrite the whole file from a blank slate.
- **Append, don't renumber, roadmap entries.** Existing numbered entries keep their numbers and status. New work units get the next free number. If the user marks an entry done or active, change only that entry's status field.
- **Never silently drop content.** When updating a section, keep prior context; if a constraint or decision is being removed, note it explicitly (e.g. move it under a `## Superseded` heading rather than deleting it).
- **Show a diff summary.** After writing, report which sections changed and which roadmap entries were added or had their status updated.

Use Edit for surgical changes to existing files and Write only for first-time creation of an absent file.

---

## Artifact formats

### `.planning/PROJECT.md`

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
- [YYYY-MM-DD] [Decision] — [rationale]. (Preserved across re-runs.)
```

### `.planning/ROADMAP.md`

```markdown
# Roadmap: [project name]

**Updated:** [YYYY-MM-DD]

Numbered work units. Reference an entry with `/brief N`.

| # | Work unit | Outcome | Status |
|---|-----------|---------|--------|
| 1 | [title]   | [one-line outcome] | pending |
| 2 | [title]   | [one-line outcome] | active  |
| 3 | [title]   | [one-line outcome] | done    |
```

---

## Output

After writing, report:

- Which artifacts were created vs updated.
- A short diff summary: changed sections and added/updated roadmap entries.
- In Auto Mode, an **Assumptions** list of inferred defaults.
- The workflow state set and the next step:

> "Mission defined. Run `/brief N` to plan work unit N."

---

## Related

- **/brief N** — turns roadmap entry N into a work unit with a why + what + spec.
- **/godmode** — reads the workflow state this skill records and tells the user the next command.
- **/onboard** — run first on an unfamiliar codebase; its findings sharpen the purpose and constraints captured here.

**Spine:** `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. Mission is the shared-context root every later step reads from.
