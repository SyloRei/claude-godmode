---
name: onboard
description: "Build a structured cheatsheet for an unfamiliar codebase — architecture, entry points, conventions, where-things-live, and how to run and test it. Run this to orient before /mission."
user-invocable: true
context: fork
agent: Plan
---

# Onboard

Orient yourself in an unfamiliar codebase fast. Produces a **structured cheatsheet** — architecture overview, entry points, key conventions, where-things-live, and how-to-run/test — by spawning `@researcher` for cited findings. Runs read-only: it observes and reports, it never edits.

This is the recommended **orientation step for an unfamiliar repo, run before `/mission`**. The cheatsheet sharpens the project charter and roadmap that `/mission` captures.

---

## Auto Mode

When `## Auto Mode Active` is present in context: do not ask clarifying questions. Orient using reasonable defaults (full repo unless a subsystem is named), surface scope assumptions inline, present the cheatsheet, and offer to persist it rather than blocking on it. Treat user course-corrections as normal input.

---

## The Job

Investigate systematically, then present a structured cheatsheet. Spawn `@researcher` for cited findings and parallel deep dives — never explore the codebase inline when `@researcher` can do it in parallel.

---

## Process

### 1. Project Detection (aligns with CLAUDE.md Auto-Detection)
- Language and framework
- Package manager and build system
- Test runner and coverage setup
- Linter and formatter
- Typechecker
- CI/CD configuration
- Monorepo or single package
- Deployment target (serverless, containers, static)

### 2. Architecture Map
- Directory structure and organization pattern
- Entry points (main, index, app, handler)
- Key abstractions: core types, interfaces, base classes
- Internal dependency graph
- External dependencies and their roles

### 3. Convention Analysis
- Naming conventions (files, variables, functions, classes)
- Error handling patterns
- State management approach
- Data flow patterns
- Testing patterns and coverage

### 4. Code Standards (prescriptive — distinct from Convention Analysis)
Where Convention Analysis above *describes* the patterns it observes, Code Standards *prescribes* the DO / DON'T rules the codebase has already established for itself. This step always runs — whether its findings end up persisted is decided later in **Saving Results**, not here.

- Output is a set of **DO / DON'T** entries, and **every entry must carry a `file:line` citation** as evidence. A DON'T cites where the codebase honors the prohibition, or where a violation was found; a DO cites where the pattern is established.
- Gather the evidence via `@researcher` (cited findings) — never explore the codebase inline, consistent with the skill's standing rule.
- Look across these categories of concern as a recommended, non-exhaustive starter set: error handling, naming, testing, types, imports, security, structure.

### 5. How to Run and Test
Detect and report the exact commands for:
- Typecheck, lint, test, build, format
- How to run the project locally
- These inform the verification done at every `/build N`

### 6. Deep Dive (on user request)
- Trace specific flows end-to-end
- Identify extension points
- Map data transformations
- Find areas of technical debt

---

## Cheatsheet Format

```markdown
## Project: [name]
**Stack:** [language] / [framework] / [runtime]
**Type:** [monorepo | single package | library | application]

## Architecture
[Text-based diagram or structured description]

## Entry Points
- [file]: [purpose]

## Key Conventions
- [Convention]: [where/how used]

## Where Things Live
- [area / responsibility]: [path]

## How to Run and Test
- Run locally: [command]
- Typecheck: [command]
- Lint: [command]
- Test: [command]
- Build: [command]
- Format: [command]

## Notable
- [Anything surprising or important]
```

---

## Agent Routing

| Step | Agent | Purpose |
|------|-------|---------|
| Detection & Architecture | MUST spawn `@researcher` (`subagent_type: claude-godmode:researcher`) | Cited, evidence-backed findings with `file:line` references |
| Code Standards | MUST spawn `@researcher` (`subagent_type: claude-godmode:researcher`) | Cited prescriptive DO / DON'T evidence, each with a `file:line` citation |
| Deep Dive | MUST spawn parallel `@researcher` agents when >20 source files | One `@researcher` per subsystem for concurrent deep dives |
| Design questions | Always spawn `@architect` | Evaluate architecture patterns, suggest improvements, validate design decisions |
| Vulnerability concerns | Always spawn `@security-auditor` | Audit security-sensitive areas discovered during orientation |

**Rule:** Never explore the codebase inline when `@researcher` can do it in parallel. Every claim in the cheatsheet should trace to a `@researcher` citation.

---

## Saving Results

After presenting the cheatsheet, offer to persist it so it can inform later work. Onboard can produce **two distinct artifacts**, each saved independently with its own offer:

- **`.planning/onboarding.md` — descriptive.** An orientation cheatsheet: what the codebase *is*, how it's laid out, and how to run and test it. It feeds `/mission`.
- **`.planning/STANDARDS.md` — prescriptive.** The code standards the codebase has established for itself: cited **DO / DON'T** rules that supplement or override the generic shipped `rules/godmode-*.md` where the codebase has spoken.

The two are written **independently** — each has its own save offer below, and one can be written without the other. The empty case is the clearest example: a greenfield repo gets an `onboarding.md` cheatsheet but **no** `STANDARDS.md`, because it has no established standards to cite.

### Offer to Save

