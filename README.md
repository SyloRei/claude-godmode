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

Claude God-Mode is a Claude Code plugin that ships rules (focused config files injected at session start), agents (specialized Claude instances with dedicated prompts, models, and memory), skills (slash-command workflows), and hooks (shell scripts on session events). Rules are individual concern-scoped files injected automatically by the SessionStart hook rather than a monolithic config, so you can read or extend any aspect independently. Your personal `CLAUDE.md` is never modified.

- **Single clear workflow** -- go from idea to merged PR with `/mission → /brief N → /plan N → /build N → /verify N → /ship`
- **Quality gates enforcement** -- typecheck, lint, test, and security checks run automatically before anything ships
- **Isolated worktrees** -- agents write code in separate git worktrees so your main branch stays clean
- **Language-agnostic** -- auto-detects your toolchain (package manager, test runner, linter, formatter, build system)
- **Rules-based config** -- concern-scoped rules injected by the SessionStart hook in every mode, your `CLAUDE.md` is never touched
- **Persistent memory** -- agents remember project patterns, conventions, and gotchas across sessions

---

### Table of Contents

- [Who It's For](#who-its-for)
- [Why Claude God-Mode?](#why-claude-god-mode)
- [Getting Started](#getting-started)
- [Workflow](#workflow)
- [Missions](#missions)
- [Agents](#agents)
- [Skills](#skills)
- [Standalone Workflows](#standalone-workflows)
- [Hooks](#hooks)
- [Bundled MCP Servers](#bundled-mcp-servers)
- [Bundled LSP Servers](#bundled-lsp-servers)
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

**Solo developer shipping a feature.** You have an idea, but turning it into a merged PR means juggling prompts, remembering to run tests, and hoping nothing slipped through. With God-Mode, you run `/mission` to set the goal, `/brief N` to define what to build, `/plan N` to break it into dependency-ordered steps, `/build N` to implement with automated review, `/verify N` to confirm every goal is covered, and `/ship` to push a clean PR -- all with quality gates enforced at every step.

**Team standardizing their AI workflow.** Your team uses Claude Code, but everyone prompts differently and quality varies. God-Mode's rules-based config gives every team member the same coding standards, testing protocols, and review process. The SessionStart hook injects the same baseline rules into every session, so the whole team gets identical behavior with no per-member setup.

**Contributor extending the plugin.** You want to add a new agent, skill, or rule. Each component is a self-contained markdown file with a clear contract. Drop a new agent into `agents/`, a new skill into `skills/`, or a new rule into `rules/` -- the plugin picks it up automatically.

## Why Claude God-Mode?

Claude Code is powerful out of the box. God-Mode adds **structure** -- the difference between a capable tool and a reliable workflow.

Without it, you write one-off prompts, manually enforce quality, and lose context between sessions. With it, you get a single clear workflow (`/godmode` through `/ship`), 19 specialized agents that handle implementation, review, testing, security, and architecture, and persistent memory that carries project knowledge across sessions. Quality gates (typecheck, lint, test, secrets scan) run on every change automatically -- not when you remember to ask.

The value isn't replacing Claude Code; it's removing the manual overhead that sits between "Claude can do this" and "this is actually production-ready." Rules are additive, components are modular, and your existing config is never touched.

## Getting Started

Check the [Prerequisites](#prerequisites) first, then follow these three steps to ship your first feature.

### Step 1: Install

#### Option A: Plugin Marketplace (Recommended)

```bash
claude plugin marketplace add SyloRei/claude-marketplace
claude plugin install claude-godmode@sylorei-plugins
```

Or, once accepted into Anthropic's community directory:

```bash
/plugin marketplace add anthropics/claude-plugins-community
/plugin install claude-godmode@claude-community
```

#### Option B: Manual Install

```bash
git clone https://github.com/sylorei/claude-godmode.git
cd claude-godmode
./install.sh
```

The install script copies agents, skills, and hooks to `~/.claude/`, keeps a private copy of the rules at `~/.claude/godmode/rules/`, and merges `settings.json` additively -- your existing config is preserved.

### Step 2: Orient

The rules that drive God-Mode's behavior are injected automatically by the SessionStart hook -- nothing is copied into `~/.claude/rules/` and there's no manual step. Start a Claude Code session and run `/godmode` to confirm you're set up and see your next step:

```
You:    /godmode
Claude: God-Mode v2.8.0 · 14 skills, 19 agents
        Where: uninitialized — no roadmap yet
        Next:  /mission   (then /brief 1)
        Spine: /mission → /brief N → /plan N → /build N → /verify N → /ship
```

Then enable the status bar:

```
You:    /godmode statusline
Claude: Statusline enabled. Context %, model, and cost now visible in status bar.
```

> **Tip:** Run `/onboard` in unfamiliar codebases -- it maps your stack before you start changing things.

### Step 3: First Feature

Ship a feature end-to-end:

```
You:    /mission
Claude: [sets project goal, writes PROJECT.md and ROADMAP.md]

You:    /brief 1
Claude: [asks clarifying questions, writes BRIEF.md for brief 1]

You:    /plan 1
Claude: [breaks brief into dependency-ordered steps, writes PLAN.md]

You:    /build 1
Claude: [spawns @executor per step, /verify review lenses validate each, atomic commits]
        Brief 1 complete! Run /verify 1 to confirm goals, then /ship.

You:    /verify 1
Claude: [goal-backward check: COVERED/PARTIAL/MISSING per criterion]

You:    /ship
Claude: Quality gates passed. PR #42 created: github.com/you/repo/pull/42
```

See [Workflow](#workflow) for the full reference.

### Uninstall

```bash
./uninstall.sh
```

Removes godmode rule files, agents, skills, and hooks. Your personal config is never touched.

### Requirements

See [Prerequisites](#prerequisites) for the full checklist.

### Updating

Re-run the install command for your method (plugin: `claude plugin install`, manual: `git pull && ./install.sh`). The installer creates a backup before updating.

## Workflow

```
/godmode  -->  /mission  -->  /brief N  -->  /plan N  -->  /build N  -->  /verify N  -->  /ship
  |               |              |              |              |               |             |
orient         PROJECT.md     BRIEF.md       PLAN.md       @executor       COVERED/       gates
               ROADMAP.md     (why+what)    (dep waves)   review lenses   PARTIAL/        PR
                                                           per step       MISSING
```

Run `/godmode` at any time to see your current position and the next command.

### Example Workflow

```
You:    /mission
Claude: [sets project goal, writes PROJECT.md and ROADMAP.md]

You:    /brief 1
Claude: [Socratic questions to clarify scope, writes BRIEF.md]

You:    /plan 1
Claude: [breaks brief into dependency-ordered waves, writes PLAN.md]

You:    /build 1
Claude: [wave-based parallel execution — @executor implements,
        /verify review lenses validate, atomic commit per step]
        Brief 1 complete! Run /verify 1 to confirm goals.

You:    /verify 1
Claude: [goal-backward check — each criterion: COVERED / PARTIAL / MISSING]

You:    /ship
Claude: [runs quality gates, pushes, creates PR, returns URL]
```

### Architect in the loop

Both `/brief` and `/plan` can spawn `@architect` (opus) for a **gated** design pass, so a load-bearing design decision is made deliberately rather than improvised mid-build. In `/brief` the pass is **spec-focused** -- it works through Context, Recommended Approach, and Tradeoffs, and lands its verdict in the brief's `## Architecture` section. In `/plan` the pass is **plan-focused** -- it reasons about implementation order, sequencing, and risks, and writes them into `PLAN.md`'s `## Design Notes`.

The pass is **gated on the brief's `## Design Risk` signal**: trivial units skip it entirely, so you pay nothing extra for work that doesn't warrant an architect. Only when the signal is raised does the design step run, keeping it fail-cheap by default and present exactly when the unit earns it.

### Findings

`/verify` doesn't just print problems and forget them -- it records them. The development loop after a brief is built is **findings → fixing findings**: `/verify` finds, `/build N --fix` fixes, `/verify` confirms, and `/ship` refuses to merge until the blocking ones are gone.

Each brief gets a tracked `FINDINGS.md` artifact at `.planning/missions/<id>/briefs/NN-*/FINDINGS.md`, owned by the deterministic `bin/godmode-findings` helper (columns: ID, lens, sev, conf, status, location, note). Every finding carries a **stable ID across re-runs**, so you can talk about "F3" today and have it still be F3 next week.

- **`/verify`** persists and reconciles findings across runs rather than re-printing a fresh list each time. A recurring problem keeps its ID, anything you waived stays waived, and a previously-fixed finding gets re-checked and reopened if it's still present. Each run reports the new / recurring / closed delta. Findings are run through an adversarial skeptic pass before they're recorded, so the set lands near-zero false positives.
- **`/build N --fix`** consumes the open findings and dispatches worktree-isolated fix agents (one atomic commit each), marking each fixed as it lands. Re-running `/verify` then confirms the fix actually closed the finding.
- **`/ship`** carries a **load-bearing blocking gate**: an unwaived CRITICAL (or high-confidence) open finding blocks the ship exactly the way an uncovered acceptance criterion does. The only escape hatch is an explicit, **reason-required waive** -- you mark a genuine false positive as waived, with a reason, and it stays waived on future runs.

## Missions

A **mission** is a named episodic feature cycle -- one initiative, from charter to merged PR. You finish one mission, then start the next under a fresh name. Running [`/mission`](#skills) with a feature name create-or-switches to that mission and makes it the active context for the rest of the spine (`/brief N → /plan N → /build N → /verify N → /ship`).

Crucially, **unit and brief numbers reset to 1 per mission** -- "brief 1" always means the first brief of the *current* mission, not the first brief you ever wrote. This keeps each initiative self-contained instead of accumulating an ever-growing global counter.

### On-disk layout

Planning artifacts live in the consumer repo's `.planning/` directory. Each mission gets its own subdirectory; two files stay project-global at the root:

```
.planning/
├── PROJECT.md                       # project-global charter (purpose, constraints, decisions) — spans all missions
├── STATE.md                         # project-global workflow state (active mission, brief/plan/wave)
├── ideas/
│   └── <slug>/                      # one per proposed feature, BEFORE any mission is allocated
│       └── IDEAS.md                 # /ideate's durable proposal — /mission auto-reads it as seed
└── missions/
    └── NN-slug/                     # one directory per mission, NN numbered in creation order
        ├── ROADMAP.md               # this mission's numbered work units
        └── briefs/
            └── NN-name/             # one per unit, numbered from 1 WITHIN the mission
                ├── BRIEF.md         # why + what + spec
                └── PLAN.md          # dependency-ordered steps
```

`PROJECT.md` (the durable charter) and `STATE.md` are **not** per-mission -- they live at the `.planning/` root and apply across every mission. `.planning/ideas/` is project-global scratch space too: it sits outside `missions/` because an `/ideate` proposal has no `mission_id` yet -- it captures the *next* mission before one exists.

### The pre-mission front door: `/ideate`

`/mission` already demands a decision -- a feature name, a purpose, success criteria, constraints. **[`/ideate`](#skills) is the front door *before* that:** the generative, exploratory step that decides what the next mission should even be. It discusses candidate directions, thinks each through, converges on one concrete proposal, and writes it to `.planning/ideas/<slug>/IDEAS.md` (where `<slug>` is the kebab-case proposed feature name). It does **not** start, switch, or mutate any mission -- it stops at the proposal.

When you later run `/mission <name>` for a feature whose slug matches an existing `.planning/ideas/<slug>/IDEAS.md`, `/mission` auto-reads that artifact as seed context for the charter and roadmap. The read is additive and best-effort: with no matching artifact, `/mission` behaves exactly as before. So the full spine reads `/ideate → /mission → /brief N → /plan N → /build N → /verify N → /ship`, with `/ideate` as the optional pre-mission front door.

### The mid-mission complement: `/refine`

Where [`/ideate`](#skills) is the pre-mission front door -- shaping the *next* mission before one exists -- **[`/refine`](#skills) works *within* the active mission.** It reads the current mission's roadmap and briefs, surfaces what's missing or underspecified, converges on one concrete gap, and appends a **new numbered roadmap unit plus its full brief** to that mission. The append is **strictly additive**: `/refine` never edits an existing brief or roadmap unit in place -- reworking an existing unit is `/brief N`'s job. The unit it adds is buildable straight away with `/plan N → /build N`.

`/refine` is a spine skill, not a new mandatory spine stage: like `/brief`, you invoke it within a mission whenever a gap surfaces -- not as a fixed step every cycle. `/ideate` shapes what the next mission should be; `/refine` extends the mission you're already in.

### New mission vs. updating the current one

`/mission <feature name>` is create-or-switch:

- **A new feature name** starts a new mission -- a fresh `missions/NN-slug/` directory with its unit counter reset to 1.
- **An existing mission name** updates that mission in place and **preserves its counter** -- you pick up where you left off rather than renumbering.

The active mission is tracked in workflow state, exposed as `mission_id` (e.g. `01-v3`) and `mission_name`; the spine resolves all briefs and roadmaps under whichever mission is active. The whole `.planning/` directory is **local-only and gitignored** -- it is your planning scratch space, not committed alongside the code.

See [`/mission`](#skills) in the Skills table for the full skill behavior.

## Agents

| Agent | Model | Memory | Effort | Purpose |
|-------|-------|--------|--------|---------|
| `@writer` | opus | project | high | General implementation in isolated worktree |
| `@executor` | opus | project | high | Step execution during `/build N` |
| `@planner` | opus | project | xhigh | Tactical planning for `/plan N` (read-only) |
| `@verifier` | opus | project | xhigh | Goal-backward verification for `/verify N` (read-only) |
| `@architect` | opus | project | xhigh | System design (advisory, read-only enforced) |
| `@security-auditor` | opus | project | xhigh | Security audit (read-only, enforced) |
| `@spec-reviewer` | sonnet | project | high | Brief/plan spec review (read-only) |
| `@code-reviewer` | sonnet | project | high | Deep code review lens (read-only) |
| `@perf-reviewer` | sonnet | project | high | Performance review lens (read-only) |
| `@convention-reviewer` | sonnet | project | high | Convention/style review lens (read-only) |
| `@test-reviewer` | sonnet | project | high | Test-quality review lens (read-only) |
| `@test-writer` | sonnet | project | high | Test generation in isolated worktree |
| `@doc-writer` | sonnet | project | high | Documentation |
| `@researcher` | sonnet | project | high | Codebase and web research (background) |

**Safety features:**
- Read-only agents (`@architect`, `@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`, `@perf-reviewer`, `@convention-reviewer`, `@test-reviewer`, `@researcher`, `@security-auditor`) have `disallowedTools: Write, Edit` enforced mechanically
- Code-writing agents (`@executor`, `@writer`, `@test-writer`) have `maxTurns` limits (80-100) to prevent runaway token burn
- Code-writing agents cap at `effort: high` even under the `quality` model profile — `effort: xhigh` is documented to skip rules on Opus 4.7
- `@researcher` runs in background mode by default for non-blocking parallel research
- `@security-auditor` has WebSearch for CVE and vulnerability lookups
- Agents run in parallel -- spawn `@researcher` + `@security-auditor` simultaneously for independent tasks

## Skills

| Skill | Purpose |
|-------|---------|
| `/godmode` | Orient: show current position and next command (reads STATE.md) |
| `/ideate` | Pre-mission front door: discuss next-mission directions, converge on one proposal → `.planning/ideas/<slug>/IDEAS.md` (seed for `/mission`) |
| `/refine` | Mid-mission gap analysis: surface gaps/improvements in the CURRENT mission's roadmap + briefs, converge on one, and append a NEW numbered roadmap unit plus its full brief to the current mission (strictly additive; does not edit existing briefs in place). Buildable by `/plan N` |
| `/mission` | Initialize/update PROJECT.md and numbered ROADMAP.md |
| `/brief N` | Socratic brief: why + what + spec → BRIEF.md |
| `/plan N` | Tactical breakdown into dependency-ordered waves → PLAN.md |
| `/build N` | Wave-based parallel execution, atomic commit per step |
| `/verify N` | Goal-backward verification: COVERED / PARTIAL / MISSING per criterion |
| `/ship` | Quality gates, git cleanup, PR creation |
| `/debug` | Structured debugging protocol (reproduce → hypothesize → isolate → fix) |
| `/tdd` | Test-driven development (red-green-refactor) |
| `/refactor` | Safe refactoring with test verification |
| `/triage` | Incident triage and response |
| `/profile` | Performance analysis and profiling |
| `/onboard` | Codebase orientation cheatsheet |
| `/adr` | Draft an Architecture Decision Record (Status / Context / Decision / Consequences) |
| `/changelog` | Draft a Keep-a-Changelog entry from recent commits (standalone -- does not replace `/ship`) |
| `/pr-describe` | Draft a PR description from the branch's commits and diff vs the base |

> **Note:** the old codebase-exploration command has been folded into `/onboard` -- use `/onboard` for codebase orientation.

> **Note:** `/adr`, `/changelog`, and `/pr-describe` are off-spine plain commands -- one-shot helpers, not steps in the `/mission → /ship` spine.

### When to Use What

| Situation | Use |
|-----------|-----|
| Shipping a feature | `/mission → /brief N → /plan N → /build N → /verify N → /ship` |
| "What do I do next?" | `/godmode` |
| Implementing a one-off change | `@writer` (general-purpose, worktree) |
| Executing a build step | `@executor` (spawned by `/build N`) |
| Code review | `/verify` (5 parallel lenses) |
| Bug fixing | `/debug` |
| Adding tests to existing code | `@test-writer` |
| TDD for new feature | `/tdd` |
| Refactoring | `/refactor` |
| Understanding a codebase | `/onboard` or `@researcher` |
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
You:    /verify my staged changes
Claude: [runs 5 parallel review lenses, returns verdict with CRITICAL/WARNING/NIT findings]
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
You:    /onboard
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
| **SessionStart** | Conversation begins | Injects the 8 godmode rules plus project context (language, package manager, test runner, git state) via `additionalContext` |
| **PostCompact** | After `/compact` | Restores quality gates and available skills after context compaction |
| **PreToolUse** | Before every tool call | Quality-gate enforcement on `git commit` — blocks commits that fail typecheck, lint, or tests |
| **PostToolUse** | After tool call | Surfaces failed exit codes; triggers secret scan on staged diffs |
| **UserPromptSubmit** | Each user message | Injects session context on first message |
| **SessionEnd** | Conversation ends | Writes install marker and last-version-seen to plugin data directory |
| **StatusLine** | Continuous | Shows context %, model, cost, project, branch (run `/godmode statusline` to enable) |

## Output Style

The plugin ships a `godmode-terse` output style: a bottom-line-up-front, severity-labeled, no-preamble response mode that leads with the answer or action and drops filler.

It is **opt-in** -- not the default. Activate it for the current session with:

```
/output-style godmode-terse
```

## Bundled MCP Servers

Claude God-Mode bundles a `.mcp.json` referenced from `.claude-plugin/plugin.json`, so three MCP servers register automatically when the plugin is enabled. They are `npx`-based stdio servers that spawn on first use.

| Server | Enables |
|--------|---------|
| **context7** | Up-to-date library and framework docs for `@writer` and `@executor`, so generated code reflects current APIs rather than stale training data |
| **github** | PR and repository operations used by `/ship` |
| **playwright** | Browser-based verification used by `/verify` |

### Requirements

- **Node and `npx`** must be available locally -- the servers spawn on demand via `npx`.
- **`github` requires a `GITHUB_TOKEN` environment variable.** The bundled config references `GITHUB_TOKEN` as a placeholder; you supply the value in your own environment. No token is stored in the repo.

### Disabling servers

- **One server:** remove its entry from `.mcp.json`.
- **All servers:** remove the `"mcpServers": "./.mcp.json"` line from `.claude-plugin/plugin.json`.

### Manual installs

The `mcpServers` manifest field applies in plugin mode. If you install manually, copy or merge `.mcp.json` into your own project or user MCP config to opt in to the same servers.

## Bundled LSP Servers

Claude God-Mode bundles a `.lsp.json` referenced from `.claude-plugin/plugin.json`, giving Claude live code intelligence -- instant diagnostics, go-to-definition, and type info -- inside `@writer` and `@executor` worktrees. Two language servers are wired up:

| Server | Enables |
|--------|---------|
| **typescript** (TypeScript Language Server) | TypeScript/JavaScript diagnostics + navigation for `.ts`/`.tsx`/`.js`/`.jsx` |
| **pyright** (Pyright) | Python type-checking diagnostics + navigation for `.py` |

### Requirements

- The language-server **binaries must be installed separately** -- the plugin only configures the connection, it does not bundle the binary.
- Install the TypeScript server with `npm install -g typescript-language-server typescript`.
- Install Pyright with `npm install -g pyright` (the npm path is canonical; `pip install pyright` also provides `pyright-langserver`).
- A server only spawns when matching files are present in the workspace **and** its binary is installed, so it is zero-cost otherwise.

### Disabling servers

- **One server:** remove its entry from `.lsp.json`.
- **All servers:** remove the `"lspServers": "./.lsp.json"` line from `.claude-plugin/plugin.json`.

### Manual installs

The `lspServers` manifest field applies in plugin mode. If you install manually, copy or merge `.lsp.json` into your own LSP config to opt in to the same servers.

## Rules-Based Configuration

Claude God-Mode uses individual rules instead of a monolithic config. The 8 rules are injected automatically by the SessionStart hook (via `additionalContext`) at the start of every conversation -- in both plugin mode and manual mode, with zero setup steps. Nothing is written to `~/.claude/rules/`.

### How rules load

**Plugin users:** Rules ship inside the plugin and are injected by the SessionStart hook. No manual file copying, no separate step.

**Manual install users:** `./install.sh` keeps a private copy of the rules at `~/.claude/godmode/rules/` for the hook to read. This directory is not auto-loaded by Claude Code -- only the SessionStart hook reads it -- so it never collides with your own `~/.claude/rules/`.

| Rule File | Concern |
|-----------|---------|
| `godmode-identity.md` | Engineering persona and response style |
| `godmode-workflow.md` | Workflow phases and entry points |
| `godmode-coding.md` | Auto-detection, coding standards, security |
| `godmode-quality.md` | Quality gates (typecheck, lint, test, build) |
| `godmode-git.md` | Git discipline and commit conventions |
| `godmode-testing.md` | Testing, debugging, and refactoring protocols |
| `godmode-context.md` | Context management and continuous learning |
| `godmode-routing.md` | Agent/skill routing and severity scales |

### Customizing Rules

- **Add** your own rule files -- any `.md` you drop into `~/.claude/rules/` is loaded automatically by Claude Code and layers on top of the godmode rules
- **Override** any godmode behavior in your own `~/.claude/rules/` file or `~/.claude/CLAUDE.md`
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

1. **Override behaviors** -- The godmode rules (identity, quality gates, routing, etc.) are injected by the SessionStart hook; add a rule file to `~/.claude/rules/` or an entry in `~/.claude/CLAUDE.md` to override any of them
2. **`~/.claude/settings.json`** -- Add/remove permissions for your toolchain
3. **Add rules** -- Drop your own `.md` files into `~/.claude/rules/` for project-specific conventions; they load automatically alongside the godmode rules

For the full file structure and contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Troubleshooting

### Prerequisites

Before installing, make sure you have:

- [ ] **Claude Code CLI** -- [install guide](https://docs.anthropic.com/en/docs/claude-code). Verify: `claude --version`
- [ ] **git** >= 2.20 -- required for worktree agents. Verify: `git --version`
- [ ] **jq** -- used by install script to merge `settings.json`. Verify: `jq --version`
- [ ] **macOS or Linux** -- Windows is not supported (Claude Code limitation)
- [ ] **Claude Code >= v2.1.33** -- required for the `@researcher` agent's persistent memory (`memory: project`)

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
Cause: The SessionStart hook isn't running, so it can't inject the rules. Fix: start a fresh Claude Code session and run `/godmode` -- it confirms the hook is wired up. Manual installs can also verify the private rules copy exists:
```bash
ls ~/.claude/godmode/rules/godmode-*.md   # should list 8 files (manual install)
./install.sh                              # re-run if missing
```

**Permission denied running install.sh**
Cause: Script not executable. Fix:
```bash
chmod +x install.sh && ./install.sh
```

**Plugin not appearing after marketplace install**
Cause: The session was started before the plugin finished installing, so the SessionStart hook didn't fire. Fix: start a fresh Claude Code session and run `/godmode` to confirm you're set up.

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

Agents specify their target models in their configuration, but you can edit any agent file to use a different model. Eight agents use Sonnet (`@spec-reviewer`, `@code-reviewer`, `@perf-reviewer`, `@convention-reviewer`, `@test-reviewer`, `@test-writer`, `@doc-writer`, `@researcher`) and six use Opus (`@writer`, `@executor`, `@planner`, `@verifier`, `@architect`, `@security-auditor`).

### What is the `model_profile` config knob?

`model_profile` is the single user-tunable config knob (defined under `userConfig` in `.claude-plugin/plugin.json`). It selects a model/effort **preset** applied across agents:

| `model_profile` | Model | Effort |
|-----------------|-------|--------|
| `quality`       | `opus`  | `xhigh` |
| `balanced` (default) | each agent's own frontmatter values | each agent's own frontmatter values |
| `budget`        | `haiku` | default |

**Hard carve-out (locked in PROJECT.md):** code-writing agents — `@executor`, `@writer`, `@test-writer` — **cap at `effort: high`** even under `quality`, and are **never** raised to `xhigh`. On Opus 4.7, `effort: xhigh` is documented to skip rules, which is unacceptable for agents that produce code. Only read-only / design agents (`@architect`, `@security-auditor`, and any planner/verifier) receive `xhigh` under `quality`.

**Current state (be honest):** the knob is now wired for **model switching at spawn**. `/build`, `/verify`, and `/ship` read the active profile from `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-balanced}`, call the resolver `bin/godmode-model <agent>` to get that agent's model under the profile, and pass it to the Agent tool's `model` override when spawning. `balanced` resolves to each agent's own frontmatter model; `quality` and `budget` apply the preset (with code-writing agents capped at `high` under `quality` per the carve-out above). This is **model-only**: the resolver also reports an effort value, but `effort` is **frontmatter-only and is NOT overridable at agent spawn** by the platform, so effort always stays whatever the agent's frontmatter declares regardless of profile. To change effort you still edit agent frontmatter.

### Will this overwrite my config?

No. The 8 godmode rules are injected automatically by the SessionStart hook (via `additionalContext`) at the start of every conversation -- no files are written to `~/.claude/rules/`, and there are zero setup steps. This works the same in plugin mode and manual mode. Your `~/.claude/CLAUDE.md` is never read, modified, or replaced. Settings are merged additively, preserving your existing permissions and plugins. Manual installs keep a private copy of the rules at `~/.claude/godmode/rules/` for the hook to read; this directory is not auto-loaded by Claude Code, so it never collides with your own config.

### Can I use individual parts?

Yes. You can cherry-pick individual agents, skills, hooks, or rule files. Copy just the files you want into your `~/.claude/` directory. Each component is self-contained.

### What languages does this support?

Claude God-Mode is language-agnostic. The SessionStart hook auto-detects your project's toolchain (package manager, test runner, linter, formatter, build system) and injects that context into every conversation.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on adding agents, skills, hooks, rules, and submitting pull requests.

## License

[MIT](LICENSE)
