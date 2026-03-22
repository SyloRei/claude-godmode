---
name: godmode
description: Show all available agents, skills, and the feature pipeline workflow
user-invocable: true
---

# Claude God-Mode — Quick Reference

## Feature Pipeline

```
/prd → /plan-stories → /execute → /ship
```

## Available Skills

| Skill | Trigger | Purpose |
|-------|---------|---------|
| `/prd` | Plan a feature | Generate Product Requirements Document |
| `/plan-stories` | Break down PRD | Convert PRD to executable stories.json |
| `/execute` | Implement stories | Run executor + reviewer agents on stories |
| `/ship` | Push & create PR | Quality gates, git cleanup, PR creation |
| `/debug` | Fix a bug | Structured debugging protocol |
| `/tdd` | Test-first dev | Red-green-refactor cycle |
| `/refactor` | Clean up code | Safe refactoring with test verification |
| `/explore-repo` | Understand codebase | Deep codebase exploration |

## Available Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| `@writer` | opus | Implementation (isolated worktree) |
| `@executor` | opus | Story execution from stories.json |
| `@reviewer` | opus | Code review (read-only) |
| `@researcher` | sonnet | Codebase & web research |
| `@architect` | opus | System design (advisory) |
| `@security-auditor` | opus | Security audit (read-only) |
| `@test-writer` | opus | Test generation (isolated worktree) |
| `@doc-writer` | sonnet | Documentation |

## Quality Gates

All tasks must pass before completion:
1. Typecheck (zero errors)
2. Lint (zero errors)
3. All tests pass
4. No hardcoded secrets
5. No regressions
6. Changes match requirements

## StatusLine Setup (Manual)

Add to `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/hooks/statusline.sh"
  }
}
```

Copy `config/statusline.sh` to `~/.claude/hooks/statusline.sh` if not already present.
