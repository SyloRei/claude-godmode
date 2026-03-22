---
name: explore-repo
description: "Deep codebase exploration and architecture analysis. Use when: explore this codebase, how does this work, architecture overview, understand this repo, what does this project do."
user-invocable: true
---

# Codebase Explorer

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
- These feed into `/plan-stories` and `/execute`

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

## Related

- **@researcher** — spawn for parallel deep dives into specific areas
- **@architect** — hand off for design decisions based on exploration findings
- **/prd** — use exploration findings to write better PRDs
