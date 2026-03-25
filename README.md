![Version](https://img.shields.io/badge/version-1.3.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blueviolet)

# Claude God-Mode

**Production-grade engineering workflow for Claude Code. Ship features, not prompts.**

- **End-to-end pipeline** -- go from idea to merged PR with `/prd`, `/plan-stories`, `/execute`, `/ship`
- **Quality gates enforcement** -- typecheck, lint, test, and security checks run automatically before anything ships
- **Isolated worktrees** -- agents write code in separate git worktrees so your main branch stays clean
- **Language-agnostic** -- auto-detects your toolchain (package manager, test runner, linter, formatter, build system)

## Pipeline

```
/prd  -->  /plan-stories  -->  /execute  -->  /ship
  |              |                 |             |
  PRD       stories.json      @executor      Quality
                               @reviewer    gates --> PR
```

## Quick Start

### Option A: Plugin Marketplace (Recommended)

```bash
# Add the marketplace registry
claude plugin marketplace add SyloRei/claude-marketplace

# Install the plugin
claude plugin install claude-godmode@sylorei-plugins
```

After installing, enable the statusline by running `/godmode statusline` in Claude Code.

### Option B: Manual Install

```bash
git clone https://github.com/sylorei/claude-godmode.git
cd claude-godmode
./install.sh
```

The install script backs up your existing `~/.claude/` config (timestamped), copies agents, skills, hooks, CLAUDE.md, and INSTRUCTIONS.md, and merges settings.json additively -- your existing permissions and plugins are preserved.

### Uninstall

```bash
./uninstall.sh
```

Restores from the most recent backup created during install.

## Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| `@writer` | opus | Implementation in isolated worktree |
| `@executor` | opus | Story execution from stories.json |
| `@reviewer` | opus | Code review (read-only) |
| `@researcher` | sonnet | Codebase and web research |
| `@architect` | opus | System design (advisory) |
| `@security-auditor` | opus | Security audit (read-only) |
| `@test-writer` | opus | Test generation in isolated worktree |
| `@doc-writer` | sonnet | Documentation |

## Skills

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

## Hooks

| Hook | Trigger | Purpose |
|------|---------|---------|
| **SessionStart** | Conversation begins | Injects project context (language, package manager, test runner, git state) |
| **PostCompact** | After `/compact` | Restores quality gates and available skills after context compaction |
| **StatusLine** | Continuous | Shows context %, model, cost, project, branch (run `/godmode statusline` to enable) |

## How It Works

Claude God-Mode is a Claude Code plugin defined by `plugin.json`. It installs **agents** (specialized Claude instances with dedicated system prompts and model assignments), **skills** (slash-command workflows composed of multiple steps), and **hooks** (shell scripts that fire on session events). The global `CLAUDE.md` provides coding standards, quality gates, and routing logic that all agents inherit. `INSTRUCTIONS.md` supplies detailed behavioral conventions. Together, these files transform Claude Code from a general assistant into a structured engineering team.

## Customization

After installing, customize to match your workflow:

1. **`~/.claude/CLAUDE.md`** -- Edit the `Identity` and `Response Style` sections to match your preferences
2. **`~/.claude/INSTRUCTIONS.md`** -- Adjust agent behaviors and conventions
3. **`~/.claude/settings.json`** -- Add/remove permissions for your toolchain

## Updating

### Plugin

```bash
claude plugin marketplace add SyloRei/claude-marketplace
claude plugin install claude-godmode@sylorei-plugins
```

### Manual

```bash
cd claude-godmode
git pull
./install.sh   # creates a new backup before overwriting
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- `jq` (for install script settings merge): `brew install jq`

## FAQ

### Does this work with Sonnet/Haiku?

Agents specify their target models in their configuration, but you can edit any agent file to use a different model. Research-oriented agents (`@researcher`, `@doc-writer`) already default to Sonnet.

### Will this overwrite my config?

No. The install script creates a timestamped backup of your `~/.claude/` directory before making any changes, and merges `settings.json` additively -- your existing permissions and plugins are preserved.

### Can I use individual parts?

Yes. You can cherry-pick individual agents, skills, or hooks. Copy just the files you want into your `~/.claude/` directory. Each component is self-contained.

### What languages does this support?

Claude God-Mode is language-agnostic. The SessionStart hook auto-detects your project's toolchain (package manager, test runner, linter, formatter, build system) and injects that context into every conversation.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on adding agents, skills, hooks, and submitting pull requests.

## License

[MIT](LICENSE)
