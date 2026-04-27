# Phase 4: Skill Layer & State Management — Research

**Researched:** 2026-04-27
**Domain:** Claude Code 2026 skill layer authoring, bash 3.2 + jq state management, wave-based subagent orchestration
**Confidence:** HIGH (Claude Code skill/permission/agent contracts re-verified against code.claude.com 2026-04-27; bash + jq idioms locked in Phases 1-3 production; Phase 4 is downstream consolidation, not greenfield protocol design)

## Summary

Phase 4 ships the entire user-facing surface of v2.0 — the 11 skills, the `.planning/STATE.md` machine-mutated state vehicle, the `init-context.sh` shared helper, the `.planning/` artifact templates, and the v1.x deprecation banners. **Every locked decision (D-01..D-55 in `04-CONTEXT.md`) constrains the implementation; nothing about "should we do X" is in scope.** This research instead resolves the *how* of those locked decisions — argument substitution syntax, Auto Mode detection mechanics, polling-fallback recipes, slug derivation, template substitution edge cases, recommended `allowed-tools` allowlists per skill.

Phase 4 sits on the substrate Phases 1-3 already shipped: live-FS scan (FOUND-11), `config/quality-gates.txt` SoT (FOUND-07), version drift CI (FOUND-02), 12 modernized agents with valid frontmatter (AGENT-01..08), four hooks (`hooks.json` and `settings.template.json` aligned, PreToolUse blocks `--no-verify`, PostToolUse surfaces failed gates, SessionStart parses STATE.md YAML front matter, PostCompact reads gates list and live FS). PostCompact and SessionStart already do STATE.md YAML parsing in `awk` — Phase 4 must lift that exact awk recipe into `skills/_shared/init-context.sh` instead of re-implementing. Phase 5 (CI + bats + parity gate + vocab gate) is downstream and treats Phase 4's output as source of truth.

**Primary recommendation:** Build `skills/_shared/init-context.sh` first (Plan 04-01) — it's the substrate every other skill `source`s. Then templates + `/godmode` + `/mission` (the entry points). Then the workflow chain (`/brief`, `/plan`, `/build`, `/verify`, `/ship`). Then helpers + deprecation banners. Author every skill against the locked frontmatter convention (D-04) and recommended `allowed-tools` allowlist below; the Phase 5 frontmatter linter (extended from AGENT-06) will mechanically enforce.

## User Constraints

### Locked Decisions

(Copied verbatim from `04-CONTEXT.md` `<decisions>` block — D-01 through D-55. Planner MUST honor these as constraints.)

**Skill file location & shape (WORKFLOW-01):**
- **D-01:** 11 user-invocable surface = `commands/godmode.md` + 10 `skills/<name>/SKILL.md`. Verification: `find commands skills -name '*.md' -type f | grep '^commands/godmode.md\|/SKILL.md$' | wc -l == 11`. `/godmode` stays in `commands/` because it's bootstrap-shaped.
- **D-02:** Slot 12 reserved, empty in v2.0. Documented in `rules/godmode-skills.md`: adding a 12th skill is a v2.x RFC.
- **D-03:** v1.x skills (`skills/{prd,plan-stories,execute}/SKILL.md`) stay on disk with deprecation banners (D-23). NOT counted toward 11-cap.

**Skill frontmatter convention (D-04, D-05):** Every v2 skill has — in this exact order — `name`, `description` (≤200 chars), `user-invocable: true`, `allowed-tools` (scoped, never wildcard), `argument-hint: "[N]"` (for the 4 parameterized skills), `arguments: [N]` (for those same 4), `disable-model-invocation: true` (for `/build`, `/ship`). Body opens with `## Connects to`. **`model:` and `effort:` keys are OMITTED** — owned by the agent the skill spawns.

**`Connects to:` chain (D-06, D-07):** Each skill body has `## Connects to` after the H1 with bullets `**Upstream:**`, `**Downstream:**`, `**Reads from:**`, `**Writes to:**`. `/godmode` renders the chain at runtime via `grep -A 20 '^## Connects to' commands/godmode.md skills/*/SKILL.md`.

**Auto-Mode detection (D-08, D-09, D-10):** Case-insensitive substring search for the literal string `"Auto Mode Active"` in the most recent system reminder. Each Socratic skill includes the detection block at top of body. The 6 workflow skills (`/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`) MUST include; the 4 helpers SHOULD. Recommended-default policy locked per skill (`/mission` scaffolds with sensible defaults, `/brief` picks first plausible interpretation, `/plan` produces single-wave unless 3+ disjoint atomic tasks, `/build` skips preview confirmation, `/verify` reports without asking, `/ship` refuses on PARTIAL/MISSING — never auto-`--force`).

**`init-context.sh` shared helper (D-11..D-15):** Path `skills/_shared/init-context.sh`. Pure bash 3.2 + jq 1.6+. `godmode_init_context "$PWD"` is the single entry point. JSON output schema locked at `schema_version: 1` with fields `project_root`, `planning.{exists,config_path,state_path,briefs_dir}`, `state.{exists,active_brief,active_brief_slug,active_brief_dir,status,next_command,last_activity}`, `config.{exists,model_profile,auto_advance}`, `briefs[]`, `v1x_pipeline_detected`. All JSON via `jq -n --arg`. STATE.md parsing via `awk` for YAML front matter. **Performance: <100ms p99 on ≤50-brief project.** Never exit non-zero.

**`.planning/STATE.md` format (D-16..D-19):** Hybrid YAML front matter (machine-mutated) + markdown audit log (append-only). Fixed v1 keys: `godmode_state_version` (always 1), `active_brief` (int), `active_brief_slug` (kebab-case), `status` (free-form), `next_command` (string starting with `/`), `last_activity` (string). Mutation via shared `godmode_state_update()` function (`init-context.sh` or `state.sh` per D-25): awk extracts → jq -n constructs → awk preserves audit log → mv atomically. v1.x compat: read either `gsd_state_version` or `godmode_state_version`, normalize on next mutation.

**Templates (D-20..D-22):** Ship under `templates/.planning/`. Substitution: `{{variable}}` placeholders, replaced via `sed -e 's|{{var}}|val|g'` (`|` delimiter — variables may contain `/`). 5 project-level + 2 brief-level template files. Brief directory: `.planning/briefs/NN-slug/` (zero-padded N).

**v1.x deprecation banners (D-23..D-25):** `/prd`, `/plan-stories`, `/execute` SKILL.md prepended with banner block (migration table), wrapped in marker check at `~/.claude/.claude-godmode-v1-banner-shown`. One-time per install. Removed in v2.x.

**`/godmode` orient (D-26..D-28):** Computes ≤5-line "what now?" answer by sourcing init-context, branching on `state.exists`. Live-lists agents + skills + briefs via `find` (D-27). Preserves `/godmode statusline` sub-command from v1.x (D-28).

**`/mission` (D-29..D-31):** 5 Socratic questions (project name, core value, tech stack, milestone, brief decomposition). Output: 5 templated files. Idempotent — no-ops if `.planning/PROJECT.md` exists.

**`/brief N` (D-32..D-34):** Title (slug derived) → why → what → spec (falsifiable) → optional research → optional spec-reviewer (default yes). Output: BRIEF.md. Updates STATE.md (`active_brief = N`, `status = "Ready to plan"`).

**`/plan N` (D-35..D-37):** Reads BRIEF.md, spawns `@planner`, writes PLAN.md (Wave 1, Wave 2, Verification status, Brief success criteria sections). Wave heuristic: disjoint file sets + no logical dependency = same wave. Concurrency cap = 5 (D-39); waves with >5 split as Xa/Xb. Updates STATE.md.

**`/build N` (D-38..D-45):** `Agent(run_in_background=true)` per task, file-polling fallback at `.planning/briefs/NN-slug/.build/{task-X.Y.started,done,failed}`. Polling interval 2s (env: `GODMODE_POLL_INTERVAL`, undocumented). Per-task timeout 30 min. Atomic commit per task: `<type>(<scope>): <task-name> [brief NN.M]`. Resume detection: grep git log for `[brief NN.M]` token. `.build/` gitignored at `.planning/.gitignore`. On failure: let running tasks finish, collect `.failed` payloads, refuse next wave.

**`/verify N` (D-46..D-48):** Spawns `@verifier` (read-only). Skill body has Write capability scoped to PLAN.md only — orchestrator does the actual mutation of the "Verification status" section. Updates STATE.md (`status = "Ready to ship"` if all COVERED; else `"Verify found gaps"`).

**`/ship` (D-49..D-51):** Verify STATE.md status → check PLAN.md for non-COVERED → run 6 quality gates from `config/quality-gates.txt` → push → `gh pr create`. `--force` flag bypasses #2 (PARTIAL/MISSING refusal) only; never bypasses gates. Updates STATE.md to `"Shipped {pr_url}"`.

**Cross-cutting helpers (D-52, D-53):** `/debug`, `/tdd`, `/refactor`, `/explore-repo` — bodies inherit from v1.x but rewritten to v2 shape (Auto Mode block, `## Connects to` section, scoped `allowed-tools`, `argument-hint`). Major rewrites deferred to v2.1.

**State helper organization (D-54, D-55):** Read entry point: `skills/_shared/init-context.sh`. Mutations: `skills/_shared/state.sh` (or merged with init-context.sh if file stays under ~150 lines). Optional `skills/_shared/_lib.sh` for color helpers, atomic file replace, slug derivation.

### Claude's Discretion

- Exact wording of the 5 Socratic questions in `/mission` (D-29) — `@planner` may rephrase based on what produces clearer answers; the 5 fields are the contract, not the question text.
- Wave heuristic specifics in `@planner` (D-36) — "disjoint file sets + no logical dependency" is the contract; tunable.
- Whether `_lib.sh` exists separately (D-55) — keep merged if `init-context.sh` stays under ~150 lines.
- Exact polling interval / timeout for `.build/` markers (D-40) — recommended values; planner may shift if benchmarking suggests.
- Banner text for v1.x deprecation (D-23) — wording illustrative; planner may adjust as long as migration table + one-time mechanism preserved.

### Deferred Ideas (OUT OF SCOPE)

