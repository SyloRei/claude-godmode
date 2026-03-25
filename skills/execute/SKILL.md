---
name: execute
description: "Execute stories from stories.json using agents. Orchestrates @executor and @reviewer to implement, validate, and commit each story. Supports parallel execution when dependsOn fields are present. Triggers on: execute stories, run stories, implement stories, start execution, run pipeline."
user-invocable: true
---

# Story Executor

Orchestrates the implementation of stories from stories.json using the agent pipeline. Supports parallel execution of independent stories when dependency information is available.

---

## The Job

For each story (highest priority, `passes: false`):
1. Display story details
2. Spawn @executor agent to implement (stories.json-aware, tracks progress)
3. Spawn @reviewer agent to validate
3.5. If security-sensitive: offer @security-auditor (optional)
4. Run quality gates
5. Commit, update stories.json
6. Continue to next story

**Parallel mode** (when `dependsOn` fields present): group independent stories into batches, spawn multiple @executor agents concurrently, merge results, then review sequentially.

---

## Process

### Step 1: Load Stories

- Read `.claude-pipeline/stories.json`
- Find all stories where `passes: false`
- If all stories pass: report completion and suggest `/ship`

**Dependency-aware batching** (when `dependsOn` fields are present in stories):
- Resolve **transitive** dependencies: if A depends on B, and B depends on C, then A transitively depends on C
- A story is eligible for the current batch when ALL its transitive dependencies have `passes: true`
- Group eligible stories into a batch, capped at `maxParallel` from stories.json (default: 3)
- If `dependsOn` is absent from all stories, fall back to sequential execution (one story at a time, highest priority first)

**Sequential fallback** (no `dependsOn` fields):
- Find next story: highest priority where `passes: false`
- Display story ID, title, description, and acceptance criteria
- Proceed to Step 2

### Step 1.5: Display Batch Plan and Confirm

Before spawning any agents, display the computed batch plan:
```
Batch plan:
  Batch 1: US-001, US-002 (parallel)
  Batch 2: US-003 (depends on US-001)
  Batch 3: US-004, US-005 (parallel, depends on US-003)
```

Ask user to confirm before proceeding. If user declines, offer to run sequentially instead.

### Step 2: Implement with @executor

**Sequential mode** (no `dependsOn` or single-story batch):

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

**Parallel mode** (batch with multiple stories):

Spawn multiple `@executor` agents concurrently (parallel Agent tool calls), each with:
```
Implement story [ID]: [title] from stories.json

parallel: true
branch: {branchName}-{storyId}

The @executor agent will:
- Read .claude-pipeline/stories.json for full context and quality gate commands
- Read .claude-pipeline/progress.txt for codebase patterns from previous stories
- Implement the story following existing patterns
- Write tests for new behavior
- Run ALL quality gates before returning
- Work on temporary branch: {branchName}-{storyId}
- Do NOT update stories.json or progress.txt (orchestrator owns shared state)
- Do NOT return until all gates pass
```

Each parallel executor works on a temporary branch `{branchName}-{storyId}` and does NOT update stories.json or progress.txt.

### Step 2.5: Post-Batch Merge

After all executors in a batch complete:

1. **Merge temp branches** into the feature branch sequentially (one at a time)
2. If **merge conflict** occurs: report conflict details to user, fall back to sequential re-execution for the conflicting story
3. **Post-merge smoke test**: run ALL quality gates on the merged result
4. If smoke test fails: diagnose which story's changes caused the failure, report to user

Only stories that merge cleanly and pass the smoke test proceed to review.

### Step 3: Validate with @reviewer

**Sequential mode**: Spawn `@reviewer` on the changes as before.

**Parallel mode**: After merge + smoke test, run `@reviewer` sequentially on each story's changes:

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

Review failure for one story in a batch does NOT block review of other independent stories in the same batch.

### Step 3.5: Security Validation (optional)

After reviewer validation, check if the story touches **security-sensitive areas**:

- Authentication (login, signup, password reset, OAuth, SSO)
- Authorization (role checks, permissions, access control, RBAC)
- Session management (cookies, tokens, JWT, session storage)
- User input handling (form validation, sanitization, parsing untrusted data)
- Database queries (SQL, ORM queries, query building, migrations with data)
- File system access (uploads, downloads, path construction, temp files)
- API endpoints (new routes, middleware, rate limiting, CORS)
- Cryptography (hashing, encryption, key generation, certificate handling)
- Secrets handling (env vars, config files, API keys, credentials)

