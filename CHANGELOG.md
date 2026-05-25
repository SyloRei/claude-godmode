# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.1.0] - 2026-05-25

v3 Phase 1: the `model_profile` knob now does something, code review fans out
into focused lenses, rules load through the SessionStart hook, three MCP servers
ship out of the box, and a selectable terse output style is available.

### Added

- **`model_profile` is now wired (model-only switching at spawn)** — `bin/godmode-model` deterministically resolves `(agent, profile)` → `model`, and the spine skills (`/build`, `/verify`, `/ship`) spawn agents with the resolver's `model` via the Agent tool override. `balanced` reads each agent's own frontmatter (single source of truth); `quality` and `budget` apply preset rules with a code-writer effort carve-out. Defaults to `balanced` when `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE}` is unset/unrecognized. Effort stays frontmatter-only (the platform cannot override it at spawn — documented). Proven by `tests/model-profile.bats`.
- **Three new code-review lens agents** — `@perf-reviewer`, `@convention-reviewer`, `@test-reviewer`, joining `@code-reviewer` (correctness) and `@security-auditor` (security) as five focused, read-only lenses.
- **Three bundled MCP servers** (`.mcp.json`, referenced via `plugin.json` `mcpServers`) — `context7` (live library docs), `github` (PR/issue ops), `playwright` (browser verification), as `npx` stdio servers. GitHub's token is an env-var placeholder, never a literal. README documents requirements, manual-mode opt-in, and how to disable.
- **`godmode-terse` output style** (`outputStyles/godmode-terse.md`, referenced via `plugin.json` `outputStyles`) — an opt-in (`/output-style godmode-terse`), bottom-line-up-front, severity-labeled (CRITICAL/WARNING/NIT), no-preamble response mode. Not the default.
- **New tests** — `tests/model-profile.bats`, `tests/mcp.bats`, `tests/output-style.bats`, plus expanded `tests/hooks.bats` and `tests/install.bats`.

### Changed

- **`/verify` runs 5 parallel review lenses** — instead of a single generalist pass, `/verify N` fans out the five lens agents + `@verifier` scoped to the unit's diff, merges findings (dedup, drop LOW-confidence NITs, group by lens, severity-ordered) using a shared finding schema (lens, severity, confidence, `file:line`, note), and reports both the unchanged AC-coverage table and the merged findings. Read-only, goal-backward semantics preserved.
- **Rules now load via the SessionStart hook** — the 8 godmode rules are injected into every conversation through the hook's `additionalContext`, automatically and in all install modes (plugin and manual), with zero setup steps. Previously `install.sh` copied them into the auto-loaded `~/.claude/rules/` and plugin-mode installs received no rules at all.
- **Agent roster expanded to 14** — net +2 from retiring the generalist `@reviewer` and adding three lenses; `plugin.json` description and README updated. Every `@reviewer` reference repointed (`rules/godmode-routing.md`, `skills/refactor`, `skills/tdd`, README, CONTRIBUTING).

### Removed

- **Retired the generalist `@reviewer` agent** (`agents/reviewer.md`) — its job is now the union of the five lenses run inside `/verify`.
- **Retired the `~/.claude/rules/` install path and drift-detection machinery** — godmode no longer writes rule files into `~/.claude/rules/`, and the hashing/drift-detection that guarded those copies is gone.
- **Removed `bin/godmode-hash-rules`** — only existed to support rule-file drift detection, which no longer applies.

### Migration

- **Upgrade note:** existing users who previously installed godmode should delete the stale auto-loaded copies to avoid double-loading the rules:
  ```bash
  rm ~/.claude/rules/godmode-*.md
  ```
  Manual installs now keep a private (non-auto-loaded) copy at `~/.claude/godmode/rules/` that only the SessionStart hook reads.

## [2.0.0] - 2026-05-25

### BREAKING

- **Removed `/prd`, `/plan-stories`, `/execute`** — the v1.x feature pipeline (PRD → stories.json → @executor loop) is gone. These skills and their `.claude-pipeline/` runtime directory are no longer part of the plugin. Migrate to the v2 workflow: `/mission → /brief N → /plan N → /build N → /verify N → /ship`.