- **OUT-01:** CI workflow + bats + parity gate + vocab gate → Phase 5.
- **OUT-02:** README rewrite + CHANGELOG dating + marketplace metadata → Phase 5.
- **OUT-03:** `GODMODE_BUILD_CONCURRENCY` knob → v2.1.
- **OUT-04:** Statusline rewrite for new brief-aware shape (already done in Phase 1 FOUND-06).
- **OUT-05:** Merging `@writer`/`@executor` → v2.1.
- **OUT-06:** `GODMODE_POLL_INTERVAL`, `GODMODE_TASK_TIMEOUT` knobs → v2.1.
- **OUT-07:** A 12th slash command — RFC required.
- **OUT-08:** Reverse migration (`godmode_state_version → gsd_state_version`) — not supported, not needed.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| WORKFLOW-01 | Exactly 11 user-facing slash commands; ≤12 cap; 1 reserved | "Frontmatter convention" + "Recommended `allowed-tools` per skill" sections below |
| WORKFLOW-02 | `/godmode` ≤5-line state-aware "what now?", live-lists agents/skills/briefs | "`/godmode` rendering recipe" + "Live-FS substrate reuse" |
| WORKFLOW-03 | `/mission` Socratic init writes 5 project files; idempotent | "Idempotent file-mutation pattern" + "Template substitution mechanics" |
| WORKFLOW-04 | `/brief N` produces single BRIEF.md (no SPEC/CONTEXT/RESEARCH) | "Brief slug derivation algorithm" + "Skill argument substitution" |
| WORKFLOW-05 | `/plan N` spawns `@planner`, writes PLAN.md | Phase 2 already shipped `@planner`; this section just shows the spawn shape |
| WORKFLOW-06 | `/build N` wave-based parallel via `Agent(run_in_background=true)` + file-polling fallback | "Wave dispatch + polling pattern" — most novel piece, deepest research |
| WORKFLOW-07 | `/verify N` spawns `@verifier`; updates PLAN.md verification | Phase 2 already shipped `@verifier`; "Read-only verifier + orchestrator-mutation pattern" |
| WORKFLOW-08 | `/ship` runs 6 gates from `config/quality-gates.txt` | "Quality-gate execution mechanism" |
| WORKFLOW-09 | 4 helpers (`/debug`, `/tdd`, `/refactor`, `/explore-repo`) rewritten to v2 shape | "Helper modernization recipe" |
| WORKFLOW-10 | v1.x deprecation banners on `/prd`, `/plan-stories`, `/execute`; one-time | "Deprecation banner one-time-marker pattern" |
| WORKFLOW-11 | Auto Mode detection in every skill | "Auto Mode reminder canonical shape + detection idiom" |
| WORKFLOW-12 | `skills/_shared/init-context.sh` — pure bash + jq, returns JSON | "init-context.sh structure + performance budget" — substrate, deepest research |
| WORKFLOW-13 | Templates ship under `templates/.planning/` | "Template substitution mechanics" |
| WORKFLOW-14 | `.planning/STATE.md` format + skill mutation mechanism | "STATE.md awk parsing + atomic replace" |

## Project Constraints (from CLAUDE.md)

