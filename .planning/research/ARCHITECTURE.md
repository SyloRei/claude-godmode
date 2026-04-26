# Architecture — claude-godmode v2 (polish mature version)

**Domain:** Claude Code plugin (configuration / extension distribution)
**Researched:** 2026-04-26
**Milestone:** v2 — polish mature version (brownfield maturation of v1.x)
**Confidence:** HIGH (constrained by locked Key Decisions in `.planning/PROJECT.md`, the v1.x baseline in `.planning-archive-v1/codebase/`, and prior architecture research at `.planning-archive-v1/research/ARCHITECTURE.md`)

## TL;DR

The v1.x two-sided shape (distribution repo + runtime files in `~/.claude/`) and its layered primitives (rules / hooks / agents / skills / commands / statusline / permissions) **stay**. v2 adds five things at the architecture level:

1. **Three new top-level dirs** at the repo root — `scripts/` (CI helpers), `tests/` (bats fixtures), `templates/` (consumer `.planning/` scaffolds). `.github/workflows/` graduates from "GitHub-UI metadata only" to "load-bearing CI substrate." Existing `.github/` stays but gains `workflows/`.
2. **Two new hooks** — `pre-tool-use.sh` (block `--no-verify`, secret patterns), `post-tool-use.sh` (surface failed gate exit codes). Total hook count: 4.
3. **One new config single-source** — `config/quality-gates.txt`. Quality-gate list lives in exactly one file; rules + hooks read from it.
4. **A consumer-side state layer** — `.planning/` artifacts in **user projects** (PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, briefs/NN-name/{BRIEF.md,PLAN.md}). The plugin ships templates for these in `templates/.planning/`. Distinct from the plugin's own `.planning/` (this directory) which is gitignored.
5. **A live-indexing contract** — `/godmode`, `PostCompact`, `SessionStart` all enumerate `agents/`, `skills/`, `briefs/` from disk via globs; no hardcoded lists anywhere.

The five-layer model (rules / agents / skills / hooks / config) is the **vocabulary for v2 work**. Every new file fits into exactly one layer. Cross-layer talk is one-directional and contract-bound.

## Section 1 — Directory Layout (v2)

### What stays at repo root

```
claude-godmode/
├── .claude-plugin/plugin.json          [PRESERVED — canonical version source]
├── rules/godmode-*.md                  [PRESERVED — 8 rule files, 1 rewritten in M4]
├── agents/*.md                         [PRESERVED — 8 agents + 4 new in M2]
├── skills/<name>/SKILL.md              [PRESERVED — 7 rewritten/new in M4 + 4 helpers]
├── skills/_shared/*.md                 [PRESERVED — fragments]
├── commands/godmode.md                 [PRESERVED — rewritten in M4]
├── hooks/{session-start,post-compact}.sh [PRESERVED — hardened in M1]
├── hooks/hooks.json                    [PRESERVED — plugin-mode mirror]
├── config/{settings.template.json,statusline.sh} [PRESERVED — hardened in M1]
├── install.sh, uninstall.sh            [PRESERVED — hardened in M1]
├── README.md, CHANGELOG.md, LICENSE, CONTRIBUTING.md, CODE_OF_CONDUCT.md [PRESERVED]
├── .github/                            [EXTENDED — workflows/ added in M5]
└── .gitignore                          [EXTENDED — .planning/, .claude/, .claude-pipeline/]
```

### What's new in v2

```
claude-godmode/
├── scripts/                            [NEW — dev/CI helpers, never installed to ~/.claude/]
│   ├── check-version-drift.sh          [M1 — fails if README/CHANGELOG drift from plugin.json]
│   ├── lint-frontmatter.sh             [M2 — validates agent + skill YAML frontmatter]
│   ├── check-parity.sh                 [M5 — plugin/manual hook+permission parity gate]
│   ├── check-vocabulary.sh             [M5 — fails if "phase"/"task" leak into user-facing surface]
│   └── prune-worktrees.sh              [M5 — referenced by CONTRIBUTING.md]
│
├── tests/                              [NEW — bats-core test substrate]
│   ├── smoke.bats                      [M5 — install→/godmode→uninstall in temp $HOME]
│   ├── adversarial.bats                [M5 — hooks under quoted/newline branch names]
│   ├── parity.bats                     [M5 — plugin vs manual hook bindings]
│   └── fixtures/
│       └── hooks/                      [M1 — JSON inputs covering adversarial cases]
│           ├── branch-with-quote.json
│           ├── branch-with-newline.json
│           ├── empty-stdin.json
│           └── valid-baseline.json
│
├── templates/                          [NEW — consumer-side .planning/ scaffolds]
│   └── .planning/
│       ├── PROJECT.md.tmpl
│       ├── REQUIREMENTS.md.tmpl
│       ├── ROADMAP.md.tmpl
│       ├── STATE.md.tmpl
│       ├── config.json.tmpl
│       └── briefs/_template/
│           ├── BRIEF.md.tmpl
│           └── PLAN.md.tmpl
│
├── config/
│   └── quality-gates.txt               [NEW — single source for the 6 gates]
│
├── .shellcheckrc                       [NEW — per-script shellcheck config]
│
└── .github/
    └── workflows/                      [NEW — GitHub Actions, CI substrate]
        ├── ci.yml                      [M5 — shellcheck + JSON + frontmatter + version-drift + bats]
        └── parity.yml                  [M5 — runs scripts/check-parity.sh on every PR]
```

### Layout decisions and rationale

