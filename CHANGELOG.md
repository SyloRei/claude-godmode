# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased] — milestone v2.0.0 in progress

### Phase 1 — Foundation & Safety Hardening (2026-04-26)

First milestone phase of the v2 polish-mature-version effort. Hardens the v1.x substrate so every later phase can build on it without re-doing plumbing. **Closes 11 of 11 phase requirements (FOUND-01..FOUND-11) and 9 of 9 v1.x audit High items.**

### Added

- `scripts/check-version-drift.sh` — CI guard asserting every version mention matches `.claude-plugin/plugin.json:.version` (FOUND-02)
- `config/quality-gates.txt` — single source of truth for the 6 quality gates (FOUND-07)
- `.shellcheckrc` — repo-root config; every shipped shell file is `shellcheck`-clean at v0.11.0 default severity (FOUND-08)
- `tests/fixtures/hooks/setup-fixtures.sh` + 5 placeholder fixtures (`cwd-{normal,quote-branch,backslash-branch,newline-branch,apostrophe-branch}.json`) — adversarial branch-name test inputs for both shipped hooks. macOS-aware: branches git refuses on macOS fall back to `main` with a marker note; Linux CI exercises the full set in Phase 5 bats smoke (FOUND-04 substrate)
- `tests/fixtures/hooks/cwd-*.json` added to `.gitignore` — fixtures are generated, not source

### Changed

- `install.sh` — version sourced from `plugin.json` at runtime via `jq` (FOUND-02). Per-file `[d/s/r/a/k]` prompt before overwriting customized rules / agents / skills / hooks; non-TTY default keeps customizations (FOUND-01). v1.x migration is detection-only, never destroys (FOUND-09). Backup rotation caps at last 5 (FOUND-10).
- `uninstall.sh` — version sourced from `plugin.json`. Refuses on `~/.claude/.claude-godmode-version` mismatch unless `--force` (FOUND-03). jq preflight added.
- `hooks/session-start.sh` — JSON output via `jq -n --arg`, never heredoc (FOUND-04). Reads `cwd` from stdin (FOUND-05). Tolerates stdin closure under `set -e` (FOUND-05).
- `hooks/post-compact.sh` — same hook safety hardening as `session-start.sh` (two atomic commits — substrate fixes separately from gates-file read, per CONTEXT D-19 so Phase 3's vocabulary rewrite layers cleanly). Agents / skills enumerated from live filesystem instead of hardcoded list (FOUND-11). Quality gates read from `config/quality-gates.txt`, not duplicated inline (FOUND-07).
- `config/statusline.sh` — collapses 4 `jq` invocations into 1 `@tsv` filter (FOUND-06). Removed unused `GRAY` color (SC2034).
- `commands/godmode.md` — drops literal version from heading; statusline carries it (FOUND-02).

### Closes (CONCERNS.md High items, all 9)

- #1 Rule customizations silently overwritten (FOUND-01)
- #2 Manual-mode agent/skill overwrite without check (FOUND-01)
- #4 No version-mismatch detection on uninstall (FOUND-03)
- #5 v1.x migration `rm`s after one keypress (FOUND-09)
- #6 Branch names interpolated into hook JSON (FOUND-04)
- #7 Hooks rely on `cwd` being project root (FOUND-05)
- #8 Hardcoded skill/agent lists in PostCompact (FOUND-11; consumer-side `/godmode` indexer lands in Phase 4)
- #9 Quality gates duplicated rules ↔ post-compact (FOUND-07)
- #18 Stdin drain under `set -e` aborts hook (FOUND-05)

### Phase 1 status

- 11 / 11 requirements closed (FOUND-01..FOUND-11)
- 9 / 9 High-severity CONCERNS items closed
- `shellcheck install.sh uninstall.sh hooks/*.sh config/statusline.sh scripts/*.sh tests/fixtures/hooks/*.sh` exits 0
- 5 adversarial fixtures × 2 hooks = 10/10 valid JSON outputs
- `bash scripts/check-version-drift.sh` exits 0 against the post-edit working tree
- 7 successive `bash install.sh < /dev/null` runs leave exactly 5 backup directories

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
