## When to Use What

```
Plan a feature           → /prd → /plan-stories → /execute → /ship
Implement a task         → @writer agent (isolated worktree, general purpose)
Execute pipeline stories → @executor agent (stories.json-aware, used by /execute)
Code review              → @reviewer agent
Find/fix a bug           → /debug skill
Write tests              → @test-writer (existing code) or /tdd (new feature)
Refactor                 → /refactor skill
Understand codebase      → /explore-repo or @researcher
Architecture advice      → @architect agent
Security audit           → @security-auditor agent
Documentation            → @doc-writer agent
Push & create PR         → /ship skill
```

## Agent Routing

When a skill's Agent Routing section says to spawn an agent, always spawn it. Never perform the agent's job inline in the main context.

## Plan Mode

- Make plans extremely concise. Sacrifice grammar for concision.
- End each plan with unresolved questions list, if any.

## Severity Scales

**Severity scales** (different domains, established conventions):
- Code review (@reviewer): CRITICAL / WARNING / NIT
- Security audit (@security-auditor): CRITICAL / HIGH / MEDIUM / LOW
