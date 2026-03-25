# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
