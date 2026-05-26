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

### 4. How to Run and Test
Detect and report the exact commands for:
- Typecheck, lint, test, build, format
- How to run the project locally
- These inform the verification done at every `/build N`

### 5. Deep Dive (on user request)
- Trace specific flows end-to-end
- Identify extension points
- Map data transformations
- Find areas of technical debt

---

## Cheatsheet Format

```
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
| Deep Dive | MUST spawn parallel `@researcher` agents when >20 source files | One `@researcher` per subsystem for concurrent deep dives |
| Design questions | Always spawn `@architect` | Evaluate architecture patterns, suggest improvements, validate design decisions |
| Vulnerability concerns | Always spawn `@security-auditor` | Audit security-sensitive areas discovered during orientation |

**Rule:** Never explore the codebase inline when `@researcher` can do it in parallel. Every claim in the cheatsheet should trace to a `@researcher` citation.

---

## Saving Results

After presenting the cheatsheet, offer to persist it so it can inform later work.

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

### After Saving

Suggest next steps:

> "Run `/mission` to capture the project charter and roadmap, or spawn `@architect` to evaluate the architecture."

---

## Feeding Back Into the Workflow

Onboarding is the orientation step at the front of the workflow spine. Its cheatsheet feeds `/mission`: the saved cheatsheet gives the charter its starting context — stack, architecture, how-to-run/test, technical-debt hotspots — so `/mission` asks fewer questions and lands a sharper purpose + roadmap. From there the spine continues `/brief N → /plan N → /build N → /verify N → /ship`.

---

## Related

- **@researcher** — spawn for cited findings and parallel deep dives into specific areas
- **@architect** — hand off for design decisions based on the cheatsheet
- **/mission** — turn the cheatsheet into a project charter and numbered roadmap

**Spine:** onboard (read-only), optionally save the cheatsheet to `.planning/onboarding.md`, then start the spine at `/mission` — the cheatsheet sharpens the charter.
