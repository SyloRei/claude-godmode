# Directory Structure

**Analysis Date:** 2026-04-25

## Top-level layout

```
claude-godmode/
├── install.sh                  ← installer entry point (v1.4.1)
├── uninstall.sh                ← uninstaller entry point
├── README.md                   ← user-facing docs (~18 KB)
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── LICENSE                     ← MIT
├── .gitignore
│
├── rules/                      ← always-on context, copied to ~/.claude/rules/
│   └── godmode-*.md            ← 8 files, one per concern
│
├── agents/                     ← subagent definitions, copied to ~/.claude/agents/ (manual mode)
│   └── *.md                    ← 8 agents, YAML frontmatter + system prompt
│
├── skills/                     ← slash commands, copied to ~/.claude/skills/ (manual mode)
│   ├── _shared/                ← reusable markdown fragments
│   ├── prd/SKILL.md
│   ├── plan-stories/SKILL.md
│   ├── execute/SKILL.md
│   ├── ship/SKILL.md
│   ├── debug/SKILL.md
│   ├── tdd/SKILL.md
│   ├── refactor/SKILL.md
│   └── explore-repo/SKILL.md
│
├── commands/                   ← lighter-weight slash commands
│   └── godmode.md              ← /godmode (quick reference + statusline setup)
│
├── hooks/                      ← shell hooks invoked by Claude Code lifecycle events
│   ├── hooks.json              ← plugin-mode hook bindings (uses ${CLAUDE_PLUGIN_ROOT})
│   ├── session-start.sh        ← SessionStart hook
│   └── post-compact.sh         ← PostCompact hook
│
├── config/                     ← settings template + statusline
│   ├── settings.template.json  ← merged into ~/.claude/settings.json by install.sh
│   └── statusline.sh           ← statusline renderer
│
├── .claude-plugin/             ← plugin metadata for Claude Code plugin registry
│   └── plugin.json             ← name, version, repo, keywords
│
├── .github/                    ← GitHub-only metadata (issue templates, PR template)
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   ├── feature_request.yml
│   │   └── config.yml
│   └── PULL_REQUEST_TEMPLATE.md
│
├── .claude-pipeline/           ← THIS REPO's own pipeline state for self-development
│   ├── stories.json            ← active story plan
│   ├── progress.txt            ← agent progress log
│   ├── prds/                   ← historical and active PRDs (8 files)
│   ├── archive/                ← archived completed cycles (8 dirs, 296 KB)
│   └── .claude/agent-memory/
│
├── .claude/                    ← local Claude Code working state (NOT distributed)
│   ├── worktrees/              ← agent isolation worktrees (~27 dirs, ~6.4 MB)
│   └── agent-memory/
│
└── .planning/                  ← codebase mapping output (this directory)
    └── codebase/
```

## Key locations

### What gets distributed to users

These dirs are copied into `~/.claude/` (manual mode) or served from `${CLAUDE_PLUGIN_ROOT}` (plugin mode):

- `rules/` — `godmode-coding.md`, `godmode-context.md`, `godmode-git.md`, `godmode-identity.md`, `godmode-quality.md`, `godmode-routing.md`, `godmode-testing.md`, `godmode-workflow.md`
- `agents/` — `architect.md`, `doc-writer.md`, `executor.md`, `researcher.md`, `reviewer.md`, `security-auditor.md`, `test-writer.md`, `writer.md`
- `skills/` — 8 skill directories, each with a `SKILL.md`
- `commands/` — `godmode.md`
- `hooks/session-start.sh`, `hooks/post-compact.sh`
- `config/statusline.sh`
- The merge result of `config/settings.template.json` into `~/.claude/settings.json`

### What does NOT get distributed

These exist for repo development, not for end users:

- `.claude/` — local agent worktrees and memory (gitignored conceptually; large, ~6.4 MB)
- `.claude-pipeline/` — this repo's own self-development pipeline state (gitignored via `.gitignore` line 6)
- `.planning/` — codebase analysis output (this directory)
- `.github/` — GitHub UI metadata only
- `install.sh`, `uninstall.sh`, `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `LICENSE`

### Configuration

| File | Role |
|---|---|
| `config/settings.template.json` | Source of truth for permissions allow/deny lists, statusLine command, hook bindings (manual mode). |
| `hooks/hooks.json` | Plugin-mode hook bindings using `${CLAUDE_PLUGIN_ROOT}/hooks/...`. |
| `.claude-plugin/plugin.json` | Plugin metadata for Claude Code plugin registry: name `claude-godmode`, version `1.6.0`, author `sylorei`, license MIT, keywords. |

### Entry-point scripts

| File | Lines | Role |
|---|---|---|
| `install.sh` | 231 | Installs/upgrades, supports plugin + manual modes, backs up prior state. Requires `jq`. |
| `uninstall.sh` | 159 | Targeted removal. Optionally restores `settings.json` from latest backup. |
| `hooks/session-start.sh` | 117 | SessionStart hook: detects project type, git branch, pipeline state. |
| `hooks/post-compact.sh` | 74 | PostCompact hook: re-injects quality gates, skills, agents, pipeline state. |
| `config/statusline.sh` | 78 | Statusline renderer: project, branch, model, ctx%, cost. |

### Skill structure

Every skill is a directory with a `SKILL.md`. Sizes (lines):

| Skill | File | Lines |
|---|---|---|
| `/debug` | `skills/debug/SKILL.md` | 180 |
| `/execute` | `skills/execute/SKILL.md` | 365 |
| `/explore-repo` | `skills/explore-repo/SKILL.md` | 196 |
| `/plan-stories` | `skills/plan-stories/SKILL.md` | 273 |
| `/prd` | `skills/prd/SKILL.md` | 210 |
| `/refactor` | `skills/refactor/SKILL.md` | 196 |
| `/ship` | `skills/ship/SKILL.md` | 165 |
| `/tdd` | `skills/tdd/SKILL.md` | 177 |

Shared fragments live in `skills/_shared/`:
- `skills/_shared/gitignore-management.md`
- `skills/_shared/pipeline-context.md`

### Agent structure

Each agent is a single markdown file with YAML frontmatter declaring `model`, `tools`, `isolation`, `memory`, `effort`, `maxTurns`, `disallowedTools`, `background`, etc.

| Agent | File | Model | Notes |
|---|---|---|---|
| `@writer` | `agents/writer.md` | opus | isolation: worktree, maxTurns: 100 |
| `@executor` | `agents/executor.md` | opus | isolation: worktree, maxTurns: 100, stories.json-aware |
| `@architect` | `agents/architect.md` | opus | read-only (`disallowedTools: Write, Edit`) |
| `@security-auditor` | `agents/security-auditor.md` | opus | read-only, +WebSearch |
| `@reviewer` | `agents/reviewer.md` | sonnet | read-only |
| `@test-writer` | `agents/test-writer.md` | sonnet | isolation: worktree, maxTurns: 80 |
| `@doc-writer` | `agents/doc-writer.md` | sonnet | +Bash |
| `@researcher` | `agents/researcher.md` | sonnet | background, read-only |

## Naming conventions

- **Rule files:** `godmode-<concern>.md`, lowercase + hyphen, no frontmatter.
- **Agent files:** `<role>.md`, lowercase + hyphen, with YAML frontmatter; agents are referenced as `@<role>`.
- **Skill files:** `skills/<command>/SKILL.md`; skills are referenced as `/<command>`.
- **Hook scripts:** `<event>-<modifier>.sh`, lowercase + hyphen (`session-start.sh`, `post-compact.sh`).
- **Shell variable casing:** `UPPER_SNAKE_CASE` for constants, `lower_snake_case` for derived/local.
- **Scripts use `#!/usr/bin/env bash`** + `set -euo pipefail`.
- **Config keys** in JSON use `camelCase` (`includeCoAuthoredBy`, `statusLine`, `hookSpecificOutput`).

## Where to look for X

| Question | File(s) |
|---|---|
| "What does godmode tell Claude to do by default?" | `rules/godmode-*.md` |
| "How does an agent get spawned?" | `agents/*.md` (defs) + `skills/execute/SKILL.md` (orchestration) |
| "How does install behave on upgrade?" | `install.sh:43-113` (backup + v1.x migration + rule install) |
| "What permissions does godmode add?" | `config/settings.template.json:7-89` |
| "Why does my session start with project context?" | `hooks/session-start.sh` |
| "Why does context come back after compaction?" | `hooks/post-compact.sh` |
| "How is the statusline drawn?" | `config/statusline.sh` |
| "What's the canonical pipeline?" | `commands/godmode.md` (Quick Reference) |

---

*Structure analysis: 2026-04-25*
