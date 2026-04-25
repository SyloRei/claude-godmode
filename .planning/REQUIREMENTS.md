# Requirements: claude-godmode v2 — polish mature version

**Defined:** 2026-04-25
**Core Value:** A single, clear workflow where every agent, skill, and tool is connected to the others and has a clearly described goal — best-in-class capability with simplest-possible usability.

> **Recount note (2026-04-25):** The header below originally said "61 total"; the roadmapper recounted and confirmed 62 (FOUND 10 + AGENT 11 + HOOK 10 + SKILL 12 + STATE 8 + QUAL 11). Use 62 as authoritative.

## v1 Requirements

Requirements for the v2.0 release of claude-godmode. Each maps to exactly one roadmap phase.

### Foundation (FOUND) — Safety, hardening, and versioning

- [ ] **FOUND-01**: Single source of truth for plugin version — `plugin.json` is canonical; `install.sh`, `commands/godmode.md`, README, and CHANGELOG all read from it
- [ ] **FOUND-02**: Hooks emit valid JSON under adversarial inputs — branch names, commit messages, paths with quotes, backslashes, and newlines are properly escaped
- [ ] **FOUND-03**: Installer prompts before overwriting customized rule, agent, or skill files — per-file diff/skip/replace
- [ ] **FOUND-04**: Backup rotation in `~/.claude/backups/` — keep last N (default 5); prune older at install time
- [ ] **FOUND-05**: Uninstaller detects version mismatch with installed `~/.claude/.claude-godmode-version` — warns when running an older uninstaller against a newer install
- [ ] **FOUND-06**: Plugin-mode and manual-mode produce equivalent UX — hook bindings (especially `timeout`) maintained in a single source, generated for both modes at install time
- [ ] **FOUND-07**: Migration path for v1.x users — `./install.sh` upgrades a v1.x install to v2 cleanly; existing `.claude-pipeline/` state preserved read-only with a one-line migration note
- [ ] **FOUND-08**: Permission deny-pattern caveats documented in README — pattern-matching limitations called out, not a fragile claim
- [ ] **FOUND-09**: `.gitignore` updated to track `.planning/` (consumer-project intent) by default; `.claude-pipeline/` and ephemeral worktrees remain ignored
- [ ] **FOUND-10**: `shellcheck` clean across every `*.sh` in the repo

### Agents (AGENT) — Modernization, frontmatter audit, two-stage review

