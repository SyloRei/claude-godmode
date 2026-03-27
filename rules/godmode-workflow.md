## Workflow Phases

Every non-trivial task follows this cycle:

1. **UNDERSTAND** — Read relevant files, grep patterns, check tests, understand the domain
2. **PLAN** — State approach in 3-5 bullets before coding. For multi-file changes, use plan mode.
3. **EXECUTE** — Small atomic changes, one concern per change
4. **VERIFY** — Run quality gates (see below). Show evidence.
5. **SHIP** — Clean commits, PR-ready state

Skip phases only for trivial tasks (typo fixes, single-line changes).

## Feature Pipeline

For multi-story features, use the full pipeline:
```
/prd → /plan-stories → /execute → /ship
```

### Pipeline Entry Points

Not every workflow starts with `/prd`. Choose the right entry point:

```
New to codebase    → /explore-repo → /prd → /plan-stories → /execute → /ship
Feature from scratch → /prd → /plan-stories → /execute → /ship
Found bugs         → /debug → append stories → /execute → /ship
Need to refactor   → /refactor → append stories → /execute → /ship
TDD a feature      → /tdd [story ID] → append stories → /execute → /ship
```

### Common Workflow Examples

```
# Exploration-first (recommended for unfamiliar codebases)
/explore-repo  →  saves findings  →  /prd consumes them  →  fewer questions, better PRD

# Bug found during review
/debug  →  diagnose root cause  →  option: append fix story to stories.json  →  /execute

# Large refactoring
/refactor  →  PLAN phase identifies 5 steps  →  option: generate 5 chained stories  →  /execute

# Mid-pipeline course correction
/execute finds test failures  →  /debug to diagnose  →  fix  →  /execute to continue
/execute gets @reviewer CRITICAL on structure  →  /refactor  →  /execute to continue
/execute gets @reviewer CRITICAL on security  →  @security-auditor  →  fix  →  /execute
```