- **Two workflow shapes** — plugin product uses brief-shape vocabulary; dev process uses GSD's phase-shape (this `.planning/`). Phase 4 is BUILDING the product. Skill bodies use brief vocabulary; rules and agents (internal docs) may use phase vocabulary.
- **Bash 3.2+ and jq 1.6+ ONLY at runtime.** No Node, no Python, no helper binary, no SDK.
- **Atomic commits per workflow gate.** Never `--no-verify`. PreToolUse hook (Phase 3) enforces.
- **macOS + Linux portability.** No bash-4-only constructs. WSL2 for Windows.
- **No new mandatory runtime deps. No telemetry. No network calls outside user-authorized tools.**
- **MIT, no copyleft deps.**
- **Single source of truth for version.** `.claude-plugin/plugin.json:.version`. `commands/godmode.md` and skills must NOT carry literal versions.
- **Reference scope:** read GSD/Superpowers/everything-claude-code freely; copy nothing structural; no vocabulary borrowed.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| User input → workflow orchestration | Skills (Layer 3) | — | Skills own all orchestration. They spawn agents, mutate `.planning/`, run gates. |
| Atomic per-task implementation | Agents (Layer 2) — `@executor` in worktree | — | Agents do one bounded job. Skills never write source. |
| State mutation (`.planning/STATE.md`) | Skills via `state.sh` helper | — | Skills only writer of STATE.md. Agents don't mutate state. |
| Live filesystem enumeration | Skills (`/godmode`) + hooks (`PostCompact`, `SessionStart`) | — | Both consumers; FOUND-11 substrate is shared. Lift hook awk parser into shared helper. |
| Quality gate execution | Skills (`/ship`) reading `config/quality-gates.txt` | Hooks enforce mechanically (PreToolUse blocks bypass; PostToolUse surfaces failed exit codes) | `/ship` runs gates as commands; hooks defend against bypass. Two layers of enforcement. |
| Per-task atomic commit | Agents inside worktree (`@executor` does `git commit`) | PreToolUse hook blocks `--no-verify` | Skills delegate commit to agent (they own the diff); hook is the safety net. |
| Wave-based parallel dispatch | `/build` skill body | — | Only the skill knows the wave plan. `Agent()` API is a tool the skill calls; the skill is the orchestrator. |
| Auto Mode awareness | Every workflow skill body | — | Detection is per-skill (skills can't introspect prior reminders portably). Convention: top-of-body block referencing `rules/godmode-skills.md`. |
| Template materialization | Skills (`/mission`, `/brief`) | — | Templates are static data files; skills own the substitution + write. |

## Standard Stack

### Core (already locked, no alternatives — ALL HIGH confidence from STACK.md and Phases 1-3 production)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 3.2+ | Skill bodies, `init-context.sh`, `state.sh`, `_lib.sh` | macOS default shell. PROJECT.md hard constraint. [VERIFIED: install.sh + Phase 1 shipped] |
| jq | 1.6+ | All JSON construction in helpers; STATE.md mutation; init-context output | Only mandatory runtime tool. PROJECT.md hard constraint. All Phase 1-3 hooks already use it via `-n --arg`. [VERIFIED: hooks/post-compact.sh, hooks/session-start.sh] |
| awk | POSIX | YAML front matter parsing in STATE.md | Already lifted in `hooks/session-start.sh:60-62` and `hooks/post-compact.sh:57-59` — Phase 4 reuses verbatim. [VERIFIED: source files] |
| sed | POSIX (BSD/GNU compatible) | Template `{{var}}` substitution; STATE.md scrub | `sed -e 's|{{var}}|val|g'` works on both BSD (macOS) and GNU. [VERIFIED: standard portable usage] |
| find | POSIX | Live FS scan in `/godmode` and init-context.sh briefs[] enumeration | Already used in `hooks/post-compact.sh:19-20` for FOUND-11. [VERIFIED: source file] |
| `Agent()` Claude Code tool | n/a | `/build` wave dispatch with `run_in_background=true` | Only documented mechanism for parallel subagent dispatch in Claude Code 2026. [CITED: code.claude.com/docs/en/sub-agents — fetched 2026-04-27] |

### Supporting (existing files Phase 4 reuses)

| File | Purpose | When to Use |
|------|---------|-------------|
| `hooks/session-start.sh:60-62` (awk YAML parser) | Reference for `init-context.sh`'s STATE.md parser | Lift verbatim into `_shared/init-context.sh`; the hook stays unchanged |
| `hooks/post-compact.sh:19-20` (find + sort + tr) | Reference for `/godmode`'s agent + skill enumeration | Same pattern with `LC_ALL=C` for deterministic ordering |
| `config/quality-gates.txt` | 6 gates one per line, no formatting | `/ship` reads via `while IFS= read -r line; do …` (bash 3.2 portable; `mapfile`/`readarray` not available) |
| `agents/{planner,verifier,spec-reviewer,code-reviewer}.md` | Agents the workflow skills spawn | Already shipped in Phase 2. Skills reference by name in `Task` invocations. |
| `install.sh` `info()/warn()/error()` color helpers | UX consistency | Lift into `skills/_shared/_lib.sh` if helpers are needed by skills (D-55 optional) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `awk` for STATE.md parsing | `yq` | yq is not bash 3.2 + jq — adds a Node/Python/Go dep. Hard NO. |
| `sed -e 's|{{var}}|val|g'` for templates | `envsubst`, `m4`, `mustache` (npm) | All add deps. `sed` is portable; `{{var}}` mustache-style is unambiguous. |
| Polling files for `Agent()` completion | Pure stdout-of-Agent-call inspection | CR-08 documents the stdout-corruption race. Files in `.build/` are atomic via `mv`; stdout is a stream. **Files are authoritative.** [CITED: PITFALLS.md CR-08] |
| `mapfile -t arr < f` (bash 4+) | `while IFS= read -r l; do arr+=("$l"); done < f` | macOS `/bin/bash` is 3.2 — `mapfile` is a fatal syntax error. [VERIFIED: PITFALLS CR-04] |
| `${var,,}` lowercase | `tr '[:upper:]' '[:lower:]'` | Same — bash 4+ only. Use `tr`. |
| Heredoc for JSON | `jq -n --arg` | CR-02 — heredoc with shell interpolation breaks on quotes/backslashes/newlines. NEVER. [VERIFIED: PITFALLS.md CR-02] |
| `Agent()` plain (foreground) | `Agent(run_in_background=true)` | Foreground serializes the wave — defeats parallelism. CR-08 mandates background + file polling. [CITED: PITFALLS.md CR-08] |

**Installation:** No new runtime dependencies. All targets already on disk after Phases 1-3.

**Version verification:** Tools verified across Phases 1-3 production:
- bash 3.2: shipped on every macOS since 2007 [CITED: PITFALLS CR-04]
- jq 1.6: PROJECT.md constraint floor
- Claude Code: floor `v2.1.111` (Opus 4.7 alias resolution); Auto Mode floor `v2.1.83`. [CITED: STACK.md "Version compatibility floor"]

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│ USER                                                                     │
│   types `/godmode`, `/mission`, `/brief 4`, `/plan 4`, `/build 4`, etc. │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ SKILL BODY (markdown + frontmatter)                                      │
│   1. Auto Mode check (grep "Auto Mode Active" in last system reminder)  │
│   2. source skills/_shared/init-context.sh                              │
│   3. CTX=$(godmode_init_context "$PWD")                                 │
│   4. Branch on state.exists / config.model_profile                      │
│   5. Spawn agent (Task tool) OR mutate .planning/ OR both               │
│   6. Update STATE.md via godmode_state_update                           │
└─┬─────────────────────────┬─────────────────────┬───────────────────────┘
  │                         │                     │
  ▼                         ▼                     ▼
┌────────────────────┐ ┌────────────────────┐ ┌──────────────────────────┐
│ init-context.sh    │ │ Agent (Task tool)  │ │ State mutation           │
│   reads:           │ │   /brief→@spec-…   │ │   awk extract YAML       │
│     .planning/     │ │   /plan→@planner   │ │   jq -n construct new    │
│     config.json    │ │   /build→@executor │ │   awk preserve audit log │
│     STATE.md       │ │     ×N parallel    │ │   mv atomic replace      │
│     briefs/*/      │ │   /verify→@verif…  │ │                          │
│   emits JSON       │ │   /ship→@security  │ │                          │
└────────────────────┘ └─────────┬──────────┘ └──────────────────────────┘
                                 │
                                 ▼ (only for /build wave dispatch)
┌──────────────────────────────────────────────────────────────────────────┐
│ WAVE DISPATCH ORCHESTRATION (`/build` skill body)                         │
│   foreach task in wave:                                                  │
│     Agent(run_in_background=true, prompt="@executor: task X")            │
│       → executor writes .planning/briefs/NN/.build/task-X.started        │
│       → executor commits (PreToolUse blocks --no-verify; gates run)      │
│       → executor writes .build/task-X.done   OR  .build/task-X.failed    │
│   loop with sleep 2s:                                                    │
│     check .build/*.done count == wave size  → next wave                  │
│     OR any .build/*.failed exists           → abort, surface failures    │
│     OR timeout 30 min/task                  → surface stuck task         │
└──────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ GIT (atomic commit per task; PreToolUse hook enforces gates)             │
│   commit message: <type>(<scope>): <task-name> [brief NN.M]              │
│   PostToolUse surfaces failed gate exit codes into next turn             │
└──────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| File | Responsibility |
|------|----------------|
| `commands/godmode.md` | Bootstrap + ≤5-line orient (D-26..D-28). Reads init-context, branches on state.exists, lists agents/skills/briefs via `find`. Preserves v1.x rules-check + statusline sub-command. |
| `skills/mission/SKILL.md` | 5 Socratic questions → 5 templated files; idempotent (D-29..D-31). |
| `skills/brief/SKILL.md` | Title→slug→why→what→spec; spawns `@spec-reviewer`; writes BRIEF.md (D-32..D-34). |
| `skills/plan/SKILL.md` | Reads BRIEF.md; spawns `@planner`; writes PLAN.md with Verification status section (D-35..D-37). |
| `skills/build/SKILL.md` | Reads PLAN.md task graph; wave-based dispatch via `Agent(run_in_background=true)`; polls `.build/` markers; per-task atomic commit (D-38..D-45). **Most complex skill.** |
| `skills/verify/SKILL.md` | Spawns `@verifier`; mutates PLAN.md "Verification status" section in place (D-46..D-48). Skill body has narrow `Write` permission scoped to PLAN.md per D-47. |
| `skills/ship/SKILL.md` | Reads `config/quality-gates.txt`; checks PLAN.md verification; runs gates; pushes; `gh pr create` (D-49..D-51). |
| `skills/{debug,tdd,refactor,explore-repo}/SKILL.md` | Modernized v2 shape (D-52, D-53). Bodies inherit v1.x semantics. |
| `skills/{prd,plan-stories,execute}/SKILL.md` | Deprecation banner prepended; one-time marker check (D-23, D-24). v1.x body preserved verbatim below banner. |
| `skills/_shared/init-context.sh` | `godmode_init_context()` function; reads `.planning/config.json` + STATE.md + briefs[]; emits JSON (D-11..D-15). p99 <100ms. |
| `skills/_shared/state.sh` | `godmode_state_update()` mutation function; awk-extract → jq-construct → awk-preserve-audit → mv atomic (D-17, D-54). |
| `skills/_shared/_lib.sh` (optional) | Color helpers, atomic file replace, slug derivation (D-55). May merge with init-context.sh if size < 150 lines. |
| `templates/.planning/{PROJECT,REQUIREMENTS,ROADMAP,STATE,config.json}.md.tmpl` | Project-level scaffolds; `{{var}}` placeholders. |
| `templates/.planning/briefs/{BRIEF,PLAN}.md.tmpl` | Brief-level scaffolds. |

### Pattern 1: Source-and-call init-context

**What:** Every skill that needs project state sources `init-context.sh` at the top and calls `godmode_init_context "$PWD"`.

**When to use:** Every workflow skill (`/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`). Helpers optional but recommended for consistency.

**Recipe (in skill body):**

```bash
# Source: skills/_shared/init-context.sh design (this phase)
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/init-context.sh"

CTX=$(godmode_init_context "$PWD")

# Read fields with safe defaults
ACTIVE=$(printf '%s' "$CTX" | jq -r '.state.active_brief // empty')
STATUS=$(printf '%s' "$CTX" | jq -r '.state.status // "Not started"')
NEXT_CMD=$(printf '%s' "$CTX" | jq -r '.state.next_command // "/godmode"')
```

**Anti-pattern:** Re-implementing `.planning/config.json` + STATE.md parsing in each skill body.

### Pattern 2: STATE.md atomic-replace mutation

**Recipe (in `skills/_shared/state.sh`):**

```bash
# Source: D-17 + Phase 3 D-13 awk pattern + Phase 1 D-08 jq pattern
godmode_state_update() {
  local active_brief="$1" active_brief_slug="$2" status="$3" next_cmd="$4" audit_line="$5"
  local state_file=".planning/STATE.md"
  local tmp_file
  tmp_file=$(mktemp -t godmode-state.XXXXXX) || return 1

  # 1. Build new YAML front matter via jq (NEVER heredoc — CR-02)
  local new_fm
  new_fm=$(jq -nr \
    --argjson v 1 \
    --argjson n "$active_brief" \
    --arg slug "$active_brief_slug" \
    --arg s "$status" \
    --arg c "$next_cmd" \
    --arg a "$(date -u +%Y-%m-%dT%H:%M:%SZ) — $audit_line" \
    '"---\ngodmode_state_version: \($v)\nactive_brief: \($n)\nactive_brief_slug: \($slug)\nstatus: \($s)\nnext_command: \($c)\nlast_activity: \"\($a)\"\n---"')

  # 2. Preserve audit log body via awk (skip prior front matter, keep rest)
  local body
  body=$(awk '/^---$/{c++; if(c==2){next} if(c==1){next}} c>=2' "$state_file" 2>/dev/null || echo "")

  # 3. Compose
  printf '%s\n\n%s\n- %s — %s\n' "$new_fm" "$body" "$(date -u +%Y-%m-%d)" "$audit_line" > "$tmp_file"

  # 4. Atomic replace
  mv "$tmp_file" "$state_file"
}
```

**Why atomic:** A skill that crashes mid-edit must NOT leave STATE.md half-rewritten. `mv` is atomic on POSIX filesystems.

### Pattern 3: Live-FS enumeration (FOUND-11 reuse)

**Recipe (lifted from `hooks/post-compact.sh:19-20`):**

```bash
# Source: hooks/post-compact.sh (Phase 1, FOUND-11 — VERIFIED in production)
LC_ALL=C  # deterministic ordering across macOS / Linux
AGENTS=$(find "$ROOT/agents" -maxdepth 1 -name '*.md' -not -name '_*' -not -name 'README.md' \
         -exec basename {} .md \; 2>/dev/null | sort)
SKILLS=$(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -not -name '_*' \
         -exec basename {} \; 2>/dev/null | sort)
BRIEFS=$(find ".planning/briefs" -mindepth 1 -maxdepth 1 -type d \
         -not -name '_*' -not -name '.*' 2>/dev/null | sort)
```

**Anti-pattern:** Hardcoded skill / agent / brief list anywhere in `commands/godmode.md` body or `skills/*/SKILL.md`. CI grep gate (Phase 5) catches `@architect`/`@executor`/etc. literals.

### Pattern 4: `Agent(run_in_background=true)` with file-polling fallback

**When to use:** `/build` skill only. Foreground `Agent()` is fine for sequential per-task review (e.g., `@code-reviewer` after each task), but parallel-within-wave MUST use background + polling.

**Recipe:**

```bash
# Source: D-40 + PITFALLS CR-08 + sub-agents docs (code.claude.com/docs/en/sub-agents)
# (This shape lives in /build skill instructions — Claude orchestrates the dispatch loop)

WAVE_DIR=".planning/briefs/${BRIEF_NN}-${SLUG}/.build"
mkdir -p "$WAVE_DIR"

# For each task in current wave, dispatch in background via Task() / Agent() with run_in_background=true
# Subagent prompt MUST instruct the agent to:
#   - touch "$WAVE_DIR/$task_id.started" on entry
#   - touch "$WAVE_DIR/$task_id.done" on success
#   - on failure, write stderr tail to "$WAVE_DIR/$task_id.failed" and exit
# (See /build SKILL.md body for the exact agent prompt template)

# Poll for completion (concurrency cap = 5 hardcoded; D-39)
INTERVAL="${GODMODE_POLL_INTERVAL:-2}"
DEADLINE=$(($(date +%s) + 1800))  # 30 min per task ceiling
while :; do
  done_count=$(find "$WAVE_DIR" -name '*.done' 2>/dev/null | wc -l | tr -d ' ')
  failed_count=$(find "$WAVE_DIR" -name '*.failed' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$failed_count" -gt 0 ]; then
    # D-43: let other running tasks finish, but refuse to start next wave
    break
  fi
  if [ "$done_count" -ge "${#WAVE_TASKS[@]}" ]; then
    break  # wave complete
  fi
  if [ "$(date +%s)" -gt "$DEADLINE" ]; then
    # surface stuck-task warning, don't assume failure
    break
  fi
  sleep "$INTERVAL"
done
```

**Why this exact shape:**
- `find -name '*.done'` is the ONLY ground truth (per CR-08 stdout corruption).
- `mv` (or `>file`) is atomic on POSIX; touching a marker is safe.
- 2s poll interval balances responsiveness vs CPU; 30-min ceiling matches `@executor maxTurns: 100`.
- Letting in-flight tasks finish on failure (D-43) is conservative — they may have salvageable commits.
- Resume detection (D-44): grep `git log --grep='\[brief NN\.'` rather than re-checking markers; commits are durable, `.build/` may be pruned.

### Pattern 5: Auto Mode detection block (top of every workflow skill body)

**Recipe (canonical — D-08, D-09):**

```markdown
## Auto Mode check

Before proceeding, scan the most recent system reminder for the case-insensitive
substring "Auto Mode Active". If detected:

- Auto-approve routine decisions (e.g., file overwrite confirms in `/mission`).
- Pick recommended defaults for ambiguity (don't ask).
- Never enter plan mode unless explicitly asked.
- Treat user course corrections as normal input.

If NOT detected: proceed in interactive Socratic mode (ask one question at a time
via AskUserQuestion).

Detection patterns and recommended defaults are documented in `rules/godmode-skills.md`.
```

**Why this works:** Skills cannot programmatically introspect prior reminders portably (Claude Code does not expose a "system reminder list" API). The convention is "the model checks at the top of every Socratic skill" — Phase 5's vocabulary gate also greps `commands/` + `skills/*/SKILL.md` for the canonical detection phrase to enforce.

**Empirical canonical reminder text** (verified in this research session by reading the live `<system-reminder>` block when `permission_mode: auto` was active):

```
## Auto Mode Active

Auto mode is active. The user chose continuous, autonomous execution. You should:

1. **Execute immediately** — Start implementing right away. Make reasonable assumptions and proceed on low-risk work.
2. **Minimize interruptions** — Prefer making reasonable assumptions over asking questions for routine decisions.
3. **Prefer action over planning** — Do not enter plan mode unless the user explicitly asks. When in doubt, start coding.
4. **Expect course corrections** — The user may provide suggestions or course corrections at any point; treat those as normal input.
5. **Do not take overly destructive actions** — Auto mode is not a license to destroy. Anything that deletes data or modifies shared or production systems still needs explicit user confirmation.
6. **Avoid data exfiltration** — Post even routine messages to chat platforms or work tickets only if the user has directed you to. You must not share secrets ...
```

The `## Auto Mode Active` heading is the stable detection target. The list under it is informational. Substring match is enough. [VERIFIED in this research session]

### Anti-Patterns to Avoid

- **Hardcoded skill/agent/brief list** in `commands/godmode.md` body. Phase 5 vocab CI gate (QUAL-04) fails the PR. [VERIFIED: PITFALLS HI-02]
- **Heredoc + variable interpolation in JSON construction** in `init-context.sh` or `state.sh`. Use `jq -n --arg`. [VERIFIED: PITFALLS CR-02]
- **`memory` used as substitute for STATE.md** — agents may use `memory: project` for cross-session learnings but MUST NOT mutate run-state via memory. State mutations go through `state.sh` only. [VERIFIED: PITFALLS HI-01]
- **Vocabulary leakage** — `phase` / `task` / `story` / `PRD` / `gsd-*` / `cycle` / `milestone` MUST NOT appear in user-facing skill bodies. Internal docs (`rules/`, `agents/`, `.planning/`) are exempt. Phase 5 enforces. [VERIFIED: PITFALLS HI-06]
- **Auto Mode rubber-stamp drift** — auto-pick must match what a user would actually want (D-10 recommended-default policy). Don't auto-pick destructive options. [VERIFIED: PITFALLS CR-06]
- **Background `Agent` stdout race** — `/build` MUST use `Agent(run_in_background=true)` with file-polling fallback (D-40). NEVER plain `Agent()` for parallel within-wave dispatch. [VERIFIED: PITFALLS CR-08]
- **Statusline regression** — Phase 1 collapsed statusline to single jq invocation. Phase 4 doesn't touch statusline. [VERIFIED: Phase 1 D-11, FOUND-06]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| YAML front matter parsing in STATE.md | Custom YAML parser in bash | Lift `awk` block from `hooks/session-start.sh:60-62` verbatim | Already production-tested in Phase 3, handles edge cases, bash 3.2 portable |
| Live-FS enumeration | Maintained skill/agent registry file | `find` with `LC_ALL=C` + `sort` (`hooks/post-compact.sh:19-20`) | Drift-free; FOUND-11 substrate; identical pattern across `/godmode`, PostCompact, SessionStart |
| JSON construction in init-context.sh | Heredoc with shell variable interpolation | `jq -n --arg KEY "$VAL"` | CR-02 — heredoc is adversarial-unsafe |
| Brief slug derivation | Custom regex in awk/sed | Bash 3.2: `tr 'A-Z ' 'a-z-' \| sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//'` | One pipeline; no edge cases that need custom logic |
| Per-skill state file format | Custom .meta files | STATE.md as the one place; init-context.sh as the read API | One source of truth; user-readable; survives compaction |
| Wave-completion detection | Parsing Agent stdout | File markers in `.planning/briefs/NN/.build/` | CR-08 — stdout is not authoritative |
| Quality gate runner | Hand-coded gate sequence in `/ship` body | Read `config/quality-gates.txt` line-by-line via `while IFS= read -r` | FOUND-07 — single source of truth |
| Atomic file replace for STATE.md | `cat > $file` (non-atomic on partial-write) | `mktemp` + write + `mv` (atomic on POSIX) | mv is the standard atomic-replace primitive |
| Argument extraction in parameterized skills | Manual `$ARGUMENTS` parsing | Declared `arguments: [N]` frontmatter + `$N` substitution | Native Claude Code 2026 feature; documented schema [CITED: code.claude.com/docs/en/skills] |
| Auto Mode detection | Reminder introspection API | Substring match on `"Auto Mode Active"` reminder text | Reminder is what Claude Code itself injects [VERIFIED: live session reminder, this session] |

**Key insight:** Almost every problem in Phase 4 has an existing solution from Phases 1-3 to lift verbatim. The novel work is (1) `Agent(run_in_background=true)` orchestration with file-polling fallback, (2) the JSON schema design for `init-context.sh`, (3) skill bodies authored to v2 shape. Everything else reuses substrate.

## Detailed Research — the locked decisions need these specifics

### `init-context.sh` structure + performance budget

**File:** `skills/_shared/init-context.sh`

**Function shape:** `godmode_init_context()` takes one positional arg `$1` (project root, default `$PWD`), emits JSON to stdout, never exits non-zero.

**Recommended structure (target ≤150 lines — D-55):**

```bash
#!/usr/bin/env bash
# skills/_shared/init-context.sh
# Pure bash 3.2 + jq 1.6+. Sourced by every skill that needs project state.
set -euo pipefail

godmode_init_context() {
  local root="${1:-$PWD}"

  local schema_version=1
  local planning_dir="$root/.planning"
  local state_path="$planning_dir/STATE.md"
  local config_path="$planning_dir/config.json"
  local briefs_dir="$planning_dir/briefs"

  # Probe planning/ existence
  local planning_exists=false
  [ -d "$planning_dir" ] && planning_exists=true

  # Probe STATE.md and parse YAML front matter (lifted from hooks/session-start.sh)
  local state_exists=false
  local active_brief='' active_brief_slug='' status='' next_cmd='' last_activity=''
  if [ -f "$state_path" ]; then
    state_exists=true
    # Accept either godmode_state_version or gsd_state_version (D-18 v1.x compat)
    active_brief=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^active_brief:/ {sub(/^active_brief:[[:space:]]*/,""); print; exit}' "$state_path" 2>/dev/null || echo "")
    active_brief_slug=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^active_brief_slug:/ {sub(/^active_brief_slug:[[:space:]]*/,""); print; exit}' "$state_path" 2>/dev/null || echo "")
    status=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^status:/ {sub(/^status:[[:space:]]*/,""); print; exit}' "$state_path" 2>/dev/null || echo "")
    next_cmd=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^next_command:/ {sub(/^next_command:[[:space:]]*/,""); print; exit}' "$state_path" 2>/dev/null || echo "")
    last_activity=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^last_activity:/ {sub(/^last_activity:[[:space:]]*/,""); print; exit}' "$state_path" 2>/dev/null || echo "")
  fi

  # Probe config.json
  local config_exists=false
  local model_profile='balanced' auto_advance=false
  if [ -f "$config_path" ]; then
    config_exists=true
    model_profile=$(jq -r '.model_profile // "balanced"' "$config_path" 2>/dev/null || echo balanced)
    auto_advance=$(jq -r '.auto_advance // false' "$config_path" 2>/dev/null || echo false)
  fi

  # v1.x detection
  local v1x_detected=false
  [ -d "$root/.claude-pipeline" ] && v1x_detected=true

  # Briefs enumeration — single find pass; jq -s to slurp into array (D-14 perf)
  local briefs_json='[]'
  if [ -d "$briefs_dir" ]; then
    briefs_json=$(find "$briefs_dir" -mindepth 1 -maxdepth 1 -type d -not -name '_*' -not -name '.*' 2>/dev/null \
      | LC_ALL=C sort \
      | while IFS= read -r d; do
          local name n slug has_brief=false has_plan=false
          name=$(basename "$d")
          n=$(printf '%s' "$name" | sed -E 's/^([0-9]+)-.*/\1/' | sed 's/^0*//' | sed 's/^$/0/')
          slug=$(printf '%s' "$name" | sed -E 's/^[0-9]+-//')
          [ -f "$d/BRIEF.md" ] && has_brief=true
          [ -f "$d/PLAN.md" ] && has_plan=true
          jq -nc --argjson n "$n" --arg slug "$slug" --arg dir "$d" \
            --argjson hb "$has_brief" --argjson hp "$has_plan" \
            '{n: $n, slug: $slug, dir: $dir, has_brief: $hb, has_plan: $hp}'
        done | jq -s '.')
  fi

  # Compose output JSON via jq -n --arg / --argjson (NEVER heredoc — CR-02)
  jq -n \
    --argjson schema_version "$schema_version" \
    --arg project_root "$root" \
    --argjson planning_exists "$planning_exists" \
    --arg config_path ".planning/config.json" \
    --arg state_path ".planning/STATE.md" \
    --arg briefs_dir ".planning/briefs" \
    --argjson state_exists "$state_exists" \
    --arg active_brief_raw "${active_brief:-}" \
    --arg active_brief_slug "${active_brief_slug:-}" \
    --arg status "${status:-}" \
    --arg next_cmd "${next_cmd:-}" \
    --arg last_activity "${last_activity:-}" \
    --argjson config_exists "$config_exists" \
    --arg model_profile "$model_profile" \
    --argjson auto_advance "$auto_advance" \
    --argjson briefs "$briefs_json" \
    --argjson v1x_detected "$v1x_detected" \
    '{
      schema_version: $schema_version,
      project_root: $project_root,
      planning: {exists: $planning_exists, config_path: $config_path, state_path: $state_path, briefs_dir: $briefs_dir},
      state: {
        exists: $state_exists,
        active_brief: ($active_brief_raw | tonumber? // null),
        active_brief_slug: $active_brief_slug,
        status: $status,
        next_command: $next_cmd,
        last_activity: $last_activity
      },
      config: {exists: $config_exists, model_profile: $model_profile, auto_advance: $auto_advance},
      briefs: $briefs,
      v1x_pipeline_detected: $v1x_detected
    }'
}
```

**Performance:**
- 5 awk calls per STATE.md (~5ms each = ~25ms)
- Single `find` pass for briefs (~10ms for ≤50 briefs)
- One `jq -n` to compose (~30ms)
- p99 target: <100ms — achievable on warm-cache filesystem

**Optimization if perf budget tight:** combine all 5 awk extracts into ONE awk pass that emits a tab-separated tuple, then `IFS=$'\t' read -r ACT SLUG STATUS NEXT_CMD LA <<< "$(awk ...)"` (mirrors Phase 1 D-11 statusline single-jq pattern).

[VERIFIED via reading hooks/session-start.sh:60-62 + hooks/post-compact.sh:57-59 + Phase 1 D-11 statusline single-jq pattern]

### Skill argument substitution (verified against code.claude.com/docs/en/skills)

| Variable | Behavior | When to use in v2 |
|----------|----------|---------------------|
| `$ARGUMENTS` | Full string as typed (`/brief 4 quick fix` → `4 quick fix`) | If skill takes free-form text |
| `$ARGUMENTS[0]`, `$ARGUMENTS[1]` | Indexed by 0; shell-style quoting (`/brief "hello world" two` → `$0=hello world`, `$1=two`) | When you need positional args without naming |
| `$N` (e.g., `$0`, `$1`) | Shorthand for `$ARGUMENTS[N]` | More readable than `$ARGUMENTS[0]` |
| `$<name>` (e.g., `$N`, `$brief_id`) | Named arg via frontmatter `arguments: [N]` | **v2 standard for parameterized skills** |
| `${CLAUDE_SESSION_ID}` | Current session ID | Logging, session-scoped temp files |
| `${CLAUDE_SKILL_DIR}` | Directory containing SKILL.md | Reference bundled scripts/data |

**v2 convention (D-04):** The 4 parameterized skills (`/brief`, `/plan`, `/build`, `/verify`) declare:
```yaml
argument-hint: "[N]"
arguments: [N]
```
The body then references `$N` (which expands to the brief number). Example: `/brief 4` → skill body sees `$N` = `4`.

**Edge cases:**
- **Missing arg:** If user types `/brief` (no N), `$N` expands to empty string. Skill body must check: `if [ -z "$N" ]; then ask user, else proceed`. The skill MUST handle this gracefully — Auto Mode picks the next missing brief number; non-Auto Mode asks.
- **Non-numeric arg:** `/brief foo` → `$N=foo`. Skill validates with `case "$N" in ''|*[!0-9]*) error ;; *) ok ;; esac` (bash 3.2 portable).
- **Quoted multi-word:** `/brief "user authentication"` → `$N=user authentication`. For brief number this is invalid; skill validates and rejects.

[CITED: code.claude.com/docs/en/skills — fetched 2026-04-27, "Available string substitutions" table; "Pass arguments to skills" section]

### `disable-model-invocation: true` interaction (verified)

Setting `disable-model-invocation: true` on `/build` and `/ship`:
- **User typing `/build 4` directly: still works.** [CITED: code.claude.com/docs/en/skills — "Control who invokes a skill" table: `disable-model-invocation: true` row → "You can invoke: Yes; Claude can invoke: No"]
- **Claude reading the skill description in context: it's NOT in context.** ("Description not in context, full skill loads when you invoke") — so Claude won't auto-trigger `/build` based on a chat message. **This is the intended behavior** for side-effecting skills.
- **`user-invocable: true` (default) + `disable-model-invocation: true`:** the combination D-04 specifies. The user can type `/build N`; Claude can't auto-trigger.

**Failure modes:**
- If user has BOTH `disable-model-invocation: true` AND `user-invocable: false`, neither party can invoke. v2 NEVER sets both.
- The Skill tool permission allow-list (`Skill(build *)` etc.) is independent of these flags.

### Recommended `allowed-tools` per skill (D-04)

Phase 4 skills should declare scoped `allowed-tools` (never wildcard) to minimize permission surface and to make `/permissions` audit clean:

| Skill | Recommended `allowed-tools` | Rationale |
|-------|------------------------------|-----------|
| `/godmode` | `Read, Bash(find *), Bash(git *), Bash(jq *), Bash(awk *), Bash(grep *)` | Read-only orient + live-FS enumeration |
| `/mission` | `Read, Write, Bash(mkdir *), Bash(jq *), Bash(sed *), AskUserQuestion` | Writes 5 project files; Socratic |
| `/brief N` | `Read, Write, Bash(mkdir *), Bash(jq *), Bash(sed *), Bash(git *), Task(spec-reviewer), AskUserQuestion` | Writes BRIEF.md; spawns spec-reviewer |
| `/plan N` | `Read, Write, Bash(jq *), Bash(sed *), Bash(git *), Task(planner)` | Spawns planner; writes PLAN.md |
| `/build N` | `Bash(*), Read, Write, Edit, Task(executor), Task(code-reviewer)` | Most permissive — needs git, mkdir, find, jq for marker polling. PreToolUse hook is the safety net. |
| `/verify N` | `Read, Write, Edit, Bash(git *), Bash(grep *), Bash(find *), Task(verifier)` | Read-only verifier, but skill body mutates PLAN.md verification section per D-47 |
| `/ship` | `Read, Bash(git *), Bash(gh *), Bash(jq *), Bash(<gate commands>)` | Runs gates; pushes; creates PR |
| `/debug` | `Read, Grep, Glob, Bash(*)` | Free-form debugging |
| `/tdd` | `Read, Write, Edit, Bash(<test commands>), Task(test-writer)` | Test-first dev |
| `/refactor` | `Read, Write, Edit, Bash(*), Task(architect)` | Multi-file changes |
| `/explore-repo` | `Read, Grep, Glob, Bash(find *), Bash(git *)` | Read-only exploration |

[CITED: D-04 + code.claude.com/docs/en/skills "Pre-approve tools for a skill"]

**Note:** `/build` is the most permissive — by design — because it's the orchestrator. The PreToolUse hook (Phase 3) blocks `--no-verify` mechanically; the worktree isolation in `@executor` (Phase 2 D-15) prevents cross-task interference.

### Brief slug derivation (D-22, bash 3.2 portable)

**Algorithm:**
```bash
# Input: free-form brief title (e.g., "User Authentication & SSO!")
# Output: kebab-case slug (e.g., "user-authentication-sso")
godmode_slug() {
  printf '%s' "$1" \
    | tr '[:upper:] ' '[:lower:]-' \
    | sed 's/[^a-z0-9-]//g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//; s/-$//'
}
```

**Edge cases:**
- Empty input → empty string. Caller must validate.
- All-special-chars (`"!@#"`) → empty string. Caller fallback: derive from brief number (e.g., `brief-04`).
- Collision (two briefs with same slug): zero-padded NN prefix prevents directory collisions even with same slug. Document collision-with-suffix handling deferred to v2.1 if surfaces.

[CITED: bash 3.2 `tr`/`sed` portable — `${var,,}` (lowercase) is bash 4+ only per PITFALLS CR-04]

### Template substitution mechanics (D-20)

**Recipe (in `/mission`, `/brief N`, `/plan N`):**

```bash
TPL="${CLAUDE_PLUGIN_ROOT}/templates/.planning/PROJECT.md.tmpl"
DEST=".planning/PROJECT.md"

