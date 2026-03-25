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
