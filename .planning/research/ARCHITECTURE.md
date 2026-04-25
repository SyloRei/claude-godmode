# Architecture — claude-godmode v2

**Domain:** Claude Code plugin (configuration / extension distribution)
**Researched:** 2026-04-26 (re-init under inspiration-only principle)
**Milestone:** v2 — polish mature version (brownfield maturation of v1.x)
**Confidence:** HIGH (architecture is constrained by locked Key Decisions in `.planning/PROJECT.md` and the v1.x baseline in `.planning/codebase/`)

## TL;DR

v2 keeps v1.x's two-sided shape (distribution repo + runtime files in `~/.claude/`) and its layered primitives (rules / hooks / agents / skills / commands / statusline / permissions). What changes:

1. **A new workflow vocabulary** (Project → Mission → Brief → Plan → Commit) replaces the v1.x flat `/prd → /plan-stories → /execute → /ship` pipeline. The user-facing surface contracts to **11 commands** (one slot reserved under the ≤12 cap).
2. **A clean internal/user split.** All orchestration agents (`@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`, plus the existing `@architect`, `@executor`, `@security-auditor`, `@test-writer`, `@doc-writer`, `@researcher`, `@writer`) are **invoked by skills, never by the user**. The user types only the 11 slash commands.
3. **Two artifact files per active brief** (`BRIEF.md` + `PLAN.md`) instead of v1.x's split state across `.claude-pipeline/prds/*.md` + `.claude-pipeline/stories.json`. `git log` IS the execution log — no `EXECUTE.md`, no `TASK.md`.
4. **A foundation-first build order.** Hooks, installer, and version single-source-of-truth must be hardened before agents/skills can be safely rebuilt on top.
5. **Live filesystem indexing.** `/godmode`, `PostCompact`, and `SessionStart` enumerate `agents/`, `skills/`, `briefs/` from disk at runtime — no hardcoded lists ever again.
6. **Plugin-mode == manual-mode UX**, generated from one source: `config/settings.template.json` is the canonical permissions / hook / statusline declaration; `hooks/hooks.json` is plugin-mode's mirror of the same hook bindings with `${CLAUDE_PLUGIN_ROOT}` paths.

## The Two-Sided Shape (Unchanged from v1.x)

```
┌──────────────────────────────────────────────────────────────────┐
│ DISTRIBUTION SIDE — this repo                                    │
│                                                                  │
│   rules/     hooks/     agents/    skills/    commands/  config/ │
│   .claude-plugin/plugin.json   install.sh   uninstall.sh         │
└─────────────────────────────────┬────────────────────────────────┘
                                  │ install.sh
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│ RUNTIME SIDE — user's machine                                    │
│                                                                  │
│   plugin mode:  served from ${CLAUDE_PLUGIN_ROOT} (this repo)    │
│   manual mode:  copied into ~/.claude/{rules,agents,skills,...}  │
│                                                                  │
│   permissions + hook bindings + statusline merged into           │
│   ~/.claude/settings.json (idempotent jq merge, with backup)     │
└─────────────────────────────────┬────────────────────────────────┘
                                  │ Claude Code reads at session start
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│ SESSION SIDE — inside a Claude Code session in a consumer repo   │
│                                                                  │
│   rules → always-on context                                      │
│   hooks → SessionStart, PostCompact, PreToolUse, PostToolUse     │
│   agents → spawned by skills via Task tool                       │
│   skills/commands → user-invocable workflow                      │
│   statusline → per-render renderer                               │
│                                                                  │
│   workflow state lives in <consumer-repo>/.planning/             │
└──────────────────────────────────────────────────────────────────┘
```

This three-tier shape is settled. v2 changes _what's inside_ each tier and _how the pieces talk to each other_, not the tier structure itself.

## Layer Model (v2)

Each new v2 component slots into exactly one of these layers. The placement rules are non-negotiable.