# Substitute (use | as delimiter — variables may contain /)
sed -e "s|{{project_name}}|$PROJECT_NAME|g" \
    -e "s|{{core_value}}|$CORE_VALUE|g" \
    -e "s|{{tech_stack}}|$TECH_STACK|g" \
    -e "s|{{milestone_name}}|$MILESTONE|g" \
    -e "s|{{date}}|$(date -u +%Y-%m-%d)|g" \
    "$TPL" > "$DEST"
```

**Edge cases:**
- **Variable contains `|`:** sed delimiter conflict. Recipe: validate user input doesn't contain `|`; if it does, reject in skill body.
- **Variable contains backslash:** sed treats `\` as escape. Pre-process: `VAL=$(printf '%s' "$VAL" | sed 's/\\/\\\\/g; s/&/\\&/g')`.
- **Multi-line value:** sed handles single-line; for true multi-line, use `awk` instead. v2.0 templates: all values are single-line by convention.
- **Variable contains `}}`:** breaks the placeholder. Validate input.

**Template variable documentation block (top of every .tmpl file):**

```markdown
<!-- TEMPLATE VARIABLES (substituted by /mission or /brief)
  {{project_name}}      — kebab-case project slug
  {{display_title}}     — human-readable title
  {{core_value}}        — one-line core-value statement
  {{tech_stack}}        — free-form tech stack notes
  {{milestone_name}}    — first milestone
  {{date}}              — ISO date YYYY-MM-DD
  Constraints: values must be single-line; no | or }} characters.
