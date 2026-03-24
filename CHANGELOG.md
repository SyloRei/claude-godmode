# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