| # | Layer | What it is | Location | Loaded by | New in v2? |
|---|-------|-----------|----------|-----------|------------|
| 1 | **Plugin manifest** | Plugin metadata + canonical version | `.claude-plugin/plugin.json` | Claude Code plugin loader; `install.sh` reads via `jq` | Hardened (single version source) |
| 2 | **Rules (always-on context)** | Identity, coding standards, quality gates, routing, workflow shape | `rules/godmode-*.md` (no frontmatter) | Claude Code rules system, every session | New file: `godmode-workflow.md` rewritten for Project→Mission→Brief→Plan→Commit |
| 3 | **Hooks (event handlers)** | Shell scripts emitting `hookSpecificOutput` JSON | `hooks/*.sh` + `hooks/hooks.json` (plugin) + `config/settings.template.json` (manual) | Claude Code on lifecycle events | Two new hooks: `pre-tool-use.sh`, `post-tool-use.sh` |
| 4 | **Statusline** | Per-render shell renderer | `config/statusline.sh` | Claude Code statusline event | Hardened (single `jq` invocation) |
| 5 | **Permissions** | allow/deny lists merged into `settings.json` | `config/settings.template.json` | `install.sh` via `jq` merge | Reviewed, not restructured |
| 6 | **Agents (internal — orchestration units)** | Subagents with model/tools/isolation/effort frontmatter | `agents/*.md` | Spawned by skills via Task tool | New: `@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer` (split from `@reviewer`) |
| 7 | **Skills (user-facing — workflow units)** | Slash commands with frontmatter + instructions | `skills/<name>/SKILL.md` | User types `/<name>` | New shape: `/mission`, `/brief`, `/plan`, `/build`, `/verify`. v1's `/prd`, `/plan-stories`, `/execute` removed (one-time deprecation note) |
| 8 | **Commands (user-facing — lighter slash)** | Quick-reference / utility slash commands | `commands/<name>.md` | User types `/<name>` | `commands/godmode.md` rewritten; live-indexes filesystem |
| 9 | **Shared skill content** | Reusable doc fragments + bash helpers | `skills/_shared/*.md`, `skills/_shared/*.sh` | Skills reference / source | New: `skills/_shared/init-context.sh` (bash + jq, reads `.planning/config.json`) |
| 10 | **Planning artifacts (consumer-side state)** | Templates + the live state files in user projects | `templates/.planning/*` (this repo) → `<consumer>/.planning/*` (user project) | `/mission` / `/brief` / `/plan` skills | New layer entirely — v1.x had `.claude-pipeline/` only |

### Where each new v2 component goes

| New thing | Layer | Path |
|-----------|-------|------|
| `@planner` agent | Agents (internal) | `agents/planner.md` |
| `@verifier` agent | Agents (internal) | `agents/verifier.md` |
| `@spec-reviewer` agent | Agents (internal) | `agents/spec-reviewer.md` |
| `@code-reviewer` agent | Agents (internal) | `agents/code-reviewer.md` |
| `/mission` skill | Skills (user-facing) | `skills/mission/SKILL.md` |
| `/brief` skill | Skills (user-facing) | `skills/brief/SKILL.md` |
| `/plan` skill | Skills (user-facing) | `skills/plan/SKILL.md` |
| `/build` skill | Skills (user-facing) | `skills/build/SKILL.md` |
| `/verify` skill | Skills (user-facing) | `skills/verify/SKILL.md` |
| `/ship` skill | Skills (user-facing) | `skills/ship/SKILL.md` (rewritten) |
| `/godmode` command | Commands (user-facing) | `commands/godmode.md` (rewritten — live filesystem index) |
| `pre-tool-use.sh` | Hooks | `hooks/pre-tool-use.sh` |
| `post-tool-use.sh` | Hooks | `hooks/post-tool-use.sh` |
| `init-context.sh` | Shared | `skills/_shared/init-context.sh` |
| `quality-gates.txt` | Config (single source) | `config/quality-gates.txt` |
| Frontmatter linter | Dev tooling | `scripts/lint-frontmatter.sh` |
| `.planning/` templates | New layer | `templates/.planning/{PROJECT,REQUIREMENTS,ROADMAP,STATE}.md.tmpl`, `templates/.planning/config.json.tmpl`, `templates/.planning/briefs/_template/{BRIEF,PLAN}.md.tmpl` |
| Workflow rule rewrite | Rules | `rules/godmode-workflow.md` (rewritten) |
| Routing rule update | Rules | `rules/godmode-routing.md` (effort policy: code-writers=`high`, design/audit=`xhigh`) |

## User-Facing Surface (the 11 commands — all of them, in order)

This is the entire user surface. **Anything not on this list is internal.**

