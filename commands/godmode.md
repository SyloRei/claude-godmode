---
name: godmode
description: Show all available agents, skills, and the feature pipeline workflow. Use "/godmode statusline" to configure the statusline.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - AskUserQuestion
user-invocable: true
---

# Claude God-Mode

Check if the user's message contains "statusline" (e.g., `/godmode statusline`). If yes, go to **StatusLine Setup** below. Otherwise, show the **Quick Reference**.

---

## Quick Reference

### Feature Pipeline

```
/prd → /plan-stories → /execute → /ship
```

### Available Skills

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

### Available Agents

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

### Quality Gates

All tasks must pass before completion:
1. Typecheck (zero errors)
2. Lint (zero errors)
3. All tests pass
4. No hardcoded secrets
5. No regressions
6. Changes match requirements

**Tip:** Run `/godmode statusline` to set up the context-aware status bar.

---

## StatusLine Setup

Configure the God-Mode statusline that shows project name, git branch, model, context usage %, and session cost.

Follow these steps in order:

### Step 1: Check current status

Read `~/.claude/settings.json` and check if a `statusLine` key already exists.

- If `statusLine` **already exists**, tell the user what it's currently set to and ask:
  - "Replace with God-Mode statusline?" → Continue to Step 2
  - "Keep current statusline" → Exit, tell the user their statusline is unchanged

- If `statusLine` **does not exist**, tell the user you'll configure it now and continue to Step 2.

- If `~/.claude/settings.json` **does not exist**, create it in Step 2.

### Step 2: Resolve the statusline script path

Determine the path to the statusline script. Run:

```bash
echo "${CLAUDE_PLUGIN_ROOT}/config/statusline.sh"
```

If `CLAUDE_PLUGIN_ROOT` is empty or unset (manual install), use `~/.claude/hooks/statusline.sh` as the fallback path.

Verify the script exists at the resolved path:

```bash
test -f "<resolved_path>" && echo "found" || echo "not_found"
```

If not found, tell the user the statusline script is missing and exit.

### Step 3: Update settings.json

Read `~/.claude/settings.json` (or start with `{}`). Add or replace the `statusLine` key:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <resolved_path>"
  }
}
```

**Important:** Preserve all existing settings. Only add/update the `statusLine` key. Use the Edit tool on the existing file, or Write if creating from scratch.

### Step 4: Verify

Tell the user:

```
StatusLine configured! Restart Claude Code to see it.

Your statusline shows: project | branch | model | context usage % | cost

To reconfigure later, run /godmode statusline
```
