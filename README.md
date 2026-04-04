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
- [Why Claude God-Mode?](#why-claude-god-mode)
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

Claude God-Mode is a Claude Code plugin for engineers who want a repeatable Claude Code workflow instead of ad-hoc prompting. Whether you're a solo developer or part of an engineering team, it brings code quality automation and AI engineering best practices to every session.

**Solo developer shipping a feature.** You have an idea, but turning it into a merged PR means juggling prompts, remembering to run tests, and hoping nothing slipped through. With God-Mode, you run `/prd` to define the feature, `/plan-stories` to break it into tasks, `/execute` to implement with automated review, and `/ship` to push a clean PR -- all with quality gates enforced at every step.

**Team standardizing their AI workflow.** Your team uses Claude Code, but everyone prompts differently and quality varies. God-Mode's rules-based config gives every team member the same coding standards, testing protocols, and review process. Rules live in `~/.claude/rules/` as individual files, so teams can share a baseline while individuals customize their setup.

**Contributor extending the plugin.** You want to add a new agent, skill, or rule. Each component is a self-contained markdown file with a clear contract. Drop a new agent into `agents/`, a new skill into `skills/`, or a new rule into `rules/` -- the plugin picks it up automatically.

## Why Claude God-Mode?

Claude Code is powerful out of the box. God-Mode adds **structure** -- the difference between a capable tool and a reliable workflow.

Without it, you write one-off prompts, manually enforce quality, and lose context between sessions. With it, you get an end-to-end pipeline (`/prd` through `/ship`), 8 specialized agents that handle implementation, review, testing, security, and architecture, and persistent memory that carries project knowledge across sessions. Quality gates (typecheck, lint, test, build) run on every change automatically -- not when you remember to ask.

The value isn't replacing Claude Code; it's removing the manual overhead that sits between "Claude can do this" and "this is actually production-ready." Rules are additive, components are modular, and your existing config is never touched.

## Getting Started

Check the [Prerequisites](#prerequisites) first, then follow these three steps to ship your first feature.

### Step 1: Install

#### Option A: Plugin Marketplace (Recommended)

```bash
claude plugin marketplace add SyloRei/claude-marketplace
claude plugin install claude-godmode@sylorei-plugins
```

#### Option B: Manual Install

```bash
git clone https://github.com/sylorei/claude-godmode.git
cd claude-godmode
./install.sh
```

The install script copies rules, agents, skills, and hooks to `~/.claude/` and merges `settings.json` additively -- your existing config is preserved.

### Step 2: First Run

Start a Claude Code session and set up rules:

```
You:    /godmode
Claude: Detected 8 rule files not yet installed. Install now? [Y/n]
You:    Y
Claude: Installed 8 rules, 8 agents, 8 skills, 3 hooks. God-Mode is active.

You:    /godmode statusline
Claude: Statusline enabled. Context %, model, and cost now visible in status bar.
```

> **Tip:** Run `/explore-repo` in unfamiliar codebases -- it maps your stack before you start changing things.

### Step 3: First Feature

Ship a feature end-to-end with four steps:

```
You:    create a prd for adding full-text search to the API
Claude: [asks clarifying questions, generates PRD]

You:    /plan-stories
Claude: Created stories.json with quality gates.

You:    /execute
Claude: [spawns @executor per story, @reviewer validates each]
        All stories complete! Run /ship to push and create PR.

You:    /ship
Claude: Quality gates passed. PR #42 created: github.com/you/repo/pull/42
```

See [Pipeline](#pipeline) for the full reference.

### Uninstall

```bash
./uninstall.sh
```

Removes godmode rule files, agents, skills, and hooks. Your personal config is never touched.

### Requirements

See [Prerequisites](#prerequisites) for the full checklist.

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

### Prerequisites

Before installing, make sure you have:

- [ ] **Claude Code CLI** -- [install guide](https://docs.anthropic.com/en/docs/claude-code). Verify: `claude --version`
- [ ] **git** >= 2.20 -- required for worktree agents. Verify: `git --version`
- [ ] **jq** -- used by install script to merge `settings.json`. Verify: `jq --version`
- [ ] **macOS or Linux** -- Windows is not supported (Claude Code limitation)

### Common Issues

**`jq: command not found` during install**
Cause: `jq` is not installed. Fix:
```bash
brew install jq        # macOS
sudo apt install jq    # Debian/Ubuntu
```

**`claude: command not found`**
Cause: Claude Code CLI is not installed or not in PATH. Fix:
```bash
npm install -g @anthropic-ai/claude-code
```

**Rules not loading after install**
Cause: Rule files are not in `~/.claude/rules/`. Fix:
```bash
ls ~/.claude/rules/godmode-*.md   # should list 8 files
./install.sh                      # re-run if missing
```

**Permission denied running install.sh**
Cause: Script not executable. Fix:
```bash
chmod +x install.sh && ./install.sh
```

**Plugin not appearing after marketplace install**
Cause: Rules need a one-time setup step. Fix: run `/godmode` inside Claude Code -- it detects missing rules and installs them with your confirmation.

### General Tips

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
