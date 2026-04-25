# Research Summary — claude-godmode v2

**Project:** claude-godmode v2 — polish mature version
**Domain:** Claude Code plugin (brownfield maturation of a shipped v1.x baseline)
**Researched:** 2026-04-26
**Synthesized:** 2026-04-26
**Overall confidence:** HIGH

---

## Executive Summary

claude-godmode v2 is a brownfield maturation of a working plugin, not a greenfield build. The v1.x baseline already ships 8 agents, 8 skills, a rules system, session hooks, a statusline, and two install paths. v2's mandate is to replace the ad-hoc `/prd → /plan-stories → /execute → /ship` pipeline with an opinionated, end-to-end workflow — Project → Mission → Brief → Plan → Commit — and to harden every known fragility identified in the codebase audit. The stack is entirely settled: Bash 3.2+, jq, Markdown, JSON, YAML. Nothing at runtime changes. What changes is the authoring surface (modern agent frontmatter, four new hook events, plugin manifest fields), the dev-time guardrails (shellcheck, bats-core, inline jq schema validation, a pure-Bash frontmatter linter), and the end-to-end coherence of the user-facing surface.

The dominant differentiator is radical simplicity: 11 user-facing slash commands (one slot reserved under a hard ≤12 cap), a single observable workflow chain (`/godmode → /mission → /brief → /plan → /build → /verify → /ship`), exactly two artifact files per active brief (BRIEF.md + PLAN.md), and a git log that IS the execution record. Reference plugins offer broader surfaces; this one offers a single path the user can hold in their head. The 11-command cap is not a limitation — it is the product.

The dominant risk is the substrate. The v1.x codebase has 21 documented concerns, 8 at High or Critical severity: silent overwrite of user-customized files during install, JSON injection in hooks via string interpolation, version drift across three files, hardcoded skill/agent lists that drift from the filesystem, hooks using `pwd` instead of stdin's `cwd` field, no version-mismatch guard in the uninstaller, settings merge that drops new top-level keys, and zero automated tests. Every one of these must be resolved before the agent and skill layers can be safely rebuilt on top. The build order is therefore non-negotiable: Foundation first, then agents, then skills, then workflow integration, then quality and CI.

---

## Key Findings

### Finding 1 — Foundation must come first; substrate fragility makes every later brief more expensive

**Title:** Foundation-first is a hard dependency, not a preference

**Finding:** All eight High/Critical concerns in `.planning/codebase/CONCERNS.md` are substrate issues — installer, hooks, version handling, settings merge. If agents and skills are rebuilt while hooks still use string-interpolated JSON, the new agents will fail under adversarial branch names exactly as the old ones did. If the installer still silently overwrites customizations, trust earned by the new surface is immediately lost on the next `./install.sh`.

**Evidence:** ARCHITECTURE.md "Build Order" section; PITFALLS.md A1 (Critical — silent overwrite), A2 (Critical — JSON injection), A3 (High — version drift), A4 (High — hardcoded lists), A5 (High — `pwd` reliance), A7 (High — uninstaller mismatch), A8 (High — settings merge), F5 (High — no tests).

**Implication:** Brief 1 (Foundation & Safety Hardening) must fully resolve all eight before Brief 2 begins. No parallelism across these two briefs.

---

### Finding 2 — The ≤12 command cap is the core product decision, not a constraint to work around

**Title:** 11 commands is the product; every addition past that breaks the Core Value

**Finding:** Reference plugins consistently fail at surface area: 30+ commands, 5+ artifact files per "phase", six-level vocabulary. The Core Value is "best-in-class capability behind the simplest possible surface." The 11-command surface is how that value becomes operational. The anti-features list (20 items) is the enforcement mechanism — each anti-feature directly removes a class of scope creep.

**Evidence:** FEATURES.md F-01 (table stakes, "why table stakes: the cap is the differentiator"); FEATURES.md D-01 (five-line "what now?"); PROJECT.md Key Decisions ("11 commands total, 1 reserved slot"); PITFALLS.md E3 (Critical — `/everything` mega-command).

**Implication:** Every brief must include a command-count assertion in its success criteria. The vocabulary CI gate (PITFALLS.md B1) and the command-count CI gate (PITFALLS.md E3) are non-negotiable quality deliverables in Brief 5.