- [ ] **AGENT-01**: Every agent file uses current model aliases (`opus` = 4.7, `sonnet` = 4.6, `haiku` = 4.5) — no pinned model IDs
- [ ] **AGENT-02**: Every agent file declares `effort` explicitly; `@architect` and `@security-auditor` use `effort: xhigh` (default for Opus 4.7); code-writing agents (`@executor`, `@writer`) use `effort: high` to avoid rule-skipping (PITFALLS #4)
- [ ] **AGENT-03**: Every code-writing parallel agent declares `isolation: worktree` (`@executor`, `@writer`, `@test-writer`)
- [ ] **AGENT-04**: Persistent learner agents declare `memory: project` (`@executor`, `@researcher`, `@reviewer`)
- [ ] **AGENT-05**: Every agent file declares `maxTurns` defensively
- [ ] **AGENT-06**: Every agent file declares a `Connects to:` line in its system prompt — upstream skill/agent and downstream skill/agent
- [ ] **AGENT-07**: New `@planner` agent — phase-level task decomposition with goal-backward verification
- [ ] **AGENT-08**: New `@verifier` agent — read-only, reads phase goal, scores success criteria as COVERED / PARTIAL / MISSING
- [ ] **AGENT-09**: `@reviewer` split into `@spec-reviewer` (spec compliance, read-only) and `@code-reviewer` (code quality, read-only) — two-stage review
- [ ] **AGENT-10**: Every agent file is internally indexable — `/godmode` lists agents by reading the live filesystem, not a hardcoded list
- [ ] **AGENT-11**: Frontmatter linter — pure-Bash script that validates every agent file's frontmatter against a known schema; exits non-zero on violations

### Hooks (HOOK) — Mechanical enforcement and event expansion

- [ ] **HOOK-01**: `PreToolUse` hook blocks `Bash(git commit --no-verify*)` and similar quality-gate-bypass patterns
- [ ] **HOOK-02**: `PreToolUse` hook scans tool input for hardcoded secret patterns (API keys, JWTs, private keys) and refuses with a clear error
- [ ] **HOOK-03**: `PostToolUse` hook detects failed quality-gate exit codes (typecheck, lint, test) and surfaces them in the next assistant turn
- [ ] **HOOK-04**: `SessionStart` hook re-reads `.planning/STATE.md` if it exists and injects current-phase context
- [ ] **HOOK-05**: `PostCompact` hook reads skill and agent lists from the live filesystem instead of hardcoded strings (CONCERNS #8)
- [ ] **HOOK-06**: All hooks use `jq -n --arg ... '$ENV.... | @json'` (or equivalent) for JSON-safe interpolation — no string concatenation into JSON output (CONCERNS #6)
- [ ] **HOOK-07**: All hooks tolerate stdin drain failure (`cat > /dev/null || true`) under `set -euo pipefail`
- [ ] **HOOK-08**: All hooks resolve project root from hook input JSON's `cwd` field, not `pwd` — works when invoked from any subdirectory (CONCERNS #7)
- [ ] **HOOK-09**: Statusline does a single `jq` invocation per render (down from four) — performance polish, optional debug log on parse failure
- [ ] **HOOK-10**: Quality gates list moved to a single source (one rule file or `config/quality-gates.txt`); `PostCompact` reads from it, not hardcoded (CONCERNS #9)

### Skills (SKILL) — Workflow consolidation and `/godmode` menu

- [ ] **SKILL-01**: User-facing slash command count is ≤ 12 — internal orchestrators are subagents, not skills
- [ ] **SKILL-02**: `/godmode` reads the live filesystem and renders a menu listing every public skill and agent with goal + connects-to + model + effort
- [ ] **SKILL-03**: First-run `/godmode` output answers "what now?" within five lines (project-state-aware)
- [ ] **SKILL-04**: New `/discuss-phase` skill — Socratic context-gathering before planning; produces `.planning/phases/<N>/DISCUSS.md`
- [ ] **SKILL-05**: New `/plan-phase` skill — generates atomic, parallelizable task list with goal-backward check; produces `.planning/phases/<N>/PLAN.md`
- [ ] **SKILL-06**: New `/execute-phase` skill — wave-based execution with `isolation: worktree`; commits per task; output-file polling fallback for `run_in_background` agents (PITFALLS #3)
- [ ] **SKILL-07**: New `/verify-phase` skill — runs `@verifier`; produces `.planning/phases/<N>/VERIFICATION.md`; surfaces gaps before /ship
- [ ] **SKILL-08**: `/ship` skill updated — quality gates, push, `gh pr create`; reads phase verification status; refuses to ship a phase with MISSING criteria
- [ ] **SKILL-09**: v1.x skills (`/prd`, `/plan-stories`, `/execute`) are aliased to the new phase-shaped skills with a one-time deprecation note; new behavior under the same names where possible
- [ ] **SKILL-10**: `/debug`, `/tdd`, `/refactor`, `/explore-repo` retained — frontmatter aligned to v2 conventions
- [ ] **SKILL-11**: Every public skill declares `connects to: <upstream skill> → <this skill> → <downstream skill>` in its description; `/godmode` renders the chain
- [ ] **SKILL-12**: Auto Mode awareness — every skill detects "Auto Mode Active" system reminder and routes accordingly (skip approval gates, surface course-corrections proactively)

### State (STATE) — `.planning/` artifact set for consumer projects

- [ ] **STATE-01**: `.planning/PROJECT.md` template ships with the plugin and is initialized by a setup skill on first use in a consumer project
- [ ] **STATE-02**: `.planning/REQUIREMENTS.md` template ships with the plugin
- [ ] **STATE-03**: `.planning/ROADMAP.md` template ships with the plugin
- [ ] **STATE-04**: `.planning/STATE.md` template ships with the plugin; updated by `/discuss-phase`, `/plan-phase`, `/execute-phase`, `/verify-phase`
- [ ] **STATE-05**: `.planning/phases/<N>-<slug>/` directory layout standardized: DISCUSS.md, PLAN.md, EXECUTE.md, VERIFICATION.md
- [ ] **STATE-06**: `.planning/codebase/` map (already implemented in this milestone) — surfaced via a public skill so consumer projects can run it
- [ ] **STATE-07**: `init-context` shell helper — pure Bash + jq function reads `.planning/config.json`, returns a single JSON blob to skill orchestrators (analog of `gsd-sdk query init.*`, but no Node dependency)
- [ ] **STATE-08**: `.planning/config.json` schema documented and JSON-schema-validated in CI

### Quality (QUAL) — CI, tests, documentation parity

- [ ] **QUAL-01**: GitHub Actions workflow runs on every PR — macOS + Linux matrix
- [ ] **QUAL-02**: CI runs `shellcheck` on every `*.sh` (FOUND-10 dependency)
- [ ] **QUAL-03**: CI runs JSON schema validation on `plugin.json`, `hooks.json`, `config/settings.template.json`, `.planning/config.json` schema
- [ ] **QUAL-04**: CI runs frontmatter linter on `agents/*.md`, `skills/*/SKILL.md`, `commands/*.md` (AGENT-11 dependency)
- [ ] **QUAL-05**: CI runs a `bats-core` smoke test of the install→use→uninstall round trip in a temporary HOME
- [ ] **QUAL-06**: README updated — v2 surface, jq-only runtime statement, plugin/manual-mode parity claim, deny-pattern caveat (FOUND-08), MCP integration recipes (Context7, Chrome DevTools, Playwright)
- [ ] **QUAL-07**: CHANGELOG entry for v2.0 — summarizes every category, links migration notes
- [ ] **QUAL-08**: CONTRIBUTING.md adds hygiene recipes — backup rotation, worktree pruning, frontmatter conventions
- [ ] **QUAL-09**: All High-severity items from `.planning/codebase/CONCERNS.md` resolved (the High-severity set is captured by FOUND-01..06, HOOK-06..08, AGENT-10) — explicit traceability table in this REQUIREMENTS.md
- [ ] **QUAL-10**: Every rule file in `rules/godmode-*.md` audited for currency — references current Claude Code primitives, current model lineup, Auto Mode awareness
- [ ] **QUAL-11**: Prompt-cache-aware rule structure — static preamble first, no dates/branches/dynamic content in rule bodies; volatile content moves to statusline or hook output (PITFALLS #2)

## v2 Requirements

Deferred to a future release (v2.1+). Tracked but not in this milestone's roadmap.

### Future skills

- **FUT-01**: `/explore` — Socratic ideation before committing to a plan (GSD `gsd-explore` model)
- **FUT-02**: `/secure-phase` — retroactive threat-model verification per phase
- **FUT-03**: `/spec-phase` — falsifiable-requirements clarification with ambiguity scoring before plan
- **FUT-04**: Stop hook for session-end learnings extraction into a markdown digest (everything-claude-code pattern)
- **FUT-05**: `memory: user` for cross-project learnings — wait until `memory: project` (AGENT-04) proves valuable

### Future integrations

- **FUT-06**: MCP integration recipes documented and shipped as cookbook entries (Context7, Chrome DevTools, Playwright)
- **FUT-07**: Knowledge graph of phases / decisions / requirements (GSD `gsd-graphify` analog) — defer until usage data justifies
- **FUT-08**: Cross-AI peer review (`gsd-review` analog) — defer; multi-vendor coupling is heavy
- **FUT-09**: Workspace isolation (`gsd-new-workspace` analog) — defer until single-worktree-per-feature limit is hit
- **FUT-10**: Plan-mode integration — `EnterPlanMode` / `ExitPlanMode` natively gates `/plan-phase` approval

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---|---|
| Mirror GSD's 80-command surface | Cognitive load destroys adoption; ≤ 12 user-facing skills is a hard cap (PROJECT.md Core Value) |
| Vendored copies of GSD / Superpowers / everything-claude-code | License + maintenance burden; we integrate ideas, not code (PROJECT.md Out of Scope) |
| Bundled MCP server | Pollutes plugin shape; couples release cadence; runtime-dep escalation (PROJECT.md Out of Scope) |
| Graphical UI / dashboard | Surface is the terminal; statusline is the visual primitive (PROJECT.md Out of Scope) |
| Cloud sync of `.planning/` state | Not a plugin's job; users have git for this |
| Telemetry / analytics | Trust killer; MIT + no-network promise is a differentiator |
| Per-language scaffolding (Next.js, Rails, etc.) | Domain creep; v2 shapes how Claude works, not what users build (PROJECT.md Out of Scope) |
| Auto-installing required tools (`brew install jq` etc.) | Privilege escalation; package-manager assumptions; v1.x preflight is the right call |
| `/everything` mega-command | Hides workflow shape; defeats Core Value |
| Backwards-compat shims beyond a one-time install.sh migration | Permanent technical debt (PROJECT.md Out of Scope) |
| Windows-native shell support (cmd / PowerShell) | WSL2 is the supported path (PROJECT.md Out of Scope) |
| Auto-prompt-engineering of user requests | Silent intent mutation breaks trust; explicit `/discuss-phase` instead |
| Hardcoded skill/agent lists in hooks | Drift between hook output and reality (CONCERNS #8); we generate from filesystem |

## Traceability

Filled by `/gsd-roadmapper` during ROADMAP.md creation. Initially all `Pending`.

| Requirement | Phase | Status |
|---|---|---|
| FOUND-01 | Phase 1 | Pending |
| FOUND-02 | Phase 1 | Pending |
| FOUND-03 | Phase 1 | Pending |
| FOUND-04 | Phase 1 | Pending |
| FOUND-05 | Phase 1 | Pending |
| FOUND-06 | Phase 1 | Pending |
| FOUND-07 | Phase 1 | Pending |
| FOUND-08 | Phase 1 | Pending |
| FOUND-09 | Phase 1 | Pending |
| FOUND-10 | Phase 1 | Pending |
| AGENT-01 | Phase 2 | Pending |
| AGENT-02 | Phase 2 | Pending |
| AGENT-03 | Phase 2 | Pending |
| AGENT-04 | Phase 2 | Pending |
| AGENT-05 | Phase 2 | Pending |
| AGENT-06 | Phase 2 | Pending |
| AGENT-07 | Phase 2 | Pending |
| AGENT-08 | Phase 2 | Pending |
| AGENT-09 | Phase 2 | Pending |
| AGENT-10 | Phase 2 | Pending |
| AGENT-11 | Phase 2 | Pending |
| HOOK-01 | Phase 2 | Pending |
| HOOK-02 | Phase 2 | Pending |
| HOOK-03 | Phase 2 | Pending |
| HOOK-04 | Phase 2 | Pending |
| HOOK-05 | Phase 2 | Pending |
| HOOK-06 | Phase 1 | Pending |
| HOOK-07 | Phase 1 | Pending |
| HOOK-08 | Phase 1 | Pending |
| HOOK-09 | Phase 1 | Pending |
| HOOK-10 | Phase 2 | Pending |
| SKILL-01 | Phase 3 | Pending |
| SKILL-02 | Phase 3 | Pending |
| SKILL-03 | Phase 3 | Pending |
| SKILL-04 | Phase 3 | Pending |
| SKILL-05 | Phase 3 | Pending |
| SKILL-06 | Phase 3 | Pending |
| SKILL-07 | Phase 3 | Pending |
| SKILL-08 | Phase 3 | Pending |
| SKILL-09 | Phase 3 | Pending |
| SKILL-10 | Phase 3 | Pending |
| SKILL-11 | Phase 3 | Pending |
| SKILL-12 | Phase 3 | Pending |
| STATE-01 | Phase 4 | Pending |
| STATE-02 | Phase 4 | Pending |
| STATE-03 | Phase 4 | Pending |
| STATE-04 | Phase 4 | Pending |
| STATE-05 | Phase 4 | Pending |
| STATE-06 | Phase 4 | Pending |
| STATE-07 | Phase 4 | Pending |
| STATE-08 | Phase 4 | Pending |
| QUAL-01 | Phase 5 | Pending |
| QUAL-02 | Phase 5 | Pending |
| QUAL-03 | Phase 5 | Pending |
| QUAL-04 | Phase 5 | Pending |
| QUAL-05 | Phase 5 | Pending |
| QUAL-06 | Phase 5 | Pending |
| QUAL-07 | Phase 5 | Pending |
| QUAL-08 | Phase 5 | Pending |
| QUAL-09 | Phase 5 | Pending |
| QUAL-10 | Phase 5 | Pending |
| QUAL-11 | Phase 2 | Pending |

**Coverage:**
- v1 requirements: 62 total (recount after roadmapper audit)
- Mapped to phases: 62
- Unmapped: 0 ✓

**Per-phase distribution:**
- Phase 1 (Foundation and Safety Hardening): 14 requirements (FOUND-01..10, HOOK-06..09)
- Phase 2 (Agent Layer Modernization + Rules Hardening): 18 requirements (AGENT-01..11, HOOK-01..05, HOOK-10, QUAL-11)
- Phase 3 (Skill Layer Rebuild): 12 requirements (SKILL-01..12)
- Phase 4 (State Management and `.planning/` Scaffold): 8 requirements (STATE-01..08)
- Phase 5 (CI Completion, Performance Polish, Documentation Parity): 10 requirements (QUAL-01..10)

---
*Requirements defined: 2026-04-25*
*Last updated: 2026-04-25 after initial definition (claude-godmode v2)*