```
Discovery / status:
  /godmode              ← reads filesystem live; renders chain; "what now?" in 5 lines

Workflow chain (linear arrow, with N = brief number):
  /mission              ← define the milestone (mutates .planning/PROJECT.md, REQUIREMENTS.md, ROADMAP.md)
  /brief N              ← Socratic context-gathering for brief N (mutates .planning/briefs/NN-name/BRIEF.md)
  /plan N               ← tactical breakdown of brief N (mutates .planning/briefs/NN-name/PLAN.md)
  /build N              ← parallel worktree-isolated execution (mutates code + git log + PLAN.md task status)
  /verify N             ← read-only goal-backward verification (mutates PLAN.md verification block)
  /ship                 ← final gates + push + gh pr create

Helpers (forks off the main chain):
  /debug                ← targeted bug-hunt with @architect + @executor
  /tdd                  ← red→green→refactor with @test-writer + @executor
  /refactor             ← scope-bounded restructure with @architect + @executor
  /explore-repo         ← @researcher-driven codebase mapping (writes to .planning/codebase/)

Reserved: 1 slot under the ≤12 cap (likely /resume or /audit in v2.x)
```

Internal agents (`@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`, `@architect`, `@executor`, `@writer`, `@security-auditor`, `@test-writer`, `@doc-writer`, `@researcher`) are **never typed by the user**. They are spawned by the skills above via Claude Code's Task tool.

## Component Boundaries — What Talks to What

The `Connects to:` line in every skill / agent frontmatter is the canonical, machine-readable boundary. Below is the human-readable map.

### Skill → Agent invocation matrix

| Skill | Spawns (in order) | Mutates | Reads |
|-------|-------------------|---------|-------|
| `/mission` | `@architect` (xhigh, read-only) → `@spec-reviewer` (sonnet, read-only) | `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md` | `.planning/codebase/*` if present |
| `/brief N` | `@researcher` (sonnet, background) → `@architect` (xhigh, read-only) → `@spec-reviewer` (sonnet, read-only) | `.planning/briefs/NN-name/BRIEF.md`, `.planning/STATE.md` | `.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `codebase/*` |
| `/plan N` | `@planner` (opus, xhigh, read-only) → `@spec-reviewer` (sonnet, read-only) | `.planning/briefs/NN-name/PLAN.md`, `.planning/STATE.md` | the brief's `BRIEF.md`, `PROJECT.md`, `codebase/*` |
| `/build N` | `@executor` (× N parallel, opus, high, isolation: worktree) → `@code-reviewer` (sonnet, read-only) per task | code in worktrees → merged commits, `.planning/briefs/NN-name/PLAN.md` (task status), `.planning/STATE.md` | `PLAN.md`, `BRIEF.md`, `rules/godmode-*.md` |
| `/verify N` | `@verifier` (opus, xhigh, read-only) | `.planning/briefs/NN-name/PLAN.md` (verification block), `.planning/STATE.md` | `BRIEF.md` (success criteria), `PLAN.md` tasks, `git log`, code |
| `/ship` | `@security-auditor` (opus, xhigh, read-only) → final quality-gate run → `gh pr create` | git remote, GitHub PR, `.planning/STATE.md` | latest verified brief |
| `/debug` | `@architect` (xhigh, read-only) → `@executor` (high, worktree) | code | bug repro, codebase |
| `/tdd` | `@test-writer` (sonnet, high, worktree) → `@executor` (high, worktree) | tests, code | spec |
| `/refactor` | `@architect` (xhigh, read-only) → `@executor` (high, worktree) | code | scope target |
| `/explore-repo` | `@researcher` (sonnet, background, read-only) | `.planning/codebase/*` | the repo |
| `/godmode` | (no agents — pure filesystem read) | nothing | `agents/*.md` frontmatter, `skills/*/SKILL.md` frontmatter, `.planning/STATE.md`, `.claude-plugin/plugin.json` |

### Agent → Agent rules

- **Agents do not spawn agents.** All fan-out is owned by skills. An agent's job is one step of one skill. This keeps the call graph a tree, not a DAG, and makes `/build`'s parallel orchestration debuggable.
- **Read-only agents (`disallowedTools: Write, Edit`)** can be safely run in `background: true` and in parallel without isolation. `@architect`, `@security-auditor`, `@spec-reviewer`, `@code-reviewer`, `@verifier`, `@researcher` are all read-only.
- **Code-writing agents (`@executor`, `@writer`, `@test-writer`)** declare `isolation: worktree` and run with `effort: high` (not `xhigh` — Routing rule lock; PITFALLS #4: xhigh on Opus 4.7 historically skips rules).
- **Persistent learners** declare `memory: project` (currently only `@architect` and `@researcher` justify this; revisit per-agent in Phase 2).

### `/build` parallel orchestration (the only fan-out skill)

This is the load-bearing concurrency primitive in v2. It deserves its own subsection.

```
/build N
  │
  ├─ read .planning/briefs/NN-name/PLAN.md
  ├─ parse tasks; partition into "waves" by dependsOn graph
  │
  ├─ for each wave:
  │     ├─ spawn @executor in parallel for each task in wave:
  │     │     each gets its own git worktree (isolation: worktree)
  │     │     each gets effort: high, maxTurns: 100
  │     │     each writes progress to .claude-pipeline/progress/<task-id>.log
  │     │     run_in_background: true; file-polling fallback if stdout race
  │     │
  │     ├─ wait for wave to complete (poll progress files OR notification)
  │     │
  │     ├─ spawn @code-reviewer (sonnet, read-only, sequential) for each task
  │     │
  │     ├─ run quality gates (typecheck/lint/tests/secrets) per task
  │     │
  │     ├─ on green: merge worktree commit; mark task done in PLAN.md; commit PLAN.md
  │     ├─ on red:   leave worktree; mark task failed; surface to user
  │
  └─ after all waves: emit "ready for /verify N"
