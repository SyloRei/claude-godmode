---
name: tdd
description: "Build new behavior test-first using strict Red-Green-Refactor cycles. Use this when you want to drive a new feature or behavior from failing tests before writing the implementation."
user-invocable: true
---

# Test-Driven Development

Implement features using strict Red-Green-Refactor cycles. Implements the testing protocol defined in CLAUDE.md.

---

## Auto Mode

Auto Mode suppresses confirmation prompts, not the clarifying questions that decide what the tests assert. **If a target behavior is genuinely ambiguous — the expected output, an edge case's contract — ask** (the tests encode it; guessing bakes the wrong contract into red-green). For low-stakes decomposition choices, use reasonable defaults and surface the behavior list + assumptions inline, then run the cycles. Treat course-corrections as normal input.

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
- Commit after each GREEN step (atomic progress)
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

| Step | Agent | Purpose |
|------|-------|---------|
| Before first RED | MUST spawn @researcher | Find test framework, utilities, naming conventions, fixtures, and existing test patterns |
| REFACTOR | Always spawn @reviewer when >3 files changed | Review refactored code for correctness and adherence to project patterns |

**Rule:** Never explore the codebase inline when @researcher can do it in parallel.

---

## Feeding Back Into the Workflow

After the behavior list is generated (end of "Workflow Per Feature" step 1), decide how the work re-enters the workflow spine:

- **Run all cycles now (default).** Drive each behavior through RED-GREEN-REFACTOR immediately, committing after each GREEN. Best when the feature is small and well-scoped.
- **Defer as a work unit.** When the feature is large (4+ behaviors) and deserves its own planning pass, append a work unit to `.planning/ROADMAP.md` describing the feature and its behaviors, then pick it up with `/brief N`. The brief captures the why + what, `/plan N` breaks it down into the same behavior list, and `/build N` drives the cycles.

In Auto Mode, run all cycles now unless the feature clearly needs its own planning pass — then append a work unit and say so inline.

**Appended work-unit note (for `.planning/ROADMAP.md`):**

```
- TDD: [feature name] — N behaviors, each one RED-GREEN-REFACTOR cycle.
  Behaviors: [short list]. Drive test-first; quality gates per cycle.
```

---

## Related

- **@test-writer** — for adding coverage to existing code (not TDD)
- **/refactor** — for refactoring existing code without adding features
- **/debug** — if a test reveals a bug, switch to debugging protocol

**Spine:** decompose into behaviors, then either run the cycles now (`/ship`) or append a work unit to `.planning/ROADMAP.md` and resume the spine at `/brief N`.
