---
name: explore-repo
description: "Deep read-only repo exploration: structure, conventions, integration points. Forked context for isolated research."
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# Codebase Explorer

## Connects to

- **Upstream:** (entry point — cross-cutting helper)
- **Downstream:** freeform — produces a structured report
- **Reads from:** working tree, git log, file structure
- **Writes to:** none (read-only exploration; report returned to user)

## Auto Mode check

Scan for "Auto Mode Active" (case-insensitive). When detected: pick a
single most-likely focus area; produce the structured summary without
asking for clarification; surface assumptions inline. See
`rules/godmode-skills.md` § Auto Mode Detection.

---

Build a comprehensive understanding of a codebase or subsystem. Implements the auto-detection defined in CLAUDE.md.

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
- These feed into `/plan N` and `/build N`

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

| When | Agent | Purpose |
|------|-------|---------|
| Deep Dive | MUST spawn parallel @researcher agents when >20 source files | One @researcher per subsystem for concurrent deep dives |
| Design questions | Always spawn @architect | Evaluate architecture patterns, suggest improvements, validate design decisions |
| Vulnerability concerns | Always spawn @security-auditor | Audit security-sensitive areas discovered during exploration |

**Rule:** Never explore the codebase inline when @researcher can do it in parallel.

---

## Related

- **@researcher** — spawn for parallel deep dives into specific areas
- **@architect** — hand off for design decisions based on exploration findings
- **/brief N** — feed exploration findings into the next brief