---

### Finding 3 — Two artifact files per brief is an architectural constraint that needs mechanical enforcement

**Title:** BRIEF.md + PLAN.md only; git log is the execution record

**Finding:** Reference plugins proliferate per-task artifact files (TASK.md, EXECUTE.md, VERIFICATION.md). The project explicitly rejects this. BRIEF.md carries why + what + spec + research summary; PLAN.md carries tasks, wave structure, verification status. The constraint needs mechanical enforcement, not just documentation: a CI gate that fails on any file in `.planning/briefs/NN/` other than BRIEF.md and PLAN.md.

**Evidence:** PITFALLS.md B2 (High — directory-shape mimicry), E2 (High — per-task files); ARCHITECTURE.md "Anti-Pattern 2"; PROJECT.md Out of Scope ("Per-task artifact files (TASK.md)").

**Implication:** The `rules/godmode-planning.md` rule file and the CI artifact-count gate are Brief 3/5 deliverables. `@planner`'s prompt must include an explicit "write to PLAN.md only" constraint.

---

### Finding 4 — Hook layer has four independent hardening requirements, each with a distinct failure mode

**Title:** Hooks fail in four distinct, independent ways; each needs its own fix

**Finding:** The four hook failure modes don't share a root cause: (A2) JSON injection from string interpolation needs `jq -n --arg` discipline throughout; (A5) wrong project root from `pwd` instead of stdin's `cwd` field needs a standard hook preamble; (A6) stdin drain failure under `pipefail` needs `|| true`; (D4) timeout inconsistency between plugin and manual mode needs a canonical source. All four must be fixed before new hooks (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionEnd`) are added, or the new hooks inherit all four problems.

**Evidence:** STACK.md "Hook events" section; PITFALLS.md A2, A5, A6, D4; ARCHITECTURE.md "Pattern 4: jq for everything JSON".

**Implication:** Brief 1 must deliver a `hooks/_lib/preamble.sh` that provides the cwd-resolution, stdin-drain, and JSON-output-via-jq standard, sourced by every hook. New hooks in Brief 3 must be built on top of that standard.

---

### Finding 5 — Agent effort policy must be a rule, not just frontmatter, because `effort: xhigh` on Opus 4.7 skips rules

**Title:** Lock the effort policy in `rules/godmode-routing.md`; frontmatter alone is insufficient

**Finding:** Empirically documented in the project's own Key Decisions: `xhigh` on Opus 4.7 skips rule application during code generation. Design and audit agents (`@architect`, `@security-auditor`, `@planner`, `@verifier`) tolerate this trade because they're read-only. Code-writing agents (`@executor`, `@writer`, `@test-writer`) cannot. The mitigation must be mechanical: a frontmatter linter that fails CI if any agent has both `effort: xhigh` and `Write`/`Edit`/`MultiEdit` in its tools, plus a locked statement in `rules/godmode-routing.md`.

**Evidence:** STACK.md "Effort assignments — locked into `rules/godmode-routing.md`"; PITFALLS.md D2 (High); PROJECT.md Key Decisions ("Code-writing agents use `effort: high`, not `xhigh`").

**Implication:** The frontmatter linter (Brief 2, AGENT-LINT-01) must enforce this. The routing rule is a Brief 4 deliverable. Both must land before `/build` (Brief 3) ships `@executor`.

---

### Finding 6 — Live filesystem indexing eliminates an entire class of drift bugs

**Title:** Enumerate agents and skills from disk at runtime; never hardcode lists

**Finding:** v1.x hardcodes eight skill names and eight agent names in `hooks/post-compact.sh`. v2 changes the entire surface. Every place that enumerates agents or skills must use `find` at runtime. This pattern applies to `/godmode`, `PostCompact`, `SessionStart`, and any CI gate that cross-checks docs against code.

**Evidence:** PITFALLS.md A4 (High — hardcoded drift); ARCHITECTURE.md "Pattern 3: Live filesystem indexing, never hardcoded lists"; FEATURES.md D-04 (differentiator).

**Implication:** Brief 3 (`/godmode` rewrite) and Brief 3 (`PostCompact` update) must both adopt the live-indexing pattern. One `find` call permanently eliminates CONCERNS #8.

---

### Finding 7 — Workflow hand-off gates need pre-flight checks to prevent silent garbage propagation

**Title:** Each workflow stage must refuse to run if its upstream artifact is absent or incomplete

**Finding:** The failure mode is concrete: `/plan` invoked without a complete BRIEF.md runs `@planner` against nothing; `@planner` hallucinates requirements; `/build` delivers the hallucination. Prevention requires pre-flight guards at each hand-off: `/plan` checks that BRIEF.md exists, has required sections, and bears a completion sentinel; `/build` checks that PLAN.md exists with a `## Tactical Plan` section and a `## Verification Status` table.

**Evidence:** PITFALLS.md C1 (Critical — `/plan` without brief), C2 (Critical — `/build` without plan), C5 (Critical — silent intent mutation); FEATURES.md F-04, F-05, F-06.

**Implication:** The BRIEF.md template must include a `<!-- BRIEF-COMPLETE -->` sentinel; the PLAN.md template must include the `## Verification Status` table. Both are Brief 3 (State) deliverables. `/brief`, `/plan`, and `/build` skill bodies must include the respective pre-flight logic.

---

### Finding 8 — Auto Mode is a live primitive that changes the safety contract for destructive operations

**Title:** Skills must detect Auto Mode and refuse destructive operations; hooks must block bypass attempts regardless

**Finding:** Auto Mode instructs the assistant to "minimize interruptions" and "prefer action over planning." This is correct for routine operations. It is dangerous for destructive operations: force pushes, settings.json writes, schema migrations. The hook layer (`PreToolUse`) must refuse bypass attempts (`--no-verify`, `-c core.hooksPath=/dev/null`) regardless of mode. Individual skills must detect the "Auto Mode Active" system reminder and refuse destructive operations with an explicit "explicit user confirmation required, exit Auto Mode" message. A new rule file (`rules/godmode-auto-mode.md`) codifies the canonical list.

**Evidence:** PITFALLS.md D1 (Critical — Auto Mode bypasses quality gates); STACK.md "Hook events" (PreToolUse purpose); FEATURES.md D-09 (Auto Mode awareness as differentiator).

**Implication:** This spans three briefs: PreToolUse hook body (Brief 1), skill-level Auto Mode detection pattern (Brief 3), and the auto-mode rule file (Brief 4). The hook portion (refuse `--no-verify` regardless) must land in Brief 1 before any other brief ships executable agents.

---

## Implications for Roadmap

Research confirms the existing 5-brief structure in ROADMAP.md is correctly ordered and correctly scoped. The findings above map directly onto it. The order is non-negotiable due to hard dependencies between layers.

### Brief 1 — Foundation & Safety Hardening

**Rationale:** The substrate everything else stands on. Eight High/Critical CONCERNS items must be resolved before agents and skills can be safely rebuilt on top. A fragile hook substrate means agent context injection fails silently; a silent-overwrite installer means trust earned by the new workflow is destroyed on the next reinstall.

**Delivers:** `jq -n --arg` discipline across all hooks; per-file diff/skip/replace installer prompt; backup rotation (keep 5); version single-source-of-truth in `plugin.json`; `hooks/_lib/preamble.sh` standard; `config/quality-gates.txt` single source; PreToolUse blocking `--no-verify`; PostToolUse surfacing failed quality-gate exits; shellcheck clean on every `*.sh`; uninstaller version-mismatch guard; v1.x migration detection (non-destructive).

**Features addressed (from FEATURES.md):** F-09 through F-15, F-26, F-27, F-28, F-29.

**Pitfalls to avoid:** A1 (silent overwrite), A2 (JSON injection), A3 (version drift), A5 (pwd reliance), A6 (stdin drain), A7 (uninstall mismatch), A8 (settings merge), D1 (Auto Mode bypass), D4 (timeout parity), D5 (plugin/manual parity), F1 (backup accumulation).

**Within-brief parallelism:** Version SOT (F-09) and installer prompt (F-11) are independent of hook hardening (A2, A5, A6). Both work streams can run in parallel.

**Open questions for `/brief 1` discussion:**
- Should PreToolUse also block `git commit -n` (short form of `--no-verify`)?
- Should `hooks-canonical.json` be a generated artifact or a hand-authored source-of-truth with a CI parity check?

---

### Brief 2 — Agent Layer Modernization

**Rationale:** Skills in Brief 3 spawn agents. Agents must exist with correct frontmatter (model aliases, effort policy, isolation, maxTurns, `Connects to:`) before skills can wire to them. The frontmatter linter must be running in CI before agents ship, so it enforces the effort policy mechanically.

**Delivers:** All 8 existing agents updated to current aliases (`opus`/`sonnet`/`haiku`), explicit `effort:`, `maxTurns`, `isolation: worktree` (code-writing) or `memory: project` (persistent learners), `Connects to:` field. Four new agents: `@planner` (opus, xhigh, read-only), `@verifier` (opus, xhigh, read-only), `@spec-reviewer` (sonnet, high, read-only), `@code-reviewer` (sonnet, high, read-only). `@reviewer` split into `@spec-reviewer` + `@code-reviewer`. Pure-Bash frontmatter linter (`scripts/lint-frontmatter.sh`) enforcing model alias, effort tier, and write-tool exclusion rule.

**Features addressed (from FEATURES.md):** F-21 through F-25.

**Pitfalls to avoid:** D2 (effort xhigh on code-writing agents), B1 (vocabulary leakage into agent prompts), C3 (context drift), E1 (borrowed prompts from reference plugins).

**Within-brief parallelism:** All four new agents are independent. Parallelizable. Frontmatter linter (AGENT-LINT-01) blocks until all agents land.

**Open questions for `/brief 2` discussion:**
- Does `@verifier` run in `background: true`, or does its thorough audit warrant foreground priority?
- Which agents justify `memory: project` — just `@architect` and `@researcher`, or also `@planner`?

---

### Brief 3 — Skill Layer Rebuild + State Management

**Rationale:** This is the user-facing surface. Each skill maps to specific agents from Brief 2 and writes to `.planning/` artifacts whose templates land in this same brief (sequenced within: templates before skill bodies). Brief 3 also delivers the `init-context.sh` shared helper, which every skill orchestrator sources instead of re-implementing `.planning/` traversal.

**Delivers:** Five new workflow skills (`/mission`, `/brief`, `/plan`, `/build`, `/verify`); `/ship` rewritten; four helpers updated (`/debug`, `/tdd`, `/refactor`, `/explore-repo`) for new agent names + Auto Mode awareness; `/godmode` rewritten with live filesystem indexing; `.planning/` artifact templates (PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, config.json, BRIEF.md template, PLAN.md template); `skills/_shared/init-context.sh`; v1.x deprecation banners on `/prd`, `/plan-stories`, `/execute`.

**Features addressed (from FEATURES.md):** F-01 through F-08, F-15, F-18, F-19, F-20.

**Pitfalls to avoid:** C1 (plan without brief), C2 (build without plan), C5 (silent intent mutation), D1 (Auto Mode in skills), E3 (`/everything` mega-command), B1 (vocabulary leakage in skill bodies), B2 (artifact proliferation beyond two files per brief).

**Within-brief sequencing:** Recommended sequential — `/mission → /brief → /plan → /build → /verify` — so each can be smoke-tested in a temp consumer repo before the next is written. Templates (State layer) land before skill bodies.

**Open questions for `/brief 3` discussion:**
- What is `/build`'s wave-concurrency cap — hardcoded 5, or a config knob in `.planning/config.json`?
- Should `STATE.md` be machine-mutated only, or is user hand-editing explicitly supported?
- Does the `<!-- BRIEF-COMPLETE -->` sentinel live in a YAML frontmatter field or a markdown comment?

---

### Brief 4 — Workflow Integration & Parity

**Rationale:** Rules tie together agents (Brief 2) and skills (Brief 3) into a coherent workflow narrative. Parity checks validate the guarantee that plugin-mode and manual-mode users see identical behavior. Migration handling reads the live state produced by Brief 1's hardened installer. This brief cannot land before Brief 3 because rule files must reference real skill names.

**Delivers:** `rules/godmode-workflow.md` rewritten for the Project → Mission → Brief → Plan → Commit chain; `rules/godmode-routing.md` with locked effort policy (code-writers=`high`, design/audit=`xhigh`); `rules/godmode-quality.md` cross-referencing `config/quality-gates.txt`; plugin-mode + manual-mode UX parity verification; README, CHANGELOG, `/godmode` surface agreement; v1.x → v2 migration note in both `/godmode` and SessionStart; prompt-cache-aware rule structure (static preamble, no dynamic content in rule bodies).

**Features addressed (from FEATURES.md):** F-30, D-06, D-09, D-10.

**Pitfalls to avoid:** D3 (prompt cache invalidation from dynamic rule content), D5 (plugin/manual parity), B1 (vocabulary leakage in rules), B3 (compatibility marketing), F3 (doc drift).

**Within-brief parallelism:** Three rule rewrites (workflow, routing, quality) are independent. Migration note is independent. Parity check is a gate after both rule files and skills land.

**Open questions for `/brief 4` discussion:**
- Should the v1.x detection note in SessionStart suppress itself after the first session, or print every time until `/mission` is run?
- Does `rules/godmode-auto-mode.md` ship as a separate file or as a section in `godmode-quality.md`?

---

### Brief 5 — Quality, CI, Tests, Documentation

**Rationale:** CI tests the substrate (Brief 1), agents (Brief 2), skills (Brief 3), and integration (Brief 4). Testing `/godmode` before it has been rewritten in Brief 3 would produce a test of the v1.x shape. All four layers must exist before the bats smoke test is meaningful.

**Delivers:** GitHub Actions matrix (`ubuntu-latest` + `macos-latest`) on every PR; shellcheck on every `*.sh`; inline `jq -e` JSON schema validation on `plugin.json`, `hooks.json`, `settings.template.json`, `config.json`; frontmatter linter in CI; bats-core smoke test (install → `/godmode` → uninstall round trip in `mktemp -d`); vocabulary CI gate (blocks reference-plugin terms from shipped artifacts); version-drift CI gate; artifact-count gate (briefs contain exactly BRIEF.md + PLAN.md); CONTRIBUTING.md with backup rotation, worktree prune, and frontmatter conventions; all High-severity CONCERNS.md items resolved with traceability.

**Features addressed (from FEATURES.md):** F-16, F-17, F-30.

**Pitfalls to avoid:** F5 (no tests = all other pitfalls escape), A2 (hook fuzz tests), A3 (version drift CI), B1 (vocabulary CI), F3 (doc drift CI gate), D2 (frontmatter linter in CI invocation).

**Within-brief parallelism:** shellcheck, JSON schema validation, frontmatter linter, and vocabulary gate are all independent. bats smoke test depends on install/skills working (Brief 1 + 3 complete).

**Open questions for `/brief 5` discussion:**
- Should the bats smoke test run against both install modes (plugin + manual) or manual-only first?
- Is the vocabulary CI gate a pre-commit hook or a CI-only check?

---

### Build Order Summary

```
Brief 1: FOUNDATION — hardens substrate (hooks, installer, version)
  |     No parallelism with Brief 2; substrate must be solid first.
  v
Brief 2: AGENTS — modernizes and adds the agent layer
  |     Depends on Brief 1: PreToolUse must be live so worktree-isolated agents
  |     can't bypass --no-verify.
  v
Brief 3: SKILLS + STATE — builds the user-facing surface + artifact templates
  |     Depends on Brief 2: every skill has a Connects to: referencing real agent files.
  v
Brief 4: INTEGRATION — rules, parity, migration, prompt-cache structure
  |     Depends on Brief 3: workflow rule references real skill names.
  v
Brief 5: QUALITY — CI, bats smoke, doc parity, all CONCERNS resolved
          Depends on Brief 4: tests are meaningful only when the full surface exists.
```

Within-brief parallelism is available in Briefs 1, 2, 4, and 5. Brief 3 is recommended sequential (each skill smoke-tested before the next is written).

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Runtime (Bash + jq) verified against v1.x baseline; dev-time tools (shellcheck v0.11.0, bats-core v1.13.0, GitHub Actions shape) verified against GitHub releases and CI docs. Model aliases verified against Anthropic docs. The jq-vs-full-JSON-Schema tradeoff is the only MEDIUM item — deliberate and documented in STACK.md. |
| Features | HIGH | All 30 table-stakes features (F-01..F-30) directly traceable to PROJECT.md Active requirements or CONCERNS.md High items. 12 differentiators are direct restatements of PROJECT.md principles. 20 anti-features map to PROJECT.md Out of Scope. F-27 (secret scanning) and D-09 (Auto Mode awareness) are MEDIUM due to implementation-time tuning required. |
| Architecture | HIGH | Layer model preserved from v1.x (HIGH baseline). 11-command surface locked in PROJECT.md Key Decisions. Skill→Agent invocation matrix derived from requirements. Build order is dependency-driven and matches existing ROADMAP.md. MEDIUM items: `/build` file-polling fallback details (Brief 3 design work) and `.planning/` template content. |
| Pitfalls | HIGH | 21 of 27 pitfalls sourced directly from CONCERNS.md (project's own codebase audit) or PROJECT.md Out of Scope items. Vocabulary-leakage and vendoring pitfalls are MEDIUM (inference from the re-init rationale rather than direct detection). |

**Overall confidence: HIGH**

The research is unusually high-confidence because it is primarily analysis of an existing shipped codebase (v1.x), not inference about an unknown domain. The CONCERNS.md audit was done against running code. The PROJECT.md Key Decisions are explicit. The stack is unchanged at runtime.

### Gaps to Address in `/brief N` Discussions

| Gap | Relevant Brief | Recommendation |
|-----|---------------|----------------|
| PreToolUse pattern scope: does `--no-verify` or `-n` (short form) need separate handling? | Brief 1 | Resolve in `/brief 1` — short-form patterns may need a different grep expression |
| `/build` concurrency cap: hardcoded 5 or config knob in `config.json`? | Brief 3 | Lean toward hardcoded for v2; config knob is v2.1 territory after demand is observed |
| `STATE.md` mutability: machine-only vs. user-editable | Brief 3 | Recommendation: machine-mutates, user reads — but brief discussion should validate |
| `@verifier` foreground vs. background | Brief 2 | Its read-only pass benefits from completeness over speed — foreground is the safer default |
| v1.x detection note suppression strategy | Brief 4 | Once per session until `/mission` is run; suppress via STATE.md presence flag |
| Secret-scanning false-positive tolerance level (F-27) | Brief 1 | MEDIUM confidence — needs brief-time decisions on pattern set and warn-vs-block behavior |

---

## Sources

### Primary (HIGH confidence)

- `.planning/codebase/CONCERNS.md` — 21 documented v1.x fragilities with line-number citations; primary source for Brief 1 scope
- `.planning/PROJECT.md` — Active requirements, Out of Scope, Key Decisions, Constraints; primary source for surface area and vocabulary constraints
- `.planning/research/STACK.md` — Full agent frontmatter schema, hook event matrix (24 events), model aliases; verified against `code.claude.com/docs/en/{plugins-reference,hooks,sub-agents,skills}` (2026-04-26)
- `.planning/research/FEATURES.md` — 30 table-stakes (F-01..F-30), 12 differentiators (D-01..D-12), 20 anti-features (A-01..A-20)
- `.planning/research/ARCHITECTURE.md` — Layer model, skill→agent invocation matrix, 5-brief build order, data flow, component boundaries
- `.planning/research/PITFALLS.md` — 27 pitfalls across 6 categories; 8 Critical, 10 High, 6 Medium, 3 Low; brief-specific warning matrix
- `https://code.claude.com/docs/en/plugins-reference` — plugin manifest schema, agent frontmatter restrictions, `${CLAUDE_PLUGIN_DATA}`, `userConfig`, `bin/` directory
- `https://code.claude.com/docs/en/hooks` — full 24-event hook matrix, deprecated output shape, timeout defaults
- `https://github.com/koalaman/shellcheck/releases` — shellcheck v0.11.0 (2025-08-04)
- `https://github.com/bats-core/bats-core/releases` — bats-core v1.13.0 (2024-11-07)

### Secondary (MEDIUM confidence)

- Reference-plugin observation (GSD, Superpowers, everything-claude-code) — used only to identify vocabulary-leakage and dependency-creep pitfall categories; no structural content adopted
- Claude Code Auto Mode contract (system reminder present in this session) — primary source for D1 pitfall prevention; live primitive

---

*Research synthesized: 2026-04-26*
*Source files: STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md*
*Ready for roadmap: yes — existing ROADMAP.md confirmed correct; this summary provides brief-level detail for `/brief N` discussions*