```

This is the only place `run_in_background` + worktree isolation is used. All other skills are sequential. That's a deliberate complexity budget — concurrency is one component, not a pattern sprayed across the system.

## Data Flow — How Context Survives Sessions and Compaction

Five state vehicles carry context across time. They are listed in order of authority.

| Vehicle | Authority | Lifetime | Survives compaction? | Survives session end? |
|---------|-----------|----------|----------------------|------------------------|
| `git log` | Highest — the execution log | Forever | Yes (read fresh each session) | Yes |
| `.planning/PROJECT.md` | Project-scope source of truth (mission, requirements, key decisions) | Project lifetime | Yes (re-read on demand) | Yes |
| `.planning/STATE.md` | Live pointer to current brief + phase | Until next brief transition | Yes (read by `SessionStart` hook) | Yes |
| `.planning/briefs/NN-name/{BRIEF,PLAN}.md` | Per-brief artifact set | Until brief verified | Yes | Yes |
| `~/.claude/.claude-godmode-version` | Installed version stamp | Until next install | Yes (read by uninstaller) | Yes |

**Session-scoped state** (does not survive end-of-session):
- The current Claude Code session's transcript
- Subagent results (each subagent invocation is a fresh context — that's the point of isolation)
- `additionalContext` injected by `SessionStart` / `PostCompact`

### The canonical workflow data flow

```
/mission
  │ writes
  ▼
.planning/PROJECT.md ──┐ (mission, requirements, decisions)
.planning/REQUIREMENTS.md ──┐
.planning/ROADMAP.md ──┐
                       │
                       │ read by
                       ▼
                  /brief N
                       │ writes
                       ▼
       .planning/briefs/NN-name/BRIEF.md (why + what + spec + research summary)
                       │
                       │ read by
                       ▼
                  /plan N
                       │ writes
                       ▼
       .planning/briefs/NN-name/PLAN.md (tasks + dependsOn + verification block)
                       │
                       │ read by
                       ▼
                  /build N
                       │ writes (in parallel, per wave)
                       ▼
                  git commits  +  PLAN.md task status
                       │
                       │ read by
                       ▼
                  /verify N
                       │ writes
                       ▼
       PLAN.md verification block (COVERED / PARTIAL / MISSING per criterion)
                       │
                       │ read by
                       ▼
                  /ship → push + gh pr create
```

### How context is re-hydrated after compaction or new session

```
new session OR PostCompact event
  │
  ▼
SessionStart hook (or PostCompact hook) runs
  │
  ├─ reads stdin's `cwd` field (NOT pwd — locked in Foundation)
  ├─ resolves project root via `git rev-parse --show-toplevel`
  ├─ reads .planning/STATE.md if it exists (current brief pointer)
  ├─ reads .planning/briefs/<current>/BRIEF.md + PLAN.md (active artifacts)
  ├─ reads recent `git log` (last 10 commits with REQ-IDs)
  ├─ enumerates agents/, skills/ from live filesystem (no hardcoded list)
  ├─ reads config/quality-gates.txt (single source)
  │
  └─ emits hookSpecificOutput.additionalContext with:
       - project + branch + recent commits
       - current brief / phase
       - quality gates list
       - available skills + agents (live)
       - "next action" hint
