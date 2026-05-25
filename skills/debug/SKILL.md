---
name: debug
description: "Find the root cause of a failure with evidence, then fix it. Use this when something is broken: a bug, a failing test, an unexpected result, or an error you need to track down."
user-invocable: true
---

# Structured Debugging

Find and fix bugs systematically using evidence, never guessing. Implements the debugging protocol defined in CLAUDE.md.

---

## Auto Mode

Auto Mode suppresses confirmation prompts and proceed-pauses — not the one clarifying question that can matter here: **if the symptom isn't reproducible and the exact error/repro steps aren't given, ask for them** (debugging the wrong symptom wastes the whole effort). Once you can reproduce, proceed: fix immediately after the root cause is found, surface assumptions inline, and treat course-corrections as normal input. Don't loop on trivia.

---

## The Job

Follow the 4-step protocol strictly. Do NOT skip steps.

---

## Step 1: REPRODUCE

- Get the exact error message, stack trace, or unexpected behavior
- Find minimal reproduction steps
- Identify: when did it last work? What changed since?
- If the bug is intermittent, identify conditions that trigger it
- Establish baseline: what is the EXPECTED behavior?

**Output:** "The bug is [X]. Expected [Y]. Triggered by [Z]."

---

## Step 2: HYPOTHESIZE

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

## Step 3: ISOLATE

- Test hypotheses one at a time, most likely first
- Add targeted logging or read code at suspect locations
- Narrow to the exact line/condition causing the failure
- DO NOT fix multiple things at once

**Output:** "Root cause: [exact cause] at [file:line]"

---

## Step 4: FIX & VERIFY

- Apply the minimal targeted fix
- Write a regression test (fails without fix, passes with fix)
- Run ALL quality gates (as defined in CLAUDE.md):
  1. Typecheck passes
  2. Lint passes
  3. All tests pass
  4. No regressions
- Remove any debug logging added in Step 3

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

| Step | Agent | Purpose |
|------|-------|---------|
| HYPOTHESIZE | MUST spawn @researcher when >5 files may be involved | Search codebase for related patterns, recent changes, similar bugs in parallel |
| FIX | Always spawn @test-writer for low-coverage areas | Ensure regression test coverage around the fix, especially in undertested code |
| Post-fix | MUST spawn @security-auditor for security-sensitive fixes | Validate that fixes touching auth, input handling, or data access are safe |

**Rule:** Never explore the codebase inline when @researcher can do it in parallel.

---

## Feeding Back Into the Workflow

Once the root cause is found (end of Step 3), decide how the fix re-enters the workflow spine:

- **Fix now (default).** Apply the fix immediately, write the regression test, run quality gates, commit. Best for small, well-understood bugs.
- **Defer as a work unit.** When the fix is larger or should be planned alongside other work, append a new work unit to `.planning/missions/<mission_id>/ROADMAP.md` describing the bug and root cause, then pick it up later with `/brief N`. The brief captures the why + what, `/plan N` breaks it down, and `/build N` ships it.

In Auto Mode, fix now unless the bug clearly needs design work — then append a work unit and say so inline.

**Appended work-unit note (for `.planning/missions/<mission_id>/ROADMAP.md`):**

```
- Fix: [root cause summary] — bug found by /debug.
  Root cause: [cause] at [file:line]. Needs: regression test + minimal fix.
```

---

## Related

- **@researcher** — use for gathering context when stuck
- **@test-writer** — use for comprehensive test coverage after the fix
- **/refactor** — if the fix reveals structural issues, refactor separately

**Spine:** find the root cause, then either fix now (`/ship`) or append a work unit to `.planning/missions/<mission_id>/ROADMAP.md` and resume the spine at `/brief N`.