**Detection:** Scan the story's description, acceptance criteria, and changed file paths/contents for keywords matching these areas.

**When detected**, prompt the user:
```
This story touches [detected area(s)]. Run @security-auditor? (recommended)
```

**If user confirms**, spawn `@security-auditor` on the story's changes:
```
Audit the changes for story [ID]: [title]

Focus areas: [detected security-sensitive areas]

Audit dimensions: injection, auth/authz, data exposure, dependencies, configuration.
Report findings using severity scale: CRITICAL / HIGH / MEDIUM / LOW.
```

**Handling results:**

| Severity | Action |
|----------|--------|
| **CRITICAL** | Blocks the story — same as @reviewer CRITICAL. Report to user, offer fix with @writer or manual fix. Loop back to Step 2 if using @writer. |
| **HIGH** | Report to user. Recommend fixing before proceeding but do not block. |
| **MEDIUM / LOW** | Report to user as informational. Proceed to Step 4. |

**If user declines** the security audit, proceed directly to Step 4. The audit is recommended but never forced.

**Parallel mode:** Security validation runs sequentially per story, after reviewer validation for that story.

### Step 4: Quality Gates

Run canonical quality gates (from stories.json qualityGates):
1. Typecheck
2. Lint
3. Test
4. Build (if configured)

**All must pass.** If any fails: diagnose with /debug protocol, fix, re-run.

### Step 5: Commit & Update

**Sequential mode** (unchanged):
- Commit all changes: `feat: [Story ID] - [Story Title]`
- Update `.claude-pipeline/stories.json`: set `passes: true` for completed story
- Append progress to `.claude-pipeline/progress.txt`

**Parallel mode** (orchestrator handles shared state):
- For each successfully merged and reviewed story in the batch:
  - Commit changes: `feat: [Story ID] - [Story Title]`
  - Update `.claude-pipeline/stories.json`: set `passes: true`
  - Append progress entry to `.claude-pipeline/progress.txt` sequentially
- Failed stories remain `passes: false` and retry in the next batch

Progress entry format:
```
## [Date] - [Story ID]: [Title]
- What was implemented
- Files changed
- Learnings for future iterations
---
```

### Step 6: Continue

- Display progress: "X of Y stories complete"
- If parallel: display batch summary before continuing
- Ask user: continue with next batch/story?
- If yes: loop to Step 1
- If all done: suggest `/ship`

---

## Failure Recovery

Classify each failure by type and route to the appropriate skill or agent. **All routing is suggested to the user with an explicit prompt — never automatic.** After any routed skill/agent completes, suggest: `Run /execute to continue`.

### Quality Gate Failures

| Failure Type | Detection | Routing | Prompt to User |
|---|---|---|---|
| Test failure | Test gate fails (non-zero exit, assertion errors) | Suggest `/debug` | `Tests failing. Run /debug to diagnose, or send back to @executor?` |
| Type error | Typecheck gate fails (type mismatch, missing types) | Retry with `@executor` (include full error output) | `Type errors found. Send back to @executor with error details?` |
| Lint failure | Lint gate fails (formatting, style violations) | Attempt auto-fix (run lint with `--fix` flag if available), then re-run gates | `Lint errors found. Attempt auto-fix and re-run gates?` |

### @reviewer Failures

| Failure Type | Detection | Routing | Prompt to User |
|---|---|---|---|
| CRITICAL on structure | @reviewer CRITICAL finding about code structure, architecture, or design | Suggest `/refactor` | `Reviewer found structural issues. Run /refactor to address, or fix manually?` |
| WARNING on test coverage | @reviewer WARNING about missing tests or insufficient coverage | Suggest `@test-writer` | `Reviewer flagged test coverage gaps. Spawn @test-writer to add tests?` |
| CRITICAL on security | @reviewer CRITICAL finding about security vulnerability | Suggest `@security-auditor` | `Reviewer found security concern. Run @security-auditor for full audit?` |
| Other CRITICAL | @reviewer CRITICAL not matching above categories | Report to user, offer re-implementation with `@executor` | `Reviewer found critical issues. Send back to @executor, or fix manually?` |

