---
name: refactor
description: "Improve code structure without changing behavior, verifying with tests at every step. Use this when you want to restructure, extract, rename, or simplify existing code that already works."
user-invocable: true
---

# Safe Refactoring

Improve code structure without changing behavior. Every step verified by tests. Implements the refactoring protocol defined in CLAUDE.md.

---

## Auto Mode

When `## Auto Mode Active` is present in context: do not pause for confirmation. Plan the steps using reasonable defaults, surface the plan and assumptions inline, then execute step by step with per-step quality gates. Treat user course-corrections as normal input.

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

| Step | Agent | Purpose |
|------|-------|---------|
| IDENTIFY | MUST spawn @researcher | Explore affected files, find all callers/consumers, map dependencies before planning |
| PLAN | Always spawn @architect when >5 files affected | Validate refactoring approach and step ordering for large-scope changes |
| VERIFY | MUST run `/verify` (5 parallel review lenses) | Review each completed refactoring step for correctness and regressions |

**Rule:** Never explore the codebase inline when @researcher can do it in parallel.

---

## Feeding Back Into the Workflow

After the PLAN step, decide how the refactoring re-enters the workflow spine:

- **Execute now (default).** Apply all steps immediately with per-step test verification and an atomic commit per step. Best for small refactorings (1-2 steps).
- **Defer as a work unit.** When the refactoring is large (3+ steps) and deserves its own planning pass, append a work unit to `.planning/missions/<mission_id>/ROADMAP.md` describing the area and the planned steps, then pick it up with `/brief N`. The brief captures the why + what, `/plan N` re-derives the steps, and `/build N` executes them with the same per-step verification.

In Auto Mode, execute now for small refactorings; for large ones, append a work unit and say so inline.

**Appended work-unit note (for `.planning/missions/<mission_id>/ROADMAP.md`):**

```
- Refactor: [area] — N steps, structure only, no behavior change.
  Steps: [short list]. Quality gates must pass before AND after each step.
```

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
- **/verify** — runs the 5 parallel review lenses on refactoring changes before committing

**Spine:** plan the steps, then either execute now (`/ship`) or append a work unit to `.planning/missions/<mission_id>/ROADMAP.md` and resume the spine at `/brief N`.