-->
```

### `/godmode` rendering recipe

**Body (≤5 lines hard constraint per D-26):**

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/init-context.sh"
CTX=$(godmode_init_context "$PWD")

EXISTS=$(printf '%s' "$CTX" | jq -r '.state.exists')
if [ "$EXISTS" != "true" ]; then
  echo "No .planning/. Run /mission to start."
  echo "Agents: $(find "$ROOT/agents" -maxdepth 1 -name '*.md' -not -name '_*' -not -name 'README.md' | wc -l | tr -d ' ')"
  echo "Skills: $(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -not -name '_*' | wc -l | tr -d ' ')"
  echo "Branch: $(git branch --show-current 2>/dev/null || echo unknown)"
  exit 0
fi

N=$(printf '%s' "$CTX" | jq -r '.state.active_brief // empty')
SLUG=$(printf '%s' "$CTX" | jq -r '.state.active_brief_slug // empty')
STATUS=$(printf '%s' "$CTX" | jq -r '.state.status // empty')
NEXT=$(printf '%s' "$CTX" | jq -r '.state.next_command // empty')
LAST=$(printf '%s' "$CTX" | jq -r '.state.last_activity // empty' | cut -c1-40)

# Line 1: the answer
echo "Brief $N: $SLUG. Status: $STATUS. Next: $NEXT. Last: $LAST."
# Lines 2-5: inventory
echo "Agents: $(find "$ROOT/agents" -maxdepth 1 -name '*.md' -not -name '_*' -not -name 'README.md' | wc -l | tr -d ' ')"
echo "Skills: $(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -not -name '_*' | wc -l | tr -d ' ')"
echo "Briefs: $(printf '%s' "$CTX" | jq -r '.briefs | length')"
echo "Branch: $(git branch --show-current 2>/dev/null || echo unknown)"
```

