# Roadmap: claude-godmode v2

## Overview

claude-godmode v1.x is a working Claude Code plugin (8 agents, 8 skills, plugin+manual install). This roadmap takes the codebase from v1.x to **v2.0.0 — polish mature version**: a single-arrow-chain workflow, hardened substrate, modernized agent layer, mechanical quality gates, and a CI'd release. The build order (Foundation → Agents → Hooks → Skills → Quality) is dependency-driven and non-negotiable: every phase requires its predecessor, and skipping any one of them poisons the rest. 46 v1 requirements map across 5 phases (0 unmapped). The journey ends when the v2.0.0 release is tagged on `main`.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4, 5): Planned milestone work — locked at re-init
- Decimal phases (e.g., 2.1): Reserved for urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation & Safety Hardening** — Substrate stops fighting the user (version SoT, hook safety, install prompts, backup, indexing, shellcheck). Closes 6 of 9 High-severity v1.x defects.
- [ ] **Phase 2: Agent Layer Modernization** — Frontmatter convention locked. New `@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`. Frontmatter linter ships.
- [ ] **Phase 3: Hook Layer Expansion** — `PreToolUse` (`--no-verify` block + secret scan), `PostToolUse` (failed-gate surfacing), `SessionStart` STATE injection, `PostCompact` live-FS scan.
- [ ] **Phase 4: Skill Layer & State Management** — All 11 user-facing skills authored to new shape. Auto-mode awareness. Wave-based parallel `/build`. `init-context.sh`.
- [ ] **Phase 5: Quality — CI, Tests, Docs Parity** — GitHub Actions (5 lints), bats smoke, plugin/manual parity gate, vocabulary gate, README + CHANGELOG + marketplace metadata. v2.0.0 release.

## Phase Details

### Phase 1: Foundation & Safety Hardening
**Goal**: The substrate stops fighting the user. Customizations preserved on reinstall; hooks emit valid JSON under adversarial inputs; version drift impossible; every shell script `shellcheck`-clean. Resolves 6 of 9 High-severity items in `.planning-archive-v1/codebase/CONCERNS.md`.
**Depends on**: Nothing (first phase)
**Requirements**: FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06, FOUND-07, FOUND-08, FOUND-09, FOUND-10, FOUND-11
**Success Criteria** (what must be TRUE):
  1. A user re-runs `./install.sh` over a `~/.claude/` with hand-edited rule, agent, skill, or hook files; the installer prompts per-file `[d/s/r/a/k]` and never silently overwrites. Non-TTY default keeps customizations.
  2. `bash hooks/session-start.sh` and `bash hooks/post-compact.sh` against a git repo whose branch name contains `"`, `\`, `\n`, or `'` produce valid JSON (passes `jq -e '.'`).
  3. `bash scripts/check-version-drift.sh` exits 0; `grep -rn '1\.[46]\.[01]' install.sh commands/godmode.md README.md` returns no hits; the plugin advertises a single version sourced from `plugin.json:.version`.
  4. `bash uninstall.sh` over a `~/.claude/` with `.claude-godmode-version=0.0.1` exits non-zero with a clear warning; `--force` proceeds.
  5. `shellcheck install.sh uninstall.sh hooks/*.sh config/statusline.sh scripts/*.sh` exits 0; `~/.claude/backups/` after 7 reinstalls contains exactly 5 timestamped directories.
**Plans**: 4 plans (3 parallel + 1 closing gate)

Plans:
- [ ] 01-01: Version SoT — install.sh / uninstall.sh / commands/godmode.md / scripts/check-version-drift.sh / config/statusline.sh single-jq
- [ ] 01-02: Hook hardening — session-start.sh / post-compact.sh JSON-via-jq, cwd-from-stdin, stdin-drain tolerance, live-FS substrate, gates-from-config
- [ ] 01-03: Installer hardening — per-file diff/skip/replace prompt loop, detection-only v1.x migration, backup rotation; uninstaller version mismatch + --force
- [ ] 01-04: Closing gate — `.shellcheckrc`, shellcheck pass over all touched `.sh`, CHANGELOG entry

### Phase 2: Agent Layer Modernization
**Goal**: Every agent uses the v2 frontmatter convention (model alias, effort tier, isolation, memory, maxTurns, `Connects to:` line). Code-writing agents at `effort: high`; design/audit at `effort: xhigh` — never both. Four new agents (`@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`) ship. Frontmatter linter is pure-bash and CI-gated. The `Connects to:` chain forms a complete dependency graph that `/godmode` can render.
**Depends on**: Phase 1 (live-indexing substrate)
**Requirements**: AGENT-01, AGENT-02, AGENT-03, AGENT-04, AGENT-05, AGENT-06, AGENT-07, AGENT-08
**Success Criteria** (what must be TRUE):
  1. Every file in `agents/*.md` parses through `bash scripts/check-frontmatter.sh` with zero errors.
  2. Four new agents exist on disk (`@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`) with correct effort tier (`xhigh` for first three, `high` for `@code-reviewer`) and read-only-where-required (`disallowedTools: Write, Edit` on review and verify agents).
  3. No agent in `agents/*.md` combines `effort: xhigh` with Write or Edit in `tools:`. Linter refuses such a commit.
  4. The `Connects to:` chain across the 12-agent set forms a connected graph (every code-writing agent is reachable from a workflow skill, every audit agent is reachable from `@spec-reviewer` or `@code-reviewer`).
  5. All v1.x agents in `agents/*.md` use model aliases (`opus`, `sonnet`, `haiku`) — `grep -E 'model: claude-' agents/*.md` returns nothing.
