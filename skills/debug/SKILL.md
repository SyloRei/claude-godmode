---
name: debug
description: "Structured debugging workflow. Use when: debug this, fix this bug, why is this failing, troubleshoot, investigate error."
user-invocable: true
---

# Structured Debugging

Find and fix bugs systematically using evidence, never guessing. Implements the debugging protocol defined in CLAUDE.md.

---

## The Job

Follow the 4-phase protocol strictly. Do NOT skip phases.

---

## Phase 1: REPRODUCE

- Get the exact error message, stack trace, or unexpected behavior
- Find minimal reproduction steps
- Identify: when did it last work? What changed since?
- If the bug is intermittent, identify conditions that trigger it
- Establish baseline: what is the EXPECTED behavior?

**Output:** "The bug is [X]. Expected [Y]. Triggered by [Z]."

---

## Phase 2: HYPOTHESIZE

- Form 2-3 hypotheses based on evidence (not intuition)
- Rank by likelihood
- For each, state what evidence would confirm or deny it

**If stuck gathering evidence:** use `@researcher` agent to search the codebase for related patterns, recent changes, or similar bugs.

**Output:**
```
H1 (most likely): [hypothesis] — confirm by [check]
H2: [hypothesis] — confirm by [check]
H3: [hypothesis] — confirm by [check]
```

---

## Phase 3: ISOLATE

- Test hypotheses one at a time, most likely first
- Add targeted logging or read code at suspect locations
- Narrow to the exact line/condition causing the failure
- DO NOT fix multiple things at once

**Output:** "Root cause: [exact cause] at [file:line]"

---

## Phase 4: FIX & VERIFY

- Apply the minimal targeted fix
- Write a regression test (fails without fix, passes with fix)
- Run ALL quality gates (as defined in CLAUDE.md):
  1. Typecheck passes
  2. Lint passes
  3. All tests pass
  4. No regressions
- Remove any debug logging added in Phase 3

**Output:** "Fixed [root cause]. Added test [name]. All quality gates pass."

---

## Rules

- Never guess. Always gather evidence first.
- State your hypothesis BEFORE each investigation step.
- One hypothesis at a time. Don't shotgun-fix.
- If stuck after 3 attempts: step back, re-examine assumptions, use @researcher for context.
- Always write a regression test.

---

## Agent Routing

| Phase | Agent | Purpose |
|-------|-------|---------|
| HYPOTHESIZE | MUST spawn @researcher when >5 files may be involved | Search codebase for related patterns, recent changes, similar bugs in parallel |
| FIX | Always spawn @test-writer for low-coverage areas | Ensure regression test coverage around the fix, especially in undertested code |
| Post-fix | MUST spawn @reviewer for security-sensitive fixes | Validate that fixes touching auth, input handling, or data access are safe |

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
| **prd-only** | May reference PRD for additional context on the bug's feature area. |
| **planning** | May reference `stories.json` to check if the bug relates to an upcoming story. |
| **executing** | Read `progress.txt` top-level sections (Codebase Patterns, Anti-Patterns, Architecture Decisions) for accumulated project knowledge. Read `.claude-pipeline/explorations/` for codebase understanding when available. Check if similar bugs were fixed in previous stories. |
| **complete** | Same as executing — accumulated knowledge is still useful for diagnosing regressions. |

---

## Related

- **@researcher** — use for gathering context when stuck
- **@test-writer** — use for comprehensive test coverage after the fix
- **/refactor** — if the fix reveals structural issues, refactor separately
