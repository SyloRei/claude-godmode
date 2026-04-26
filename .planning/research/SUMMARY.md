# Project Research Summary

**Project:** claude-godmode v2 (polish mature version)
**Domain:** Claude Code plugin (rules + agents + skills + hooks + statusline + permissions; bash + jq runtime)
**Researched:** 2026-04-26 (Path A re-bootstrap onto GSD planning shape)
**Confidence:** HIGH

## Executive Summary

claude-godmode v1.x is a shipped, working Claude Code plugin (8 agents, 8 skills, full pipeline, plugin+manual install). The v2 milestone — **polish mature version** — replaces the v1.x `/prd → /plan-stories → /execute → /ship` pipeline with a single arrow chain (`/godmode → /mission → /brief → /plan → /build → /verify → /ship`), hardens 9 High-severity defects identified in the v1.x audit, modernizes the agent layer to the Claude Code 2026 capability surface (Opus 4.7, `effort: xhigh`, auto mode, plugin marketplace, native skills/agents/hooks, persistent memory, foreground+background subagents), and incorporates the strongest validated patterns from three reference plugins (GSD, Superpowers, everything-claude-code) without becoming a clone.

The recommended approach is a **5-milestone, dependency-driven build** (Foundation → Agents → Hooks → Skills → Quality) with strict architectural discipline: 11 user-facing slash commands (≤12 cap), bash 3.2 + jq 1.6 only at runtime, plugin-mode == manual-mode UX parity (CI-asserted), `.claude-plugin/plugin.json:.version` as the canonical version source (jq read at runtime), live-filesystem indexing of agents/skills (no hardcoded inventories), atomic commits per workflow gate (PreToolUse hook blocks `--no-verify`), goal-backward verification before ship. The five layers (rules / agents / skills / hooks / config) are one-directionally connected and contract-bound.

The biggest risks are the **Opus 4.7 `effort: xhigh` rule-skipping pitfall** (mitigated by locking code-writing agents at `effort: high` and reserving `xhigh` for read-only design/audit), **hook JSON construction under adversarial branch names** (mitigated by `jq -n --arg` everywhere — never heredoc string interpolation), and **bash 3.2 portability landmines** on macOS default shell (mitigated by an explicit forbid list in STACK.md and CI shellcheck). All three risks have known, mechanical mitigations; the v2 milestone is HIGH-confidence executable on the existing v1.x baseline.

## Key Findings

### Recommended Stack

The runtime stack is **bash 3.2+ and jq 1.6+ only** — no Node, Python, helper binary, or SDK dependency. The authoring surface adds Claude Code 2026 native primitives: model aliases (`opus`, `sonnet`, `haiku` — never pinned numeric IDs), `effort` tier (`high` for code-writing, `xhigh` for design/audit), `isolation: worktree` for code-touching agents, `memory: project|user|local` for persistent learners, `Connects to:` frontmatter line for live indexing, `${CLAUDE_PLUGIN_DATA}` for state survival across plugin updates. CI tooling (zero runtime impact): `shellcheck` 0.11.0+, `bats-core` for smoke tests, GitHub Actions for the 5 quality gates.

**Core technologies:**
- **bash 3.2+** — runtime shell (macOS default, Linux, WSL2). Forbid list documented (no `mapfile`, `[[ -v ]]`, `${var,,}`, `declare -A`, GNU `head -n -N`, etc.) — purpose: zero-install-friction; why: every plugin user already has it
- **jq 1.6+** — JSON construction and parsing. Pattern: `jq -n --arg ctx "$CTX" '{...}'` for safe construction (never heredoc string-interp); `[..., ..., ...] | @tsv` for batched extraction — purpose: adversarial-safe hook output; why: closes CONCERNS #6 / #18 from v1.x audit
- **`.claude-plugin/plugin.json`** — single source of truth for version. `install.sh` reads via `jq -r .version` at runtime — purpose: zero version drift; why: closes CONCERNS #10 (v1.x has three files claiming three versions)
- **Native Claude Code primitives (2026)** — agents/, skills/, hooks/, commands/, rules/ as first-class layers. `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}` env vars provided by runtime. `hookSpecificOutput.permissionDecision` (allow/deny/ask/defer) is the current shape — never the deprecated `decision: approve|block` — purpose: forward compatibility; why: 2026 surface shipped after v1.x baseline
- **shellcheck (CI-only)** — gates every shipped `.sh` file at v0.11.0 default severity — purpose: catch portability regressions before they ship; why: macOS bash 3.2 + Linux bash 5 split