### Added

- **`/godmode`** — orient command: reads `.planning/STATE.md` and tells you the next command in 5 lines
- **`/mission`** — initializes and updates `PROJECT.md` and a numbered `ROADMAP.md`
- **`/brief N`** — Socratic brief session (why + what + spec) → writes `BRIEF.md`
- **`/plan N`** — tactical breakdown into dependency-ordered waves → writes `PLAN.md`
- **`/build N`** — wave-based parallel execution with `@executor` + `@reviewer` per step; atomic commit per step
- **`/verify N`** — goal-backward verification: each criterion reported as COVERED / PARTIAL / MISSING
- **`@planner` agent** — opus + `effort: xhigh`; drives `/plan N`; read-only
- **`@verifier` agent** — opus + `effort: xhigh`; drives `/verify N`; read-only
- **`@spec-reviewer` agent** — sonnet + `effort: high`; reviews briefs and plans
- **`@code-reviewer` agent** — sonnet + `effort: high`; deep code review pass
- **Quality-gate enforcement hook (PreToolUse)** — blocks `git commit` when typecheck, lint, or tests fail; single source of truth in `config/quality-gates.txt`
- **Secret-scan hook (PostToolUse)** — scans staged diffs for secrets before each commit
- **`UserPromptSubmit` hook** — injects session context on first message
- **`SessionEnd` hook** — writes install marker and last-version-seen to `${CLAUDE_PLUGIN_DATA}`
- **CI workflow** — GitHub Actions matrix (`ubuntu-latest`, `macos-latest`): shellcheck, lint-json, lint-frontmatter, bats smoke tests, plugin-mode/manual-mode parity gate, v2 vocabulary gate
- **`userConfig.model_profile` knob** — single user-tunable config (`quality | balanced | budget`); exposed as `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE}` to hooks and subprocesses
- **`config/quality-gates.txt`** — single source of truth for gate definitions; `post-compact.sh` reads from it

### Changed

- **Single clear workflow** — replaces the multi-command v1.x pipeline with one obvious arrow chain: `/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship`
- **Agent roster expanded to 12** — added `@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`
- **Model/effort policy hardened** — code-writing agents (`@executor`, `@writer`, `@test-writer`) cap at `effort: high`; design/audit/read-only agents use `effort: xhigh`; all agents use `opus`/`sonnet`/`haiku` aliases, never pinned IDs
- **Install/uninstall parity** — plugin-mode and manual-mode hook bindings, permissions, and timeouts are identical; CI parity gate enforces this on every commit
- **Hook JSON construction** — all hooks use `jq -n --arg`/`--argjson` (never heredoc string interpolation) to prevent adversarial input corruption

## [1.6.0] - 2026-04-04

### Added

- ASCII art banner and dynamic shields.io badges (version, license, Claude Code Plugin, stars, last commit)
- "Who It's For" section with three audience scenarios (solo dev, team, contributor)
- "Why Claude God-Mode?" value differentiation section
- Step-by-step Getting Started tutorial (install, first run, first feature)
- Prerequisites checklist with version requirements and verify commands
- Troubleshooting section with 5 common issues (symptom/cause/fix format)
- GitHub topics for discoverability: claude-code, claude-code-plugin, ai-engineering, developer-tools, code-quality, ai-agents, workflow-automation, claude, anthropic

### Changed

- README restructured with logical reading flow: intro -> audience -> tutorial -> reference -> troubleshooting -> FAQ
- Table of contents added for section navigation
- Redundant content consolidated (How It Works, File Locations, Tips dissolved into relevant sections)
- Agent Memory section trimmed to table + summary
- Repository description updated for GitHub search discoverability
- SEO keyword phrases added naturally to opening paragraphs

## [1.5.0] - 2026-04-04

### Added

- Structured heading hierarchy in `progress.md`: `# Progress` > `## Knowledge Base` (with `### Codebase Patterns`, `### Anti-Patterns`, `### Architecture Decisions`) > `## Story Log` (with `### [Date] - [Story ID]: [Title]` entries)
- Auto-migration for existing `progress.txt` files — runs as a pre-phase-detection step in `pipeline-context.md`, inherited by all consumer skills