```

The `jq -n --arg` discipline in Foundation guarantees this JSON is well-formed under adversarial branch names, commit messages, and paths — the v1.x string-interpolated version is a known fragility.

## Build Order — Dependencies Drive Sequencing

This is the core of the milestone planning recommendation. The order is not arbitrary; later layers literally cannot be safely built without earlier layers.

```
              Phase 0: Setup (already complete — re-init, .planning/ scaffolded)
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ Phase 1: FOUNDATION & SAFETY HARDENING (hooks, installer, version)│
   │   FOUND-01..10, HOOK-06..09                                      │
   │                                                                  │
   │   Hardens the substrate everything else stands on:               │
   │     - plugin.json as single version source; install.sh reads it  │
   │     - hooks emit valid JSON via `jq -n --arg` (no interpolation) │
   │     - hooks read cwd from stdin (not pwd)                        │
   │     - statusline single jq invocation per render                 │
   │     - installer prompts per-file before overwriting              │
   │     - backup rotation (keep last 5)                              │
   │     - shellcheck clean across every *.sh                         │
   │     - PreToolUse hook blocks --no-verify and secret patterns     │
   │     - PostToolUse hook surfaces failed quality-gate exits        │
   │     - quality-gates.txt as single source                         │
   │                                                                  │
   │   Why first: every later phase touches hooks/installer/version.  │
   │   Building agents on a fragile hook substrate doubles the bugs.  │
   └──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ Phase 2: AGENT LAYER MODERNIZATION                               │
   │   AGENT-01..08 (frontmatter modernization)                       │
   │   AGENT-NEW-01..04 (@planner, @verifier, @spec-reviewer,         │
   │                     @code-reviewer)                              │
   │   AGENT-LINT-01 (frontmatter linter, CI-enforced)                │
   │                                                                  │
   │   Why second: skills in Phase 3 will spawn these agents.         │
   │   Agents must exist with correct frontmatter (model aliases,     │
   │   effort policy, isolation, maxTurns, Connects to:) before       │
   │   skills can be wired to them.                                   │
   │                                                                  │
   │   Depends on Phase 1: PreToolUse + PostToolUse hooks must be     │
   │   live so worktree-isolated agents can't bypass --no-verify.     │
   └──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ Phase 3: SKILL LAYER REBUILD + STATE MANAGEMENT                  │
   │   SKILL-01..05 (/mission, /brief, /plan, /build, /verify)        │
   │   SKILL-06 (/ship rewrite)                                       │
   │   SKILL-07 (helpers: /debug, /tdd, /refactor, /explore-repo —    │
   │             updated to new agent names + Auto Mode awareness)    │
   │   SKILL-08 (/godmode rewrite — live filesystem index)            │
   │   STATE-01..04 (.planning/ templates, init-context.sh,           │
   │                 config.json schema, briefs/ layout)              │
   │   DEPRECATE-01 (v1 /prd, /plan-stories, /execute one-time notes) │
   │                                                                  │
   │   Why third: this is where the user-facing surface gets built.   │
   │   Each skill maps to specific agents from Phase 2 and writes to  │
   │   .planning/ artifacts whose templates land in this phase.       │
   │                                                                  │
   │   Depends on Phase 2: every skill has a `Connects to:` referencing│
   │   real agent files.                                              │
   └──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ Phase 4: WORKFLOW INTEGRATION & PARITY                           │
   │   WORKFLOW-01 (rules/godmode-workflow.md rewrite for the chain)  │
   │   WORKFLOW-02 (rules/godmode-routing.md effort policy lock)      │
   │   WORKFLOW-03 (rules/godmode-quality.md cross-references         │
   │                quality-gates.txt single source)                  │
   │   PARITY-01 (plugin-mode + manual-mode UX parity check)          │
   │   PARITY-02 (README, CHANGELOG, /godmode agree on surface)       │
   │   MIGRATE-01 (v1.x → v2 one-time migration: detect              │
   │               .claude-pipeline/, emit note, never destructive)   │
   │   PROMPT-CACHE-01 (rule structure: static preamble first,        │
   │                    no dynamic content in rule bodies)            │
   │                                                                  │
   │   Why fourth: rules tie together the agents (Phase 2) and skills │
   │   (Phase 3) into a coherent workflow story. Migration reads the  │
   │   live state from Phase 1's installer and the new artifacts from │
   │   Phase 3.                                                       │
   └──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ Phase 5: QUALITY — CI, TESTS, DOCUMENTATION                      │
   │   QUAL-01 (GitHub Actions matrix: macOS + Linux on every PR)     │
   │   QUAL-02 (shellcheck on every *.sh)                             │
   │   QUAL-03 (JSON schema validation on every *.json)               │
   │   QUAL-04 (frontmatter linter run in CI)                         │
   │   QUAL-05 (bats-core smoke test: install → /godmode → uninstall  │
   │            in temporary $HOME)                                   │
   │   QUAL-06 (CONTRIBUTING.md: backup rotation, worktree prune,     │
   │            frontmatter conventions)                              │
   │   QUAL-07 (resolve all High-severity items in CONCERNS.md with   │
   │            traceability)                                         │
   │                                                                  │
   │   Why last: testing the substrate (Phase 1), agents (Phase 2),   │
   │   skills (Phase 3), and integration (Phase 4) requires all four  │
   │   to exist. Trying to write the bats smoke test before /godmode  │
   │   is rewritten produces a test of the v1.x shape.                │
   └──────────────────────────────────────────────────────────────────┘