**Phase 5 bats can verify:** `wc -l` on `/godmode` output ≤ 5.

**Inventory mode:** D-27 — when user types `/godmode` mid-session, render three columns (agent count, skill count, brief count) plus the chain `Connects to:` graph rendered from D-07. Same skill body — append after the ≤5-line answer.

**Statusline subcommand (`/godmode statusline`):** preserved verbatim from v1.x lines 106-167. The new orient body wraps the existing flow.

### v1.x deprecation banner one-time mechanic (D-23, D-24)

**Marker file location: `~/.claude/.claude-godmode-v1-banner-shown`**

**Why `~/.claude/` not `${CLAUDE_PLUGIN_DATA}`:**
- `${CLAUDE_PLUGIN_ROOT}` resets on plugin update (per Phase 1 D-04 / STACK.md "${CLAUDE_PLUGIN_ROOT} vs ${CLAUDE_PLUGIN_DATA}")
- `${CLAUDE_PLUGIN_DATA}` (= `~/.claude/plugins/data/<id>/`) survives updates **and is per-installation persistent** — but is plugin-scoped
- The v1.x deprecation banner is **user-scoped** ("show this user the migration note once"). If they uninstall and reinstall, they should see it again. **Therefore `~/.claude/` is correct** — survives plugin updates AND uninstall.

**Banner block (in v1.x SKILL.md bodies, prepended above existing v1.x body):**

```markdown
<!-- v2.0 DEPRECATION BANNER — display once per install -->

If `~/.claude/.claude-godmode-v1-banner-shown` does not exist:
1. Display the migration banner below.
2. `touch ~/.claude/.claude-godmode-v1-banner-shown`
3. Proceed to v1.x body.

If the marker file exists, skip the banner block and proceed to v1.x body.

# ⚠ Deprecated — use `/brief N` instead

This command was renamed in v2.0:

| v1.x | v2.0 |
|---|---|
| `/prd` | `/brief N` |
| `/plan-stories` | `/plan N` |
| `/execute` | `/build N` |

The old body still works for projects on the v1.x layout (`.claude-pipeline/`).
Run `/mission` to migrate to the v2 layout (`.planning/`).

Banner shown once per install — re-display: `rm ~/.claude/.claude-godmode-v1-banner-shown`.

--- v1.x body below ---

[original v1.x content preserved verbatim]
```

The skill body itself is the marker check — Claude reads the body, sees the conditional, evaluates, optionally touches the marker, then proceeds.

### `/ship` quality-gate execution (D-49)

**File format reminder:** `config/quality-gates.txt` has 6 lines, **descriptions not commands** (verified):

```
Typecheck (zero errors)
Lint (zero errors; shellcheck clean for any .sh change)
All tests pass
No hardcoded secrets
No regressions
Changes match requirements (REQ-IDs in commit message where applicable)
```

These are **assertions**, not executable commands. `/ship` body must:

1. **Read the gate descriptions** from `config/quality-gates.txt` to display the checklist.
2. **Auto-detect actual commands** for gates 1-3 from project config (preserve verbatim from v1.x `skills/ship/SKILL.md` lines 25-32):
   - Typecheck: `tsc --noEmit`, `mypy`, `cargo check`, `go vet`, `shellcheck` (for our repo)
   - Lint: `eslint`, `ruff`, `cargo clippy`, `golangci-lint`, `shellcheck`
   - Tests: `vitest`, `pytest`, `cargo test`, `go test`, `bats`
3. **Gate 4 (no secrets):** delegate to PreToolUse hook (Phase 3 D-05) — already enforced; `/ship` re-runs as belt-and-suspenders via `git diff --staged | grep -E '<secret patterns>'`.
4. **Gate 5 (no regressions):** run full test suite; compare to baseline if `git diff main` shows test-file changes.
5. **Gate 6 (REQ-ID coverage):** grep recent commit messages for `[brief NN.M]` token (D-38) and validate every PLAN.md task has a matching commit.

**Recipe:**
```bash
GATES_FILE="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/config/quality-gates.txt"
gate_num=0
all_passed=true
while IFS= read -r gate_desc; do
  gate_num=$((gate_num + 1))
  echo "Gate $gate_num: $gate_desc"
  # Auto-detect command + run; per-gate logic per the table above
done < "$GATES_FILE"

if [ "$all_passed" = false ]; then
  echo "[!] One or more gates failed. Refusing to ship."
  exit 1
fi
```

**Bash 3.2 portability note:** `mapfile -t lines < "$GATES_FILE"` is bash 4+ only. Use `while IFS= read -r line; do ... done < "$GATES_FILE"`. (PITFALLS CR-04.)

### Atomic commit message format `<type>(<scope>): <task-name> [brief NN.M]` (D-38)

**Resume detection regex (D-44):**
```bash
git log --grep='\[brief 04\.[0-9]\+\]' --pretty=format:'%H %s' main..HEAD
```

**Pattern:** literal `[brief NN.M]` where NN is zero-padded brief number, M is task index. Examples: `[brief 04.1]`, `[brief 04.10]`.

**PreToolUse interaction (Phase 3 D-01..D-04):** the hook only blocks bypass patterns (`--no-verify`, `-n`, `core.hooksPath`). Normal commits with the `[brief NN.M]` token format pass through unchanged. **No special handling needed in `/build`.** [VERIFIED: hooks/pre-tool-use.sh exists; Phase 3 D-01..D-04 documented]

### `/verify N` PLAN.md "Verification status" mutation pattern (D-46, D-47)

**Why orchestrator mutates, not `@verifier`:** D-47 — `@verifier` has `disallowedTools: Write, Edit` (read-only by mechanical contract, AGENT-04). The skill body has narrow Write capability scoped to PLAN.md. Flow:

1. `/verify N` skill body: spawn `@verifier` (Task tool), capture output (markdown table per `agents/verifier.md` output contract).
2. Parse the verifier's COVERED/PARTIAL/MISSING report.
3. Skill body uses `Edit` tool on `.planning/briefs/NN-slug/PLAN.md` to replace the "Verification status" section in place.
4. Append audit line to STATE.md via `godmode_state_update`.

**PLAN.md "Verification status" section (template per D-35):**

```markdown
## Verification status

- [ ] **Task 1.1** — STATUS (set by /verify)
- [ ] **Task 1.2** — STATUS
- [ ] **Task 2.1** — STATUS

## Brief success criteria

- [ ] **SC-1** — STATUS (set by /verify)
- [ ] **SC-2** — STATUS
```

After `/verify`, `STATUS` becomes `COVERED`, `PARTIAL`, or `MISSING` per task and per success criterion.

**Mutation recipe (Edit tool):**
- Skill body uses Edit with `old_string` = the entire `## Verification status\n\n...\n## Brief success criteria\n\n...` block
- `new_string` = the rewritten block with statuses filled in
- Single Edit call replaces the section atomically

## Runtime State Inventory

> Phase 4 is greenfield/additive — new skills, new templates, new helpers. NO RUNTIME STATE RENAME. Briefly:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — `.planning/STATE.md` is itself a NEW state vehicle this phase introduces (greenfield). The dev-side `.planning/STATE.md` (this repo) already uses `gsd_state_version` per GSD's shape — D-18 specifies forward-compat read but NOT migration of THIS repo's STATE.md. | None. Dev-side STATE.md stays GSD-shaped per "Two workflow shapes" doctrine. |
| Live service config | None — no external services. | None. |
| OS-registered state | None — no daemons, no Task Scheduler entries, no launchd plists. | None. |
| Secrets/env vars | `GODMODE_POLL_INTERVAL`, `GODMODE_TASK_TIMEOUT` — undocumented v2.0 env vars (D-40, OUT-06). Code reads them with `${VAR:-default}`; absent = default. No secret material. | None — undocumented escape hatches. |
| Build artifacts/installed packages | None — Phase 4 is markdown + bash files; no compilation, no package install. | After Phase 4, user re-runs `./install.sh` (manual mode) or pulls plugin update (plugin mode). Phase 5 verifies install round-trip via bats. |

**Nothing else found.** The `~/.claude/.claude-godmode-v1-banner-shown` marker (D-24) is created BY this phase, not pre-existing.

## Common Pitfalls

### Pitfall 1: Hardcoded skill/agent list in `commands/godmode.md`

**What goes wrong:** Adding `@planner` to the agent set requires editing 3+ files (godmode.md, post-compact.sh, README, CHANGELOG). PostCompact already reads from FS; godmode.md must too.