| Decision | Why |
|---|---|
| `scripts/` separate from `hooks/` | Hooks are **runtime** (loaded into user's Claude Code session). Scripts are **dev-time** (CI, parity checks, frontmatter linting). Mixing them in `hooks/` would make the install logic ambiguous about what to copy. |
| `tests/` at root, not `scripts/tests/` | bats-core convention; CI runs `bats tests/`. Keeping it root-level matches every Bash test repo on GitHub. |
| `templates/.planning/` distinct from plugin's own `.planning/` | The plugin's `.planning/` (this dir) is gitignored development planning. The shipped `templates/.planning/` are scaffolds installed into **consumer repos** when they run `/mission`. Confusing the two would cause `/mission` to overwrite our own planning. |
| `config/quality-gates.txt` not `rules/quality-gates.md` | Plain-text, line-per-gate, machine-readable. Hooks parse it with `grep -v '^#'`. Putting it in `rules/` would make Claude Code treat it as always-on context (wasted tokens) and rules-style markdown is harder for shell to parse. |
| `.shellcheckrc` at root | Standard tool location. Per-script disable comments live in scripts; project-wide config lives at root. |
| `.github/workflows/` as a real component (not just metadata) | v1.x had `.github/` for issue templates only. v2's parity gates, version-drift gate, and bats smoke test ALL run in GitHub Actions — the workflow files are load-bearing, not optional. |
| **No** `docs/` directory | README + CHANGELOG + CONTRIBUTING + CODE_OF_CONDUCT cover all docs. Adding a `docs/` invites duplication; user-facing docs live in README, dev-facing in CONTRIBUTING. The 11 skill files are self-documenting. |
| **No** `lib/` or `src/` directory | This is not an application. Source is shell scripts in `hooks/`, `config/`, `scripts/`, plus markdown in `rules/`, `agents/`, `skills/`, `commands/`. Adding `src/` would force a build step. There is no build step. |

### What's installed where (unchanged contract from v1.x)

| Source path | Plugin mode | Manual mode |
|---|---|---|
| `rules/godmode-*.md` | merged into `~/.claude/settings.json` permissions only | copied to `~/.claude/rules/` |
| `agents/*.md` | served from `${CLAUDE_PLUGIN_ROOT}/agents/` | copied to `~/.claude/agents/` |
| `skills/<name>/SKILL.md` | served from `${CLAUDE_PLUGIN_ROOT}/skills/` | copied to `~/.claude/skills/<name>/` |
| `commands/godmode.md` | served from `${CLAUDE_PLUGIN_ROOT}/commands/` | copied to `~/.claude/commands/` |
| `hooks/*.sh` | served from `${CLAUDE_PLUGIN_ROOT}/hooks/` | copied to `~/.claude/hooks/` |
| `hooks/hooks.json` | read by plugin loader | (not used) |
| `config/statusline.sh` | served from `${CLAUDE_PLUGIN_ROOT}/config/` | copied to `~/.claude/hooks/` |
| `config/settings.template.json` | merged (permissions only) into `~/.claude/settings.json` | merged (permissions + hooks + statusLine) into `~/.claude/settings.json` |
| `config/quality-gates.txt` | served from `${CLAUDE_PLUGIN_ROOT}/config/` | copied to `~/.claude/config/` |
| `templates/.planning/` | served from `${CLAUDE_PLUGIN_ROOT}/templates/` | copied to `~/.claude/templates/` |
| `scripts/*.sh` | NOT installed | NOT installed (dev-time only) |
| `tests/` | NOT installed | NOT installed |
| `.github/`, `.shellcheckrc` | NOT installed | NOT installed |

## Section 2 — Component Boundaries (the five-layer model)

Every v2 component fits into exactly one of these layers. Boundaries are non-negotiable.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 1 — RULES (philosophy / always-on context)                             │
│ Path: rules/godmode-*.md                                                     │
│ No frontmatter. Markdown only.                                               │
│ Loaded by: Claude Code rules system (every session)                          │
│ Allowed to: state principles, list quality gates, declare workflow shape,    │
│             set routing policy                                               │
│ NOT allowed to: contain dynamic content, hardcode agent/skill lists,         │
│                 reference specific REQ-IDs, mutate state                     │
│ Reads: nothing (rules are static text)                                       │
│ Writes: nothing                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
                            ▼ informs
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 2 — AGENTS (labor / specialized subagents)                             │
│ Path: agents/<name>.md                                                       │
│ YAML frontmatter required (model, tools, isolation, memory, effort,          │
│                            maxTurns, disallowedTools, background, Connects)  │
│ Loaded by: Claude Code subagent system (when spawned via Task tool)          │
│ Allowed to: do one bounded job (analysis, write code in worktree, review,    │
│             verify), declare its own model/effort/tool budget                │
│ NOT allowed to: spawn other agents, mutate ~/.claude/settings.json,          │
│                 know about the workflow chain (only knows its own step)      │
│ Reads: code, .planning/ artifacts, rules (via system prompt)                 │
│ Writes: code (if isolation: worktree); planning artifacts (if Write/Edit     │
│         allowed); never settings.json                                        │
└──────────────────────────────────────────────────────────────────────────────┘
                            ▼ invoked by
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 3 — SKILLS (user-facing surface / orchestration)                       │
│ Path: skills/<name>/SKILL.md (+ commands/<name>.md for lighter ones)         │
│ YAML frontmatter required (name, description, Connects to:, spawns: [list])  │
│ Loaded by: Claude Code skill/command system (when user types /<name>)        │
│ Allowed to: own all orchestration, spawn agents in any order, mutate         │
│             .planning/ artifacts, run quality gates, commit                  │
│ NOT allowed to: spawn other skills (the user is the only orchestrator        │
│                 across skills), mutate ~/.claude/settings.json,              │
│                 hardcode agent lists (read frontmatter at runtime)           │
│ Reads: .planning/* (consumer side), agents/*.md (for live discovery),        │
│        config/quality-gates.txt                                              │
│ Writes: .planning/* (consumer side), git commits, code (via spawned agents)  │
└──────────────────────────────────────────────────────────────────────────────┘
                            ▼ events fire
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 4 — HOOKS (safety substrate / event-driven shell)                      │
│ Path: hooks/*.sh + hooks/hooks.json (plugin) + config/settings.template.json │
│ Pure shell, Bash 3.2+ compatible. shellcheck-clean. Single jq invocation     │
│ for any JSON construction (jq -n --arg, never string interpolation).         │
│ Loaded by: Claude Code on lifecycle events (SessionStart, PostCompact,       │
│            PreToolUse, PostToolUse)                                          │
│ Allowed to: read stdin JSON, read filesystem, call git, emit                 │
│             hookSpecificOutput JSON, BLOCK tool calls (PreToolUse)           │
│ NOT allowed to: write to ~/.claude/, spawn agents, run longer than the       │
│                 event timeout (5s SessionStart, 1s PreToolUse), use          │
│                 string interpolation for JSON, depend on `pwd` (must read    │
│                 cwd from stdin)                                              │
│ Reads: stdin JSON, .planning/STATE.md, config/quality-gates.txt,             │
│        agents/*.md frontmatter, skills/*/SKILL.md frontmatter                │
│ Writes: stdout JSON only                                                     │
└──────────────────────────────────────────────────────────────────────────────┘
                            ▼ reads
┌──────────────────────────────────────────────────────────────────────────────┐
│ LAYER 5 — CONFIG (data / single sources of truth)                            │
│ Path: config/{settings.template.json, statusline.sh, quality-gates.txt} +    │
│       .claude-plugin/plugin.json                                             │
│ Plain data files (JSON, plain text) + the statusline renderer.               │
│ Allowed to: declare permissions, declare hook bindings, declare quality      │
│             gates list, declare canonical version, render statusline         │
│ NOT allowed to: contain logic that belongs in hooks (statusline.sh is        │
│                 the one rendering script; everything else is data)           │
│ Reads: stdin JSON (statusline only)                                          │
│ Writes: stdout text (statusline only); other config files are read-only      │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Layer assumption matrix (what each layer can rely on)

| Layer | Assumes about lower-numbered layers | Assumes about higher-numbered layers |
|---|---|---|
| 1 Rules | (nothing — bottom of stack) | Nothing. Rules are static; they don't reach forward. |
| 2 Agents | Rules are loaded (system prompt has identity, coding standards) | Skills will spawn it; it doesn't care which skill. |
| 3 Skills | Rules + Agents exist; agents have correct frontmatter | Hooks will fire; hooks don't change skill semantics. |
| 4 Hooks | Rules + Agents + Skills exist on disk; .planning/ may exist | (nothing — hooks are leaf-level; they emit JSON and exit) |
| 5 Config | Read by 1–4 as static data | (nothing — config is leaf data) |

### Cross-layer talk rules

- **Skills → Agents:** ONLY direction agents are invoked. Via Task tool, with explicit subagent_type and prompt.
- **Hooks → Skills:** Hooks NEVER call skills. Hooks emit `additionalContext` that informs the next assistant turn; the assistant chooses the next skill.
- **Skills → Hooks:** Skills NEVER call hooks. Hooks fire on lifecycle events, not on skill demand.
- **Agents → Agents:** FORBIDDEN. All fan-out is owned by skills. Tree call graph, never DAG.
- **Anything → Config:** READ-ONLY for all five layers. Only `install.sh` writes to `~/.claude/settings.json`.
- **Anything → Rules:** READ-ONLY. Rules are user-editable on disk, but the plugin never mutates them at runtime.

## Section 3 — Data Flow

### State vehicles (in order of authority)

| Vehicle | Authority | Lifetime | Survives compaction? | Survives session end? |
|---|---|---|---|---|
| `git log` | Highest — execution log | Forever | Yes | Yes |
| Source files (`rules/`, `agents/`, `skills/`, `hooks/`, `config/`) | Plugin's own truth | Until plugin upgrade | Yes | Yes |
| Consumer's `.planning/PROJECT.md` | Project source of truth | Project lifetime | Yes | Yes |
| Consumer's `.planning/REQUIREMENTS.md` | Requirements source of truth | Project lifetime | Yes | Yes |
| Consumer's `.planning/ROADMAP.md` | Mission decomposition | Until next mission | Yes | Yes |
| Consumer's `.planning/STATE.md` | Live pointer to current brief | Until next brief transition | Yes (read by SessionStart) | Yes |
| Consumer's `.planning/briefs/NN-name/{BRIEF,PLAN}.md` | Per-brief artifacts | Until brief verified | Yes | Yes |
| `~/.claude/.claude-godmode-version` | Installed version stamp | Until next install | Yes | Yes |
| Subagent transcripts | Session-scoped | Single subagent run | No | No |
| Hook `additionalContext` | Session-scoped (re-emitted on PostCompact) | Single injection | Re-injected on PostCompact | No |

### Memory boundary — what lives where (the question the milestone explicitly asks)

| Question | Answer | Why |
|---|---|---|
| State a skill machine-mutates: STATE.md or memory? | **`.planning/STATE.md`** | User-readable, gitignorable per-project, survives compaction via SessionStart hook re-injecting it. `~/.claude/projects/.../memory/` is global and opaque. |
| Cross-session learnings (what worked, what didn't): STATE.md or memory? | **`memory: project`** on specific agents (`@architect`, `@researcher`) | Cross-cutting tribal knowledge belongs in agent memory; per-brief execution state belongs in STATE.md. |
| Per-task progress during `/build`: STATE.md or git? | **git commits + PLAN.md task-status block** | git is the execution log. PLAN.md gets a status update per task. STATE.md only points at the current brief, not per-task. |
| Decision log: STATE.md or git or PROJECT.md? | **PROJECT.md "Key Decisions" + git commit messages** | Decisions are rationale, not state. They live with the requirements they justify. |
| Quality gates list: rule file or config? | **`config/quality-gates.txt`** | Single source. Hooks `grep` it; rules reference it ("see config/quality-gates.txt"). v1.x had it duplicated in CLAUDE.md + post-compact.sh — that's PITFALLS #9. |
| Version: which file? | **`.claude-plugin/plugin.json:.version`** | Canonical. Everything else (`install.sh`, `commands/godmode.md`, statusline) reads via `jq -r .version`. CI gate (`scripts/check-version-drift.sh`) blocks drift. |

### The canonical workflow data flow

```
User runs /godmode (any time)
  │ READS:  agents/*.md frontmatter (Connects to:)
  │         skills/*/SKILL.md frontmatter (Connects to:, spawns)
  │         .planning/STATE.md (current brief pointer)
  │         .claude-plugin/plugin.json (.version)
  │ WRITES: nothing — pure read + render
  ▼
User runs /mission
  │ SPAWNS: @architect (xhigh, read-only) → @spec-reviewer (sonnet, read-only)
  │ READS:  IDEA.md if present, .planning/codebase/* if present
  │ WRITES: .planning/PROJECT.md
  │         .planning/REQUIREMENTS.md
  │         .planning/ROADMAP.md
  │         .planning/STATE.md (active_brief: 1)
  │ COMMIT: "docs: define mission (X reqs, Y briefs)"
  ▼
User runs /brief N
  │ SPAWNS: @researcher (background) → @architect → @spec-reviewer
  │ READS:  PROJECT.md, REQUIREMENTS.md, ROADMAP.md, codebase/*
  │ WRITES: .planning/briefs/NN-name/BRIEF.md
  │         .planning/STATE.md (status: BRIEF.md drafted)
  │ COMMIT: "docs: brief N — <name> (why + what + spec)"
  ▼
User runs /plan N
  │ SPAWNS: @planner (xhigh, read-only) → @spec-reviewer
  │ READS:  briefs/NN-name/BRIEF.md, PROJECT.md, codebase/*
  │ WRITES: .planning/briefs/NN-name/PLAN.md
  │         .planning/STATE.md (status: PLAN.md drafted)
  │ COMMIT: "docs: plan N — <name> (T tasks, W waves)"
  ▼
User runs /build N
  │ SPAWNS: per wave: @executor × N (parallel, worktree, high)
  │         per task: @code-reviewer (sonnet, read-only, sequential)
  │ READS:  briefs/NN-name/PLAN.md (task graph)
  │         rules/godmode-*.md (via subagent system prompt)
  │         config/quality-gates.txt (gate list)
  │ WRITES: code (via worktree merges → main commits)
  │         briefs/NN-name/PLAN.md (task status)
  │         .planning/STATE.md (status: building, current_wave: N)
  │ COMMIT: per task — "<type>(scope): <subject> (REQ-XX-NN)"
  │         per wave close — "docs: plan N wave W complete"
  ▼
User runs /verify N
  │ SPAWNS: @verifier (xhigh, read-only)
  │ READS:  briefs/NN-name/BRIEF.md (success criteria)
  │         briefs/NN-name/PLAN.md (tasks)
  │         git log --grep "BRIEF-NN"
  │         actual code
  │ WRITES: briefs/NN-name/PLAN.md (verification block: COVERED/PARTIAL/MISSING)
  │         .planning/STATE.md (status: verified | gaps_found)
  │ COMMIT: "docs: verify N — <X covered>/<Y partial>/<Z missing>"
  ▼
User runs /ship
  │ SPAWNS: @security-auditor (xhigh, read-only)
  │ READS:  the latest verified brief
  │ WRITES: git push, GitHub PR (via gh)
  │ COMMIT: nothing local; remote PR created
```

### How context is re-hydrated after compaction or new session

```
new session starts OR PostCompact event fires
  │
  ▼
Hook reads stdin JSON (cwd, transcript, model, etc.)
  │ jq -r '.cwd' < stdin   # NEVER pwd
  │
  ▼
project_root=$(cd "$cwd" && git rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
  │
  ▼
collect:
  - basename "$project_root"
  - current branch (git symbolic-ref --short HEAD)
  - last 10 commits (git log --oneline -10)
  - .planning/STATE.md if exists (cat, but escape via jq --arg)
  - active brief: derive from STATE.md → briefs/<active>/{BRIEF.md,PLAN.md} headers
  - config/quality-gates.txt (cat, escape via jq --arg)
  - agents available: ls agents/*.md | xargs -n1 basename | sed 's/.md$//' | sort
  - skills available: ls skills/*/SKILL.md | awk -F/ '{print $(NF-1)}' | sort
  │
  ▼
emit JSON:
  jq -n \
    --arg project "$project" \
    --arg branch "$branch" \
    --arg state "$state_md" \
    --arg gates "$gates_txt" \
    --argjson agents "$(printf '%s\n' "${agents[@]}" | jq -R . | jq -s .)" \
    --argjson skills "$(printf '%s\n' "${skills[@]}" | jq -R . | jq -s .)" \
    '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: "Project: \($project)\nBranch: \($branch)\n\nState:\n\($state)\n\nGates:\n\($gates)\n\nAgents: \($agents | join(", "))\nSkills: \($skills | join(", "))"
      }
    }'
```

### Hook-to-skill handoff contract (JSON via stdin/stdout)

**Hooks NEVER directly invoke skills.** The contract is:

1. Hook reads JSON from stdin (Claude Code provides it).
2. Hook emits JSON on stdout matching `{ hookSpecificOutput: { hookEventName, additionalContext } }` for context-injecting hooks, or `{ decision: "block", reason: "..." }` for blocking hooks (PreToolUse).
3. Claude Code adds `additionalContext` to the next assistant turn's context.
4. The assistant — informed by additionalContext — proposes the next skill invocation. The user runs it.
5. The skill exists in `skills/<name>/SKILL.md`; user types `/<name>`; Claude Code loads SKILL.md as a system message; the skill's instructions take over.

**There is no API call from hook to skill.** Hooks influence the assistant's next utterance via `additionalContext`. That's the entire contract.

### Skill-to-subagent handoff contract (Task tool)

A skill spawns a subagent via Claude Code's Task tool:

```
Task(
  subagent_type: "planner",          # matches agents/planner.md filename
  description: "Plan brief 3",        # short summary
  prompt: <verbatim instructions>,    # full instructions for the agent
)
```

Claude Code:
1. Reads `agents/planner.md` (or `~/.claude/agents/planner.md` in manual mode).
2. Loads its YAML frontmatter (model, effort, tools, isolation, maxTurns, disallowedTools, memory).
3. Loads its body as the system prompt.
4. Spawns a fresh subagent context with that prompt + the skill's invocation prompt.
5. Returns the subagent's final assistant message to the calling skill.

**The skill never sees the subagent's intermediate steps.** Only the final result. This is intentional — it forces agents to be designed for one-shot completeness, not chatty back-and-forth.

## Section 4 — Build Order (5 milestones, non-negotiable)

```
                Milestone 0: Setup (already complete — re-init, .planning/ scaffolded)
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ M1 — FOUNDATION & SAFETY HARDENING                               │
   │   Plugin manifest version single-source                          │
   │   Hooks emit valid JSON via jq -n --arg                          │
   │   Hooks read cwd from stdin                                      │
   │   Hooks tolerate stdin drain failure                             │
   │   Statusline single jq invocation                                │
   │   Installer per-file customization preservation + backup-5       │
   │   Uninstaller version-mismatch refusal                           │
   │   v1.x migration detection-only (never destructive)              │
   │   shellcheck clean across every *.sh                             │
   │   config/quality-gates.txt single source                         │
   │   New: scripts/check-version-drift.sh                            │
   │   New: tests/fixtures/hooks/                                     │
   │   New: .shellcheckrc                                             │
   │                                                                  │
   │   ASSUMES: nothing — this is the substrate.                      │
   │   PROVIDES: a substrate that can't corrupt user files, that      │
   │             survives adversarial inputs, and that has a single   │
   │             version source M2-M5 can read.                       │
   └──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ M2 — AGENT LAYER MODERNIZATION                                   │
   │   8 existing agents updated (model aliases, effort policy,       │
   │     Connects to:, maxTurns, isolation/memory)                    │
   │   4 new agents: @planner, @verifier, @spec-reviewer,             │
   │     @code-reviewer                                               │
   │   New: scripts/lint-frontmatter.sh                               │
   │                                                                  │
   │   ASSUMES (from M1): hooks won't corrupt subagent context with   │
   │                       malformed JSON; version is canonical.      │
   │   PROVIDES: 12 agents with correct frontmatter that M3 hooks     │
   │             can enumerate and M4 skills can spawn.               │
   └──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ M3 — HOOK LAYER EXPANSION                                        │
   │   New hook: pre-tool-use.sh (block --no-verify, secret patterns) │
   │   New hook: post-tool-use.sh (surface failed gate exits)         │
   │   Update: session-start.sh reads .planning/STATE.md              │
   │   Update: post-compact.sh reads quality-gates.txt + live agents  │
   │   Hook bindings updated in hooks/hooks.json AND                  │
   │     config/settings.template.json                                │
   │                                                                  │
   │   ASSUMES (from M2): agents/*.md exist and have valid frontmatter│
   │                       so PostCompact can enumerate them.         │
   │   PROVIDES: a safety substrate around M4 skills' code-writing    │
   │             that mechanically blocks --no-verify and surfaces    │
   │             failed gates.                                        │
   └──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ M4 — SKILL LAYER REBUILD + STATE MANAGEMENT                      │
   │   New skills: /mission, /brief, /plan, /build, /verify           │
   │   Rewritten: /ship, /godmode (live filesystem index)             │
   │   Updated helpers: /debug, /tdd, /refactor, /explore-repo        │
   │     (new agent names, Auto Mode awareness)                       │
   │   v1.x deprecation notes: /prd, /plan-stories, /execute          │
   │   New: templates/.planning/ scaffolds                            │
   │   New: skills/_shared/init-context.sh                            │
   │   Update: rules/godmode-workflow.md (rewritten for new chain)    │
   │   Update: rules/godmode-routing.md (effort policy lock)          │
   │                                                                  │
   │   ASSUMES (from M3): hooks fire correctly; PreToolUse blocks     │
   │                       --no-verify so /build can't bypass gates;  │
   │                       PostCompact re-injects skill list.         │
   │   ASSUMES (from M2): all agents skills spawn exist with correct  │
   │                       frontmatter.                               │
   │   PROVIDES: complete user-facing surface (11 commands).          │
   └──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ M5 — QUALITY: CI, TESTS, DOCS PARITY                             │
   │   New: .github/workflows/ci.yml                                  │
   │   New: tests/{smoke,adversarial,parity}.bats                     │
   │   New: scripts/check-parity.sh                                   │
   │   New: scripts/check-vocabulary.sh                               │
   │   New: scripts/prune-worktrees.sh                                │
   │   README rewritten (< 500 lines)                                 │
   │   CHANGELOG entry for v2.0.0                                     │
   │   Plugin marketplace metadata polished                           │
   │   Version bump 1.6.0 → 2.0.0 in plugin.json                      │
   │                                                                  │
   │   ASSUMES (from M1-M4): everything exists in its final shape.    │
   │                          bats smoke needs install.sh +           │
   │                          /godmode + uninstall.sh to all work.    │
   │                          Parity check needs both hook bindings   │
   │                          to be final. Vocabulary check needs the │
   │                          11-skill surface in place.              │
   │   PROVIDES: ship-ready v2.0.0 release.                           │
   └──────────────────────────────────────────────────────────────────┘
```

### Why this order is non-negotiable (the "Phase N requires Phase N-1 because…" justifications)

| Boundary | The hard dependency |
|---|---|
| **M1 first** | Every later milestone touches hooks, installer, or version. Building agents on a hook substrate that emits invalid JSON under quoted branch names doubles the bugs because every agent context will be corrupted by SessionStart. The version single-source must exist before M5's drift CI gate has anything to check. shellcheck-cleanness is the gate every later `.sh` must pass. |
| **M2 before M3** | The PostCompact hook (M3 update) reads `agents/*.md` from the filesystem. If `@planner.md` doesn't exist (M2), PostCompact's enumeration omits it, and post-compaction the assistant doesn't know `@planner` is available. Build agents → then make hooks aware of them. |
| **M2 before M4** | Every skill in M4 has `spawns: [@<agent-name>]` in its frontmatter. Those agents must exist and have correct frontmatter before skills can be wired to them. `/plan` literally cannot work without `@planner.md` on disk. |
| **M3 before M4** | M4's `/build` skill orchestrates parallel `@executor` runs that commit code. Without M3's PreToolUse hook, an `@executor` could run `git commit --no-verify` and bypass quality gates. The safety substrate must be in place before the workflow exercises it. |
| **M4 before M5** | M5's bats smoke test runs `install → /godmode → /mission → … → uninstall` against a temp $HOME. If `/godmode` is still v1.x shape, the smoke test would test the wrong surface. Vocabulary CI gate needs final skill names to grep. Parity CI gate needs final hook bindings on both sides. |
| **M5 last** | CI gates the whole substrate, so it can only run after the substrate is built. README rewrite needs final command surface to document. Version bump to 2.0.0 happens at M5 close — bumping earlier would lie about which milestones are done. |

### Within-milestone parallelism (informs roadmap brief decomposition)

- **M1:** Version single-source (FOUND-01..02) is independent of hook hardening (HOOK-06..09). Two parallel briefs possible. Installer hardening (FOUND-03..06) is independent of statusline (FOUND-08). Three-way split possible.
- **M2:** All four new agents (`@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`) are file-independent. Parallelizable. Frontmatter-linter blocks until all agents land.
- **M3:** Two new hooks (pre-tool-use, post-tool-use) are independent. The two existing-hook updates (session-start, post-compact) are independent. Parallelizable up to 4-wide.
- **M4:** Skills are file-independent but **semantically chained**. Recommend sequential build (`/mission` → `/brief` → `/plan` → `/build` → `/verify` → `/ship`) so each can be smoke-tested in a temp consumer repo before the next is written. Helpers (`/debug`, `/tdd`, `/refactor`, `/explore-repo`) parallelizable after main chain.
- **M5:** Five CI gates are mostly independent. shellcheck, JSON-schema, frontmatter-linter, vocabulary, version-drift can land in parallel. bats smoke depends on all install/skill machinery working.

## Section 5 — Plugin-mode vs Manual-mode Parity Contract

**The contract:** plugin mode and manual mode produce the **same user-visible behavior**. Hook bindings, permissions, statusline, agent invocation, skill discovery — all identical. The only difference is **where files load from**.

### File-by-file parity table

| File | Plugin mode | Manual mode | Identical behavior? |
|---|---|---|---|
| `.claude-plugin/plugin.json` | Read by plugin loader for metadata | Read by `install.sh` for version | YES |
| `rules/godmode-*.md` | Read from `${CLAUDE_PLUGIN_ROOT}/rules/` | Copied to `~/.claude/rules/`, read from there | YES |
| `agents/<name>.md` | Read from `${CLAUDE_PLUGIN_ROOT}/agents/` | Copied to `~/.claude/agents/`, read from there | YES |
| `skills/<name>/SKILL.md` | Read from `${CLAUDE_PLUGIN_ROOT}/skills/` | Copied to `~/.claude/skills/<name>/`, read from there | YES |
| `commands/godmode.md` | Read from `${CLAUDE_PLUGIN_ROOT}/commands/` | Copied to `~/.claude/commands/` | YES |
| `hooks/session-start.sh` | Bound via `hooks/hooks.json` with `${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh` | Copied to `~/.claude/hooks/`, bound via `~/.claude/settings.json` with `~/.claude/hooks/session-start.sh` | YES (same script, same args, same env) |
| `hooks/post-compact.sh` | Same as above | Same as above | YES |
| `hooks/pre-tool-use.sh` | Same as above | Same as above | YES |
| `hooks/post-tool-use.sh` | Same as above | Same as above | YES |
| `config/statusline.sh` | Bound via `hooks/hooks.json` | Copied to `~/.claude/hooks/`, bound via `~/.claude/settings.json` | YES |
| `config/quality-gates.txt` | Read from `${CLAUDE_PLUGIN_ROOT}/config/` by hooks | Copied to `~/.claude/config/`, read from there | YES |
| `config/settings.template.json` | Permissions block merged into `~/.claude/settings.json` | Permissions + hooks + statusLine all merged | Same end state in `~/.claude/settings.json` |
| `templates/.planning/` | Read from `${CLAUDE_PLUGIN_ROOT}/templates/` by `/mission` | Copied to `~/.claude/templates/`, read from there | YES |

### What guarantees parity

1. **Single source for hook event metadata.** The hook bindings (event name, matcher, command, timeout) live in `config/settings.template.json[hooks]`. `hooks/hooks.json` is its plugin-mode mirror — same events, same matchers, same timeouts, only the command path differs (`${CLAUDE_PLUGIN_ROOT}/hooks/x.sh` vs `~/.claude/hooks/x.sh`).

2. **CI parity gate** (`scripts/check-parity.sh`, called by `.github/workflows/parity.yml`) asserts:
   - `hooks/hooks.json` and `config/settings.template.json[hooks]` reference the same event names.
   - Same matchers per event.
   - Same timeout per event.
   - Same script basename per command (only path prefix differs).
   - Same permissions block (allow / deny / ask lists agree byte-for-byte).
   - If they drift, CI fails the PR.

3. **`install.sh` is the only writer of `~/.claude/settings.json`.** Both modes go through it. Plugin mode merges only the permissions block; manual mode merges permissions + hooks + statusLine. The merge is `jq -s '.[0] * .[1]'` — last-wins on conflicts, idempotent on re-run.

4. **Same scripts, same env, same args.** A hook script doesn't care whether it lives at `${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh` or `~/.claude/hooks/session-start.sh`. It reads stdin, calls `git`, emits JSON. Path-independent.

5. **Live indexing reads the actual install location.** `/godmode` does `ls "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/agents/"` — same enumeration, same result, different prefix.

### Where parity could silently break (and how M5 prevents it)

| Drift mode | M5 mechanism that catches it |
|---|---|
| Add a hook to `hooks/hooks.json` but forget `config/settings.template.json` | `scripts/check-parity.sh` diffs the two; CI fails. |
| Change a timeout in one but not the other | Same script — diffs timeouts. |
| Add a permission to `settings.template.json` but document a different one in README | `scripts/check-vocabulary.sh` (greps README for documented permissions; cross-refs settings.template.json). Optional v2.x extension; v2.0 just gates hooks/permissions. |
| Hook script path uses `~` expansion in plugin mode (which fails because `${CLAUDE_PLUGIN_ROOT}` is the right prefix) | bats `parity.bats` test installs both modes in temp $HOME and asserts hook fires correctly in both. |
| Bump version in `plugin.json` but forget `install.sh` echo | `scripts/check-version-drift.sh` — already in M1. |

## Section 6 — Live Indexing Contract

`/godmode`, `PostCompact` hook, and `SessionStart` hook all need to enumerate "what agents and skills are available?" from the live filesystem. The contract that makes this safe:

### Glob patterns (canonical)

```bash
# Agents — single .md file per agent at the top of agents/
agents_glob="agents/*.md"

# Skills — directory per skill, with SKILL.md inside
skills_glob="skills/*/SKILL.md"

# Briefs (consumer-side, in user repos) — directory per brief, with BRIEF.md inside
briefs_glob=".planning/briefs/*/BRIEF.md"

# Commands — single .md file per command at the top of commands/
commands_glob="commands/*.md"
```

### Frontmatter requirements (what makes a file "indexable")

A file is **discoverable** if its glob matches **and** it has the required frontmatter. Files without required frontmatter are skipped silently (allows `_shared/`, drafts, READMEs to coexist).

| Layer | Required frontmatter keys | Example |
|---|---|---|
| Agent | `name`, `model`, `effort`, `Connects to:` | `agents/planner.md` with `name: planner`, `model: opus`, `effort: xhigh`, `Connects to: /plan invokes @planner` |
| Skill | `name`, `description`, `Connects to:`, `spawns:` | `skills/build/SKILL.md` with `name: build`, `description: "..."`, `Connects to: /plan → /build → /verify`, `spawns: [@executor, @code-reviewer]` |
| Command | `name`, `description` | `commands/godmode.md` with `name: godmode`, `description: "Show project state and next action"` |
| Brief (consumer-side) | `# Brief NN — <name>` H1 (no YAML frontmatter; first H1 line is the index entry) | `# Brief 3 — Hook Layer Expansion` |

### Ignored paths (never indexed)

```
agents/_*.md        # underscore-prefix = private/draft
agents/README.md    # README files at any layer
skills/_shared/     # shared fragments are NOT skills
skills/*/README.md
commands/_*.md
.planning/briefs/_template/   # template scaffold, never an active brief
*.tmpl              # all template files
*.bak, *.swp        # editor artifacts
```

### Ordering rules (deterministic, no flakiness)

1. **Lexicographic by filename.** `ls` + `sort` (LC_ALL=C sort, not locale-dependent).
2. **Briefs ordered by NN prefix** (numeric, zero-padded). `briefs/01-foundation/`, `briefs/02-agents/`, etc.
3. **Within `/godmode` output:** workflow-chain order (mission → brief → plan → build → verify → ship), then helpers (debug, tdd, refactor, explore-repo) lexicographic.

### Frontmatter linter contract (M2's `scripts/lint-frontmatter.sh`)

The linter is the **enforcement mechanism** for the indexing contract. It runs in CI and fails the PR on any of:

- Missing required key for the layer.
- `model` not in {opus, sonnet, haiku} (no pinned numeric IDs).
- `effort` not in {low, medium, high, xhigh}.
- `effort: xhigh` on a code-writing agent (`@executor`, `@writer`, `@test-writer` — Opus 4.7 xhigh-skips-rules pitfall).
- `spawns:` (skill frontmatter) referencing an agent that doesn't exist on disk.
- `Connects to:` referencing a skill or agent that doesn't exist.
- YAML parse error.

This makes "live indexing safe" mechanical: any drift between frontmatter and reality fails CI before merge.

### Reading the index at runtime (the actual shell)

```bash
# /godmode skill — enumerate agents
agents=$(
  for f in "${ROOT}/agents/"*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    case "$name" in _*|README) continue ;; esac
    # Extract Connects to: line; skip if absent (file is not indexable)
    connects=$(awk '/^Connects to:/{sub(/^Connects to: */,""); print; exit}' "$f")
    [ -n "$connects" ] || continue
    printf '%s\t%s\n' "$name" "$connects"
  done | sort
)

# /godmode skill — enumerate skills
skills=$(
  for d in "${ROOT}/skills/"*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    case "$name" in _*) continue ;; esac
    [ -f "$d/SKILL.md" ] || continue
    connects=$(awk '/^Connects to:/{sub(/^Connects to: */,""); print; exit}' "$d/SKILL.md")
    [ -n "$connects" ] || continue
    printf '%s\t%s\n' "$name" "$connects"
  done | sort
)
```

This is the same shape used by `PostCompact` and `SessionStart` hooks — three call sites, one pattern.

## Section 7 — Memory Boundary (consolidated answer)

The milestone explicitly asks: what's persisted in `~/.claude/projects/.../memory/` vs `.planning/` vs git? The boundary:

| Kind of state | Storage | Why |
|---|---|---|
| **Mission, requirements, decisions, key tradeoffs** | `<consumer>/.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md` | Project-scoped source of truth. User-readable. Survives plugin upgrades. |
| **Active brief pointer + status** | `<consumer>/.planning/STATE.md` | Machine-mutated by `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`. User reads, never writes. SessionStart hook re-injects so context survives compaction. |
| **Per-brief artifacts (why + what + spec; tasks + verification)** | `<consumer>/.planning/briefs/NN-name/{BRIEF.md, PLAN.md}` | Two files per active brief. Discoverable. git-trackable. Survives session end. |
| **Per-task execution log (what changed, why, by whom)** | `git log` (atomic commits with REQ-IDs) | The execution log IS git. PLAN.md tracks status (pending/in-flight/done/failed); git carries the diff and rationale. |
| **Cross-cutting tribal knowledge an agent learns over time** (e.g. "this codebase uses snake_case for shell vars") | `~/.claude/projects/<project-id>/memory/` via `memory: project` in the agent's frontmatter | Only `@architect` and `@researcher` justify this in v2 — they're the agents whose value compounds with project history. Other agents (executor, writer, reviewer) get fresh context per invocation, by design. |
| **Plugin's installed version stamp** | `~/.claude/.claude-godmode-version` | Read by `uninstall.sh` for version-mismatch refusal. Single line file. |
| **Plugin source files (rules, agents, skills, hooks, config)** | `${CLAUDE_PLUGIN_ROOT}` (plugin mode) or `~/.claude/{rules,agents,skills,hooks}` (manual mode) | Distributed via `install.sh`. Updated on plugin upgrade. |
| **The plugin's OWN development planning** | `<this-repo>/.planning/` (gitignored) | This directory. Distinct from consumer-side `.planning/`. v2 is built using GSD's planning shape; the plugin we ship uses its own shape. Two different concerns. |

### When does each get written?

- **`config.json`** — once, by `/mission` on first run. Stable thereafter.
- **`PROJECT.md`** — by `/mission` on init; appended-to at milestone transitions.
- **`REQUIREMENTS.md`** — by `/mission` on init; mutated as requirements move {Active → Validated → Out of Scope}.
- **`ROADMAP.md`** — by `/mission` on init; mutated when briefs are added/reordered.
- **`STATE.md`** — by EVERY skill transition. Tiny file, mostly two fields: `active_brief: NN`, `status: <enum>`.
- **`briefs/NN-name/BRIEF.md`** — by `/brief N`; rare edits during `/plan` if spec changes.
- **`briefs/NN-name/PLAN.md`** — by `/plan N` (initial); per-task status updates by `/build N`; verification block by `/verify N`.
- **`git log`** — by every quality-gated commit during `/build`.
- **`~/.claude/projects/<id>/memory/`** — by `@architect`/`@researcher` on their natural rhythm; opaque to skills.
- **`~/.claude/.claude-godmode-version`** — by `install.sh` only.

### When NOT to write to memory

Never write to `~/.claude/projects/<id>/memory/` from a skill. Memory is for agents, not for orchestration. If a skill needs cross-session state, it goes in `.planning/STATE.md` (which is in the consumer's git, surviving compaction and discoverable by the user).

## Section 8 — Patterns to Follow (v2-specific)

### Pattern 1: Skills own orchestration; agents are atomic

Skills know the order, the fan-out, and which agents to call. Agents do not call agents. Tree call graph, never DAG.

### Pattern 2: Read-only by default; isolation when writing

Every agent declares either `disallowedTools: Write, Edit` (read-only — safe to parallelize) or `isolation: worktree` (write-bounded — won't corrupt user's tree). Never both unset.

### Pattern 3: Live filesystem indexing, never hardcoded lists

Anywhere the system enumerates agents/skills/briefs (`/godmode`, `PostCompact`, `/build` task validation), it reads the directory at runtime per the live-indexing contract above.

### Pattern 4: jq for everything JSON; never string-interpolate JSON

`jq -n --arg name "$value" '{...}'`, never `echo "{\"name\": \"$value\"}"`. Hardened in M1.

### Pattern 5: One artifact per workflow gate, atomic commit

Every workflow transition mutates exactly one file (or one tightly-coupled set) and commits atomically with a REQ-ID-bearing message. `git log` IS the execution log.

### Pattern 6: Single source of truth for everything that drifts

- Version → `.claude-plugin/plugin.json`
- Hook bindings → `config/settings.template.json` + `hooks/hooks.json` (CI-checked mirror)
- Quality gates → `config/quality-gates.txt`
- Skill list / agent list → the filesystem (live-indexed)

If two files claim authority over the same fact, that's a bug; M5 CI catches the common cases.

## Section 9 — Anti-Patterns to Avoid (v2-specific)

### Anti-Pattern 1: A `/everything` mega-command

A single command that runs the whole pipeline. Hides the workflow. Locked Out of Scope.

### Anti-Pattern 2: Per-task artifact files (`TASK.md`)

Duplicates state with git log; forces every task commit to also commit a markdown file. Use PLAN.md task-status block + git log only.

### Anti-Pattern 3: Agents spawning agents

Turns the call graph from tree to DAG. Hides cost from the skill (which is the only place a budget can be set). Forbidden.

### Anti-Pattern 4: Auto-prompt-engineering of user intent

A skill silently rewrites the user's request before invoking an agent. Breaks trust. The user's words are the spec, verbatim.

### Anti-Pattern 5: Touching `~/.claude/settings.json` outside `install.sh`

That file is the user's, not the plugin's. Direct mutation breaks idempotency, races with other plugins, prevents `uninstall.sh` from cleanly restoring.

### Anti-Pattern 6: Hardcoded skill/agent lists in PostCompact (v1.x bug #8)

PostCompact previously hardcoded the list. v2 reads from the filesystem per the live-indexing contract.

### Anti-Pattern 7: Quality gates in two files (v1.x bug #9)

Gates list lived in CLAUDE.md AND post-compact.sh. Drift inevitable. v2 has `config/quality-gates.txt` as single source.

## Section 10 — Scalability Considerations

The system is single-user single-repo, but parallelism inside `/build` is a real scalability axis: how many `@executor` instances run concurrently?

| Scale | Tasks per wave | Strategy |
|---|---|---|
| Small brief (≤5 tasks) | 1–3 | All in one wave; trivially parallel |
| Medium brief (6–20 tasks) | 3–5 per wave | Wave-based; partition by `dependsOn` |
| Large brief (>20 tasks) | 5 max per wave | Cap concurrency at 5; queue overflow |

Cap exists because each `@executor` worktree is a checkout, and disk + Claude Code Task tool concurrency limits are real. v1.x already accumulates ~27 worktrees in `.claude/worktrees/`. M5 ships `scripts/prune-worktrees.sh` and a CONTRIBUTING.md recipe.

## Section 11 — Confidence by Component

| Component | Confidence | Source |
|---|---|---|
| Five-layer model (rules / agents / skills / hooks / config) | HIGH | v1.x baseline + locked Key Decisions |
| 11-command user surface | HIGH | Locked in PROJECT.md + IDEA.md |
| Skill→Agent invocation matrix | HIGH | REQUIREMENTS.md Active section + locked routing |
| Build order M1→M5 | HIGH | Dependency-driven; matches existing ROADMAP.md |
| New top-level dirs (scripts/, tests/, templates/) | HIGH | Each has explicit reason; no overlap with existing dirs |
| Plugin/manual parity contract | HIGH | Identical to v1.x; v2 adds CI gate to enforce |
| Live-indexing contract (globs + frontmatter + ignores) | HIGH | Glob patterns are mechanical; frontmatter linter enforces in CI |
| Memory boundary (STATE.md vs git vs memory:) | HIGH | PROJECT.md locks the artifacts; `memory: project` justified per-agent in M2 |
| `/build` parallel orchestration internals | MEDIUM | `run_in_background` + worktree pattern locked; file-polling fallback details land in M4 |
| `templates/.planning/` content | MEDIUM | Layout fixed (PROJECT/REQUIREMENTS/ROADMAP/STATE + briefs/_template); .tmpl bodies designed in M4 |

## Section 12 — Open Questions for Brief Discussion

These belong in `/brief N` Socratic discussions for the relevant milestone, not blockers for roadmap construction:

1. **M1 (Foundation):** Should `PreToolUse` block `git commit -n` (short form) in addition to `--no-verify`? Recommend: yes, both patterns.
2. **M2 (Agents):** Does `@verifier` run with `background: true`, or foreground? Recommend foreground — verification is interactive enough that streaming output matters.
3. **M3 (Hooks):** Should `post-tool-use.sh` re-run gates on every Bash exit, or only on commit-related ones? Recommend commit-related only — performance budget.
4. **M4 (Skills):** `/build`'s wave-concurrency cap — hardcoded 5, or `.planning/config.json` knob? Recommend hardcoded 5 in v2.0; knob in v2.1 if users hit the ceiling.
5. **M4 (State):** Should `STATE.md` be hand-editable, or always machine-mutated? Recommend machine-mutated only; user reads, never writes. If user wants to override active brief, they edit ROADMAP.md and re-run `/godmode` which re-derives.
6. **M4 (Migration):** Detection note in `/godmode`, `SessionStart`, or both? Recommend both, but suppressed in `SessionStart` after first session via a marker file.

---

*Architecture research: 2026-04-26 (claude-godmode v2 — polish mature version)*
*Sources: PROJECT.md (locked decisions), IDEA.md (vision + workflow model), .planning-archive-v1/codebase/{ARCHITECTURE,STRUCTURE}.md (v1.x baseline), .planning-archive-v1/research/ARCHITECTURE.md (prior architecture pass under same constraints).*