Full stack with field-by-field schemas, alternatives considered, and confidence levels in `STACK.md`.

### Expected Features

The plugin ships exactly **11 user-facing slash commands** (12-cap, 1 reserved): `/godmode`, `/mission`, `/brief N`, `/plan N`, `/build N`, `/verify N`, `/ship` (the workflow chain) plus 4 cross-cutting helpers (`/debug`, `/tdd`, `/refactor`, `/explore-repo`). Two artifact files per active brief (`BRIEF.md` + `PLAN.md`) — no per-task files. `git log` IS the execution log.

**Must have (table stakes — won't ship without):**
- Workflow surface (F-01..F-08) — the locked 11-command chain with one-line state-aware orient
- Foundation hardening (F-09..F-16, F-28, F-38) — version SoT, hook JSON safety, per-file install prompts, backup rotation, version-mismatch uninstall, detection-only v1.x migration, live indexing, shellcheck-clean
- Agent modernization (F-17..F-22) — Claude Code 2026 frontmatter convention, new `@planner` and `@verifier`, two-stage review (`@spec-reviewer` + `@code-reviewer`), frontmatter linter
- Hook expansion (F-23..F-27) — PreToolUse `--no-verify` block + secret scan, PostToolUse failed-gate surfacing, SessionStart STATE.md injection, PostCompact live-FS scan
- Skill rebuild (F-29..F-33) — all 11 skills authored to new shape, auto-mode awareness, init-context shared helper, artifact templates
- Quality gates (F-34..F-37) — GitHub Actions CI (5 lints), bats smoke, README + CHANGELOG + marketplace metadata

**Should have (differentiators that distinguish best-in-class):**
- D-01 ≤5-line state-aware orient
- D-02 two-files-per-brief (vs. GSD's 4–5)
- D-03 zero runtime dependency (vs. GSD's gsd-sdk Node requirement)
- D-04 live filesystem indexing (no hardcoded lists, drop-a-file-restart upgrade)
- D-05 mechanically enforced quality gates (PreToolUse + PostToolUse, not aspirational rule docs)
- D-06 plugin-mode == manual-mode parity, CI-asserted byte-for-byte
- D-08 atomic commits per workflow gate, mechanically enforced
- D-09 auto-mode awareness in every skill
- D-10 wave-based parallel `/build` with file-polling fallback
- D-11 two-stage read-only review
- D-12 adversarial-safe hooks (branch-name fuzz survives)
- D-13 vocabulary discipline (no `phase`/`task`/`PRD` leakage in user-facing surface — CI-gated)
- D-14 single source of truth for version (jq runtime read)
- D-16 `Connects to:` chain rendered from agent frontmatter
- D-17 prompt-cache-aware rule and agent prompt structure

**Defer / out of scope (v2 will not ship):**
- A-01 Cross-runtime support (Codex / Gemini / OpenCode adapters) — Claude Code only
- A-02 Workspace / multi-repo orchestration — single repo, single workflow
- A-03 External CLI dependency — bash + jq only at runtime
- A-04 Native Windows shell — WSL2 is the path
- A-05 Telemetry / phone-home — none, ever (trust is the brand)
- A-06 Cloud features (ultraplan-to-cloud, remote review, scheduled background agents) — not the plugin's job
- A-08 Vendored copies of reference plugin code — read freely, copy nothing structural
- A-09 ≥12 user-facing slash commands — the cap IS the differentiator
- A-10 Six-level workflow vocabulary — collapsed to 5 (Project / Mission / Brief / Plan / Commit)
- A-11 Per-task artifact files (TASK.md / EXECUTE.md) — git log IS the execution log

Full feature catalog (F-01..F-38, D-01..D-17, A-01..A-24) with complexity, dependencies, milestone-area assignment, and reference-plugin coverage in `FEATURES.md`.

### Architecture Approach

The plugin is structured as **five one-directionally connected layers**: rules (philosophy, static, no frontmatter) → agents (atomic labor, frontmatter required, never spawn other agents) → skills (orchestration, the only fan-out point that calls Agent tool) → hooks (event-driven shell, JSON via jq -n --arg only) → config (data, single sources). Cross-layer talk is contract-bound. The `.planning/` directory is the consumer-side state vehicle (PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, briefs/NN-name/{BRIEF.md, PLAN.md}); `git log` is the execution log; `~/.claude/projects/<id>/agent-memory/<agent>/` is per-agent persistent memory for cross-cutting tribal knowledge.

**Major components:**
1. **rules/** — godmode-*.md philosophy / convention files. Loaded into every session by Claude Code's rules system. No frontmatter. Static. Single source for canonical guidance (quality gates list lives in `config/quality-gates.txt`, NOT duplicated here).
2. **agents/** — 8 v1.x + 4 new (`@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`) = 12 atomic-labor units. Frontmatter-locked: model alias, effort tier, isolation, memory, maxTurns, `Connects to:` line. Agents never spawn other agents — only skills do.
3. **skills/** — 11 user-facing skill directories at `skills/<name>/SKILL.md`, plus `skills/_shared/init-context.sh` (the bash-native equivalent of `gsd-sdk`, loaded by every skill). Skills are the only orchestration layer that fans out to subagents via the Agent tool.
4. **hooks/** — `session-start.sh`, `post-compact.sh`, plus v2 additions (`pre-tool-use.sh`, `post-tool-use.sh`). Plus `hooks/hooks.json` (plugin-mode bindings) which must agree byte-for-byte with `config/settings.template.json[hooks]` (manual-mode bindings) — CI-asserted in M5.
5. **config/** — `statusline.sh`, `settings.template.json`, `quality-gates.txt` (the new SoT for the 6 quality gates). Pure data files; no logic.
6. **scripts/** (new in v2, never installed) — CI helpers: `check-version-drift.sh`, `check-frontmatter.sh`, `check-parity.sh`, `check-vocab.sh`. Run only by GitHub Actions or manual CI invocation.
7. **tests/** (new in v2, never installed) — `tests/fixtures/hooks/{cwd-quote-branch,cwd-newline-branch,...}.json` + bats smoke test in `tests/install.bats`.
8. **`.claude-plugin/plugin.json`** — canonical version. Read at runtime via jq.

The data flow for the canonical workflow is: `/mission` writes PROJECT.md / ROADMAP.md / STATE.md → `/brief N` writes briefs/NN/BRIEF.md (Socratic, optionally spawns `@researcher` + `@spec-reviewer`) → `/plan N` writes briefs/NN/PLAN.md (spawns `@planner`) → `/build N` reads PLAN.md, dispatches waves of `@executor` / `@test-writer` agents, atomic commit per task → `/verify N` (spawns `@verifier`, read-only) updates PLAN.md verification section to COVERED / PARTIAL / MISSING → `/ship` runs quality gates, refuses on non-COVERED, then push + `gh pr create`. STATE.md is machine-mutated at each step. Hook handoff: stdin JSON in (with `cwd` field), stdout JSON out (built via `jq -n --arg`).

The plugin-mode vs manual-mode parity contract operates file-by-file: same scripts, same args, same env, only the path prefix differs (`${CLAUDE_PLUGIN_ROOT}` vs `~/.claude/`). M5's `scripts/check-parity.sh` enforces hook bindings / timeouts / permissions byte-for-byte agreement. Live indexing operates on canonical glob patterns (`agents/*.md`, `skills/*/SKILL.md`, `.planning/briefs/*/BRIEF.md`) with deterministic `LC_ALL=C` ordering and ignored prefixes (`_*`, README, `*.tmpl`).

Full architecture with directory layout decisions, layer-assumption matrix, data flow diagrams, build-order justifications, parity contract, and live-indexing rules in `ARCHITECTURE.md`.

### Critical Pitfalls

1. **CR-01: `effort: xhigh` on a Write/Edit-capable agent silently relaxes rule adherence.** Opus 4.7 documented to skip rules at xhigh. **Mitigation:** Lock code-writing agents (`@executor`, `@writer`, `@test-writer`, `@doc-writer`, `@code-reviewer`) at `effort: high`; reserve `xhigh` for read-only design/audit (`@architect`, `@security-auditor`, `@planner`, `@verifier`, `@spec-reviewer`). Frontmatter linter (M2) refuses commits with `xhigh` + Write/Edit in `tools:`.
2. **CR-02: Hook JSON via heredoc + shell variable interpolation under adversarial branch / commit / path inputs.** Branch named `feat/"weird"` produces invalid JSON. **Mitigation:** All hook output via `jq -n --arg branch "$BRANCH" --arg ctx "$CTX" '{...}'`. Never heredoc. Tested via bats fixtures (M5) with `"`, `\`, `\n`, `'` in branch names.
3. **CR-03: `cat > /dev/null` under `set -euo pipefail` aborts hook on early stdin closure.** **Mitigation:** `cat > /dev/null || true` (M1). Or capture once: `INPUT=$(cat || true)` then operate on `$INPUT`.
4. **CR-04: bash 3.2 syntax landmines on macOS default shell** (`mapfile`, `readarray`, `${var,,}`, `[[ -v ]]`, `declare -A`, GNU-only flags). Easy to write code that works on Linux bash 5 and breaks on macOS 12. **Mitigation:** Explicit forbid list in `rules/godmode-shell-portability.md` (M2); shellcheck `--shell=bash --severity=warning` in CI (M5); `tests/install.bats` runs on both `macos-latest` and `ubuntu-latest`.
5. **CR-05: `diff -q` exit code 2 (error) treated as 1 (different) under `set -e`.** Causes silent installer corruption. **Mitigation:** `if ! diff -q "$src" "$dst" >/dev/null 2>&1; then` (M1) instead of `diff -q ...; if [ $? -eq 1 ]; then`. Documented in shell portability rule file.
6. **CR-08: Foreground vs background subagent — file-write race + cache thrash + polling deadlock.** Wave-based parallel `/build` is exposure-prone. **Mitigation:** File-polling fallback (M4): each parallel agent writes to a unique `briefs/NN/_locks/<task>-<id>.lock`; orchestrator polls without piping stdout. Document the `run_in_background=true` cache-warming pattern in M4 brief.
7. **HI-01: Persistent memory used as a substitute for STATE.md or a commit message.** Memory is for cross-session, cross-cutting tribal knowledge — not for ephemeral state. **Mitigation:** Memory only for `@architect`, `@researcher`, `@security-auditor`. STATE.md for current-brief state. Commit messages for what-changed-and-why.
8. **HI-06: Vocabulary leakage — internal tokens (`phase`, `task`, `gsd-*`, `cycle`, `story`) appear in user-facing skill output.** **Mitigation:** M5 vocabulary CI gate greps user-facing surface (`commands/`, `skills/`, `README.md`) for forbidden tokens. Internal docs (`rules/`, `agents/`, `.planning/`) exempt.

Full pitfall catalog (10 Critical + 10 High + 6 Medium) with warning signs, prevention strategies, and milestone-area assignment in `PITFALLS.md`.

## Implications for Roadmap

Based on research, the suggested phase structure mirrors the IDEA.md milestone areas. Build order is dependency-driven and **non-negotiable**: Foundation underwrites everything; Agents define labor; Hooks define safety; Skills define user surface; Quality is the closing gate.

### Phase 1: Foundation & Safety Hardening
**Rationale:** The substrate stops fighting the user. Everything downstream assumes hooks emit valid JSON, version is single-sourced, customizations survive reinstall, shellcheck is clean. Skipping any of this poisons every later phase.
**Delivers:** `scripts/check-version-drift.sh` (new), `config/quality-gates.txt` (new), `.shellcheckrc` (new), `tests/fixtures/hooks/` (new); install.sh + uninstall.sh + hooks/*.sh + commands/godmode.md + config/statusline.sh hardened. Plugin version reads from `plugin.json` at runtime.
**Addresses:** F-09..F-16, F-28, F-38; closes CONCERNS #1, #2, #4, #5, #6, #7 (six of nine High items)
**Avoids:** CR-02, CR-03, CR-04, CR-05, CR-09, CR-10, HI-04, HI-05, HI-08, HI-10

### Phase 2: Agent Layer Modernization
**Rationale:** Hooks (Phase 3) need to enumerate agents from the live filesystem (Phase 1 substrate), and skills (Phase 4) need to spawn agents via the Agent tool. Agents must exist with locked frontmatter convention before either can be built.
**Delivers:** New agents `@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`. All 12 agents (8 v1.x + 4 new) modernized to F-17 convention (model aliases, effort tiers, isolation, memory, maxTurns, Connects-to). `scripts/check-frontmatter.sh` (new) refuses commits with malformed agent metadata. `Connects to:` chains complete and consistent.
**Addresses:** F-17..F-22, D-07, D-11, D-16, D-17
**Uses:** Live indexing contract (Phase 1)
**Avoids:** CR-01 (xhigh on Write-capable agent), HI-02 (hardcoded inventories), HI-07 (frontmatter typos / pinned IDs)

### Phase 3: Hook Layer Expansion
**Rationale:** Skills (Phase 4) must not be able to bypass quality gates. Hooks are the only mechanical enforcement layer. PreToolUse blocks `--no-verify` before commits; PostToolUse surfaces failed gate exits before the next prompt; SessionStart/PostCompact inject canonical state. Without this, gates remain aspirational.
**Delivers:** New hooks `pre-tool-use.sh`, `post-tool-use.sh`. Existing hooks read agents/skills from filesystem (live indexing) and gates from `config/quality-gates.txt`. SessionStart reads `.planning/STATE.md` and injects active-brief context.
**Addresses:** F-23..F-27, D-05, D-08
**Uses:** Live indexing (Phase 1), agent enumeration (Phase 2)
**Avoids:** HI-09 (gate duplication), CR-06 (auto-mode rubber-stamp drift)

### Phase 4: Skill Layer & State Management
**Rationale:** All 11 user-facing skills are rewritten or freshly authored to the new arrow chain. State management via `.planning/STATE.md` machine-mutated by skills. Auto-mode awareness in every skill. Wave-based parallel `/build` with file-polling fallback. This is the visible product layer; everything before it is substrate.
**Delivers:** `/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo` — 11 user-invocable skills. `skills/_shared/init-context.sh` (the bash-native gsd-sdk replacement). `.planning/` artifact templates (PROJECT.tmpl, REQUIREMENTS.tmpl, ROADMAP.tmpl, STATE.tmpl, BRIEF.tmpl, PLAN.tmpl). v1.x deprecation banners on `/prd`, `/plan-stories`, `/execute`.
**Addresses:** F-01..F-08, F-29..F-33, D-01, D-02, D-09, D-10
**Uses:** Agents (Phase 2), hooks (Phase 3), state vehicle (Phase 1 substrate)
**Avoids:** ME-01 (skill ignores auto mode), ME-03 (sequential when parallel-able), CR-08 (foreground/background race)

### Phase 5: Quality — CI, Tests, Docs Parity
**Rationale:** Gates the whole substrate before v2 ships. CI workflow runs 5 lints (shellcheck, frontmatter, version drift, parity, vocabulary) on every PR. bats smoke exercises install → uninstall → reinstall → adversarial fixtures. README + CHANGELOG + plugin marketplace metadata polished. Plugin-mode == manual-mode parity asserted byte-for-byte.
**Delivers:** `.github/workflows/ci.yml` (new). `scripts/check-parity.sh`, `scripts/check-vocab.sh` (new). `tests/install.bats`. README ≤500 lines, CHANGELOG dated, plugin.json description SEO-tuned. v2.0.0 release tag.
**Addresses:** F-34..F-37, D-06, D-13
**Uses:** Everything
**Avoids:** CR-04 (bash 3.2 regression), CR-07 (marketplace invisibility), HI-03 (parity drift), HI-06 (vocab leakage), ME-04 (release-doc drift), ME-05 (README duplication)

### Phase Ordering Rationale

- **Foundation first** because every later phase touches hooks, version-aware behavior, and shell scripts that must be `shellcheck`-clean. A defect in Phase 1 contaminates everything above it.
- **Agents before hooks** because hooks (Phase 3) read the live agent inventory, and the new `pre-tool-use.sh` / `post-tool-use.sh` hooks reference agent semantics. Agents must have stable frontmatter and a complete `Connects to:` chain before hooks operationalize them.
- **Hooks before skills** because skills (Phase 4) call the Agent tool — a fan-out point that's only safe behind PreToolUse / PostToolUse / SessionStart enforcement. Skills authored without hook protection would bypass quality gates by default.
- **Skills before quality CI** because the CI gates (Phase 5) lint the user-facing skill output (vocabulary, frontmatter, parity). The lints have nothing to assert against until skills exist.
- **Within-phase parallelism**: Phase 1 has 3-way parallelism (version SoT vs. hook hardening vs. installer prompts + backup rotation, with shellcheck as a closing gate). Phase 2 has 4-way (4 new agents are independent). Phase 3 has 4-way (4 hooks independent). Phase 4 is semantically chained — recommend sequential (`/godmode` and `/mission` first, then the workflow chain `/brief → /plan → /build → /verify → /ship`, then helpers). Phase 5 has 5-way for CI gates with bats smoke as the closing gate.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4:** wave-based parallel `/build` race-handling pattern needs validation. `run_in_background=true` is documented but the file-polling fallback for stdout corruption races requires bench-testing on macOS + Linux. Recommend Phase 4 brief includes a small spike (≤½ day) to validate the lock-file pattern on both OSes before locking it into the skill.
- **Phase 3:** secret-scanning false-positive tolerance (CR-07 mitigation). The PreToolUse `(api_key|secret|password)\s*=\s*['"][^'"]+['"]` heuristic catches real leaks but also false-positives on test fixtures. Recommend Phase 3 brief enumerates exemption patterns (file paths, tool inputs) before locking the regex.

Phases with standard patterns (skip research-phase):
- **Phase 1:** all decisions are mechanical (jq -n, runtime version read, per-file diff prompt, backup rotation). Pattern-validated by Superpowers (per-file prompt) and ECC (jq hooks). Just-build.
- **Phase 2:** frontmatter convention is locked by IDEA.md and STACK.md. Just-build.
- **Phase 5:** standard CI patterns. shellcheck + bats are well-trodden. Just-build.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All 10 focus areas verified via live Claude Code 2026 docs (code.claude.com/docs/en/) on 2026-04-26. Bash 3.2 portability and jq idioms are well-trodden. |
| Features | HIGH | 38 table-stakes + 17 differentiator + 24 anti-feature catalog with explicit reference-plugin coverage. All 9 CONCERNS High items have a feature that closes them. All 5 IDEA must-have properties have falsifiable Active requirements. |
| Architecture | HIGH | Five-layer model is the v1.x baseline + locked PROJECT.md decisions. Build order M1→M5 is dependency-driven, not preference. Plugin/manual parity contract is file-by-file. |
| Pitfalls | HIGH | 10 Critical + 10 High + 6 Medium, all with concrete mitigations and milestone assignments. Distinct from CONCERNS.md (augments rather than restates). |

**Overall confidence:** HIGH. The v2 milestone is HIGH-confidence executable on the existing v1.x baseline.

### Gaps to Address

- **Opus 4.7 `effort: xhigh` rule-skipping** (CR-01) — listed at MEDIUM external confidence in STACK.md per Anthropic's documented behavior. Mitigation (effort: high for code-writing) is locked in PROJECT.md and IDEA.md, but the underlying behavior should be spot-verified during M2 brief. If Anthropic changes behavior between now and ship, the discipline still applies (xhigh is for design/audit, not Write/Edit).
- **Auto Mode reminder string** (D-09) — STACK.md notes the "Auto Mode Active" literal is observed in the current session but the wording could change. Mitigation: case-insensitive substring match. Spot-verify during M4 brief; document the canonical detection regex.
- **Wave-based parallel `/build` race-handling** (CR-08, D-10) — the `run_in_background=true` pattern is documented but the file-polling fallback for stdout corruption needs bench-testing. Recommend Phase 4 brief includes a small spike before locking it into the skill.

## Sources

### Primary (HIGH confidence — live docs verified 2026-04-26)
- `code.claude.com/docs/en/plugins-reference` — plugin.json schema, fields, env vars
- `code.claude.com/docs/en/hooks` — hook contracts, JSON shapes, timeout defaults, permissionDecision precedence
- `code.claude.com/docs/en/sub-agents` — Agent tool contract, frontmatter fields, isolation modes, memory contract
- `code.claude.com/docs/en/skills` — skill frontmatter, `<command-name>`, args, fork/agent context, lifecycle
- `code.claude.com/docs/en/statusline` — stdin JSON schema (28 fields), refresh cadence, ANSI/OSC 8
- `code.claude.com/docs/en/permission-modes` — auto / acceptEdits / bypassPermissions / plan / default semantics

### Secondary (HIGH confidence — local archive)
- `.planning-archive-v1/codebase/STACK.md` / `STRUCTURE.md` / `ARCHITECTURE.md` / `CONCERNS.md` / `CONVENTIONS.md` / `INTEGRATIONS.md` / `TESTING.md` — v1.x baseline audit (preserved across re-init)
- `.planning-archive-v1/research/{STACK,FEATURES,ARCHITECTURE,PITFALLS,SUMMARY}.md` — prior pass research from 2026-04-26 re-init (incorporated and superseded)
- `IDEA.md` — v2 idea brief (the input that drove this research pass)
- `.planning/PROJECT.md` — synthesized project context (this milestone)

### Tertiary (MEDIUM confidence — reference plugin observation)
- GSD (Get Shit Done) — observed slash command surface, agent frontmatter conventions, planning artifact shape. Treated as inspiration only; copy nothing structural.
- Superpowers — observed install script per-file diff prompts, backup rotation idioms. Treated as inspiration only.
- everything-claude-code — observed adversarial-safe hook idioms (jq -n --arg, cwd-from-stdin), shellcheck CI. Treated as inspiration only.

---
*Research completed: 2026-04-26*
*Ready for roadmap: yes*
