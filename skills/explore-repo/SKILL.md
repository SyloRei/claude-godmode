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

## Agent Routing

| Phase | Agent | Purpose |
|-------|-------|---------|
| Deep Dive | MUST spawn parallel @researcher agents when >20 source files | One @researcher per subsystem for concurrent deep dives |
| Design questions | Always spawn @architect | Evaluate architecture patterns, suggest improvements, validate design decisions |
| Vulnerability concerns | Always spawn @security-auditor | Audit security-sensitive areas discovered during exploration |

**Rule:** Never explore the codebase inline when @researcher can do it in parallel.

---

## Pipeline Context

<!-- canonical: skills/_shared/pipeline-context.md -->

On activation, detect the current pipeline phase:

| # | Condition | Phase |
|---|-----------|-------|
| 1 | `.claude-pipeline/` does not exist | **no-pipeline** |
| 2 | PRD exists but no `stories.json` | **prd-only** |
| 3 | `stories.json` exists but `branchName` does not match current git branch | **no-pipeline** |
| 4 | All stories have `passes: false` | **planning** |
| 5 | Some `passes: true`, some `passes: false` | **executing** |
| 6 | All stories have `passes: true` | **complete** |

### Branch Check

```bash
current_branch=$(git branch --show-current)
pipeline_branch=$(jq -r '.branchName' .claude-pipeline/stories.json)
```

If branches differ, phase is **no-pipeline** — the pipeline belongs to a different feature.

### Phase Behaviors

| Phase | Behavior |
|-------|----------|
| **no-pipeline** | Operate in standalone mode. No pipeline artifacts read or written. Zero regression from pre-pipeline behavior. |
| **prd-only** | May reference PRD to focus exploration on areas relevant to the planned feature. |
| **planning** | May reference `stories.json` to prioritize exploration of areas relevant to upcoming stories. |
| **executing** | Read `progress.txt` top-level sections (Codebase Patterns, Anti-Patterns, Architecture Decisions) for accumulated project knowledge. Read `.claude-pipeline/explorations/` for previous exploration findings when available. Avoid re-exploring areas already covered. |
| **complete** | Same as executing — accumulated knowledge supplements exploration findings. |

---

## Saving Results

After presenting the exploration output, offer to persist findings for downstream pipeline consumption.

### Offer to Save

> "Save these findings to `.claude-pipeline/explorations/` for use by /prd and /plan-stories?"

- Saving is **optional** — the user must confirm before writing anything
- If the user declines, continue in standalone mode with no further prompts about saving

### Save Procedure

1. Create `.claude-pipeline/explorations/` directory if it does not exist
2. Write findings to `.claude-pipeline/explorations/exp-[project-name]-[date].md` (e.g., `exp-my-api-2026-03-25.md`)
3. Use the **Saved Exploration Format** below — structured with markdown headers so `/prd` and `/plan-stories` can parse sections

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

> "Run `/prd` to create a PRD based on these findings, or spawn `@architect` to evaluate the architecture."

---

## Related

- **@researcher** — spawn for parallel deep dives into specific areas
- **@architect** — hand off for design decisions based on exploration findings
- **/prd** — use exploration findings to write better PRDs

**Pipeline:** consumes nothing (entry point). Produces exploration file at `.claude-pipeline/explorations/exp-[project]-[date].md` (quality gates, architecture, patterns). Next: `/prd` to create a PRD based on findings, or `@architect` to evaluate the architecture.