> "Save this cheatsheet to `.planning/onboarding.md` so `/mission` can use it?"

- Saving is **optional** — the user must confirm before writing anything
- If the user declines, continue without further prompts about saving
- In Auto Mode, save by default and note the path inline

### Saved Cheatsheet Format

```markdown
# Onboarding: [project-name]
**Date:** [YYYY-MM-DD]
**Stack:** [language] / [framework] / [runtime]
**Type:** [monorepo | single package | library | application]

## How to Run and Test
- Run locally: [command]
- Typecheck: [command]
- Lint: [command]
- Test: [command]
- Build: [command]
- Format: [command]

## Architecture
[Text-based diagram or structured description]

## Entry Points
- [file]: [purpose]

## Where Things Live
- [area / responsibility]: [path]

## Key Conventions
- [Convention]: [where/how used]

## Technical Debt
- [Area]: [description and severity]

## Notable
- [Anything surprising or important]
```

### STANDARDS.md Format

The Code Standards step (Process step 4) produces a **prescriptive** artifact, distinct from the descriptive cheatsheet above. It is written to **`.planning/STANDARDS.md`**.

The format:

- **Grouped by concern category.** Entries sit under category headings — a recommended, non-exhaustive starter set is error handling, naming, testing, types, imports, security, structure. Add or omit categories per what the codebase actually evidences; only include a category where you have cited entries for it.
- **Each entry marked DO or DON'T.** Lead every entry with a bold **DO** or **DON'T** marker stating the rule the codebase has established for itself.
- **Each entry carries at least one `file:line` citation** as evidence. A DO cites where the pattern is established; a DON'T cites where the codebase honors the prohibition or where a violation was found. List multiple citations where prevalence is worth showing.
- **Rule-mapping note (optional).** Where an entry sharpens or contradicts a shipped generic rule in `rules/godmode-*.md`, append a short note — **"supplements godmode rule X"** when it tightens the generic rule, or **"overrides godmode rule X"** when it diverges. This note is **optional: include it only where the codebase has spoken** — i.e. where a project standard actually tightens or contradicts the generic rule. Omit it for entries that simply restate a generic rule. The generic rule names are `godmode-coding`, `godmode-context`, `godmode-git`, `godmode-identity`, `godmode-quality`, `godmode-recommend`, `godmode-routing`, `godmode-testing`, and `godmode-workflow`.

```markdown
# Project Standards: [project-name]
**Date:** [YYYY-MM-DD]

## Error Handling
- **DON'T** swallow errors with a bare catch — every caught error is logged or rethrown. Cited: [src/api/client.ts:88] — overrides godmode rule godmode-coding.
- **DO** wrap external calls in a typed `Result<T, E>` rather than throwing across module boundaries. Cited: [src/core/result.ts:12], [src/api/fetchUser.ts:40].

## Testing
- **DO** colocate `*.test.ts` files next to the unit under test. Cited: [src/core/result.test.ts:1].
- **DON'T** mock the database in integration tests — they run against a real test instance. Cited: [tests/integration/db.test.ts:9] — supplements godmode rule godmode-testing.

## Naming
- **DO** name React hooks `useX` and export them as named exports. Cited: [src/hooks/useAuth.ts:3].
```

### Saving STANDARDS.md

The Code Standards discovery step (Process step 4) **always runs** — it always gathers findings. **Writing** them to `.planning/STANDARDS.md` follows the same optional-save convention as the cheatsheet above.

> "Save the discovered code standards to `.planning/STANDARDS.md`?"

- Saving is **optional** — the user must confirm before writing anything
- If the user declines, continue without further prompts about saving
- In Auto Mode, save by default and note the `.planning/STANDARDS.md` path inline

**Empty case.** When **no standard has evidence to cite** — a greenfield repo, a tiny repo, or one with no established patterns — `STANDARDS.md` is **not written**. In that case onboard reports **"no project-specific standards found"** and notes that the generic shipped `rules/godmode-*.md` still apply.

### After Saving

Suggest next steps:

> "Run `/mission` to capture the project charter and roadmap, or spawn `@architect` to evaluate the architecture."

---

## Feeding Back Into the Workflow

Onboarding is the orientation step at the front of the workflow spine. Its **descriptive** cheatsheet feeds `/mission`: the saved `.planning/onboarding.md` gives the charter its starting context — stack, architecture, how-to-run/test, technical-debt hotspots — so `/mission` asks fewer questions and lands a sharper purpose + roadmap. From there the spine continues `/brief N → /plan N → /build N → /verify N → /ship`.

`.planning/STANDARDS.md` plays a different role. It is **prescriptive**, not orientation: the cited DO / DON'T standards it captures are written for later code-writing surfaces, where they supplement or override the generic shipped `rules/godmode-*.md` for *this* codebase. It is not consumed by `/mission` the way the cheatsheet is — it exists to carry the codebase's own conventions downstream into the work.

---

## Related

- **@researcher** — spawn for cited findings and parallel deep dives into specific areas
- **@architect** — hand off for design decisions based on the cheatsheet
- **/mission** — turn the cheatsheet into a project charter and numbered roadmap

**Spine:** onboard → `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. Onboard is the read-only orientation step that sharpens the charter `/mission` captures.
