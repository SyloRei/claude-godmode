# claude-godmode

## What This Is

`claude-godmode` is a Claude Code plugin that ships an opinionated, end-to-end engineering workflow: rules, agents, skills, hooks, statusline, and permissions — installed into a user's Claude Code config so that Claude Code itself behaves like a senior engineering team. The current v1.x baseline has 8 agents, 8 skills, a `/prd → /plan-stories → /execute → /ship` pipeline, and a rules-based configuration system. This milestone (v2 — "polish mature version") matures it into the best-in-class general-purpose plugin for Claude Code.

## Core Value

**A single, clear workflow where every agent, skill, and tool is connected to the others and has a clearly described goal — best-in-class capability with simplest-possible usability.**

If everything else fails, this must hold: a user who installs claude-godmode gets one obvious workflow, runs it, and produces production-grade work — without having to assemble parts from three different plugins.

## Requirements

### Validated

<!-- Inherited from existing claude-godmode v1.x baseline (see .planning/codebase/ map). -->

- ✓ Rules-based configuration installed to `~/.claude/rules/godmode-*.md` — existing (8 rule files)
- ✓ 8 specialized subagents distributed (`@writer`, `@executor`, `@architect`, `@security-auditor`, `@reviewer`, `@test-writer`, `@doc-writer`, `@researcher`) — existing
- ✓ 8 user-invocable skills (`/prd`, `/plan-stories`, `/execute`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`) — existing
- ✓ `/godmode` slash command for quick reference and statusline setup — existing
- ✓ SessionStart hook injects project context — existing (`hooks/session-start.sh`)
- ✓ PostCompact hook re-injects critical context after compaction — existing (`hooks/post-compact.sh`)
- ✓ Statusline showing project / branch / model / context% / cost — existing (`config/statusline.sh`)
- ✓ Plugin-mode + manual-mode installer with backup, v1.x migration, version tracking — existing (`install.sh`)
- ✓ Targeted uninstaller with optional settings.json restore — existing (`uninstall.sh`)
- ✓ Permissions allow/deny lists merged into `~/.claude/settings.json` — existing (`config/settings.template.json`)
- ✓ Quality gates (typecheck / lint / tests / no-secrets / no-regressions / matches-requirements) enforced by `/execute` — existing
- ✓ MIT license, plugin metadata declared for Claude Code plugin registry — existing (`.claude-plugin/plugin.json`)

### Active

<!-- Hypotheses for v2. Each should become a roadmap requirement with REQ-ID. -->

**Modernization — leverage current Claude Code surface area**
- [ ] Adopt Opus 4.7 by default for high-leverage agents; offer Sonnet 4.6 / Haiku 4.5 fallbacks
- [ ] Support Extra High effort for design/architecture agents
- [ ] Recognize and explain Auto Mode in rules, skills, and PostCompact context
- [ ] Replace bespoke pipeline (`.claude-pipeline/` + `stories.json`) with — or interoperate with — the current Claude Code primitives (TaskCreate/TaskList, AskUserQuestion, ScheduleWakeup, etc.) where they reduce surface area
- [ ] Prompt-cache-aware agent prompts (system prompts, tool definitions, persistent rules placed in cache-friendly positions)

**GSD parity — single source of truth for the workflow**
- [ ] Workflow vocabulary aligned to GSD: project → milestone → roadmap → phase → plan → task
- [ ] `.planning/` directory replacing or complementing `.claude-pipeline/` (PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, phases/, codebase/, research/)
- [ ] Phase lifecycle: discuss → spec → plan → execute → verify → secure → ship
- [ ] Atomic-commit discipline at every workflow gate
- [ ] Goal-backward verification (every phase goal traceable from a requirement and verified after execution)

**Best-of-breed integration — Superpowers + everything-claude-code**
- [ ] Audit Superpowers for high-value patterns (e.g. structured thinking, delegation idioms, persistent skills) and integrate the best fits without bloating the surface
- [ ] Audit everything-claude-code for missing primitives (e.g. statusline variants, hook patterns, MCP integrations) and adopt selectively
- [ ] Keep total user-facing slash-command count small (target: ≤ 12 user-invocable skills); merge or hide internals
- [ ] Every agent, skill, and command must declare its goal and its upstream/downstream connections in a one-line "Connects to:" field

**Simplicity & wholeness — the plugin must feel like one thing, not a kit**
- [ ] One canonical "happy path" documented in README and `/godmode`
- [ ] Internal agents (orchestrators, helpers) hidden from the slash-command surface; only meaningful user actions exposed
- [ ] Every skill links to the next skill in the workflow (forward arrow) and the upstream skill (back arrow)
- [ ] One `/godmode` reference command lists every public agent and skill with: model, effort, goal, connects to, isolation
- [ ] First-run UX: `./install.sh` followed by `/godmode` answers "what do I do next?" within five lines

**Quality & safety — the polish part**
- [ ] Address every concern from `.planning/codebase/CONCERNS.md` rated High
- [ ] Plugin metadata version (`plugin.json` 1.6.0), installer version (`install.sh` 1.4.1), and `commands/godmode.md` version unified to a single source of truth
- [ ] Hooks emit valid JSON under adversarial inputs (shell-meaningful chars in branch names, commit messages, paths)
- [ ] Installer prompts before overwriting customized rule / agent / skill files; per-file diff/skip/replace
- [ ] Backup rotation (keep last N) and worktree pruning recipe in CONTRIBUTING.md
- [ ] CI: at minimum `shellcheck` on every `*.sh`, JSON-schema-validate every `*.json`, frontmatter-lint every agent/skill markdown
- [ ] Smoke-test the install→use→uninstall round trip in CI on macOS + Linux

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- **Windows native shell support (cmd / PowerShell)** — WSL2 remains the supported path; native PowerShell ports are a separate effort with non-trivial cost and currently no validated demand.
- **Vendored copies of GSD, Superpowers, or everything-claude-code** — we integrate ideas, not code; doing so would invert the dependency direction and create license/maintenance burden.
- **A custom MCP server bundled with the plugin** — keep the plugin shape pure (rules, agents, skills, hooks, statusline, permissions); MCP servers can be referenced but live elsewhere.
- **Cloning the GSD `.planning/` schema verbatim if it conflicts with simplicity** — adopt the spirit and the artifact set, but allow this plugin to deviate from GSD's CLI tooling (`gsd-sdk`) if a simpler shape serves users better.
- **Domain-specific scaffolding (Next.js starters, Rails templates, etc.)** — this plugin shapes how Claude works, not what users build.
- **A graphical UI / dashboard** — the surface is the terminal; the statusline is the only visual primitive.
- **Backwards compatibility for v1.x users beyond a one-time migration path** — v1.x → v2 will provide an installer migration, but the v2 workflow is the canonical surface; old `/prd` / `/plan-stories` shapes may change.

## Context

**Existing baseline.** Claude-godmode v1.x is already shipped (plugin metadata claims 1.6.0; installer says 1.4.1 — version drift is one of the v2 cleanup items). The full codebase map lives in `.planning/codebase/` (STACK, ARCHITECTURE, STRUCTURE, CONVENTIONS, INTEGRATIONS, TESTING, CONCERNS). Treat that as the v1 surface to mature.

**Reference plugins.** GSD (Get Shit Done) is the primary structural reference: its phase-based workflow, atomic commits, and goal-backward verification are the spine of v2. Superpowers and everything-claude-code are secondary references for patterns and primitives; we audit them, take the best, and stay simpler.

**Current Claude Code primitives we should leverage (knowledge cutoff Jan 2026).**
- Opus 4.7, Sonnet 4.6, Haiku 4.5 model lineup
- Auto Mode (continuous autonomous execution) — should be discoverable in our docs and respected by skills
- Effort levels: default / high / extra high
- Prompt caching (5-minute TTL) — agent prompt structure should maximize hits
- TaskCreate / TaskList / TaskUpdate primitives in the harness
- AskUserQuestion / EnterPlanMode / ScheduleWakeup as workflow gates
- Subagent spawning with `run_in_background` and `TaskOutput` for parallel work
- MCP servers (Context7, Chrome DevTools, Playwright) as standardized capability extensions
- Hooks: SessionStart, PostCompact, plus newer events that may have appeared since v1

**Known concerns.** From the codebase map: install/uninstall safety holes, hook fragility under adversarial inputs (unescaped JSON interpolation), version drift across `plugin.json` / `install.sh` / `commands/godmode.md`, no automated test suite, hardcoded skill/agent lists that drift from the actual filesystem, and accumulating backups/worktrees with no pruning. v2 must address every one rated High in `.planning/codebase/CONCERNS.md`.

**No prior `.planning/` GSD setup.** This is the first GSD-shaped milestone for this repo. Phase numbering starts at 1.

## Constraints

- **Tech stack** — Bash 3.2+, jq, Markdown, JSON, YAML; no compiled artifacts. Stay shell-portable across macOS and Linux. New v2 work may add Python/Node helpers ONLY if they ship with a pure-shell fallback or are clearly optional.
- **Distribution** — must remain installable as a Claude Code plugin (plugin mode, via plugin registry) AND via direct shell install (manual mode). Both paths must produce equivalent UX.
- **Dependencies** — the only required runtime tool is `jq`; everything else (`shellcheck`, `bats`, etc.) is dev-time. No new mandatory runtime deps.
- **Surface area** — target ≤ 12 user-invocable slash commands. Every additional skill must justify its existence over composing existing ones.
- **Compatibility** — v1.x installs must be upgradable via `./install.sh` without manual intervention; downgrade is best-effort.
- **License** — MIT, no copyleft dependencies, no vendored code from differently-licensed sources.
- **Single source of truth for version** — `plugin.json` is canonical; everything else reads from it.
- **Documentation parity** — README, CHANGELOG, and `/godmode` quick reference must always agree on the public surface (agents, skills, version).
- **No telemetry, no network calls at install or runtime** — except via tools the user already authorized (e.g., `git`, `gh`, MCP servers they configured).
- **Atomic commits per workflow gate** — every phase, every artifact change is its own commit; hooks must never bypass `--no-verify`.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| GSD as primary structural reference (not Superpowers, not everything-claude-code) | GSD's phase-based discipline (project → milestone → phase → plan → task) is the cleanest mental model and matches the user's stated goal of one clear workflow. Superpowers is broader / more eclectic; everything-claude-code is more of a kit. | — Pending validation in research phase |
| Adopt `.planning/` directory shape and artifact set (PROJECT, REQUIREMENTS, ROADMAP, STATE, phases/) | Aligns with GSD; gives the plugin a documented home for context that survives compaction; supersedes `.claude-pipeline/` long-term. | — Pending — interop path with `.claude-pipeline/` to be designed in research/discuss phase |
| Default agent model: Opus 4.7 for high-leverage agents (architect, executor, security-auditor, writer); Sonnet 4.6 for review/test/research; Haiku 4.5 for trivially-bounded helpers | Matches Anthropic's current strongest tier and the cost / quality / latency tradeoff for each role. Lets `/gsd-set-profile`-style overrides flip the whole tree. | — Pending |
| Hidden internal agents, exposed user-facing skills | Surface-area minimization is a top-line goal; users should see ≤ 12 commands; orchestrators stay invisible behind composed skills. | — Pending |
| Single source of truth for version: `.claude-plugin/plugin.json` | Eliminates the 1.6.0 / 1.4.1 / 1.4.1 drift currently across three files. Installer and `/godmode` will read from it. | — Pending |
| Keep `jq` as the only mandatory runtime dep | Adding Python or Node would increase install friction and break Bash-only environments; users already need jq for Claude Code itself. | — Pending |
| Phase numbering starts at 1 (no `--reset-phase-numbers` needed) | First GSD-shaped milestone for this repo; clean slate. | ✓ Decided |
| Treat `.planning/codebase/CONCERNS.md` items rated High as v1 (this milestone) requirements | The user's goal includes "polish mature version" — concerns are precisely what polish means. | ✓ Decided |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-25 after initialization (milestone v2 — "polish mature version")*
