# Claude God-Mode

Production-grade engineering workflow for Claude Code. 8 specialized agents, 8 skills, hooks, quality gates, and a full feature pipeline.

## What's Inside

### Feature Pipeline

```
/prd → /plan-stories → /execute → /ship
```

### Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| `@writer` | opus | Implementation in isolated worktree |
| `@executor` | opus | Story execution from stories.json |
| `@reviewer` | opus | Code review (read-only) |
| `@researcher` | sonnet | Codebase & web research |
| `@architect` | opus | System design (advisory) |
| `@security-auditor` | opus | Security audit (read-only) |
| `@test-writer` | opus | Test generation in isolated worktree |
| `@doc-writer` | sonnet | Documentation |

### Skills

| Skill | Purpose |
|-------|---------|
| `/prd` | Generate Product Requirements Document |
| `/plan-stories` | Convert PRD to executable stories.json |
| `/execute` | Run executor + reviewer agents on stories |
| `/ship` | Quality gates, git cleanup, PR creation |
| `/debug` | Structured debugging protocol |
| `/tdd` | Test-driven development (red-green-refactor) |
| `/refactor` | Safe refactoring with test verification |
| `/explore-repo` | Deep codebase exploration |

### Hooks

- **SessionStart** — Injects project context (language, package manager, test runner, git state)
- **PostCompact** — Restores quality gates and available skills after context compaction
- **StatusLine** — Shows context %, model, cost, project, branch

### Config

- **CLAUDE.md** — Global instructions: coding standards, quality gates, workflow phases, agent routing
- **INSTRUCTIONS.md** — Detailed behavioral instructions and conventions

## Installation

### Option A: Plugin (Recommended)

```bash
# From local clone
claude /plugin install --source ./path/to/claude-godmode

# From GitHub
claude /plugin install --source url --url https://github.com/youruser/claude-godmode.git
```

### Option B: Install Script

```bash
git clone https://github.com/youruser/claude-godmode.git
cd claude-godmode
./install.sh
```

The install script:
- Backs up your existing `~/.claude/` config (timestamped)
- Copies agents, skills, and hooks
- Copies CLAUDE.md and INSTRUCTIONS.md
- Merges settings.json (additive — your existing permissions and plugins are preserved)

### Uninstall

```bash
./uninstall.sh
```

Restores from the most recent backup created during install.

## Customization

After installing, you'll want to customize:

1. **`~/.claude/CLAUDE.md`** — Edit the `Identity` and `Response Style` sections to match your preferences
2. **`~/.claude/INSTRUCTIONS.md`** — Adjust agent behaviors and conventions
3. **`~/.claude/settings.json`** — Add/remove permissions for your toolchain

## Updating

### Plugin path

```bash
claude /plugin update claude-godmode
```

### Install script path

```bash
cd claude-godmode
git pull
./install.sh   # creates a new backup before overwriting
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- `jq` (for install script settings merge): `brew install jq`

## License

MIT
