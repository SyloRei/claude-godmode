# Project Research Summary

**Project:** claude-godmode v2 — "polish mature version"
**Domain:** Claude Code plugin (Bash + Markdown + JSON multi-agent engineering workflow)
**Researched:** 2026-04-25
**Confidence:** HIGH (all four dimensions verified against live files and official docs)

---

## Executive Summary

Claude-godmode v2 is a Claude Code plugin maturation — not a greenfield build. The v1.x baseline is functionally sound but fraying at the seams: three divergent version strings, unescaped JSON in hooks, hardcoded skill/agent lists that drift from the filesystem, no CI, and a user-facing surface that feels like a kit rather than a workflow. The research confirms that the path to "best-in-class" is not adding features — it is removing brittleness, adopting Claude Code's expanded primitives (21 hook events, new agent frontmatter fields, model aliases), and aligning the workflow vocabulary with GSD's phase model (discuss → plan → execute → verify) while keeping the command surface at or below 12.

The recommended approach is layer-by-layer: stabilize the foundation (hooks, installer, version), upgrade the agent layer (new frontmatter fields, model assignments, internal vs. user-facing split), rebuild the skill layer on top of that (new GSD-aligned workflow skills), then harden with state management, `.planning/` scaffold, and CI. Each layer is independently shippable and the dependency chain is explicit: rules and hooks must be sound before agents depend on them; agents must exist before skills spawn them; `.planning/` shape must be stable before any workflow writes to it.

The dominant risk is that Phase 1 work (hook hardening, installer safety, version unification) is less visible than new features but more load-bearing. Shipping Phase 2 workflow upgrades on a still-fragile hook layer compounds every existing bug. The roadmapper must protect Phase 1 scope against feature pressure. A secondary risk is effort-level misconfiguration: Opus 4.7 at `xhigh` effort has been confirmed to reason past rule files; setting `effort: high` on compliance-critical agents (executor, security-auditor) is a non-negotiable v2 requirement, not a nice-to-have.

---

## Key Findings

### 1. Stack: No new runtime deps; significant authoring-surface expansion

v2 adds nothing at runtime — `jq` remains the only mandatory dep. The expansion is entirely at the Claude Code plugin authoring layer: new agent frontmatter fields (`effort`, `memory`, `background`, `isolation`, `maxTurns`, `skills`, `color`), 19 new hook events beyond the 2 v1.x uses, model aliases (`opus`, `sonnet`, `haiku`) that must replace any pinned IDs, and dev-time CI tools (shellcheck v0.11.0, bats-core v1.13.0, sourcemeta/jsonschema CLI, pure-Bash frontmatter linter). `gsd-sdk` is the GSD development tool used to orchestrate godmode's own development — it is not a runtime dep of godmode and must not become one.

**Core technologies (unchanged):**
- Bash 3.2+: hooks, installer, statusline — ships on every macOS/Linux
- jq 1.6+: JSON parsing in all shell scripts — use `--arg`/`--argjson`, never string concat
- Markdown + YAML frontmatter: agent, skill, command, rule definitions — Claude Code native format

**New authoring surface (v2 additions):**
- Agent frontmatter: `effort`, `memory`, `background`, `isolation`, `maxTurns`, `skills`, `color` — all unused in v1.x
- Hook events to adopt: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `PreCompact`, `SubagentStart`, `SubagentStop`
- Model aliases: `opus` = Opus 4.7 (default effort `xhigh`), `sonnet` = Sonnet 4.6, `haiku` = Haiku 4.5
- Deprecated: `TaskOutput` (use file Read), `ScheduleWakeup` (use `CronCreate`), `TodoWrite` (interactive only)
- Plugin manifest: `userConfig` block for model profile at install time; `${CLAUDE_PLUGIN_DATA}` for persistent state

See STACK.md for full field tables, CI tool versions, and "what not to add."

### 2. Features: Integration is the differentiator, not invention

The competitive position of v2 is the combination of GSD-grade phase lifecycle + ≤ 12 user-facing skills via hidden internals + jq-only runtime + PreToolUse mechanical gate enforcement + first-run UX that answers "what now?" in 5 lines. None of the reference plugins delivers all five in one package.