```

### Why this order is non-negotiable

| Dependency | Earlier phase | Later phase |
|------------|---------------|-------------|
| Hooks must emit valid JSON before agents can rely on `additionalContext` | Phase 1 (hooks hardened) | Phase 2 (agents reference context) |
| Agents must exist with correct frontmatter before skills can spawn them | Phase 2 (`@planner` exists) | Phase 3 (`/plan` spawns `@planner`) |
| `.planning/` templates must exist before skills can write to them | Phase 3 (`STATE-01`) | Phase 3 (`/mission` writes templates) — same phase, sequenced within |
| Workflow rule must reference real skill names | Phase 3 (skills exist) | Phase 4 (`godmode-workflow.md` references them) |
| CI bats smoke test must run against real surface | Phase 4 (parity exists) | Phase 5 (smoke test) |

### Within-phase parallelism

- **Phase 1:** FOUND-01 (version) is independent of HOOK-06..09 (hook hardening). Parallelizable.
- **Phase 2:** All four new agents (`@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`) are independent. Parallelizable. Frontmatter linter (AGENT-LINT-01) blocks until all agents land.
- **Phase 3:** `/mission`, `/brief`, `/plan`, `/build`, `/verify` are mostly independent _file_-wise but _semantically_ chained — recommend sequential build (`/mission` → `/brief` → `/plan` → `/build` → `/verify`) so each can be smoke-tested in a temp consumer repo before the next is written.
- **Phase 4:** Three rule rewrites are independent. Parallelizable.
- **Phase 5:** Five CI gates (shellcheck, JSON schema, frontmatter linter, bats smoke, matrix) are mostly independent. Parallelizable, but bats-smoke depends on all install/skills working.

## Integration Points

### v1.x → v2 migration (one-time, never destructive)

Two state-shapes need to coexist briefly:
- **v1.x consumer state:** `<consumer-repo>/.claude-pipeline/{prds/, stories.json, ...}`
- **v2 consumer state:** `<consumer-repo>/.planning/{PROJECT.md, briefs/, STATE.md, ...}`

The migration is **detection-only by default**:

```
on /godmode or SessionStart in a consumer repo:
  if .claude-pipeline/ exists and .planning/ does NOT:
    emit one-line note in additionalContext:
      "v1.x pipeline detected at .claude-pipeline/. Run /mission to start v2 workflow.
       Existing pipeline state will not be touched. Run `mv .claude-pipeline .claude-pipeline-archive`
       when ready to retire v1."
  if both exist:
    v2 wins; .claude-pipeline/ ignored silently (still on disk for the user)
```

Installer-side migration (in `install.sh`):
- Detects `~/.claude/CLAUDE.md` from pre-v1.4 era → offers to remove (existing v1.x behavior, retained)
- Detects v1.x `~/.claude/.claude-godmode-version` < 2.0.0 → upgrades rules in place, prompts per-file before overwriting customized agents/skills/hooks (FOUND-07)
- Never deletes user data. Backup rotation keeps last 5 in `~/.claude/backups/`.

### `/godmode` reads the live filesystem

```bash
# Pseudo-pseudocode for /godmode skill (real version is markdown instructions)

