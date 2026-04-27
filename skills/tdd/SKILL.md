---
name: tdd
description: "Test-first development: red → green → refactor. May spawn @test-writer for test scaffolding."
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Task
---

# Test-Driven Development

## Connects to

- **Upstream:** (entry point — cross-cutting helper)
- **Downstream:** @test-writer (optional — scaffolds tests)
- **Reads from:** working tree (source under test)
- **Writes to:** test files, source files (red→green iteration)

## Auto Mode check

Scan for "Auto Mode Active" (case-insensitive). When detected: skip prompts
on iteration decomposition; pick the most plausible behavior list; surface
assumptions inline. Never batch-write tests — one iteration at a time even
under Auto Mode. See `rules/godmode-skills.md` § Auto Mode Detection.

---

Implement features using strict Red-Green-Refactor iterations. Implements the testing protocol defined in CLAUDE.md.

---

## The Job

Break the feature into small behaviors. For each behavior, run one Red-Green-Refactor iteration.

---

## The Iteration

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

After each iteration:
```
Iteration N: [test name]
  RED:      Test written, fails as expected
  GREEN:    [approach taken], all tests pass
  REFACTOR: [what was cleaned up] (or "none needed")
  Tests:    X passing / X total
```

---

## Agent Routing

| When | Agent | Purpose |
|------|-------|---------|
| Before first RED | MUST spawn @researcher | Find test framework, utilities, naming conventions, fixtures, and existing test patterns |
| REFACTOR | Always spawn @reviewer when >3 files changed | Review refactored code for correctness and adherence to project patterns |

**Rule:** Never explore the codebase inline when @researcher can do it in parallel.

---

## Related

- **@test-writer** — for adding coverage to existing code (not TDD)
- **/refactor** — for refactoring existing code without adding features
- **/debug** — if a test reveals a bug, switch to debugging protocol
