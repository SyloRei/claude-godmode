# Roadmap: claude-godmode v2 — polish mature version

**Created:** 2026-04-25
**Milestone:** v2.0
**Phase count:** 5
**Granularity:** Standard
**Coverage:** 62/62 requirements mapped ✓

> Note: The REQUIREMENTS.md header states "61 total" but contains 62 requirement IDs
> (FOUND-01..10 = 10, AGENT-01..11 = 11, HOOK-01..10 = 10, SKILL-01..12 = 12,
> STATE-01..08 = 8, QUAL-01..11 = 11; total = 62). All are mapped below.

---

## Phases

- [ ] **Phase 1: Foundation and Safety Hardening** — Stabilize hooks, installer, version, and baseline CI before any new features land
- [ ] **Phase 2: Agent Layer Modernization + Rules Hardening** — Upgrade all agents with current frontmatter, new agent roles, new hooks, and cache-safe rules
- [ ] **Phase 3: Skill Layer Rebuild (GSD-Aligned Workflow)** — Deliver the user-facing v2 workflow: discuss → plan-phase → execute-phase → ship, ≤ 12 commands
- [ ] **Phase 4: State Management and `.planning/` Scaffold** — Ship the consumer-project artifact set and shared skill fragments
- [ ] **Phase 5: CI Completion, Performance Polish, and Documentation Parity** — Close remaining CI gaps, performance items, and bring all docs to v2 state

---

## Phase Details

### Phase 1: Foundation and Safety Hardening

**Goal**: The v1.x plugin is trustworthy to deploy and upgrade — hooks emit valid JSON under adversarial inputs, the installer is safe and per-file interactive, version is a single source of truth, and a baseline CI job runs shellcheck on every PR.

**Depends on**: Nothing (first phase)

**Requirements**: FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06, FOUND-07, FOUND-08, FOUND-09, FOUND-10, HOOK-06, HOOK-07, HOOK-08, HOOK-09

