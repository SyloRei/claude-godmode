---
name: ship
description: "Pre-push verification and PR creation. Use when: ship it, ready to ship, create pr, push this, prepare for merge."
user-invocable: true
---

# Ship

Verify all quality gates, clean up commits, push, and create PR.

---

## The Job

1. Run canonical quality gates
2. Verify requirements match
3. Security scan
4. Git cleanup
5. Push and create PR

---

## Step 1: Quality Gates (from CLAUDE.md — canonical list)

Run ALL gates. Auto-detect commands from project config:

| Gate | Example Commands |
|------|-----------------|
| Typecheck | `tsc --noEmit`, `mypy`, `cargo check`, `go vet` |
| Lint | `eslint`, `ruff`, `cargo clippy`, `golangci-lint` |
| Tests | `vitest`, `pytest`, `cargo test`, `go test` |
| Build | `tsup`, `cargo build`, `go build` |

```
Quality Gates:
  [✓/✗] Typecheck
  [✓/✗] Lint
  [✓/✗] Tests
  [✓/✗] Build
```

**If ANY gate fails:**
- Use `/debug` to diagnose test/typecheck failures
- Use `@writer` agent for complex fixes
- For lint: run auto-fix if available, otherwise fix manually
- **Do NOT skip. Do NOT push with failures.**

---

## Step 2: Requirements Verification

- Review the original task/issue/PRD
- Confirm all acceptance criteria are met
- Check: does the diff match what was requested?

```
Requirements:
  [✓/✗] Changes match original request
  [✓/✗] No unrelated changes included
```

---

## Step 3: Security Scan

Scan the diff for:
- Hardcoded secrets, API keys, tokens, passwords
- .env files or credentials in staged changes
- Sensitive data in logs or error messages

If found: STOP. Remove them. Never push secrets.

---

## Step 4: Git Cleanup

- Check for uncommitted changes — commit or stash
- Ensure branch is up to date with base branch
- Review commit history — atomic and well-messaged?
- If messy: suggest rebase (ask user first)

---

## Step 5: Push & PR

```bash
git push -u origin <branch>
```

Create PR:
```
gh pr create --title "<concise, <70 chars>" --body "$(cat <<'EOF'
## Summary
- What changed and why (2-3 bullets)

## Changes
- Specific changes list

## Test Plan
- How to verify
- Tests added/modified
EOF
)"
```

Return PR URL.

---

## Agent Routing

| Phase | Agent | Purpose |
|-------|-------|---------|
| Step 1 (Gate failure) | Spawn @writer for complex fixes | Fix typecheck, lint, or test failures that need multi-file changes |
| Step 2 (Requirements) | MUST spawn @reviewer for deep code review | Validate all changes match acceptance criteria before pushing |
| Step 3 (Security) | MUST spawn @security-auditor for comprehensive audit | Scan for vulnerabilities, secrets, injection risks before shipping |

**Rule:** Never perform code review or security audit inline — always spawn the designated agent.

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
| **no-pipeline** | Operate in standalone mode. Ship changes without pipeline context. Zero regression from pre-pipeline behavior. |
| **prd-only** | Standalone mode — no stories to verify against. Ship normally. |
| **planning** | Warn user: stories are planned but none are implemented. Confirm they want to ship without executing the pipeline. |
| **executing** | Read `progress.txt` for context on completed stories. Use `stories.json` to verify all stories pass before shipping. If incomplete stories remain, warn user and confirm intent. Use quality gate commands from `stories.json.qualityGates` instead of re-detecting. |
| **complete** | All stories pass. Read `progress.txt` for PR description context. Use `stories.json` for quality gate commands and story summaries to populate the PR body. Reference the PRD via `prdSource` for requirements verification (Step 2). |

---

## Related

- **/debug** — when quality gates fail
- **@reviewer** — for deep code review before shipping
- **@security-auditor** — for comprehensive security audit before shipping
- **/execute** — if shipping stories from the pipeline
