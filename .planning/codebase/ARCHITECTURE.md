# Architecture

**Analysis Date:** 2026-04-25

## Pattern

**Configuration / extension distribution for Claude Code.**

`claude-godmode` is not an application. It is a packaged set of files (rules, agents, skills, commands, hooks, statusline, permissions) installed into a user's Claude Code config directory (`~/.claude/`) so that Claude Code itself behaves a specific way during sessions.

The architecture is two-sided:
1. **Distribution side** (this repo): authoring + an installer that copies files into the right places.
2. **Runtime side** (Claude Code, on the user's machine): Claude Code loads those files at session start and during specific lifecycle events (compaction, statusline render).

There is no server, no daemon, no compiled artifact. The "behavior" of godmode emerges from Claude Code reading these files.

## Two installation modes

Both modes are handled by `install.sh` and detected via the `CLAUDE_PLUGIN_ROOT` env var.

| Mode | Trigger | What gets copied |
|---|---|---|
| **plugin** | `CLAUDE_PLUGIN_ROOT` is set (Claude Code plugin loader) | `rules/` → `~/.claude/rules/`; permissions merged into `~/.claude/settings.json`. Agents/skills/hooks/statusline are served by the plugin loader from this repo's source dir, NOT copied. |
| **manual** | `CLAUDE_PLUGIN_ROOT` is unset (user runs `./install.sh` directly) | `rules/`, `agents/`, `skills/`, `hooks/session-start.sh`, `hooks/post-compact.sh`, `config/statusline.sh` all copied into `~/.claude/`; full `settings.template.json` (permissions + hooks + statusLine) merged into `~/.claude/settings.json`. |

Plugin metadata for plugin mode is declared in `.claude-plugin/plugin.json`. Hook bindings for plugin mode are declared in `hooks/hooks.json` (uses `${CLAUDE_PLUGIN_ROOT}/hooks/...` paths). Hook bindings for manual mode live inside `config/settings.template.json` (uses `~/.claude/hooks/...` paths).

## Layers

```
┌──────────────────────────────────────────────────────────┐
│ User's Claude Code session                               │
│                                                          │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│   │ Rules        │  │ Hooks        │  │ Statusline   │  │
│   │ (always-on   │  │ (event-      │  │ (per-render  │  │
│   │  context)    │  │  driven      │  │  shell exec) │  │
│   │              │  │  shell exec) │  │              │  │
│   └──────────────┘  └──────────────┘  └──────────────┘  │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│   │ Agents       │  │ Skills       │  │ Commands     │  │
│   │ (Task-spawn  │  │ (slash-      │  │ (slash-      │  │
│   │  subagents)  │  │  invocable)  │  │  invocable)  │  │
│   └──────────────┘  └──────────────┘  └──────────────┘  │
└──────────────────────────────────────────────────────────┘
                          ▲
                          │ loaded from
                          │
┌──────────────────────────────────────────────────────────┐
│ ~/.claude/  (manual mode)        OR                      │
│ this repo via CLAUDE_PLUGIN_ROOT (plugin mode)           │
└──────────────────────────────────────────────────────────┘
                          ▲
                          │ installed by
                          │
┌──────────────────────────────────────────────────────────┐
│ install.sh   (this repo, run by user)                    │
└──────────────────────────────────────────────────────────┘
```

### 1. Distribution layer (this repo)

- **Authoring:** `rules/`, `agents/`, `skills/`, `commands/`, `hooks/`, `config/` are all hand-edited markdown / shell / JSON.
- **Packaging:** `.claude-plugin/plugin.json` declares the plugin for the Claude Code plugin registry.
- **Installation:** `install.sh` (idempotent, with backup) and `uninstall.sh` (targeted removal).

### 2. Runtime layer (inside a Claude Code session)

The installed files take effect at four touchpoints:

| Touchpoint | Files involved | What happens |
|---|---|---|
| **Always-on context** | `rules/godmode-*.md` | Loaded into every session by Claude Code's rules system. Defines identity, coding standards, quality gates, routing, workflow phases. |
| **SessionStart** | `hooks/session-start.sh` | Detects project type (`package.json`, `Cargo.toml`, etc.), git branch, recent commits, `.claude-pipeline/` state. Returns JSON with `additionalContext` to inject into the session. |
| **PostCompact** | `hooks/post-compact.sh` | Re-injects project info, quality gates, available skill/agent lists, and pipeline state after the session compacts (so context loss doesn't break workflow). |
| **Statusline render** | `config/statusline.sh` | Receives session JSON via stdin (model, cost, context %, cwd) and prints a colorized one-line status string. |
| **Slash commands** | `commands/godmode.md`, `skills/*/SKILL.md` | User types `/godmode`, `/prd`, `/plan-stories`, `/execute`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`. Each is a markdown file with frontmatter + instructions. |
| **Agent invocation** | `agents/*.md` | Skills (notably `/execute`) spawn agents (`@executor`, `@reviewer`, `@architect`, etc.) via Claude Code's subagent system. Each agent file declares model, tools, isolation, memory in YAML frontmatter. |

## Data flow

### Install-time data flow

```
user runs ./install.sh
  ├─ preflight: check jq, ~/.claude/ exists
  ├─ detect MODE (plugin vs manual via $CLAUDE_PLUGIN_ROOT)
  ├─ backup ~/.claude/rules + ~/.claude/settings.json → ~/.claude/backups/godmode-<timestamp>/
  ├─ v1.x migration check (offer to remove old CLAUDE.md / INSTRUCTIONS.md)
  ├─ copy rules/godmode-*.md → ~/.claude/rules/
  ├─ jq-merge config/settings.template.json into ~/.claude/settings.json
  │     (plugin mode merges only permissions; manual mode merges permissions+hooks+statusLine)
  ├─ if MODE=manual:
  │     ├─ copy agents/*.md → ~/.claude/agents/
  │     ├─ copy skills/*/ → ~/.claude/skills/
  │     └─ copy hooks/{session-start,post-compact}.sh + config/statusline.sh → ~/.claude/hooks/
  └─ write VERSION to ~/.claude/.claude-godmode-version
```

### Runtime data flow (per Claude Code session)

```
Claude Code starts
  ├─ loads ~/.claude/settings.json (permissions, hooks bindings, statusLine command)
  ├─ loads ~/.claude/rules/godmode-*.md (always-on system prompts)
  ├─ fires SessionStart hook → bash session-start.sh < {hookInputJSON}
  │     └─ outputs {hookSpecificOutput.additionalContext} (project, branch, pipeline state)
  ├─ statusline command runs on each render: bash statusline.sh < {sessionMetaJSON}
  │     └─ prints colored line (project, branch, model, ctx%, cost)
  └─ during long sessions, on compaction:
        fires PostCompact hook → bash post-compact.sh < {hookInputJSON}
              └─ outputs {hookSpecificOutput.additionalContext} (re-inject quality gates, skills, agents)
```

### Feature pipeline data flow (the canonical workflow)

```
/prd              → writes .claude-pipeline/prds/prd-<slug>.md
  ↓
/plan-stories     → reads PRD, writes .claude-pipeline/stories.json
  ↓
/execute          → reads stories.json, spawns @executor + @reviewer per story (sequential or parallel by dependsOn),
                    runs quality gates, commits, marks story passes:true
  ↓
/ship             → final quality gates, push, gh pr create
```

State for the pipeline lives in `.claude-pipeline/` inside each *consumer* project (not this repo's own pipeline state, which is `.claude-pipeline/` here used for self-development).

## Abstractions

| Abstraction | Where defined | Purpose |
|---|---|---|
| **Rule file** | `rules/godmode-*.md` (no frontmatter) | Always-on context. One concern per file (`-identity`, `-coding`, `-testing`, `-quality`, `-routing`, `-workflow`, `-context`, `-git`). |
| **Agent** | `agents/<name>.md` with YAML frontmatter | A specialized subagent with a model, tool allowlist, isolation, memory scope, and a system prompt. |
| **Skill** | `skills/<name>/SKILL.md` with YAML frontmatter | A user-invocable workflow (slash command). May spawn agents. |
| **Shared skill content** | `skills/_shared/*.md` | Reusable doc fragments (e.g., `pipeline-context.md`) referenced by multiple skills. |
| **Command** | `commands/<name>.md` with YAML frontmatter | A simpler slash command (e.g., `/godmode` shows quick reference + statusline setup). |
| **Hook** | shell script + JSON binding (`hooks/hooks.json` for plugin mode, `config/settings.template.json` for manual mode) | Event handler that emits `hookSpecificOutput` JSON. |
| **Statusline script** | `config/statusline.sh` | Pure stdin-JSON-in / stdout-text-out renderer. |

## Entry points

| Entry point | Triggered by | Path |
|---|---|---|
| `install.sh` | User shell | `install.sh` |
| `uninstall.sh` | User shell | `uninstall.sh` |
| `session-start.sh` | Claude Code SessionStart event | `hooks/session-start.sh` |
| `post-compact.sh` | Claude Code PostCompact event | `hooks/post-compact.sh` |
| `statusline.sh` | Claude Code statusline render (every redraw) | `config/statusline.sh` |
| `/godmode` | User slash command | `commands/godmode.md` |
| `/prd`, `/plan-stories`, `/execute`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo` | User slash commands | `skills/*/SKILL.md` |
| `@writer`, `@executor`, `@architect`, `@security-auditor`, `@reviewer`, `@test-writer`, `@doc-writer`, `@researcher` | Spawned by skills via Claude Code Task tool | `agents/*.md` |

## Lifecycle

```
[author commits to repo]
        │
        ▼
[user installs]   ./install.sh        (copies files, merges settings.json, backs up prior state)
        │
        ▼
[user starts a Claude Code session]
        │   SessionStart hook fires once
        │   rules/ loaded as always-on context
        │   statusline renders continuously
        ▼
[user invokes a workflow]
        │   /prd → /plan-stories → /execute → /ship
        │   /execute spawns @executor + @reviewer per story
        ▼
[long session triggers compaction]
        │   PostCompact hook re-injects critical context
        ▼
[user uninstalls]   ./uninstall.sh    (targeted removal, optional settings.json restore from backup)
```

## Why this shape

- **No build step.** Everything is plain text Claude Code can read directly. Fast iteration.
- **Two install modes.** Plugin mode is preferred (loader serves files in-place, easy upgrade). Manual mode exists for users not on the plugin registry.
- **Hooks output JSON, not raw text.** Claude Code's hook protocol expects `hookSpecificOutput.additionalContext`. Both `session-start.sh` and `post-compact.sh` emit conforming JSON.
- **Rules-based, not CLAUDE.md-based.** v1.x put behavior in a single `~/.claude/CLAUDE.md`. v1.4+ split into per-concern `rules/godmode-*.md` files (and migrates v1.x users automatically).

---

*Architecture analysis: 2026-04-25*
