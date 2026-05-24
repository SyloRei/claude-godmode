---
name: explore-repo
description: "Build a structured understanding of an unfamiliar codebase or subsystem. Use this when you need an architecture overview, want to know how a repo works, or are orienting before planning new work."
user-invocable: true
context: fork
agent: Plan
---

# Codebase Explorer

Build a comprehensive understanding of a codebase or subsystem. Implements the auto-detection defined in CLAUDE.md. Runs read-only in a forked subagent context — it observes and reports, it never edits.

---

## Auto Mode

When `## Auto Mode Active` is present in context: do not ask clarifying questions. Explore using reasonable defaults (full repo unless a subsystem is named), surface scope assumptions inline, present the structured summary, and offer to persist findings rather than blocking on it. Treat user course-corrections as normal input.

---

## The Job

Explore systematically, then present a structured summary. Use `@researcher` agent for parallel deep dives.

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

### 3. Pattern Analysis
- Naming conventions (files, variables, functions, classes)
- Error handling patterns
- State management approach
- Data flow patterns
- Testing patterns and coverage

### 4. Quality Gate Commands
Detect and report the exact commands for:
- Typecheck, lint, test, build, format
- These inform the verification section of every `/plan N`

### 5. Deep Dive (on user request)
- Trace specific flows end-to-end
- Identify extension points
- Map data transformations
- Find areas of technical debt

---

## Output Format

```
## Project: [name]
**Stack:** [language] / [framework] / [runtime]
**Type:** [monorepo | single package | library | application]

## Architecture
[Text-based diagram or structured description]

## Key Patterns
- [Pattern]: [where/how used]

## Entry Points
- [file]: [purpose]

## Quality Gate Commands
- Typecheck: [command]
- Lint: [command]
- Test: [command]
- Build: [command]

## Notable
- [Anything surprising or important]
```

---

## Agent Routing

| Step | Agent | Purpose |
|------|-------|---------|
| Deep Dive | MUST spawn parallel @researcher agents when >20 source files | One @researcher per subsystem for concurrent deep dives |
| Design questions | Always spawn @architect | Evaluate architecture patterns, suggest improvements, validate design decisions |
| Vulnerability concerns | Always spawn @security-auditor | Audit security-sensitive areas discovered during exploration |

**Rule:** Never explore the codebase inline when @researcher can do it in parallel.

---

## Saving Results

After presenting the exploration output, offer to persist findings so they can inform later planning.

### Offer to Save

> "Save these findings to `.planning/exploration.md` so `/brief` can use them?"

- Saving is **optional** — the user must confirm before writing anything
- If the user declines, continue without further prompts about saving
- In Auto Mode, save by default and note the path inline

### Saved Exploration Format

```markdown
# Exploration: [project-name]
**Date:** [YYYY-MM-DD]
**Stack:** [language] / [framework] / [runtime]
**Type:** [monorepo | single package | library | application]

## Quality Gate Commands
- Typecheck: [command]
- Lint: [command]
- Test: [command]
- Build: [command]
- Format: [command]

## Architecture
[Text-based diagram or structured description]

## Key Files and Roles
- [file]: [purpose]

## Key Patterns
- [Pattern]: [where/how used]

## Technical Debt
- [Area]: [description and severity]

## Notable
- [Anything surprising or important]
```

### After Saving

Suggest next steps:

> "Run `/brief N` to turn these findings into a work unit, or spawn `@architect` to evaluate the architecture."

---

## Feeding Back Into the Workflow

Exploration is the orientation step at the front of the workflow spine. Its findings feed `/brief N`: the saved exploration gives the brief its starting context — stack, architecture, quality-gate commands, technical-debt hotspots — so the Socratic brief asks fewer questions and lands a sharper why + what. From there the spine continues `/plan N → /build N → /verify N → /ship`.

---

## Related

- **@researcher** — spawn for parallel deep dives into specific areas
- **@architect** — hand off for design decisions based on exploration findings
- **/brief N** — turn exploration findings into a work unit

**Spine:** explore (read-only), optionally save findings to `.planning/exploration.md`, then resume the spine at `/brief N` — findings sharpen the brief.
