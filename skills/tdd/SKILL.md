---
name: tdd
description: "Test-driven development workflow. Use when: tdd, test first, write tests for, red green refactor, test driven."
user-invocable: true
---

# Test-Driven Development

Implement features using strict Red-Green-Refactor cycles. Implements the testing protocol defined in CLAUDE.md.

---

## The Job

Break the feature into small behaviors. For each behavior, run one Red-Green-Refactor cycle.

---

## The Cycle

### RED — Write a failing test

- Write ONE test for the next desired behavior
- Run it. It MUST fail. If it passes, the test is wrong.
- The test should fail for the RIGHT reason (not syntax/import error)
- Test name: `should [expected behavior] when [condition]`

### GREEN — Make it pass with minimal code

- Write the SIMPLEST code that makes the test pass
- No optimization, no elegance — just pass
- Run ALL tests. Every test must pass.

### REFACTOR — Clean up while green

- Remove duplication, improve naming, simplify logic
- Run tests after EACH refactoring change
- If any test breaks: revert and try smaller step

---

## Rules

- **NEVER write production code without a failing test first**
- One test at a time. Don't batch.
- Commit after each GREEN phase (atomic progress)
- Test behavior, not implementation details
- Keep tests independent — no shared mutable state
- Detect and use the project's existing test framework

---

## Workflow Per Feature

1. List the behaviors to implement (3-7 items typically)
2. Order from simplest to most complex
3. For each: RED → GREEN → REFACTOR → COMMIT
4. After all: run quality gates (CLAUDE.md canonical list)

---

## Progress Report

After each cycle:
```
Cycle N: [test name]
  RED:      Test written, fails as expected
  GREEN:    [approach taken], all tests pass
  REFACTOR: [what was cleaned up] (or "none needed")
  Tests:    X passing / X total
```

---

## Agent Routing

| Phase | Agent | Purpose |
|-------|-------|---------|
| Before first RED | MUST spawn @researcher | Find test framework, utilities, naming conventions, fixtures, and existing test patterns |
| REFACTOR | Always spawn @reviewer when >3 files changed | Review refactored code for correctness and adherence to project patterns |

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
| **prd-only** | May reference PRD for context on what feature is being built. |
| **planning** | May reference `stories.json` to align test behaviors with upcoming story acceptance criteria. |
| **executing** | Read `progress.md` Knowledge Base sections (Codebase Patterns, Anti-Patterns, Architecture Decisions) for accumulated project knowledge. Read `.claude-pipeline/explorations/` for codebase understanding when available. Use test patterns from previous stories to maintain consistency. |
| **complete** | Same as executing — accumulated knowledge is still useful for writing consistent tests. |

### Pipeline Integration

**Consumes:**
- `stories.json` — accepts a story ID as input (e.g., `/tdd US-003`), loads the story's description and acceptance criteria as the feature spec to drive behavior decomposition
- `progress.md` — reads Codebase Patterns section for test patterns from previous stories (naming conventions, test utilities, fixture patterns)

**After behavior list is generated (end of "Workflow Per Feature" step 1):**

When `.claude-pipeline/stories.json` exists, phase is not **no-pipeline**, AND the behavior list has **4 or more items**, present the user with two options:

```
Behaviors identified (N items):
1. [behavior]
2. [behavior]
...

How to proceed?
(a) Execute all cycles immediately (default) — run RED-GREEN-REFACTOR for each behavior now
(b) Generate one story per behavior — append to stories.json for /execute to pick up
```

Press enter or choose (a) to execute immediately. Option (b) defers execution to the pipeline.

**Option (b) generated story format:**

Each behavior becomes one story. Stories are chained sequentially with `dependsOn`:

```json
{
  "id": "US-NNN",          // next available ID (continue sequence from existing stories)
  "title": "TDD: [behavior description]",
  "description": "One RED-GREEN-REFACTOR cycle for: [behavior]. Part of /tdd decomposition from [source story ID or feature name].",
  "acceptanceCriteria": [
    "Failing test written for: [behavior]",
    "Minimal implementation makes the test pass",
    "Code refactored while all tests remain green",
    "All quality gates pass"
  ],
  "dependsOn": ["US-PPP"],  // previous story in chain (first story depends on nothing or source story)
  "priority": N,             // max existing priority + 1, incrementing for each
  "passes": false,
  "notes": ""
}
```

The first generated story has `dependsOn: []` (or `["US-source"]` if invoked with a story ID). Each subsequent story depends on the previous one, ensuring sequential execution.

**Standalone mode:** When `.claude-pipeline/stories.json` does not exist, phase is **no-pipeline**, OR the behavior list has **fewer than 4 items**, always execute all cycles immediately without prompting about pipeline options.

---

## Related

- **@test-writer** — for adding coverage to existing code (not TDD)
- **/refactor** — for refactoring existing code without adding features
- **/debug** — if a test reveals a bug, switch to debugging protocol

**Pipeline:** consumes stories.json (story ID as feature spec), progress.md (test patterns from previous stories). Produces one story per behavior (each = one RED-GREEN-REFACTOR cycle, chained with dependsOn). Next: `/execute` to implement TDD stories.