**Must have for v2.0 (P1):**
- Modernization pass: model aliases, `effort`, `memory: project` on persistent agents, `isolation: worktree` enforced
- Hook hardening: JSON-safe interpolation, `async: true` on SessionStart, filesystem-scanned skill/agent lists, `PreToolUse` gate enforcement
- Version unification: `plugin.json` canonical; installer and `/godmode` read from it via `jq`
- `.planning/` artifact set: PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md for consumer projects
- Phase lifecycle skills: `/discuss`, `/plan-phase`, `/execute-phase` — replaces v1.x `/prd → /plan-stories → /execute`
- Goal-backward verification: `@verifier` agent checks phase goal against codebase, not just test passage
- Two-stage review: spec-compliance check + code-quality check (Superpowers pattern)
- `/godmode` menu refresh: live filesystem scan, ≤ 12 public skills listed, first-run "what now?" in 5 lines
- CI: shellcheck + bats-core + JSON schema + frontmatter lint on macOS + Linux
- All High-severity CONCERNS.md items resolved (21 items, all mapped to phases in PITFALLS.md)

**Defer to v2.1+:**
- `/explore` advisory ideation skill
- `/secure-phase` retroactive threat-model
- `memory: user` for cross-project learnings
- Stop hook for session learnings extraction

**Anti-features to keep out:**
- Mirroring GSD's 80-command surface (cognitive load kills adoption)
- Bundled MCP server (pollutes plugin shape, adds Node.js runtime dep)
- Hardcoded skill/agent lists in any file (drift is guaranteed)
- `effort: xhigh` on compliance-critical agents (rules bypassed — confirmed GitHub issue #23936)

See FEATURES.md for full prioritization matrix and competitor comparison table.

### 3. Architecture: Six-layer, dependency-safe build order

The architecture has five clean layers with a strict dependency chain. ARCHITECTURE.md section 9 defines the build order. The most important design decision is the skill/agent split: if the user types it, it's a skill; if only other agents call it, it's an agent. Internal orchestration agents (planner, verifier, plan-checker) must never appear as user-facing slash commands.

**Major components:**
1. Rules (always-on context) — one concern per file, static, cache-eligible leading position
2. Hooks (event-driven) — `session-start.sh`, `post-compact.sh`, plus new `pre-tool-use.sh` and `post-tool-use.sh`; output valid JSON always via `jq -n --arg`
3. Internal agents — `@planner`, `@verifier`, `@executor`, `@architect`, `@security-auditor`, `@researcher`, `@reviewer`, `@writer`, `@doc-writer`, `@test-writer`; hidden from user surface
4. User-facing skills (≤ 12) — `/godmode`, `/discuss`, `/plan-phase`, `/execute-phase`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo` + 1-3 remaining slots
5. Planning artifacts (`.planning/`) — PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, phases/NN-name/{PLAN,SUMMARY,CONTEXT,VERIFICATION}.md
6. Plugin manifest + installer — `plugin.json` canonical version; plugin mode and manual mode generated from one source

**Key patterns:**
- Skill → Agent boundary: skills are lean orchestrators (<30% context budget); execution goes to typed agents via `Task(subagent_type=...)`
- Prompt caching: rules and agent system prompts must have static preambles; dynamic context (branch, phase, plan) injected last or via hook `additionalContext`, never into rule files themselves
- No SDK: GSD's `gsd-sdk` Node.js binary is replaced by shell+jq fragments in `skills/_shared/` (init-context.md, state-ops.md, commit-ops.md)
- Completion markers: every agent returns `## PLAN COMPLETE` / `## PLANNING COMPLETE` style headers; orchestrators parse these to route

See ARCHITECTURE.md sections 7-9 for full component boundaries, data flow diagram, and v1.x → v2 migration map.

### 4. Critical Pitfalls

1. **Hook JSON fragility blocks everything downstream** — Branch names with `"`, `\`, or newlines break the hook contract; Claude Code silently discards malformed output. Fix: `jq -n --arg` throughout, never string interpolation. Must land in Phase 1 before any new hooks are added.

2. **Dynamic content in `additionalContext` invalidates prompt cache** — Timestamps, git log output, context% in hook-injected system content burns the cache on every PostCompact, multiplying token cost ~5x on long Opus 4.7 sessions. Cache TTL in practice is ~3 min. Fix: stable context in rules, volatile context in statusline only.

3. **Opus 4.7 `xhigh` effort ignores rules and skill instructions** — Confirmed GitHub issue #23936. Fix: `effort: high` for executor and security-auditor; `xhigh` only for architect and writer. Embed critical constraints in task description (user-turn layer), not only in rules.

4. **Auto Mode / YOLO Mode bypasses instructional quality gates** — Only mechanical gates (PreToolUse hooks exiting code 2) are enforced in Auto Mode. Fix: `hooks/pre-tool-use.sh` must mechanically block `git commit --no-verify`, dangerous `rm` patterns, and `gh pr create` when gates are red. Exit code 2 (not exit 1) is the blocking signal.

5. **`run_in_background` + TaskOutput race conditions cause silent session freezes** — Crashed background agents stay listed as "running"; `TaskOutput(block: true)` waits forever. Fix: always specify timeout; implement file-polling fallback. Affects v2's wave-based `/execute-phase` directly.

See PITFALLS.md for 14 full pitfalls, 10 integration gotchas, the "Looks Done But Isn't" checklist, and CONCERNS.md cross-reference resolution map (21 items).

---

## Implications for Roadmap

The ARCHITECTURE.md build order (section 9) provides the dependency-safe phase structure. The PITFALLS.md pitfall-to-phase mapping validates it. The FEATURES.md MVP list maps cleanly to this ordering. Each phase is independently shippable.

### Phase 1: Foundation and Safety Hardening

**Rationale:** Every subsequent phase depends on hooks emitting valid JSON, the installer being safe, and version being a single source of truth. No user-facing feature additions — this phase makes v2 trustworthy.

**Delivers:**
- Hook JSON safety: `jq -n --arg` throughout; `async: true` on SessionStart; cwd from stdin JSON
- Filesystem-scanned skill/agent lists in post-compact.sh (no more hardcoded lists)
- Version unification: `plugin.json` canonical; `install.sh` and `/godmode` read from it via `jq`
- Installer per-file diff/skip/replace prompt for customized rules/agents/skills
- v1.x migration: detect `.claude-pipeline/stories.json`, emit visible warning, offer archive
- Plugin mode / manual mode parity: generate manual settings section from `hooks/hooks.json`
- `timeout: 10` and `async: true` on all hook bindings in both config surfaces
- Backup rotation (keep last 5), `.DS_Store` cleanup, CONCERNS #1-18 resolved
- shellcheck CI: GitHub Actions on macOS + Linux matrix
- Agent naming convention decision (e.g., `gm-` prefix) to prevent multi-plugin collision

**Avoids:** PITFALLS #1, #6, #7, #8, #9; CONCERNS #1-18

**Research flag:** Standard patterns — no research needed. All items defined in CONCERNS.md with explicit fix directions.

---

### Phase 2: Agent Layer Modernization + Rules Hardening

**Rationale:** Agents are the execution layer. They must be correct (model/effort assignments), safe (prompt-cache-friendly, `xhigh` restricted to appropriate roles), and architecturally sound (internal vs user-facing split decided) before skills are rebuilt on top.

**Delivers:**
- All 8 existing agents updated: model aliases, `effort`, `memory: project`, `isolation: worktree`, `maxTurns`
- `@executor`: effort `high`; `@security-auditor`: effort `xhigh`; `@architect`: effort `xhigh`
- Two new internal agents: `@planner` (goal-backward PLAN.md writer) and `@verifier` (post-execution verification)
- Agent naming convention applied: internal helpers marked in description as "Internal — invoke via /skill, not directly"
- Rules refactored: static preamble only (no timestamps, no dynamic data); `godmode-routing.md` adds model profile table
- PostCompact hook: reads quality gates from `rules/godmode-quality.md` at runtime (eliminates CONCERNS #9 duplication)
- New hooks: `hooks/pre-tool-use.sh` (blocks `--no-verify`, dangerous Bash patterns, secret patterns), `hooks/post-tool-use.sh` (gate failure detection), `hooks/user-prompt-submit.sh` (session title)
- JSON schema validation CI step added

**Avoids:** PITFALLS #2, #4, #12

**Research flag:** No research needed — effort level assignments and hook event schema are fully specified in STACK.md and PITFALLS.md.

---

### Phase 3: Skill Layer Rebuild (GSD-Aligned Workflow)

**Rationale:** With a sound agent layer, the user-facing skill surface can be rebuilt. This is the highest-value user-visible work: v1.x `/prd → /plan-stories → /execute → /ship` becomes `/discuss → /plan-phase → /execute-phase → /ship` with wave-based execution, goal-backward verification, and two-stage review.

**Delivers:**
- `/discuss` (new): Socratic interview → writes phase CONTEXT.md; replaces `/prd`
- `/plan-phase` (new): spawns `@planner`, produces wave-structured PLAN.md files; replaces `/plan-stories`
- `/execute-phase` (new): wave orchestrator with `run_in_background` + file-polling fallback; spawns `@executor` per plan; writes SUMMARY.md; replaces `/execute`
- `/ship` (upgraded): blocked by PreToolUse hook until all gates green
- `/debug`, `/tdd`, `/refactor`, `/explore-repo` (upgraded): GSD-style completion markers, forward/back arrows
- `/godmode` (upgraded): live filesystem scan, ≤ 12 public skills, first-run "what now?" in 5 lines
- Two-stage review: `@spec-reviewer` + `@code-reviewer` split from single `@reviewer`
- Command count audit: must be ≤ 12 before phase closes
- bats-core smoke test CI: install → `/godmode` → `/discuss` → `/plan-phase` → `/execute-phase` → uninstall

**Avoids:** PITFALLS #3, #5, #11, #13

**Research flag:** The PLAN.md frontmatter schema (wave structure, `depends_on`, `must_haves`, `verification` blocks) is the most complex new artifact. If GSD template inspection is insufficient, a targeted research pass on the planner → executor data contract is warranted. Likely 1-2 hours of `~/.claude/get-shit-done/templates/` inspection rather than a full research phase.

---

### Phase 4: State Management + `.planning/` Scaffold

**Rationale:** The workflow skills depend on `.planning/` artifacts existing per-project; state management fragments must exist before they can be called by skills. This is a late phase because the exact shape of STATE.md and config.json emerges from Phase 3 execution.

**Delivers:**
- `skills/_shared/init-context.md`: pure shell+jq config.json reader + model resolution (no `gsd-sdk`)
- `skills/_shared/state-ops.md`: STATE.md mutation fragments (advance-plan, update-progress)
- `skills/_shared/commit-ops.md`: gitignore-aware planning commit fragment
- `.planning/` scaffold for consumer projects: PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, config.json
- `session-start.sh` upgraded: reads STATE.md, injects currentPhase/currentPlan into additionalContext
- `post-compact.sh` upgraded: re-injects only volatile STATE.md delta (not full boilerplate)
- Per-project `config.json`: model_profile, commit_docs, branching_strategy

**Avoids:** PITFALLS #2 (static vs dynamic context), #14 (PROJECT.md drift)

**Research flag:** No research needed. GSD state management shape is inspectable from live install at `~/.claude/get-shit-done/templates/state.md` and `references/planning-config.md`.

---

### Phase 5: CI Completion + Performance Polish + Documentation

**Rationale:** Final hardening pass. CI was partially established in Phases 1-3; this closes remaining gaps. Performance items (statusline jq collapse, git log bounding) are low severity but affect every user every session.

**Delivers:**
- Frontmatter lint CI: pure-Bash `scripts/lint-frontmatter.sh` validates required fields on all agents/skills/commands
- Full smoke test round-trip on macOS + Linux in CI
- Statusline: collapse 4 `jq` calls to 1 `jq -r '[...] | @tsv'` invocation
- `git log --max-count=5` + `timeout 3` bounds on all hook git calls
- README, CHANGELOG, `/godmode`, rule files: full documentation parity pass against v2 surface
- `plugin.json` `userConfig` block: model profile prompt at install time
- CONTRIBUTING.md: worktree prune recipe, backup rotation policy, per-file diff guidance
- Worktree cleanup: documented `git worktree prune` recipe or automated cleanup script

**Avoids:** PITFALL #10 (statusline overhead); documentation drift

**Research flag:** Standard patterns throughout. No research needed.

---

### Phase Ordering Rationale

- **Safety before features:** Phases 1-2 address hook fragility, installer safety, and agent model correctness before any user-visible workflow changes. Building on a fragile base means rework in every subsequent phase.
- **Agents before skills:** Skills spawn agents — agents must exist first. Phase 3 skills cannot be built without Phase 2's `@planner` and `@verifier`.
- **Skills before state management:** The exact shape of STATE.md and init-context fragments depends on what Phase 3 skills actually need. Designing state management before the skill shape is known produces premature abstraction.
- **CI woven in:** shellcheck lands in Phase 1, JSON schema in Phase 2, smoke tests in Phase 3, frontmatter lint in Phase 5. Each CI step covers the layer built in that phase.
- **CONCERNS.md items:** All 21 CONCERNS items have explicit phase assignments per the cross-reference map in PITFALLS.md. Phase 1 resolves 15 of them; the remaining 6 are distributed across Phases 2-5.

### Research Flags

Phases likely needing `/gsd-research-phase` during planning:
- **Phase 3 (Skill Rebuild):** PLAN.md frontmatter schema and the planner → executor data contract. Inspect `~/.claude/get-shit-done/templates/` first; escalate to full research only if ambiguity remains.

Phases with well-documented patterns (skip research):
- **Phase 1:** All items are CONCERNS.md entries with explicit fix directions. Pure execution.
- **Phase 2:** Agent frontmatter fields, hook event schemas, and effort level assignments are fully specified in STACK.md and PITFALLS.md.
- **Phase 4:** GSD state management shape is locally inspectable.
- **Phase 5:** CI tooling versions and shell idioms all specified in STACK.md.

---

## Cross-Dimension Dependencies

Load-bearing dependencies the roadmapper must track:

| Dependency | Blocks |
|---|---|
| Hook JSON safety (PITFALLS #1, CONCERNS #6) | PreToolUse enforcement layer; any new hook event |
| Plugin mode / manual mode parity (PITFALLS #1, CONCERNS #11-12) | Every new hook — adding without fixing parity repeats the pattern |
| Agent effort level assignments (PITFALLS #4, STACK model table) | All compliance-critical agent behavior; executor must be `effort: high` |
| Version unification (CONCERNS #10) | installer, `/godmode`, README, CHANGELOG all reading from canonical source |
| `@planner` and `@verifier` agent existence (ARCHITECTURE phase 2) | `/plan-phase` and `/execute-phase` skills (ARCHITECTURE phase 3) |
| `.planning/` artifact schema stability (ARCHITECTURE phase 5) | `skills/_shared/` state fragments (ARCHITECTURE phase 4) |
| `async: true` on SessionStart hook (PITFALLS #9) | Every user's session startup performance |
| `run_in_background` + file-polling fallback (PITFALLS #3) | Wave-based `/execute-phase` — without fallback, parallel execution will freeze |
| `isolation: worktree` per parallel writer (STACK agent table) | Conflict-free parallel story execution |

---

## Top 5 Risks for Roadmapper

1. **Phase 1 scope erosion under feature pressure.** Phase 1 contains no user-visible additions. Pressure will arise to slip "just one workflow feature" in. The hook layer must be sound before anything builds on it — this is the gating constraint.

2. **`effort: xhigh` misconfiguration on executor or security-auditor.** These agents must be `effort: high`. Getting this wrong is invisible until rules are silently bypassed in production. Lock it in `rules/godmode-routing.md` as an explicit constraint, not only in agent frontmatter.

3. **`run_in_background` parallel execution without file-polling fallback.** If Phase 3 implements wave-based `/execute-phase` using blocking `TaskOutput`, sessions will silently freeze on any agent crash. The fallback must be in Phase 3 scope, not a follow-up.

4. **`.planning/` schema designed before Phase 3 reveals what it needs.** If Phase 4 state fragments are designed in Phase 2, they will be redesigned after Phase 3 shows what skills actually require. The phase ordering protects against this; scope creep is the risk.

5. **Command count drift past 12.** Each new user-facing skill added in Phase 3 (discuss, plan-phase, execute-phase) is a risk to the ≤ 12 limit. Every phase close must include a command count check. This is a hard constraint per PROJECT.md, not a guideline.

---

## Open Questions for /discuss-phase or /plan-phase

- **Agent naming prefix decision.** PITFALLS #8 recommends `gm-` prefix (e.g., `gm-executor`) to prevent multi-plugin collision. This is a breaking change for existing users who reference agents by name. Decide before Phase 2 — cannot be changed post-v2 launch without a major version bump.

- **`/godmode-migrate` skill scope.** PITFALLS #6 recommends a migration skill for `stories.json` → `.planning/`. Does this count toward the ≤ 12 limit? If yes, which existing skill does it replace? Decide before Phase 1 installer work.

- **`isolation: worktree` on `@planner`.** The planner only writes `.planning/` files and reads codebase — no code writing. Should it run in an isolated worktree (prevents conflicts) or main tree (simpler)? Decide before Phase 2.

- **PLAN.md schema for godmode.** GSD's PLAN.md frontmatter (`wave`, `depends_on`, `must_haves`, `verification`, `threat_model`) is designed for GSD's executor. Does godmode adopt the same schema or a simplified subset? This determines both `@planner` and `@executor` agent design in Phase 2/3.

- **`/tdd` fate.** ARCHITECTURE.md recommends deprecating `/tdd` and folding TDD into PLAN.md `type: tdd`. This removes one user-facing command (helps ≤ 12 limit) but breaks existing `/tdd` users. Decide during Phase 3 planning.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All Claude Code primitives verified against official docs 2026-04-25; GSD plugin inspected from live install; tool versions from GitHub releases |
| Features | HIGH | v1.x baseline read directly from repo; GSD surface from live install; Superpowers and everything-claude-code cross-referenced from STACK.md at MEDIUM confidence |
| Architecture | HIGH | Primary sources: live GSD agent/workflow files; v1.x codebase analysis from `.planning/codebase/` |
| Pitfalls | HIGH | Hook schema from official docs; GitHub issues cited with numbers; effort-level behavior confirmed against closed issue #23936 |

**Overall confidence:** HIGH

### Gaps to Address

- **Superpowers direct inspection deferred.** Patterns adopted (worktree isolation, two-stage review) are consistent with v1.x practice and GSD patterns — this gap does not materially affect roadmap decisions.
- **GSD workflow internals at depth.** 50+ GSD workflow files not individually inspected. If Phase 3 skill design surfaces unexpected complexity in the planner → executor contract, inspect `~/.claude/get-shit-done/` `gsd-planner.md` and `gsd-executor.md` directly.
- **Opus 4.7 xhigh → rules bypass in production.** Based on closed GitHub issue on Opus 4.6. Phase 2 should include a fixture test validating compliance before locking effort level assignments.

---

## Sources

### Primary (HIGH confidence)
- `https://code.claude.com/docs/en/hooks` — 21 hook events, input/output schema, async flag, exit code semantics
- `https://code.claude.com/docs/en/plugins-reference` — Plugin manifest schema, agent frontmatter fields, `${CLAUDE_PLUGIN_DATA}`
- `https://code.claude.com/docs/en/sub-agents` — Full agent frontmatter including `memory`, `background`, `isolation`
- `https://code.claude.com/docs/en/model-config` — Model aliases, effort levels, prompt caching
- `~/.claude/get-shit-done/` (v1.38.3, live install) — GSD workflow files, agent definitions, templates, references
- `.planning/codebase/` (this repo) — v1.x architecture, concerns, stack, conventions

### Secondary (MEDIUM confidence)
- GitHub issue #23936 — Opus 4.6 high effort ignores skills/CLAUDE.md (closed not-planned)
- GitHub issues #21352, #20236, #17540, #17147 — TaskOutput / run_in_background hang issues
- GitHub issue #15882 — Plugin namespacing always required
- `https://github.com/obra/superpowers` — Superpowers patterns (README-level)
- `https://github.com/affaan-m/everything-claude-code` — everything-claude-code patterns (README + directory listing)
- `https://www.claudecodecamp.com/p/how-prompt-caching-actually-works-in-claude-code` — Dynamic content cache invalidation patterns
- YOLO/Auto Mode security analysis gist (March 2026) — Auto Mode gate bypass confirmation

### Tertiary (LOW confidence)
- Community report: prompt cache TTL silently dropped from 1hr to 5min (dev.to)

---

*Research completed: 2026-04-25*
*Ready for roadmap: yes*
