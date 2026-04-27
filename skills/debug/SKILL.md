---
name: debug
description: "Structured debugging protocol: reproduce → isolate → fix → verify. Free-form Bash for investigation; Read/Grep/Glob for source navigation."
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# Structured Debugging

## Connects to

- **Upstream:** (entry point — cross-cutting helper)
- **Downstream:** freeform — calls into source files; no agent spawned
- **Reads from:** working tree, test output, error logs
- **Writes to:** working tree (when fix is applied)

## Auto Mode check

Scan for "Auto Mode Active" (case-insensitive). When detected: skip
confirmation prompts on hypothesis testing; pick the most plausible failure
cause first; surface assumptions inline. See `rules/godmode-skills.md` § Auto Mode Detection.

---

Find and fix bugs systematically using evidence, never guessing. Implements the debugging protocol defined in CLAUDE.md.

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
| Post-fix | MUST spawn @reviewer for security-sensitive fixes | Validate that fixes touching auth, input handling, or data access are safe |

**Rule:** Never explore the codebase inline when @researcher can do it in parallel.

---

## Related

- **@researcher** — use for gathering context when stuck
- **@test-writer** — use for comprehensive test coverage after the fix
- **/refactor** — if the fix reveals structural issues, refactor separately