### Changed

- **BREAKING:** `progress.txt` renamed to `progress.md`
  - Pipeline progress file now uses `.md` extension to match its markdown content
  - Auto-migration renames existing `progress.txt` files automatically
  - If both `progress.txt` and `progress.md` exist, `progress.md` is preferred — remove the stale `.txt` file manually

## [1.4.2] - 2026-04-03

### Changed

- Agent model rebalancing: moved from 6 opus / 2 sonnet to 4 opus / 4 sonnet split
  - `@reviewer`: opus -> sonnet (with effort: high)
  - `@test-writer`: opus -> sonnet (added effort: high)
  - `@doc-writer`: added effort: high (already sonnet)
- `@architect` gains `disallowedTools: Write, Edit` for mechanical read-only enforcement
- Documentation updated to reflect four-tier model strategy: opus+high (architecture/security), opus (code-writing), sonnet+high (analysis/generation), sonnet (research)
- CONTRIBUTING.md model selection guide expanded with decision tree for placing future agents

## [1.4.1] - 2026-03-29

### Fixed

- Agent routing: added explicit `subagent_type` mapping table to `godmode-routing.md` to prevent Claude Code from substituting built-in agents (`Explore`, `general-purpose`) for godmode agents (`@researcher`, `@writer`)

## [1.4.0] - 2026-03-29

### Added

- 8 rule files (`rules/godmode-*.md`) replacing monolithic config files with modular, scopeable rules
- Memory scopes for all 8 agents — each agent now has a dedicated memory scope for persistent context
- `.claude-godmode-version` file for tracking installed version
- Plugin-mode and manual-mode installer detection — `install.sh` auto-detects installation method
- v1.x migration detection — installer identifies old `CLAUDE.md`-based installs and offers cleanup

### Changed

- **BREAKING:** `install.sh` fully rewritten — rules-based architecture replaces config-file copying
- **BREAKING:** `uninstall.sh` fully rewritten — targeted removal of rules, hooks, and settings entries
- Agent memory scopes updated for all 8 agents — `@architect` and `@researcher` use project (not user), `@security-auditor` uses project (not local)
- `effort: high` added to `@reviewer`, `@security-auditor`, `@architect` for thoroughness protection
- `maxTurns` safety limits added to `@executor` (100), `@writer` (100), `@test-writer` (80)
- `disallowedTools: Write, Edit` enforced on read-only agents (`@reviewer`, `@researcher`, `@security-auditor`)
- `@researcher` defaults to background mode for non-blocking parallel research
- `@security-auditor` gains WebSearch tool for CVE and vulnerability lookups
- `@doc-writer` gains Bash tool for doc generation and git commands
- `/godmode` command enhanced with memory column and configuration section
- `README.md` major rewrite — updated for rules-based architecture, new install flow, and feature overview
- `CONTRIBUTING.md` updated with rules authoring guide and memory scope guide

### Removed

- **BREAKING:** `config/CLAUDE.md` — replaced by modular `rules/godmode-*.md` files
- **BREAKING:** `config/INSTRUCTIONS.md` — content merged into `rules/` and `README.md`

### Migration

Upgrading from v1.x (config-based) to v1.4 (rules-based):

1. Run the new `install.sh` — it detects the old `config/CLAUDE.md` installation automatically
2. Accept the cleanup prompt to remove legacy `config/CLAUDE.md` and `config/INSTRUCTIONS.md` entries
3. Verify new `rules/godmode-*.md` files are in place
4. Confirm `.claude/settings.json` references rules instead of config files
5. Remove any manual `CLAUDE.md` includes that referenced the old config paths

> **Note:** The installer handles most migration steps automatically. Manual intervention is only needed if you customized the old config files — review your customizations and port them to the appropriate rule file.

## [1.3.0] - 2026-03-25

### Added

