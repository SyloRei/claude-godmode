---
name: execute
description: "Execute stories from stories.json using agents. Orchestrates @executor and @reviewer to implement, validate, and commit each story. Triggers on: execute stories, run stories, implement stories, start execution, run pipeline."
user-invocable: true
---

# Story Executor

Orchestrates the implementation of stories from stories.json using the agent pipeline.

---

## The Job

For each story (highest priority, `passes: false`):
1. Display story details
2. Spawn @executor agent to implement (stories.json-aware, tracks progress)
3. Spawn @reviewer agent to validate
4. Run quality gates
5. Commit, update stories.json
6. Continue to next story

---

## Process

### Step 1: Load Stories

- Read `.claude-pipeline/stories.json`
- Find next story: highest priority where `passes: false`
- If all stories pass: report completion and suggest `/ship`
- Display story ID, title, description, and acceptance criteria

### Step 2: Implement with @executor

Spawn `@executor` agent with context:
```
Implement story [ID]: [title] from stories.json

The @executor agent will:
- Read .claude-pipeline/stories.json for full context and quality gate commands
- Read .claude-pipeline/progress.txt for codebase patterns from previous stories
- Implement the story following existing patterns
- Write tests for new behavior
- Run ALL quality gates before returning
- Update .claude-pipeline/stories.json and .claude-pipeline/progress.txt
- Do NOT return until all gates pass
```

@executor works in a worktree and returns changes. Unlike @writer (general-purpose), @executor is stories.json-aware and manages progress tracking.

### Step 3: Validate with @reviewer

Spawn `@reviewer` agent on the changes:
```
Review the changes for story [ID]: [title]

Check against acceptance criteria:
- [criteria list]

Review dimensions: correctness, edge cases, security, performance, readability, testing, patterns.
```

**If @reviewer finds CRITICAL issues:**
- Report issues to user
- Ask: fix with @writer or fix manually?
- Loop back to Step 2 if using @writer

### Step 4: Quality Gates

Run canonical quality gates (from stories.json qualityGates):
1. Typecheck
2. Lint
3. Test
4. Build (if configured)

**All must pass.** If any fails: diagnose with /debug protocol, fix, re-run.

### Step 5: Commit & Update

- Commit all changes: `feat: [Story ID] - [Story Title]`
- Update `.claude-pipeline/stories.json`: set `passes: true` for completed story
- Append progress to `.claude-pipeline/progress.txt`:
```
## [Date] - [Story ID]: [Title]
- What was implemented
- Files changed
- Learnings for future iterations
---
```

### Step 6: Continue

- Display progress: "X of Y stories complete"
- Ask user: continue with next story?
- If yes: loop to Step 1
- If all done: suggest `/ship`

---

## Failure Recovery

| Failure | Action |
|---------|--------|
| @executor returns with failing gates | Send back with specific errors |
| @reviewer finds CRITICAL | Report to user, offer re-implementation |
| Quality gate fails after merge | Use /debug to diagnose, fix, re-run |
| Story too large for one session | Split story in .claude-pipeline/stories.json, re-execute |

---

## Output Format

After each story:
```
Story [ID]: [Title]
  Writer:   ✓ Implemented (N files changed)
  Reviewer: ✓ Approved (0 critical, N warnings, N nits)
  Gates:    ✓ typecheck | ✓ lint | ✓ test | ✓ build
  Commit:   [hash] feat: [ID] - [Title]

Progress: X/Y stories complete
```

After all stories:
```
All stories complete!
Next: run /ship to push and create PR
```