### @security-auditor Failures

| Failure Type | Detection | Routing | Prompt to User |
|---|---|---|---|
| CRITICAL finding | @security-auditor reports CRITICAL severity vulnerability | Blocks story — same as @reviewer CRITICAL. Offer fix with `@writer` or manual fix. | `Security audit found CRITICAL vulnerability: [finding]. Fix with @writer, or fix manually?` |
| HIGH finding | @security-auditor reports HIGH severity vulnerability | Report to user, recommend fixing before proceeding | `Security audit found HIGH severity issue: [finding]. Recommended to fix before proceeding. Continue anyway?` |

### Parallel-Mode Failures

| Failure Type | Detection | Routing | Prompt to User |
|---|---|---|---|
| Merge conflict | Git merge fails during post-batch merge (Step 2.5) | Fall back to sequential re-execution for the conflicting story | `Merge conflict on [story ID]. Re-run this story sequentially?` |
| Partial batch failure | One or more executors in a batch fail while others succeed | Merge passing stories; failed stories remain `passes: false` and retry in next batch | `[N] stories succeeded, [M] failed. Merge passing stories and retry failed in next batch?` |
| Post-merge smoke test failure | Quality gates fail on merged result (Step 2.5) | Identify causal story, revert its merge, retry sequentially | `Post-merge smoke test failed. Identified [story ID] as cause. Revert and retry sequentially?` |

### Other Failures

| Failure Type | Detection | Routing | Prompt to User |
|---|---|---|---|
| Story too large | @executor cannot complete within session limits | Split story in stories.json, re-execute | `Story too large for one session. Split into smaller stories?` |

---

## Output Format

After each story (sequential):
```
Story [ID]: [Title]
  Writer:   Implemented (N files changed)
  Reviewer: Approved (0 critical, N warnings, N nits)
  Security: Passed (0 critical, 0 high) | Skipped | Not applicable
  Gates:    typecheck | lint | test | build
  Commit:   [hash] feat: [ID] - [Title]

Progress: X/Y stories complete
```

After each batch (parallel):
```
Batch N: [ID1], [ID2] (parallel)
  [ID1]: Implemented + Merged + Reviewed
  [ID2]: Implemented + Merged + Reviewed
  Gates (post-merge): typecheck | lint | test | build

Progress: X/Y stories complete
```

After all stories:
```
All stories complete!
Next: run /ship to push and create PR
```

---

## Agent Routing

| Phase | Agent | Purpose |
|-------|-------|---------|
| Step 2 (Implement) | MUST spawn @executor for each story | Implement story in isolated worktree — stories.json-aware, tracks progress |
| Step 2 (Parallel) | MUST spawn multiple @executor agents concurrently | Each works on a temporary branch for independent stories in the batch |
| Step 3 (Validate) | MUST spawn @reviewer on changes for each story | Validate against acceptance criteria — correctness, security, patterns |
| Step 3.5 (Security) | Spawn @security-auditor when story touches security-sensitive areas | Optional security audit — user confirms before spawning. CRITICAL findings block story. |
| Gate failure | Spawn @writer for complex fixes | Fix quality gate failures that need multi-file changes |

**Rule:** Never perform implementation or review inline — always spawn the designated agent.

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
| **no-pipeline** | Cannot execute — `stories.json` is required. Suggest `/prd` then `/plan-stories` to create one. |
| **prd-only** | Cannot execute — stories not yet planned. Suggest `/plan-stories` to convert the PRD. |
| **planning** | Ready to begin execution. All stories are pending. |
| **executing** | Resume execution. Read `progress.txt` top-level sections (Codebase Patterns, Anti-Patterns, Architecture Decisions) to pass accumulated project knowledge to @executor agents. Read `.claude-pipeline/explorations/` for codebase understanding when available. Skip stories that already pass. |
| **complete** | All stories pass. Report completion and suggest `/ship`. |

---

## Backward Compatibility

All parallel execution behavior is **conditional on `dependsOn` presence**:
- If no story in stories.json has a `dependsOn` field: sequential execution exactly as before
- If `maxParallel` is missing: default to 3
- Existing stories.json files without dependency fields work without modification