**Why it happens:** Markdown can't enumerate the filesystem inline; the temptation is to write a static table.

**How to avoid:** D-26..D-27 — `/godmode` body instructs Claude to "list `${CLAUDE_PLUGIN_ROOT}/skills/` and `${CLAUDE_PLUGIN_ROOT}/agents/`" via `find`, not write the list inline. Phase 5 vocab CI gate greps for `@architect`/`@executor`/etc. literals in `commands/godmode.md` and refuses any matches.

**Warning signs:** A new agent added in a PR with no test of `/godmode`'s output. The phrase "Available Agents:" followed by a static table in `commands/godmode.md`.

[VERIFIED: PITFALLS HI-02; existing `hooks/post-compact.sh` does this correctly]

### Pitfall 2: Background `Agent` race + polling deadlock

**What goes wrong:** `/build` spawns 5 parallel `@executor` agents. One crashes silently. Parent polls `.build/*.done` count, gets stuck because the failed task never wrote `.failed` either (it just died). Parent loops forever (or until 30-min timeout) — and the user sees no output.

**Why it happens:** `Agent(run_in_background=true)` returns an agent reference but no robust completion notification stream. CR-08 documents this. The workaround is files written by the agent, but that requires the agent itself to write the marker — which fails if the agent crashes before its first instruction.

**How to avoid:**
1. **Subagent prompt MUST `touch .build/$task_id.started` as its first action.** Proves the subagent at least started.
2. **Subagent prompt MUST `touch .build/$task_id.done` on success OR write `.build/$task_id.failed` on failure.** Both before agent return.
3. **Parent polls with two thresholds:** wave-complete (all `.done` count == wave size), wave-failed (any `.failed` exists). If neither AND a `.started` is older than 30 min, surface "Task X stalled" warning.
4. **Compounding insurance:** `git log --grep='[brief NN.M]'` is the durable evidence. If a `.started` marker exists but no `.done`, AND the commit doesn't appear after timeout, the task didn't complete. Resume retries it.

**Warning signs:** `/build` running >> wall-clock estimate. `.build/` has `.started` markers without matching `.done` or `.failed`.

[VERIFIED: PITFALLS CR-08; sub-agents docs (code.claude.com/docs/en/sub-agents) — fetched 2026-04-27]

### Pitfall 3: Skill body ignores Auto Mode → asks routine clarifying questions

**What goes wrong:** `/mission` always asks "Is this a TypeScript or Rust project?" In Auto Mode, this is interruption-as-default — violates the contract.

**Why it happens:** Skill author copies v1.x body verbatim, doesn't add the Auto Mode block.

**How to avoid:** D-08, D-09 — every workflow skill body opens with the Auto Mode check (Pattern 5 above). Phase 5's vocab gate greps for the canonical detection phrase ("Auto Mode Active" substring search instructions) in every `commands/*.md` and `skills/*/SKILL.md` and refuses if absent on the 6 workflow skills.

**Warning signs:** Skill body uses `AskUserQuestion` without first checking Auto Mode. Skill body lacks the `## Auto Mode check` heading.

[VERIFIED: PITFALLS ME-01 + CR-06]

### Pitfall 4: STATE.md mutation race when two skills run concurrently

**What goes wrong:** User runs `/build 4` in background while running `/godmode` in foreground. Both read STATE.md. `/build` updates `status` to "Building". `/godmode` re-reads, sees old status because `mv` wasn't atomic from `/godmode`'s read perspective.

**Why it happens:** Multi-skill concurrency is rare in user practice but possible. Atomic-replace via `mv` is atomic at the FS level but doesn't prevent stale reads.

**How to avoid:**
1. STATE.md mutations are infrequent (one per workflow gate). Skills don't loop-update.
2. Skills that *read* STATE.md (`/godmode`, `/build` resume detection) tolerate slightly-stale reads — they're rendering "what's true now," not enforcing invariants.
3. If a true ordering issue surfaces in v2.x, document deferral. (`flock` is GNU-only.)

**Warning signs:** STATE.md shows old status after a workflow transition. User reports `/godmode` says "Ready to plan" after `/plan` already finished.

[ASSUMED — no production data on concurrency rate. Mitigation is "infrequent updates make races unlikely."]

### Pitfall 5: Vocabulary leakage in skill bodies

**What goes wrong:** A skill body says "Phase 1 of the workflow" or "Story complete." User sees v1.x / GSD-internal vocabulary in v2.0 output. Trust collapse.

**Why it happens:** Skill author copies v1.x body, forgets to substitute terms.

**How to avoid:** Phase 5 vocab gate (QUAL-04) greps `commands/`, `skills/`, `README.md` for `phase`, `task`, `story`, `PRD`, `gsd-*`, `cycle`, `milestone`. Phase 4 ships clean. Internal docs (`rules/`, `agents/`, `.planning/`) are exempt.

**Warning signs:** Any skill body containing `phase`, `task`, etc. The v1.x deprecation banner table itself is the only legitimate use of `/prd`, `/plan-stories`, `/execute` (those are deprecated commands users may run).

[VERIFIED: PITFALLS HI-06]

### Pitfall 6: Performance regression in `init-context.sh`

**What goes wrong:** A naive implementation does `for d in briefs/*; do BRIEF=$(jq ... "$d/BRIEF.md"); ...; done` — 50 briefs × jq cold-start (~30ms) = 1.5s. Every `/godmode` invocation hits this.

**How to avoid:** Single `find` pass; pipe to `while IFS= read -r d` with `jq -nc` per brief; final `jq -s` to slurp into array. Total: ~30ms regardless of brief count. D-14 mandates p99 <100ms.

**Warning signs:** `time bash skills/_shared/init-context.sh "$PWD"` reports >100ms. Phase 5 bats can include a perf assertion.

[VERIFIED: STACK.md "JSON construction (NEVER string-interpolate)" + PITFALLS HI-04 single-jq pattern]

## Code Examples

### Example 1: Skill frontmatter authored to D-04 convention

```yaml
---
name: build
description: "Wave-based parallel execution of PLAN.md tasks. Spawns @executor per task with worktree isolation; per-task atomic commit; file-polling fallback for stdout race."
user-invocable: true
allowed-tools: Bash(*), Read, Write, Edit, Task(executor), Task(code-reviewer)
argument-hint: "[N]"
arguments: [N]
disable-model-invocation: true
---

# /build N

## Connects to
- **Upstream:** /plan N (consumed PLAN.md)
- **Downstream:** /verify N (after wave complete)
- **Reads from:** .planning/briefs/NN-slug/PLAN.md, config/quality-gates.txt
- **Writes to:** .planning/briefs/NN-slug/.build/{task-X.Y.started,done,failed}, git commits with `[brief NN.M]` token, .planning/STATE.md

## Auto Mode check

Before proceeding, scan the most recent system reminder for the case-insensitive
substring "Auto Mode Active". If detected: skip the wave-plan preview confirmation;
proceed to dispatch. Treat user course corrections as normal input.

If not detected: present the wave plan, ask user "Proceed with N waves?" via AskUserQuestion.

[... rest of skill body ...]
```

### Example 2: `init-context.sh` field access from a skill body

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/init-context.sh"
CTX=$(godmode_init_context "$PWD")

ACTIVE=$(printf '%s' "$CTX" | jq -r '.state.active_brief // empty')
EXISTS=$(printf '%s' "$CTX" | jq -r '.state.exists')

if [ "$EXISTS" != "true" ]; then
  echo "No .planning/. Run /mission to start."
  exit 0
fi

if [ -z "$ACTIVE" ] || [ "$ACTIVE" = "null" ]; then
  echo "STATE.md exists but no active brief. Run /brief N to start one."
  exit 0
fi

echo "Active brief: $ACTIVE"
```

### Example 3: Spawning `@planner` from `/plan` skill body

```markdown
## Spawn @planner

Use the Task tool:

  subagent_type: planner
  description: "Plan brief $N"
  prompt: |
    Read .planning/briefs/${BRIEF_DIR}/BRIEF.md and produce PLAN.md per the
    template at templates/.planning/briefs/PLAN.md.tmpl. Wave assignment per
    D-36: disjoint file sets + no logical dependency = same wave; concurrency
    cap 5 per D-39.

    Return your output as a complete PLAN.md body. The orchestrator will
    write it to .planning/briefs/${BRIEF_DIR}/PLAN.md.
