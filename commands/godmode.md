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

# Claude God-Mode v1.4.1

Check if the user's message contains "statusline" (e.g., `/godmode statusline`). If yes, go to **StatusLine Setup** below. Otherwise, **run the Rules Check first**, then show the **Quick Reference**.

---

## Rules Check (runs automatically)

Before showing the Quick Reference, silently check whether godmode rules are installed:

```bash
ls ~/.claude/rules/godmode-identity.md 2>/dev/null && echo "rules_installed" || echo "rules_missing"
```

**If rules are missing:**

1. Tell the user:
   ```
   God-Mode rules are not installed yet. Rules provide coding standards, quality gates,
   workflow guidance, and agent routing that make the system work at full capacity.

   Without rules, agents and skills still work but won't follow godmode conventions.
   ```

2. Ask: "Install godmode rules to ~/.claude/rules/? [Y/n]"

3. If user confirms (or presses Enter for default Y):
   - Resolve the plugin root: `echo "${CLAUDE_PLUGIN_ROOT}"`
   - If `CLAUDE_PLUGIN_ROOT` is set, copy from there:
     ```bash
     mkdir -p ~/.claude/rules && cp "${CLAUDE_PLUGIN_ROOT}/rules/godmode-"*.md ~/.claude/rules/
     ```
   - If `CLAUDE_PLUGIN_ROOT` is empty (manual install), check if the repo `rules/` dir exists relative to the command file and copy from there
   - Report: "Installed N rule files to ~/.claude/rules/. They'll be active in your next session."

4. If user declines: "Skipping. Run /godmode anytime to install rules later."

**If rules are already installed:** Skip silently, proceed to Quick Reference.

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

| Agent | Model | Memory | Effort | Purpose |
|-------|-------|--------|--------|---------|
| `@writer` | opus | project | default | Implementation (isolated worktree, maxTurns: 100) |
| `@executor` | opus | project | default | Story execution from stories.json (maxTurns: 100) |
| `@architect` | opus | project | high | System design (advisory, read-only enforced) |
| `@security-auditor` | opus | project | high | Security audit (read-only enforced, +WebSearch) |
| `@reviewer` | sonnet | project | high | Code review (read-only enforced) |
| `@test-writer` | sonnet | project | high | Test generation (isolated worktree, maxTurns: 80) |
| `@doc-writer` | sonnet | project | high | Documentation (+Bash) |
| `@researcher` | sonnet | project | default | Codebase & web research (background, read-only enforced) |

### Quality Gates

All tasks must pass before completion:
1. Typecheck (zero errors)
2. Lint (zero errors)
3. All tests pass
4. No hardcoded secrets
5. No regressions
6. Changes match requirements

### Configuration

God-Mode uses rules-based configuration. Rule files live in `~/.claude/rules/godmode-*.md` and are loaded automatically by Claude Code. To customize behavior, edit the relevant rule file directly.

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