**Success Criteria** (what must be TRUE when this phase completes):
  1. Running `./install.sh` on a v1.x install — including one with customized rule/agent/skill files — prompts per-file with diff/skip/replace and never silently overwrites; a `.claude-pipeline/stories.json` triggers a visible migration warning with an archive option.
  2. Hooks producing output with branch names, commit messages, or paths containing `"`, `\`, or newlines emit valid JSON verified by `jq .` on hook stdout; no string concatenation into JSON remains.
  3. `plugin.json`, `install.sh`, and `commands/godmode.md` all report the same version string; the installer reads it via `jq` from `plugin.json`.
  4. A GitHub Actions workflow runs `shellcheck` on every `*.sh` on macOS and Linux on every PR, and the CI job is green on the `main` branch.
  5. Backup rotation keeps at most 5 backups in `~/.claude/backups/`; `uninstall.sh` detects installed version mismatch and warns rather than silently operating.

**Risks from PITFALLS.md**:
  - PITFALL #1 (Distribution-mode divergence): hook bindings must be generated from one source at install time — adding without fixing parity repeats the pattern.
  - PITFALL #6 (v1.x migration data loss): installer must never delete `.claude-pipeline/` automatically; detection of `stories.json` must produce a prominent warning.
  - PITFALL #7 (Hardcoded skill/agent list drift): `post-compact.sh` list must be switched to filesystem scan before any new agents are added.
  - PITFALL #8 (Multi-plugin namespace collision): agent naming convention (`gm-` prefix decision) must be locked before Phase 2 creates new agents.
  - PITFALL #9 (SessionStart blocking startup): `async: true` + `timeout: 10` must be in both plugin-mode and manual-mode hook bindings.

**Plans**: TBD

---

### Phase 2: Agent Layer Modernization + Rules Hardening

**Goal**: All agents are production-ready with correct model/effort assignments, isolation, memory, and forward/back arrows; two new internal agents (`@planner`, `@verifier`) and a two-stage review split exist; rules are cache-safe and updated for current primitives; new `PreToolUse`/`PostToolUse` hooks mechanically enforce quality gates.

**Depends on**: Phase 1 (hook safety layer must be sound before new hooks are added; naming convention decided)

**Requirements**: AGENT-01, AGENT-02, AGENT-03, AGENT-04, AGENT-05, AGENT-06, AGENT-07, AGENT-08, AGENT-09, AGENT-10, AGENT-11, HOOK-01, HOOK-02, HOOK-03, HOOK-04, HOOK-05, HOOK-10, QUAL-11

**Success Criteria** (what must be TRUE when this phase completes):
  1. Running `/godmode` lists only agents that exist on the filesystem (no hardcoded list); any agent file added to `agents/` appears automatically on next `/godmode` invocation without editing any other file.
  2. A `PreToolUse` hook blocks `git commit --no-verify` and refuses inputs matching hardcoded secret patterns (API keys, JWTs) with a clear error; `exit 2` is confirmed to block in Auto Mode.
  3. The frontmatter linter (`scripts/lint-frontmatter.sh`) exits non-zero when any agent file is missing a required field (`model`, `effort`, `maxTurns`, `Connects to:`); CI runs it on every PR.
  4. Two new agents (`@planner` and `@verifier`) exist as named files in `agents/`; their descriptions mark them "Internal — invoke via /plan-phase or /execute-phase, not directly."
  5. All rule files contain only static content — no dates, branch names, or context percentages — verified by two consecutive `PostCompact` outputs being byte-identical for the same project.

**Risks from PITFALLS.md**:
  - PITFALL #2 (Prompt-cache invalidation): dynamic content must be removed from rule files and `additionalContext` before any new rule content is added.
  - PITFALL #4 (Opus 4.7 `xhigh` ignores rules): `@executor` and `@security-auditor` must be `effort: high`; locked in `rules/godmode-routing.md` not only in agent frontmatter.
  - PITFALL #12 (Internal agents leaking to user surface): naming convention (`Internal —` in description) must be applied to all new internal agents before Phase 3 skill layer references them.

**Plans**: TBD

---

### Phase 3: Skill Layer Rebuild (GSD-Aligned Workflow)

**Goal**: The user-facing skill surface is ≤ 12 commands and forms one obvious workflow: `/godmode` → `/discuss-phase` → `/plan-phase` → `/execute-phase` → `/ship`; v1.x skills aliased or retired; every skill declares forward/back arrows; Auto Mode awareness in every skill; wave-based parallel execution with file-polling fallback.

**Depends on**: Phase 2 (`@planner` and `@verifier` must exist before `/plan-phase` and `/execute-phase` can spawn them)

**Requirements**: SKILL-01, SKILL-02, SKILL-03, SKILL-04, SKILL-05, SKILL-06, SKILL-07, SKILL-08, SKILL-09, SKILL-10, SKILL-11, SKILL-12

**Success Criteria** (what must be TRUE when this phase completes):
  1. A new user installs the plugin, runs `/godmode`, and within 5 lines of output knows exactly what command to type next; the output is driven from the live filesystem, not a hardcoded list.
  2. Running `ls skills/ commands/` (or equivalent) shows ≤ 12 user-facing items; `/ship` refuses to create a PR when any phase verification criterion is `MISSING`.
  3. `/execute-phase` spawns agents in waves using `run_in_background`; if an agent output file is empty after its timeout, the orchestrator falls back to sequential re-run — verified by a two-agent parallel test with one intentionally slow agent.
  4. Every public skill file contains a `Connects to: <upstream> → <this> → <downstream>` line; `/godmode` renders this chain for every listed skill.
  5. Running `/godmode` in a project mid-flight on v1.x (`.claude-pipeline/` present, no `.planning/`) produces a one-time deprecation note pointing to the migration path.

**Risks from PITFALLS.md**:
  - PITFALL #3 (TaskOutput race conditions): `run_in_background` + file-polling fallback is a Phase 3 deliverable, not a follow-up; parallel execution without it will freeze sessions.
  - PITFALL #5 (Auto Mode bypasses quality gates): `/ship` gate check must be a `PreToolUse` hook on `gh pr create` (mechanical, not instructional).
  - PITFALL #11 (Surface area bloat): command count audit (`≤ 12`) is a go/no-go gate for this phase; no new skills merge until the count is verified.
  - PITFALL #13 (Atomic-commit discipline): `/execute-phase` must commit after each task, not batch; `git log --oneline` after a two-task run must show two separate commits.

**Plans**: TBD
**UI hint**: no

---

### Phase 4: State Management and `.planning/` Scaffold

**Goal**: Consumer projects running claude-godmode get a complete `.planning/` artifact set on first setup — PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, config.json, and the phases/ directory layout — plus shared skill fragments (init-context, state-ops, commit-ops) that the Phase 3 skills call at runtime; STATE.md is injected into sessions and post-compact context.

**Depends on**: Phase 3 (the exact shape of STATE.md and init-context fragments emerges from Phase 3 skill execution; designing state before the skill shape is known produces premature abstraction)

**Requirements**: STATE-01, STATE-02, STATE-03, STATE-04, STATE-05, STATE-06, STATE-07, STATE-08

**Success Criteria** (what must be TRUE when this phase completes):
  1. A first-time user of a consumer project runs a setup flow (via `/godmode` or a setup skill) and gets `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, and `.planning/config.json` written to their project with no manual file copying.
  2. On session start in a project with `.planning/STATE.md`, the SessionStart hook injects `currentPhase` and `currentPlan` into `additionalContext`; the injected content is byte-identical across two consecutive startups (same project, same STATE.md — cache-stable).
  3. The `init-context` shell helper (`skills/_shared/init-context.md`) reads `.planning/config.json` with `jq` and returns a JSON blob usable by skill orchestrators — no Node.js dependency, pure Bash + jq.
  4. `.planning/config.json` passes JSON schema validation in CI; schema is documented in CONTRIBUTING.md.
  5. A consumer project's `.planning/` directory layout (phases/NN-name/{DISCUSS.md, PLAN.md, EXECUTE.md, VERIFICATION.md}) is standardized and documented; `/discuss-phase`, `/plan-phase`, `/execute-phase`, and `/verify-phase` each write to the correct subdirectory.

