---
name: refactor
description: "Safe refactoring with test verification at each step. Use when: refactor this, clean up, restructure, extract, simplify, reorganize."
user-invocable: true
---

# Safe Refactoring

Improve code structure without changing behavior. Every step verified by tests. Implements the refactoring protocol defined in CLAUDE.md.

---

## The Job

1. Verify baseline
2. Plan steps
3. Execute one step at a time with test verification
4. Report results

---

## Process

### 1. BASELINE
- Run ALL quality gates (CLAUDE.md canonical list). They must pass.
- If not: fix quality issues first (separate commit).
- Note current test count and coverage.

### 2. IDENTIFY
- What specifically needs improving and WHY
- Is this refactoring or a behavior change? (If behavior → wrong skill, use normal workflow)
- Scope: list exactly which files/functions are affected

### 3. PLAN
- Break into steps, each independently committable
- Order: safest/simplest first, riskiest last
- Each step leaves the code in a working state

### 4. EXECUTE (repeat per step)
```
a. Apply one refactoring
b. Run quality gates
c. If GREEN → commit: "refactor: [what was done]"
d. If RED → revert immediately, try smaller step
```

### 5. VERIFY
- Run full quality gates
- Compare test count (same or higher, never lower)
- Compare coverage (same or higher)
- Confirm: no behavior changed

---

## Common Refactorings

| Refactoring | When to use |
|-------------|------------|
| Extract function | >40 lines, mixed responsibilities |
| Rename | Name doesn't describe purpose |
| Inline | Abstraction adds complexity without value |
| Move | Code in wrong module/file |
| Split file | >300 lines or mixed responsibilities |
| Simplify conditional | Nested if/else, complex booleans |
| Replace magic values | Hardcoded numbers/strings |
| Improve types | `any`, loose types where precise ones exist |

---

## Rules (Non-Negotiable)

- NEVER mix refactoring with feature changes in the same commit
- Quality gates must pass before AND after EACH step
- If gates break: REVERT. Don't fix forward during refactoring.
- Commit after each successful step

---

## Agent Routing

| Phase | Agent | Purpose |
|-------|-------|---------|
| IDENTIFY | MUST spawn @researcher | Explore affected files, find all callers/consumers, map dependencies before planning |
| PLAN | Always spawn @architect when >5 files affected | Validate refactoring approach and step ordering for large-scope changes |
| VERIFY | MUST spawn @reviewer | Review each completed refactoring step for correctness and regressions |

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
| **prd-only** | May reference PRD for context on the feature area being refactored. |
| **planning** | May reference `stories.json` to check if refactoring aligns with planned stories. |
| **executing** | Read `progress.txt` top-level sections (Codebase Patterns, Anti-Patterns, Architecture Decisions) for accumulated project knowledge. Read `.claude-pipeline/explorations/` for codebase understanding when available. Check Anti-Patterns section to avoid repeating past mistakes. |
| **complete** | Same as executing — accumulated knowledge is still useful for safe refactoring. |

### Pipeline Integration

**Consumes:**
- `stories.json` — if a story mentions refactoring (e.g., `/refactor US-005`), load its description and acceptance criteria as context for scoping the refactoring
- `progress.txt` — check Anti-Patterns section to avoid repeating structural mistakes from previous stories

**After PLAN phase (end of Step 3):**

When `.claude-pipeline/stories.json` exists, phase is not **no-pipeline**, and the refactoring plan has **3 or more steps**, present the user with three options:

```
Refactoring plan: [summary]
Steps: N planned

How to proceed?
(a) Execute immediately (default) — apply all steps now with per-step test verification
(b) Generate refactoring PRD — save to .claude-pipeline/prds/prd-refactor-[area].md for later planning
(c) Append refactoring stories to stories.json — add one story per step for /execute to pick up
```

Press enter or choose (a) to execute immediately. Options (b) and (c) defer execution for pipeline-driven workflow.

**Small refactors (1-2 steps):** Always execute immediately without prompting about pipeline options, regardless of pipeline state. The overhead of pipeline stories is not justified for small changes.

**Option (c) appended story format:**

Each refactoring step maps to one story. Stories are chained sequentially with `dependsOn` to enforce execution order:

```json
{
  "id": "US-NNN",          // next available ID (continue sequence from existing stories)
  "title": "Refactor: [step description]",
  "description": "Refactoring step N of M: [what this step does]. Part of [area] refactoring.",
  "acceptanceCriteria": [
    "[specific refactoring criterion for this step]",
    "All tests pass before AND after this refactoring step",
    "No behavior changes — only structural improvement",
    "All quality gates pass"
  ],
  "dependsOn": ["US-PPP"],  // previous step's ID (first step: [] or existing dependency)
  "priority": N,             // max existing priority + 1 (incremented per step)
  "passes": false,
  "notes": ""
}
```

**Example:** A 4-step refactoring produces stories US-015 through US-018, where US-016 depends on US-015, US-017 depends on US-016, and US-018 depends on US-017.

**Standalone mode (no pipeline):** When `.claude-pipeline/stories.json` does not exist or phase is **no-pipeline**, always proceed directly to Step 4 (execute) without prompting about pipeline options.

---

## Output

```
Refactoring: [what and why]
Steps completed: N
  1. [step] — gates pass ✓
  2. [step] — gates pass ✓
Tests: [before] → [after]
Coverage: [before] → [after]
```

---

## Related

- **/tdd** — for TDD-style development of new features
- **/debug** — if refactoring reveals bugs, switch to debug protocol
- **@reviewer** — for review of refactoring changes before committing