- Shared reference files: `gitignore-management.md` and `pipeline-context.md` for cross-skill consistency
- Agent routing sections in all standalone skills (/debug, /tdd, /refactor, /explore-repo) and pipeline skills (/prd, /plan-stories, /execute, /ship)
- Pipeline context sections in standalone and pipeline skills for `.claude-pipeline/` awareness
- Explore-repo output persistence to `.claude-pipeline/exploration/`
- Pipeline integration for /debug, /refactor, /tdd: story-aware context and progress tracking
- Failure recovery routing in /execute: structured re-entry after failed stories
- Security auditor integration in /execute: optional `@security-auditor` pass on security-tagged stories
- Session-start hook pipeline state detection (active stories, progress)
- Post-compact hook pipeline state restoration
- Workflow composition documentation (US-014)

### Changed

- All skills now reference shared modules instead of duplicating gitignore and pipeline logic
- /execute skill enhanced with failure recovery, security audit, and richer pipeline context
- Hooks enriched with pipeline awareness for better context injection and recovery
- CLAUDE.md updated with agent routing rule for skill-to-agent dispatch

## [1.2.0] - 2026-03-25

### Added

- PLAN phase in @executor: structured thinking (restate criteria, identify files, pseudocode, flag risks) before coding
- PLAN phase in @writer: lightweight plan-before-code discipline for ad-hoc tasks
- Anti-Patterns section in progress.txt: tracks what didn't work, auto-populated on @reviewer CRITICAL rework
- Architecture Decisions section in progress.txt: records design choices with rationale
- Dependency declaration in /plan-stories: `dependsOn` field with conservative heuristics (shared files, API/schema, infrastructure, PRD ordering)
- Parallel story execution in /execute: spawns concurrent @executor agents for independent stories
- Batch computation with transitive dependency resolution and `maxParallel` cap (default 3)
- Post-merge smoke test: quality gates on combined result after parallel merge
- Dry-run batch plan display with user confirmation before spawning
- Concurrency directive in @executor and @writer: batch independent tool calls in parallel

### Changed

- @executor workflow: CONTEXT → PLAN → BRANCH → IMPLEMENT → TEST → QUALITY GATES → COMMIT → PROGRESS → COMPLETION CHECK (9 phases, was 8)
- @writer workflow: UNDERSTAND → PLAN → IMPLEMENT → TEST → QUALITY GATES → RETURN (6 phases, was 5)
- /execute skill: supports both sequential (backward compatible) and parallel execution modes
- @executor supports parallel mode: skips shared state updates when orchestrator signals `parallel: true`

## [1.1.1] - 2026-03-25

### Changed

- Pipeline artifacts (PRDs, stories) now write to `.claude-pipeline/` directory
- `/prd` and `/plan-stories` skills manage `.gitignore` for pipeline artifacts
- `/plan-stories` references updated with `prdSource` field support
- Archive structure updated with PRD tracking
- Documentation and plugin repo cleanup

### Fixed

- `.claude-pipeline/` added to `.gitignore` and removed from tracking

## [1.1.0] - 2025-03-23

### Added

- `/godmode statusline` command for plugin-based statusline setup
- CONTRIBUTING.md, CODE_OF_CONDUCT.md, CHANGELOG.md
- GitHub issue templates (bug report, feature request) and PR template
- Enriched plugin.json with expanded keywords and author URL

### Changed

- README.md rewritten with badges, value proposition, pipeline diagram, FAQ, and correct marketplace install commands

## [1.0.0] - 2025-03-23

### Added

- **8 agents**: writer, executor, reviewer, researcher, architect, security-auditor, test-writer, doc-writer
- **8 skills**: /prd, /plan-stories, /execute, /ship, /debug, /tdd, /refactor, /explore-repo
- **3 hooks**: SessionStart (context injection), PostCompact (recovery), StatusLine (display)
- Feature pipeline: `/prd → /plan-stories → /execute → /ship`
- Quality gates: typecheck, lint, test, secrets scan, regression check, requirements match
- CLAUDE.md with coding standards, workflow phases, agent routing
- INSTRUCTIONS.md with detailed behavioral conventions
- Install and uninstall scripts with backup and additive settings merge
- `/godmode` command for quick reference