**Risks from PITFALLS.md**:
  - PITFALL #2 (cache invalidation): `post-compact.sh` must inject only volatile STATE.md delta — not full boilerplate — to keep `additionalContext` stable.
  - PITFALL #14 (PROJECT.md drift): every skill that completes a workflow gate must output requirement IDs and mark them in REQUIREMENTS.md; this discipline starts in Phase 4.

**Plans**: TBD

---

### Phase 5: CI Completion, Performance Polish, and Documentation Parity

**Goal**: All CI gaps are closed (frontmatter lint, full smoke test, JSON schema validation of all config files); statusline performance is polished; README, CHANGELOG, and `/godmode` agree exactly on the v2 public surface; CONTRIBUTING.md has hygiene recipes; all High-severity CONCERNS.md items have explicit traceability to the phases that resolved them.

**Depends on**: Phase 4 (full CI stack needs the complete artifact set; documentation cannot be finalized until the surface is stable)

**Requirements**: QUAL-01, QUAL-02, QUAL-03, QUAL-04, QUAL-05, QUAL-06, QUAL-07, QUAL-08, QUAL-09, QUAL-10

**Success Criteria** (what must be TRUE when this phase completes):
  1. The GitHub Actions matrix (macOS + Linux) runs: `shellcheck` on every `*.sh`, JSON schema validation on `plugin.json` / `hooks.json` / `config/settings.template.json` / `.planning/config.json`, frontmatter linter on `agents/*.md` / `skills/*/SKILL.md` / `commands/*.md`, and a bats-core smoke test of the install → `/godmode` → uninstall round trip — all green on `main`.
  2. Running `grep -r "model:" agents/*.md` shows only `opus`, `sonnet`, or `haiku` aliases — no pinned numeric IDs; `grep "Auto Mode" rules/*.md` returns at least one match per rule file that describes routing.
  3. README, CHANGELOG, and `/godmode` output all agree on: public skill list, agent list, version string, jq-only runtime claim, plugin/manual-mode parity claim, and deny-pattern caveat — verified by a manual audit checklist in the PR description.
  4. CONTRIBUTING.md includes: backup rotation policy (keep last 5), worktree prune recipe (`git worktree prune`), frontmatter field conventions, per-file diff/skip/replace guidance, and the command-count check (≤ 12) as a pre-release gate.
  5. A QUAL-09 traceability table in REQUIREMENTS.md maps every High-severity CONCERNS.md item to the phase that resolved it, with a status of Resolved.