agents=$(ls "$HOME/.claude/agents/" 2>/dev/null | grep '\.md$' | sed 's/\.md$//')
skills=$(ls -d "$HOME/.claude/skills/"*/ 2>/dev/null | xargs -n1 basename)
version=$(jq -r .version "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null \
          || jq -r .version "$HOME/.claude/.claude-plugin/plugin.json" 2>/dev/null \
          || echo "unknown")
state=$(cat "$(git rev-parse --show-toplevel)/.planning/STATE.md" 2>/dev/null || echo "")

# Render with current state:
#  - workflow chain (/mission → /brief → /plan → /build → /verify → /ship)
#  - what now? (one of: "run /mission", "continue brief NN", "run /verify N", "run /ship")
#  - skills/agents enumerated from filesystem
```

This eliminates the v1.x bug where `commands/godmode.md` listed agents that had been renamed and skills that had been removed. **Source of truth = filesystem.**

### Plugin-mode + manual-mode UX parity (one source)

The single source for hook bindings, permissions, and statusline is `config/settings.template.json`. `hooks/hooks.json` is its plugin-mode mirror.

```
config/settings.template.json   ←  canonical for manual mode
  permissions  → merged into ~/.claude/settings.json (both modes)
  hooks        → merged into ~/.claude/settings.json (manual only)
  statusLine   → merged into ~/.claude/settings.json (manual only)

hooks/hooks.json                ←  plugin-mode mirror of hooks block
  paths use ${CLAUDE_PLUGIN_ROOT}/hooks/...

install.sh
  if MODE=plugin:  merge only `permissions`
  if MODE=manual:  merge `permissions` + `hooks` + `statusLine`
```

A CI parity check (Phase 5) asserts that `hooks/hooks.json` and `config/settings.template.json[hooks]` reference the same hook events with consistent timeouts. If they drift, CI fails.

The user's experience:
- **Plugin mode:** Claude Code plugin loader reads `hooks/hooks.json`, `agents/`, `skills/`, `commands/`, `config/statusline.sh` directly from this repo via `${CLAUDE_PLUGIN_ROOT}`. Updates flow on plugin upgrade.
- **Manual mode:** `install.sh` copies the same files into `~/.claude/`. Updates flow on `./install.sh` re-run.

Same files. Same `Connects to:` chain. Same `/godmode` output. Different load mechanism — invisible to the user.

## Patterns to Follow (v2-Specific)

### Pattern 1: Skills own orchestration; agents are atomic

**What:** A skill is the only thing that knows about ordering, fan-out, and which agents to call. Agents do not call agents.

**Why:** Keeps the call graph a tree. Makes `/build`'s parallel orchestration debuggable. Lets `/godmode` render an accurate `Connects to:` chain.

**Example:**
```yaml
# skills/plan/SKILL.md frontmatter
name: plan
description: "Tactical breakdown of a brief into a parallelizable task list"
Connects to: /brief → /plan → /build
spawns: [@planner, @spec-reviewer]
```

```yaml
# agents/planner.md frontmatter
name: planner
model: opus
effort: xhigh
maxTurns: 60
disallowedTools: Write, Edit
Connects to: /plan invokes @planner; outputs to PLAN.md
```

### Pattern 2: Read-only by default; isolation when writing

**What:** Every agent declares either `disallowedTools: Write, Edit` (read-only) or `isolation: worktree` (write-bounded). Never both unset.

**Why:** Read-only agents can run in parallel safely. Write-bounded agents can't corrupt the user's working tree. The user's `git status` stays clean during `/build`.

### Pattern 3: Live filesystem indexing, never hardcoded lists

**What:** Anywhere the system needs to enumerate agents or skills (`/godmode`, `PostCompact` injection, `/build` task validation), it reads the directory at runtime.

**Why:** v1.x had a hardcoded skill list in `commands/godmode.md` that drifted from `skills/` — users saw `/explore` documented when only `/explore-repo` existed. Live indexing is one `ls | grep .md | sed` away.

### Pattern 4: jq for everything JSON; never string-interpolate JSON

**What:** Hooks emit JSON via `jq -n --arg name "$value" '{...}'`, never via `echo "{\"name\": \"$value\"}"`.

**Why:** Adversarial branch names (`feat/'-O'-RemoveItem`), commit messages with quotes, and paths with spaces all break string interpolation. `jq -n --arg` is bulletproof.

### Pattern 5: One artifact per workflow gate, atomic commit

**What:** Every workflow transition mutates exactly one file (or one tightly-coupled set) and commits atomically with a REQ-ID-bearing message.

**Why:** `git log` IS the execution log. Atomicity means `/verify N` can `git log --grep "BRIEF-NN"` and reconstruct exactly what happened.

## Anti-Patterns to Avoid (v2-Specific)

### Anti-Pattern 1: A `/everything` mega-command

**What:** A single command that runs the whole pipeline.

**Why bad:** Hides the workflow shape. Users learn the chain by typing each command. A mega-command makes them never learn it. (Listed in PROJECT.md Out of Scope.)

**Instead:** Each command in the 11-command surface does one thing well; `/godmode` shows the chain.

### Anti-Pattern 2: Per-task artifact files (TASK.md)

**What:** Writing a `.planning/briefs/NN/tasks/T01.md` per task.

**Why bad:** `git log` already records what each task did. TASK.md duplicates state with no upside, and forces every task commit to also commit a markdown file.

**Instead:** PLAN.md tracks per-task status (pending / in-flight / done / failed). git log carries the diff and the rationale.

### Anti-Pattern 3: Agents spawning agents

**What:** `@planner` invokes `@architect` mid-execution.

**Why bad:** Turns the call graph from a tree into a DAG. Makes parallel orchestration in `/build` impossible to reason about. Hides cost from the skill (which is the only place a budget can be set).

**Instead:** Skills do all fan-out. If `/plan` needs both `@planner` and `@architect`, the skill calls both sequentially.

### Anti-Pattern 4: Auto-prompt-engineering of user intent

**What:** A skill silently rewrites the user's request before invoking an agent.

**Why bad:** Breaks trust. The user types `/brief 3` expecting their words to be the spec; if the skill mutates them, the resulting brief surprises them. (Listed in PROJECT.md Out of Scope.)

**Instead:** `/brief` runs an explicit Socratic discussion that the user sees. The user's answers are the spec, verbatim.

### Anti-Pattern 5: Touching `~/.claude/settings.json` outside `install.sh`

**What:** A skill or hook directly mutates the user's settings.json.

**Why bad:** That file is the user's, not the plugin's. Direct mutation breaks idempotency, races with the user's other plugins, and prevents `uninstall.sh` from cleanly restoring.

**Instead:** Only `install.sh` and `uninstall.sh` touch `~/.claude/settings.json`. Both via `jq` merges with backup rotation.

## Scalability Considerations

The system is single-user and single-repo, but parallelism inside `/build` introduces a real scalability axis: how many `@executor` instances can run concurrently?

| Scale | Tasks per wave | Strategy |
|-------|----------------|----------|
| Small brief (≤ 5 tasks total) | 1–3 | All in one wave; trivially parallel |
| Medium brief (6–20 tasks) | 3–5 per wave | Wave-based; partition by `dependsOn` |
| Large brief (> 20 tasks) | 5 max per wave | Cap concurrency at 5; queue overflow |

The cap exists because each `@executor` worktree is a checkout, and disk + Claude Code Task tool concurrency limits are real. v1.x already accumulates ~27 worktrees in `.claude/worktrees/` — Phase 5 adds a worktree-prune recipe in CONTRIBUTING.md.

## Confidence by Component

| Component | Confidence | Source |
|-----------|------------|--------|
| Layer model (rules / hooks / agents / skills / commands / statusline / permissions) | HIGH | v1.x baseline in `.planning/codebase/ARCHITECTURE.md`; preserved in v2 |
| 11-command user surface | HIGH | Locked in PROJECT.md Key Decisions |
| Skill → Agent invocation matrix | HIGH | Derived from REQUIREMENTS.md Active section + PROJECT.md decisions |
| Build order (Phase 1 → 5) | HIGH | Dependency-driven; matches existing ROADMAP.md (5f6c389) |
| `/build` parallel orchestration | MEDIUM | `run_in_background` + worktree pattern is in PROJECT.md but the file-polling fallback details need Phase 3 design |
| v1.x → v2 migration policy | HIGH | "Never destructive" is locked; one-line detection note is in REQUIREMENTS.md |
| Plugin/manual parity mechanism | HIGH | Identical to v1.x; v2 just adds a CI parity check |
| `.planning/` template layout | MEDIUM | PROJECT.md fixes the artifact files (BRIEF.md, PLAN.md); template content lands in Phase 3 |

## Open Questions for Brief Discussion

These are intentionally _not_ resolved here — they belong in `/brief N` Socratic discussions for the relevant phase.

1. **Phase 1 (Foundation):** Should the `PreToolUse` hook block all `--no-verify` patterns, or also block `git commit -n`? (REQ HOOK-06 left this implicit.)
2. **Phase 2 (Agents):** Does `@verifier` run in `background: true`, or does its read-only-but-thorough pass want foreground priority?
3. **Phase 3 (Skills):** What's `/build`'s wave-concurrency cap — a hardcoded 5, or a config knob in `.planning/config.json`?
4. **Phase 3 (State):** Should `STATE.md` be hand-edited by the user, or always machine-mutated? (Recommendation: machine-mutated; user reads, never writes.)
5. **Phase 4 (Migration):** Does the v1.x → v2 migration print the detection note in `/godmode`, or also in `SessionStart`? (Recommendation: both, but suppressed in `SessionStart` after first session.)

These are flags for the per-phase research and `/brief` discussions, not blockers for roadmap construction.

---

*Architecture research: 2026-04-26 (claude-godmode v2 — polish mature version, re-init under inspiration-only principle)*
