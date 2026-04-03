```
  ___  _                 _         ___            _       __  __             _
 / __|| | __ _  _  _  __| | ___   / __| ___   __| | ___ |  \/  | ___   __| | ___
| (__ | |/ _` || || |/ _` |/ -_) | (_ |/ _ \ / _` ||___|| |\/| |/ _ \ / _` |/ -_)
 \___||_|\__,_| \_,_|\__,_|\___|  \___|\___/ \__,_|     |_|  |_|\___/ \__,_|\___|
```

**Production-grade engineering workflow for Claude Code. Ship features, not prompts.**

[![GitHub release](https://img.shields.io/github/v/release/SyloRei/claude-godmode?label=version)](https://github.com/SyloRei/claude-godmode/releases)
[![License](https://img.shields.io/github/license/SyloRei/claude-godmode)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blueviolet)](https://github.com/SyloRei/claude-godmode)
[![GitHub stars](https://img.shields.io/github/stars/SyloRei/claude-godmode)](https://github.com/SyloRei/claude-godmode/stargazers)
[![Last commit](https://img.shields.io/github/last-commit/SyloRei/claude-godmode)](https://github.com/SyloRei/claude-godmode/commits)

## Claude God-Mode

Claude God-Mode is a Claude Code plugin that installs rules (focused config files loaded at session start), agents (specialized Claude instances with dedicated prompts, models, and memory), skills (slash-command workflows), and hooks (shell scripts on session events). Rules are individual files in `~/.claude/rules/` rather than a monolithic config, so you can customize, disable, or extend any aspect independently. Your personal `CLAUDE.md` is never modified.

- **End-to-end pipeline** -- go from idea to merged PR with `/prd`, `/plan-stories`, `/execute`, `/ship`
- **Quality gates enforcement** -- typecheck, lint, test, and security checks run automatically before anything ships
- **Isolated worktrees** -- agents write code in separate git worktrees so your main branch stays clean
- **Language-agnostic** -- auto-detects your toolchain (package manager, test runner, linter, formatter, build system)
- **Rules-based config** -- additive rule files in `~/.claude/rules/`, your `CLAUDE.md` is never touched
- **Persistent memory** -- agents remember project patterns, conventions, and gotchas across sessions

---

### Table of Contents

- [Who It's For](#who-its-for)
- [Getting Started](#getting-started)
- [Pipeline](#pipeline)
- [Agents](#agents)
- [Skills](#skills)
- [Standalone Workflows](#standalone-workflows)
- [Hooks](#hooks)
- [Rules-Based Configuration](#rules-based-configuration)
- [Agent Memory](#agent-memory)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

---

## Who It's For

<!-- Placeholder: US-002 will expand this section -->

Claude God-Mode is designed for developers who use Claude Code as their daily coding assistant and want a structured, repeatable workflow for shipping features.

## Getting Started

<!-- Placeholder: US-003 will expand this section -->

Use `/explore-repo` first when working in an unfamiliar codebase -- it detects your stack, maps architecture, and reports patterns before you start changing things.

### Option A: Plugin Marketplace (Recommended)

```bash
# Add the marketplace registry
claude plugin marketplace add SyloRei/claude-marketplace

# Install the plugin
claude plugin install claude-godmode@sylorei-plugins
```

After installing, run `/godmode` in Claude Code. It will detect that rules are not yet installed and offer to set them up automatically. Then run `/godmode statusline` to enable the status bar.

### Option B: Manual Install

```bash
git clone https://github.com/sylorei/claude-godmode.git
cd claude-godmode
./install.sh
```

The install script copies rule files to `~/.claude/rules/`, installs agents, skills, and hooks, and merges `settings.json` additively -- your existing permissions, plugins, and personal `CLAUDE.md` are preserved. If upgrading from v1.x, the installer detects and offers to clean up the old configuration.

### Uninstall

```bash
./uninstall.sh
```

Removes godmode rule files, agents, skills, and hooks. Your personal config is never touched.

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- `jq` (for install script settings merge): `brew install jq`

### Updating

Re-run the install command for your method (plugin: `claude plugin install`, manual: `git pull && ./install.sh`). The installer creates a backup before updating.

## Pipeline

```
/prd  -->  /plan-stories  -->  /execute  -->  /ship
  |              |                 |             |
  PRD       stories.json      @executor      Quality
                               @reviewer    gates --> PR
```

### Example Workflow

```
You:    create a prd for adding user authentication
Claude: [asks 3-5 clarifying questions with lettered options]
You:    1A, 2C, 3B
Claude: [generates PRD, saves to .claude-pipeline/prds/prd-user-auth.md]

You:    /plan-stories
Claude: [converts PRD -> stories.json with 6 stories + quality gates]

You:    /execute
Claude: [picks US-001, spawns @executor, implements, @reviewer validates]
        Story US-001: Add users table
        Story US-002: Create auth middleware
        ...
        All stories complete! Run /ship to push and create PR.

You:    /ship
Claude: [runs quality gates, pushes, creates PR, returns URL]
```

## Agents

| Agent | Model | Memory | Effort | Purpose |
|-------|-------|--------|--------|---------|
| `@writer` | opus | project | default | Implementation in isolated worktree |
| `@executor` | opus | project | default | Story execution from stories.json |
| `@architect` | opus | project | high | System design (advisory, read-only enforced) |
| `@security-auditor` | opus | project | high | Security audit (read-only, enforced) |
| `@reviewer` | sonnet | project | high | Code review (read-only, enforced) |
| `@test-writer` | sonnet | project | high | Test generation in isolated worktree |
| `@doc-writer` | sonnet | project | high | Documentation |
| `@researcher` | sonnet | project | default | Codebase and web research (background) |

**Safety features:**
- Read-only agents (`@architect`, `@reviewer`, `@researcher`, `@security-auditor`) have `disallowedTools: Write, Edit` enforced mechanically
- Write agents (`@executor`, `@writer`, `@test-writer`) have `maxTurns` limits (80-100) to prevent runaway token burn
- `@researcher` runs in background mode by default for non-blocking parallel research
- `@security-auditor` has WebSearch for CVE and vulnerability lookups
- Agents run in parallel -- spawn `@researcher` + `@security-auditor` simultaneously for independent tasks

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

### When to Use What

| Situation | Use |
|-----------|-----|
| Planning a feature | `/prd` -> `/plan-stories` -> `/execute` -> `/ship` |
| Implementing a one-off task | `@writer` (general-purpose, worktree) |
| Implementing pipeline stories | `@executor` (stories.json-aware, worktree) |
| Code review | `@reviewer` |
| Bug fixing | `/debug` |
| Adding tests to existing code | `@test-writer` |
| TDD for new feature | `/tdd` |
| Refactoring | `/refactor` |
| Understanding a codebase | `/explore-repo` or `@researcher` |
| Architecture decisions | `@architect` |
| Security analysis | `@security-auditor` |
| Writing docs | `@doc-writer` |
| Ready to push | `/ship` |

## Standalone Workflows

### Fix a Bug
```
You:    /debug the login page returns 500 after password reset
Claude: [follows 4 phases: reproduce -> hypothesize -> isolate -> fix]
```

### Add Test Coverage
```
You:    @test-writer add tests for the auth middleware
Claude: [analyzes code, writes tests, runs them, reports coverage]
```

### Code Review
```
You:    @reviewer review my staged changes
Claude: [analyzes diff, returns verdict with CRITICAL/WARNING/NIT findings]
```

### Refactor Safely
```
You:    /refactor extract the validation logic from UserService
Claude: [baseline tests -> plan steps -> execute one-at-a-time -> verify]
```

### TDD New Feature
```
You:    /tdd implement email validation
Claude: [RED: write test -> GREEN: minimal code -> REFACTOR -> repeat]
```

### Security Audit
```
You:    @security-auditor audit the API endpoints
Claude: [scans for OWASP Top 10, secrets, dependencies, reports findings]
```

### Understand a Codebase
```
You:    /explore-repo
Claude: [detects stack, maps architecture, reports patterns and commands]
```

### Design Architecture
```
You:    @architect design the notification system
Claude: [analyzes requirements, proposes design, evaluates tradeoffs]
```

## Hooks

| Hook | Trigger | Purpose |
|------|---------|---------|
| **SessionStart** | Conversation begins | Injects project context (language, package manager, test runner, git state) |
| **PostCompact** | After `/compact` | Restores quality gates and available skills after context compaction |
| **StatusLine** | Continuous | Shows context %, model, cost, project, branch (run `/godmode statusline` to enable) |

## Rules-Based Configuration

Claude God-Mode uses individual rule files instead of a monolithic config. Rule files live in `~/.claude/rules/` and are loaded automatically by Claude Code at session start.

### Installing Rules

**Plugin users:** Run `/godmode` after installing the plugin. It auto-detects missing rules and offers to install them with your confirmation. No manual file copying needed.

**Manual install users:** The `./install.sh` script handles rules installation automatically.

> **Why a separate step?** Claude Code's plugin system doesn't yet support a `rules` directory natively ([tracking issue](https://github.com/anthropics/claude-code/issues/14200)). Until that ships, `/godmode` bridges the gap by copying rule files on first run with your explicit consent.

| Rule File | Concern |
|-----------|---------|
| `godmode-identity.md` | Engineering persona and response style |
| `godmode-workflow.md` | Feature pipeline phases and entry points |
| `godmode-coding.md` | Auto-detection, coding standards, security |
| `godmode-quality.md` | Quality gates (typecheck, lint, test, build) |
| `godmode-git.md` | Git discipline and commit conventions |
| `godmode-testing.md` | Testing, debugging, and refactoring protocols |
| `godmode-context.md` | Context management and continuous learning |
| `godmode-routing.md` | Agent/skill routing and severity scales |

### Customizing Rules

- **Edit** any `godmode-*.md` file to change behavior for that concern
- **Remove** a rule file to disable that behavior entirely
- **Add** your own rule files -- any `.md` in `~/.claude/rules/` is loaded automatically
- Your personal `~/.claude/CLAUDE.md` is never touched and always takes precedence

## Agent Memory

Agents have persistent memory that carries learnings across sessions. Each agent's memory scope determines what it remembers and who can see it.

| Scope | Where | Shared? | Use Case |
|-------|-------|---------|----------|
| **user** | `~/.claude/memory/` | Cross-project, single user | Research patterns, architecture knowledge |
| **project** | `.claude/memory/` in repo | Team-shareable via git | Project conventions, quality gates, gotchas |
| **local** | `.claude/local-memory/` | Never shared, gitignored | Security findings, sensitive audit results |

Memory persists between sessions -- agents remember project patterns, conventions, and debugging solutions automatically.

## Customization

After installing, customize to match your workflow:

1. **`~/.claude/rules/godmode-*.md`** -- Edit individual rule files to change specific behaviors (identity, quality gates, routing, etc.)
2. **`~/.claude/settings.json`** -- Add/remove permissions for your toolchain
3. **Remove rules** -- Delete any `godmode-*.md` file to disable that behavior entirely
4. **Add rules** -- Drop your own `.md` files into `~/.claude/rules/` for project-specific conventions

For the full file structure and contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Troubleshooting

<!-- Placeholder: US-005 will expand this section -->

- **Start a new session** after making changes to rule files, agents, or hooks to pick up updates
- **Quality gates are mandatory** -- no skill or agent skips them. If a gate fails, fix the issue rather than bypassing it.
- **Long sessions are safe** -- the PostCompact hook restores critical context after `/compact`

### Context Monitoring

The statusline shows context capacity at all times (enable with `/godmode statusline`):

```
 myapp | main | Opus | ████░░░░░░ 42% | $0.45
```

The bar turns yellow at 60% and red at 80%. Compact proactively at ~70% with `/compact "preserve X"`. Use subagents (`@researcher`) for heavy research to keep main context clean.

## FAQ

### Does this work with Sonnet/Haiku?

Agents specify their target models in their configuration, but you can edit any agent file to use a different model. Four agents use Sonnet (`@reviewer`, `@test-writer`, `@doc-writer`, `@researcher`) and four use Opus (`@writer`, `@executor`, `@architect`, `@security-auditor`).

### Will this overwrite my config?

No. Claude God-Mode uses a rules-based approach -- it installs individual rule files into `~/.claude/rules/` which Claude Code loads alongside your existing config. Your `~/.claude/CLAUDE.md` is never read, modified, or replaced. Settings are merged additively, preserving your existing permissions and plugins. You can disable any godmode behavior by removing the corresponding rule file.

### Can I use individual parts?

Yes. You can cherry-pick individual agents, skills, hooks, or rule files. Copy just the files you want into your `~/.claude/` directory. Each component is self-contained.

### What languages does this support?

Claude God-Mode is language-agnostic. The SessionStart hook auto-detects your project's toolchain (package manager, test runner, linter, formatter, build system) and injects that context into every conversation.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on adding agents, skills, hooks, rules, and submitting pull requests.

## License

[MIT](LICENSE)