```

After `@planner` returns, the skill body uses `Write` to persist the result, then calls `godmode_state_update` from `state.sh`.

## State of the Art

| Old Approach (v1.x) | Current Approach (v2 — this phase) | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `/prd → /plan-stories → /execute → /ship` chain | `/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship` | This phase | New 7-step chain replaces 4-step v1.x; `/verify` is a new gate. |
| `.claude-pipeline/stories.json` (single JSON) | `.planning/briefs/NN-slug/{BRIEF.md, PLAN.md}` (markdown per brief) | This phase | Two markdown files per brief; users edit by hand if needed; git log IS the execution log. |
| Hardcoded skill list in `commands/godmode.md` | Live-FS enumeration via `find` | Phase 1 (substrate) + this phase (consumer) | Drift-free; new skill = no documentation update needed |
| Sequential story execution via `@executor` | Wave-based parallel via `Agent(run_in_background=true)` + file polling | This phase | 2-3× wall-clock speedup on disjoint-file waves |
| Hooks emit JSON via heredoc | `jq -n --arg` everywhere | Phase 1 | Adversarial-input-safe (CR-02) |
| `effort: high` on all agents | `effort: xhigh` on read-only design/audit agents; `high` on code-writers | Phase 2 | xhigh skips rules on Opus 4.7 with Write/Edit; mechanically separated by AGENT-06 linter |
| No state file (only stories.json) | `.planning/STATE.md` (machine-mutated YAML front matter + audit log) | This phase | Survives compaction via SessionStart hook; user-readable |
| No template substitution | `templates/.planning/*.tmpl` with `{{var}}` placeholders | This phase | `/mission` and `/brief` materialize from templates; structural lint mechanical |

**Deprecated/outdated:**
- `/prd`, `/plan-stories`, `/execute`: kept on disk with deprecation banners (D-23). Removed in v2.x.
- `@reviewer` (general): kept for v1.x compat; split into `@spec-reviewer` and `@code-reviewer` in Phase 2 (AGENT-05).
- `skills/_shared/pipeline-context.md`: v1.x phase-detection logic for `.claude-pipeline/stories.json`. Folded into `init-context.sh` as the `v1x_pipeline_detected` field. The shared file itself stays for v1.x skill bodies that reference it; not used by v2 skills.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Auto Mode reminder text always starts with `## Auto Mode Active` heading | Pattern 5: Auto Mode detection block | Detection misses; skills run in Socratic mode under Auto Mode. Mitigation: substring match is case-insensitive; multiple variants of the heading still trigger. |
| A2 | `mv` on tmpfile + STATE.md is atomic on user's filesystem (POSIX semantics) | Pattern 2: STATE.md atomic-replace | On NFS or some Windows-mounted filesystems, `mv` is not atomic. Mitigation: WSL2 + native macOS/Linux are POSIX; documented in README. |
| A3 | `Agent(run_in_background=true)` reliably executes the subagent's first instruction (the `touch .started` marker) before any race-causing event | Pattern 4: file-polling fallback | If subagent crashes mid-spawn before its first instruction, no marker written; parent times out at 30 min. **Mitigation already in design** — 30-min ceiling is the safety net; user retries. |
| A4 | The subagent has `Write` capability to its worktree-internal `.planning/briefs/NN/.build/` path | Pattern 4 — subagent prompt MUST touch markers | If `@executor`'s `tools:` list excludes Write to that path, marker never appears. Mitigation: `@executor` has `Write, Edit` in tools; `.build/` is a normal directory in the worktree — should work. Test in Phase 5 bats. |
| A5 | `git log --grep='\[brief NN\.M\]'` matches the canonical commit message format reliably across `git` versions | Atomic commit message format | If user has unusual git config, grep matches less reliably. Mitigation: format is deliberate; PreToolUse can enforce in v2.1. |
| A6 | Brief slug collision (two briefs with same kebab-case title) is rare enough to defer | Brief slug derivation | Two briefs titled "User auth" → both slugs `user-auth`. Mitigation: zero-padded NN prefix prevents directory collisions; document deferral. |
| A7 | The 30-minute per-task timeout matches `@executor maxTurns: 100` real-world wall time | Pattern 4 | If a real task takes 45 min, `/build` aborts wave. Mitigation: ceiling tunable via `GODMODE_POLL_INTERVAL` env (deferred v2.1); 30-min is conservative. |
| A8 | Brief-state v1 schema is sufficient (no need for `worktree.dirty`, `agents.unfree`, etc.) | `init-context.sh` JSON schema (D-12) | Future skills want fields not in v1 schema. Mitigation: `schema_version: 1` field exists for evolution; v2 schema in v2.x. |

**Mitigation rule:** None of these assumptions block planning. Each has a documented fallback. Phase 5's bats smoke test is the verification harness.

## Open Questions

1. **Should `state.sh` be merged into `init-context.sh`?**
   - What we know: D-54 separates read (init-context.sh) from write (state.sh). D-55 says merge if combined size < 150 lines.
   - What's unclear: actual line count until written.
   - Recommendation: start separate (cleaner mental model). If both stay <80 lines individually, planner may merge.

2. **`@code-reviewer` per-task vs per-wave invocation?**
   - What we know: D-12 (Phase 2) — `@code-reviewer` writes to `.planning/phases/NN/<task>-REVIEW.md` per task; spawned per-task by `/build`.
   - What's unclear: does `/build` dispatch `@code-reviewer` in parallel after each `@executor` returns, or batch reviews after wave complete?
   - Recommendation: per-task review, sequentially after each `@executor` returns within the wave (reviews are read-only and parallel-safe; orchestrator can serialize for simplicity in v2.0). Documented in `/build SKILL.md`.

3. **Auto Mode behavior for `/ship` --force?**
   - What we know: D-50 — `--force` bypasses PARTIAL/MISSING refusal only, never bypasses gates. D-10 — Auto Mode never auto-`--force`.
   - What's unclear: should `/ship` in Auto Mode refuse PARTIAL/MISSING entirely (no --force option) or surface as a confirmable prompt?
   - Recommendation: refuse, period. User exits Auto Mode and re-runs with `--force` if needed. Documented.

4. **Concurrency cap edge case: wave with exactly 6 tasks?**
   - What we know: D-39 cap = 5; D-36 says "if a wave would have >5 parallel tasks, split into Wave Xa / Wave Xb."
   - What's unclear: does the planner do the split, or does `/build` orchestrate it dynamically?
   - Recommendation: planner does split (D-36 implies static plan-time split). `/build` enforces — if it sees a wave with >5 tasks, it errors out with "PLAN.md violates concurrency cap; re-run /plan." Documented.

5. **Does `/godmode` detect the v1.x `.claude-pipeline/` and route to migration?**
   - What we know: D-19 — when STATE.md doesn't exist, `/godmode` says "Run `/mission` to initialize project state." `init-context.sh` emits `v1x_pipeline_detected: true` if `.claude-pipeline/` exists.
   - What's unclear: should `/godmode` say "v1.x detected, run `/mission` to migrate" specifically, or just "Run `/mission`"?
   - Recommendation: yes — surface the v1.x banner via the init-context flag. Modify the answer line text inline (not a new line — within the 5-line budget).

## Environment Availability

> Phase 4 has no NEW external dependencies beyond what Phases 1-3 already required.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Bash | All skills + helpers | ✓ | 3.2+ on macOS, 5.x on Linux | — (hard requirement; install.sh checks at preflight) |
| jq | All JSON construction in helpers | ✓ | 1.6+ | — (hard requirement) |
| awk | YAML parsing | ✓ | POSIX (BSD/GNU compat) | — |
| sed | Template substitution | ✓ | POSIX (BSD/GNU compat) | — |
| find | Live FS scan | ✓ | POSIX | — |
| git | Atomic commits, log resume detection | ✓ | 2.x+ | — |
| gh CLI | `/ship` PR creation | optional | 2.x | If absent, `/ship` falls back to printing `git push` command + manual PR-creation hint. Document in `/ship SKILL.md`. |
| Claude Code `Agent` tool | `/build` wave dispatch | ✓ | v2.1.83+ (Auto Mode floor) | — |
| Claude Code `Task` tool | All skill→agent spawns | ✓ | v2.1.x | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** `gh` (graceful degradation in `/ship`).

## Sources

### Primary (HIGH confidence)
- `code.claude.com/docs/en/skills` — fetched 2026-04-27. Skill frontmatter complete reference, argument substitution, `disable-model-invocation` interaction, content lifecycle.
- `code.claude.com/docs/en/permission-modes` — fetched 2026-04-27. Auto Mode requirements, classifier behavior, subagent classification (3-stage check).
- `code.claude.com/docs/en/sub-agents` — referenced via STACK.md (full doc fetched 2026-04-26 in prior research pass; v2 skills only need the Task tool contract + `run_in_background` flag).
- `.planning/research/STACK.md` — full Claude Code 2026 skill / agent / hook / plugin manifest contracts; verified against code.claude.com 2026-04-26.
- `.planning/research/PITFALLS.md` — CR-01..CR-10, HI-01..HI-10, ME-01..ME-08; cross-cutting risks.
- `.planning/research/ARCHITECTURE.md` — five-layer model, data flow, plugin/manual parity contract, live-indexing contract.
- `.planning-archive-v1/codebase/STACK.md`, `CONCERNS.md` — v1.x baseline.
- `hooks/session-start.sh`, `hooks/post-compact.sh` — Phase 1+3 substrate, lifted into init-context.sh.
- `agents/{planner,verifier,spec-reviewer,code-reviewer}.md` — Phase 2 outputs, spawned by Phase 4 skills.
- `config/quality-gates.txt` — Phase 1 SoT, read by `/ship`.
- `commands/godmode.md` (v1.x) — bootstrap behavior preserved.
- `skills/_shared/{pipeline-context,gitignore-management}.md` — v1.x pattern references.

### Secondary (MEDIUM confidence)
- Auto Mode reminder canonical text — verified via live `<system-reminder>` block in this research session; not contractually documented as a stable string at code.claude.com.
- `Agent(run_in_background=true)` exact return shape and stdout race details — documented in PITFALLS CR-08 with multiple sources (claudefa.st, johnsonlee.io); not in primary Anthropic docs.
- 30-minute per-task timeout — recommended value, not benchmarked.

### Tertiary (LOW confidence)
- STATE.md mutation race under multi-skill concurrency (Pitfall 4) — assumed rare; no production data.

## Metadata

**Confidence breakdown:**
- Standard stack (bash, jq, awk, sed, find): HIGH — locked by PROJECT.md, in production via Phases 1-3
- Architecture patterns (5 patterns): HIGH — 4 of 5 already in production; Pattern 4 (file polling) is novel but well-specified by D-40 + CR-08
- Pitfalls (6): HIGH for first 3 (production-validated); MEDIUM for #4 (concurrency); HIGH for #5 (vocab); HIGH for #6 (perf)
- `init-context.sh` design: HIGH — schema locked by D-12; substrate parsers lifted from production
- Skill frontmatter convention (D-04): HIGH — verified against code.claude.com/docs/en/skills 2026-04-27
- Auto Mode detection (D-08): MEDIUM — heading is empirical; substring match works, but stability of heading is not contractually documented
- `Agent(run_in_background=true)` orchestration: HIGH — locked by D-40; CR-08 prevention strategies are production-validated patterns from sub-agents docs
- Templates `{{var}}` substitution: HIGH — sed is portable; mustache-style is conventional
- Brief slug derivation: HIGH — bash 3.2 portable verified
- `/ship` quality gates: HIGH — config file format verified; auto-detection table preserved from v1.x

**Research date:** 2026-04-27
**Valid until:** 2026-05-27 (30 days — Claude Code stack is stable; most novel piece is `Agent(run_in_background)` which is a v2.1.x feature unlikely to break)

---

*Phase: 04-skill-layer-state-management*
*Research: 2026-04-27 (auto mode — 55 locked decisions consumed; novel research focused on the *how* of those decisions)*
