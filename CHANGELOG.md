# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