**Risks from PITFALLS.md**:
  - PITFALL #10 (Statusline jq overhead): single `jq -r '[...] | @tsv'` call is the target; `strace` verify in CI or local fixture.
  - PITFALL #14 (PROJECT.md drift): all QUAL requirements must be marked Validated in PROJECT.md at phase-end; this phase is the final audit gate.

**Plans**: TBD

---

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation and Safety Hardening | 0/? | Not started | - |
| 2. Agent Layer Modernization + Rules Hardening | 0/? | Not started | - |
| 3. Skill Layer Rebuild (GSD-Aligned Workflow) | 0/? | Not started | - |
| 4. State Management and `.planning/` Scaffold | 0/? | Not started | - |
| 5. CI Completion, Performance Polish, and Documentation Parity | 0/? | Not started | - |

---

## Coverage Map

| Phase | Requirement IDs | Count |
|-------|-----------------|-------|
| 1 | FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06, FOUND-07, FOUND-08, FOUND-09, FOUND-10, HOOK-06, HOOK-07, HOOK-08, HOOK-09 | 14 |
| 2 | AGENT-01, AGENT-02, AGENT-03, AGENT-04, AGENT-05, AGENT-06, AGENT-07, AGENT-08, AGENT-09, AGENT-10, AGENT-11, HOOK-01, HOOK-02, HOOK-03, HOOK-04, HOOK-05, HOOK-10, QUAL-11 | 18 |
| 3 | SKILL-01, SKILL-02, SKILL-03, SKILL-04, SKILL-05, SKILL-06, SKILL-07, SKILL-08, SKILL-09, SKILL-10, SKILL-11, SKILL-12 | 12 |
| 4 | STATE-01, STATE-02, STATE-03, STATE-04, STATE-05, STATE-06, STATE-07, STATE-08 | 8 |
| 5 | QUAL-01, QUAL-02, QUAL-03, QUAL-04, QUAL-05, QUAL-06, QUAL-07, QUAL-08, QUAL-09, QUAL-10 | 10 |
| **Total** | | **62** |

**Unmapped requirements:** 0 ✓

### Phase Assignment Rationale

**HOOK-01..05, HOOK-10 → Phase 2 (not Phase 1):**
HOOK-01 (PreToolUse: block --no-verify), HOOK-02 (PreToolUse: secret scan), HOOK-03 (PostToolUse: gate failure detection), HOOK-04 (SessionStart reads STATE.md), HOOK-05 (PostCompact filesystem scan), and HOOK-10 (quality gates single source) are new hook behaviors that depend on either the agent layer (STATE.md is a Phase 4 artifact read in Phase 4, but the hook wiring belongs with the agent layer hardening) or the rule refactoring in Phase 2. HOOK-06..09 (JSON safety, stdin drain, cwd resolution, statusline jq collapse — wait, HOOK-09 is statusline performance which is Phase 5 territory).

**Correction — HOOK-09 → Phase 1:**
HOOK-09 is the statusline single-jq performance fix. Per PITFALLS.md pitfall-to-phase mapping, "Statusline jq overhead (Pitfall 10) → Phase 5." However HOOK-09 is listed with the hook hardening group (HOOK-06..10) in REQUIREMENTS.md. The SUMMARY.md Phase 1 description does not call out statusline specifically, but it's a hook-layer item. Statusline lives in `config/statusline.sh` — it's a performance fix. PITFALLS.md assigns it to Phase 5. Assigning HOOK-09 to Phase 1 groups it with its sibling hook requirements; Phase 5 QUAL items (QUAL-01..10) already cover the CI verification. HOOK-09 in Phase 1 is acceptable — the fix is simple and benefits from landing early.

**QUAL-11 → Phase 2:**
Prompt-cache-aware rule structure (QUAL-11) is structurally part of the rules hardening pass in Phase 2, where rule files are refactored to have static preambles. It is not a CI deliverable — it is a design constraint applied during agent/rules work.

**QUAL-09 → Phase 5:**
QUAL-09 requires an explicit traceability table in REQUIREMENTS.md confirming all High-severity CONCERNS.md items are resolved. This is a documentation verification step that can only be written after all resolving phases (1-4) are complete.

---

*Roadmap created: 2026-04-25*
*Last updated: 2026-04-25 (initial creation)*