**Plans**: 3 plans

Plans:
- [ ] 02-01: Frontmatter convention + linter (rules/godmode-routing.md, scripts/check-frontmatter.sh)
- [ ] 02-02: Four new agents (@planner, @verifier, @spec-reviewer, @code-reviewer) + Connects-to wiring
- [ ] 02-03: Modernize 8 v1.x agents to v2 convention (aliases, effort tiers, Connects-to)

### Phase 3: Hook Layer Expansion
**Goal**: Mechanical (not aspirational) quality gates. `PreToolUse` blocks `--no-verify` and quality-gate-bypass patterns; scans for hardcoded secrets. `PostToolUse` surfaces failed gate exit codes in the next turn. `SessionStart` injects active-brief context from `.planning/STATE.md`. `PostCompact` reads the live agent/skill inventory and the canonical quality-gates list. Plugin-mode and manual-mode hook bindings stay in sync (M5 asserts byte-for-byte parity).
**Depends on**: Phase 2 (agent inventory must be stable)
**Requirements**: HOOK-01, HOOK-02, HOOK-03, HOOK-04, HOOK-05, HOOK-06
**Success Criteria** (what must be TRUE):
  1. `bash hooks/pre-tool-use.sh` invoked with stdin describing `Bash("git commit --no-verify")` returns a `permissionDecision: deny` JSON response with a clear remediation message.
  2. `bash hooks/pre-tool-use.sh` invoked with stdin containing a hardcoded AWS key in tool input returns `permissionDecision: deny` with remediation pointer (env var, `.env`).
  3. After a typecheck/lint command exits non-zero, `bash hooks/post-tool-use.sh` injects `additionalContext` flagging the failure for the next turn.
  4. `bash hooks/session-start.sh` against a project with `.planning/STATE.md` populated injects active-brief context (brief #, status, next command) into `additionalContext`.
  5. `bash hooks/post-compact.sh` produces output that lists the actual `agents/*.md` filenames and `skills/*/SKILL.md` directory names found at runtime; the 6 quality gates rendered match `config/quality-gates.txt` line-for-line.
**Plans**: 3 plans

Plans:
- [ ] 03-01: PreToolUse hook — `--no-verify` block + secret pattern scan
- [ ] 03-02: PostToolUse hook — failed-gate exit-code surfacing
- [ ] 03-03: SessionStart STATE injection + PostCompact live-FS scan + gates from config (vocabulary alignment to v2 chain)

### Phase 4: Skill Layer & State Management
**Goal**: All 11 user-facing skills (`/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`) rewritten or freshly authored to v2 shape. Auto-mode awareness in every skill. Wave-based parallel `/build` with file-polling fallback. `skills/_shared/init-context.sh` is the bash-native equivalent of `gsd-sdk`. State management via `.planning/STATE.md` machine-mutated by skills, user-readable. v1.x deprecation banners on `/prd`, `/plan-stories`, `/execute`. Two-files-per-brief discipline (BRIEF.md + PLAN.md, no others).
**Depends on**: Phase 3 (hook substrate enforces atomic commits and detects secrets — `/build` and `/ship` rely on this)
**Requirements**: WORKFLOW-01, WORKFLOW-02, WORKFLOW-03, WORKFLOW-04, WORKFLOW-05, WORKFLOW-06, WORKFLOW-07, WORKFLOW-08, WORKFLOW-09, WORKFLOW-10, WORKFLOW-11, WORKFLOW-12, WORKFLOW-13, WORKFLOW-14
**Success Criteria** (what must be TRUE):
  1. `find commands skills -name '*.md' -type f` lists exactly 11 user-invocable skills (counting `commands/godmode.md` + 10 `skills/<name>/SKILL.md` files where frontmatter declares `user-invocable: true`).
  2. `/godmode` skill (executed as a script or its body inspected) produces a ≤5-line "what now?" answer when `.planning/STATE.md` is present.
  3. `bash skills/_shared/init-context.sh` returns a valid JSON blob (`jq -e '.'` passes) describing the current `.planning/` state. No Node, no Python, no helper binary invoked.
  4. The 6 workflow skills (`/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`) each contain an Auto Mode detection block (string-match on the canonical reminder regex documented in `rules/godmode-skills.md`).
  5. After a `/brief 1 → /plan 1 → /build 1` round-trip in a sample project, `.planning/briefs/01-name/` contains exactly 2 files (`BRIEF.md`, `PLAN.md`); the git log contains 1 atomic commit per task in PLAN.md.
**Plans**: 4 plans

Plans:
- [ ] 04-01: `init-context.sh` shared helper + `.planning/` artifact templates
- [ ] 04-02: Orient + mission skills (`/godmode`, `/mission`)
- [ ] 04-03: Workflow chain (`/brief`, `/plan`, `/build`, `/verify`, `/ship`) — wave-based parallel build with file-polling fallback
- [ ] 04-04: Cross-cutting helpers (`/debug`, `/tdd`, `/refactor`, `/explore-repo`) + v1.x deprecation banners

### Phase 5: Quality — CI, Tests, Docs Parity
**Goal**: Gate the entire substrate before v2.0.0 ships. CI workflow runs 5 lints (shellcheck, frontmatter, version drift, plugin/manual parity, vocabulary). bats-core smoke exercises install → uninstall → reinstall → adversarial-input hook fixtures on macOS + Linux. README ≤500 lines, CHANGELOG dated, plugin marketplace metadata polished. Settings merge regression test prevents silent key drops on upgrade.
**Depends on**: Phase 4 (every prior layer is the substrate that CI and bats lint)
**Requirements**: QUAL-01, QUAL-02, QUAL-03, QUAL-04, QUAL-05, QUAL-06, QUAL-07
**Success Criteria** (what must be TRUE):
  1. `.github/workflows/ci.yml` exists; on a fresh push, all 5 gates run and pass: shellcheck, frontmatter linter, version-drift check, plugin/manual parity gate, vocabulary gate.
  2. `bats tests/install.bats` exits 0 on `macos-latest` and `ubuntu-latest`; the suite covers install → uninstall → reinstall and the 4 adversarial-branch hook fixtures.
  3. `bash scripts/check-parity.sh` exits 0 — hook bindings, timeouts, and permissions are byte-for-byte equivalent between `hooks/hooks.json` and `config/settings.template.json[hooks]`.
  4. `bash scripts/check-vocab.sh` exits 0 — no occurrences of `phase`, `task`, `story`, `PRD`, `gsd-*`, `cycle`, or `milestone` in `commands/`, `skills/`, or `README.md`.
  5. `wc -l README.md` ≤ 500; `head -3 CHANGELOG.md` shows a dated `## v2.0.0` heading; `jq -r .description .claude-plugin/plugin.json` returns a marketplace-polished string ≤200 chars; `git tag` shows `v2.0.0`.
**Plans**: 7 plans (3 executed + 4 gap-closure from 05-VERIFICATION.md)

Plans:
- [x] 05-01: CI workflow with 5 lint gates (shellcheck + frontmatter + version drift + parity + vocab)
- [x] 05-02: bats smoke test with adversarial fixtures + settings merge regression test
- [x] 05-03: README rewrite + CHANGELOG dated entry + marketplace metadata polish + v2.0.0 tag
- [x] 05-04: vocabulary gate green — scrub Phase N from 6 SKILL.md bodies + scoped milestone allowlist for /mission (CR-01)
- [x] 05-05: add userConfig.model_profile to plugin.json — documented public API now exists (CR-02)
- [x] 05-06: bats Tests 7-10 actually exercise adversarial code path via PATH-shimmed fake git on session-start.sh (CR-03)
- [ ] 05-07: CONTRIBUTING.md v2 rewrite — file structure, 12-agent enumeration, xhigh pitfall, skill-conventions pointer (CR-04)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5. Decimal phases (e.g., 2.1) reserved for urgent insertions, none planned at re-init.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & Safety Hardening | 0/4 | Not started | - |
| 2. Agent Layer Modernization | 0/3 | Not started | - |
| 3. Hook Layer Expansion | 0/3 | Not started | - |
| 4. Skill Layer & State Management | 0/4 | Not started | - |
| 5. Quality — CI, Tests, Docs Parity | 0/3 | Not started | - |

**Phase Ordering Rationale:**
- **Phase 1 first** because every later phase touches hooks, version-aware behavior, and shell scripts that must be `shellcheck`-clean. A defect in Phase 1 contaminates everything above it.
- **Phase 2 before Phase 3** because Phase 3 hooks read the live agent inventory and reference agent semantics. Agents must have stable frontmatter and a complete `Connects to:` chain before hooks operationalize them.
- **Phase 3 before Phase 4** because Phase 4 skills call the Agent tool — a fan-out point that's only safe behind PreToolUse/PostToolUse/SessionStart enforcement.
- **Phase 4 before Phase 5** because Phase 5 CI gates lint the user-facing skill output (vocabulary, frontmatter, parity). The lints have nothing to assert against until skills exist.
- **Within-phase parallelism**: Phase 1 has 3-way parallelism (version SoT vs. hook hardening vs. installer hardening, with shellcheck as a closing gate). Phase 2 has 2-way (linter foundation can ship before/after new agents). Phase 3 has 3-way (3 hooks mostly independent). Phase 4 is semantically chained — recommend sequential. Phase 5 has 3-way for CI/bats/docs with the v2.0.0 tag as the closing commit.
