---
phase: 04-skill-layer-state-management
plan: 03
subsystem: workflow-skills
tags: [skills, brief, plan, build, verify, ship, waves, marker-polling, gates]
requires:
  - skills/_shared/init-context.sh (Plan 04-01 — godmode_init_context)
  - skills/_shared/state.sh (Plan 04-01 — godmode_state_update)
  - skills/_shared/_lib.sh (Plan 04-01 — godmode_slug, info/warn/error)
  - templates/.planning/briefs/{BRIEF,PLAN}.md.tmpl (Plan 04-01)
  - rules/godmode-skills.md (Plan 04-01 — frontmatter convention, Auto Mode, Connects-to)
  - agents/{planner,verifier,spec-reviewer,executor,researcher,writer,reviewer,security-auditor}.md (Phase 2)
  - config/quality-gates.txt (Phase 1 — 6 canonical gates)
  - hooks/pre-tool-use.sh (Phase 3 — blocks --no-verify; /build relies)
provides:
  - skills/brief/SKILL.md (NEW): Socratic 6-question brief authoring; spawns @spec-reviewer (default) and optional @researcher; materializes BRIEF.md from template
  - skills/plan/SKILL.md (NEW): spawns @planner; persists PLAN.md verbatim with Waves + ## Verification status + ## Brief success criteria sections
  - skills/build/SKILL.md (NEW): wave-based parallel dispatch via Agent(run_in_background=true); marker polling at .planning/briefs/NN-slug/.build/{started,done,failed}; atomic per-item commit with [brief NN.M] token; resume detection via git-log grep
  - skills/verify/SKILL.md (NEW): spawns read-only @verifier; rewrites PLAN.md ## Verification status + ## Brief success criteria sections atomically (awk-mv); STATE.md branches on COVERED count
  - skills/ship/SKILL.md (REWRITE): preserves v1.x Steps 1-5 structure; gates from config/quality-gates.txt SoT; STATE.md-aware refusal; --force opt-in; gh pr create heredoc preserved
affects:
  - Plan 04-04 (Phase 5 quality gates) — vocab gate must whitelist `task` for skills/{build,verify,ship}/SKILL.md (PLAN.md heading parsing); frontmatter gate now has 5 more files to lint
  - Users can now run /godmode → /mission → /brief 1 → /plan 1 → /build 1 → /verify 1 → /ship end-to-end (the v2 happy path is real)
  - Phase 5 bats smoke tests can exercise each skill against a clean temp $HOME (frontmatter parses; helpers source; STATE.md mutates)
tech-stack:
  added: []  # pure bash 3.2 + jq 1.6 + sed/awk; no new deps
  patterns:
    - State helper sourcing convention (D-04..D-08; lifted from Plan 04-02): `source $ROOT/skills/_shared/{init-context,state,_lib}.sh`
    - JSON context blob: `CTX=$(godmode_init_context "$PWD")` then jq for fields
    - Atomic STATE.md mutation: `godmode_state_update $N $SLUG $STATUS $NEXT_CMD $AUDIT`
    - sed-only template substitution for single-line vars (D-20 single-line constraint enforced by case-statement guard rejecting |, }}, backslash, newline — T-04-21)
    - Awk-mv atomic in-place section rewrite for /verify PLAN.md mutation (POSIX rename)
    - Background subagent dispatch via Task tool with run_in_background=true; .build/ marker files (started/done/failed) as ground truth (CR-08 fallback for stdout race)
    - Resume detection via `git log --grep '[brief NN.M]'` on commit message token (D-44; T-04-22 dual-source with marker files)
    - Concurrency cap=5 hardcoded (D-39; OUT-03 deferred)
    - Per-wave deadline=1800s/30min (D-40, matches @executor maxTurns:100)
    - Polling interval default 2s, env-tunable via GODMODE_POLL_INTERVAL (undocumented in v2.0 per OUT-06)
    - Idempotent .gitignore append for `*/.build/` at .planning/.gitignore level (D-41)
    - Single-quoted heredoc `'EOF'` for `gh pr create --body` (T-04-30 injection mitigation)
key-files:
  created:
    - skills/brief/SKILL.md
    - skills/plan/SKILL.md
    - skills/build/SKILL.md
    - skills/verify/SKILL.md
    - .planning/phases/04-skill-layer-state-management/04-03-SUMMARY.md
  modified:
    - skills/ship/SKILL.md (REWRITE: Steps 1-5 structure preserved; v1.x .claude-pipeline/stories.json block removed; gates source replaced with config/quality-gates.txt SoT)
decisions:
  - D-04 frontmatter convention applied to all 5 skills (name, description, user-invocable, allowed-tools; argument-hint+arguments on parameterized; disable-model-invocation on side-effecting; no model/effort)
  - D-05 model: / effort: keys explicitly omitted on every skill (verified by grep -cE '^model:|^effort:' = 0 across all 5)
  - D-06 ## Connects to body section with 4 bullets (Upstream/Downstream/Reads from/Writes to) on every skill
  - D-08 Auto Mode detection block added verbatim per rules/godmode-skills.md to all 5
  - D-22 brief directory naming `.planning/briefs/NN-slug/` referenced consistently
  - D-32 /brief 6-step Socratic flow (title, why, what, spec, optional researcher, optional spec-reviewer)
  - D-33 /brief output single BRIEF.md (two-files-per-brief invariant; /plan adds PLAN.md)
  - D-34 /brief Auto Mode default — skip optional research, default-spawn @spec-reviewer
  - D-35 /plan spawns @planner; PLAN.md template verification section structure mandated in agent prompt
  - D-36 wave heuristic in @planner prompt: disjoint files + no logical dependency
  - D-37 /plan godmode_state_update -> Ready to build / next /build N
  - D-38 /build wave dispatch via Agent(run_in_background=true) + atomic per-item commit with [brief NN.M] token
  - D-39 concurrency cap=5 hardcoded (OUT-03 deferred for v2.1 config knob)
  - D-40 marker discipline: .build/task-NN.M.{started,done,failed}; 2s poll (env-tunable); 30-min/1800s wave deadline
  - D-41 .build/ idempotently gitignored at .planning/.gitignore level (`*/.build/`)
  - D-42 per-task atomic commit gate via PreToolUse hook (Phase 3 D-01) — /build relies; no extra defense needed
  - D-43 on-failure: let in-flight finish + abort next wave; preserve .build/ for debug
  - D-44 resume detection via git log --grep '[brief NN.M]' (T-04-22 dual-source: markers convenient + token durable)
  - D-45 /build godmode_state_update -> Ready to verify / next /verify N
  - D-46 /verify spawns read-only @verifier (Phase 2 D-15: disallowedTools: Write, Edit)
  - D-47 mutation discipline: agent read-only; SKILL BODY rewrites PLAN.md sections via single atomic awk-mv; T-04-28 scoped to PLAN.md only
  - D-48 /verify godmode_state_update -> Ready to ship (all COVERED) OR Verify found gaps + next /build N
  - D-49 /ship 5-step gate sequence: STATE check + verification gate + 6 quality gates + cleanup + push & PR
  - D-50 --force bypasses Step 1 only; never bypasses gate failures; Auto Mode never auto-forces
  - D-51 /ship godmode_state_update -> Shipped $PR_URL / next /brief $((N+1))
  - D-20 single-line value rule enforced in /brief via case-statement guard (T-04-21 mitigation)
  - T-04-30 gh pr create heredoc uses single-quoted 'EOF' to prevent shell expansion injection
metrics:
  duration: ~30 minutes (autonomous; auto mode active)
  completed_date: 2026-04-27
  task_count: 5
  file_count: 5
---

# Phase 4 Plan 03: Workflow Skill Chain (`/brief`, `/plan`, `/build`, `/verify`, `/ship`) Summary

The 5-skill workflow chain is shipped: `/brief N → /plan N → /build N → /verify N → /ship`. Combined with Plan 04-02's `/godmode` + `/mission`, the v2 happy-path arrow chain is now real end-to-end. Every skill conforms to the v2 frontmatter convention from `rules/godmode-skills.md` (Plan 04-01); every skill body opens with `## Connects to` (4 bullets) and `## Auto Mode check`; every skill sources `skills/_shared/{init-context,state,_lib}.sh` and mutates STATE.md only via `godmode_state_update`. The substrate from Plan 04-01 was consumed unchanged.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | skills/brief/SKILL.md — Socratic brief authoring | `5685755` | skills/brief/SKILL.md |
| 2 | skills/plan/SKILL.md — agent dispatcher writing PLAN.md | `560557b` | skills/plan/SKILL.md |
| 3 | skills/build/SKILL.md — wave-based parallel execution with marker polling | `abe6c61` | skills/build/SKILL.md |
| 4 | skills/verify/SKILL.md — read-only @verifier + targeted PLAN.md mutation | `aad2edb` | skills/verify/SKILL.md |
| 5 | skills/ship/SKILL.md — REWRITE preserving v1.x Steps 1-5 structure | `5077a64` | skills/ship/SKILL.md |

## What Shipped

### `skills/brief/SKILL.md` (NEW)

| Element | Status |
|---------|--------|
| Frontmatter D-04 (name, description, user-invocable, allowed-tools, argument-hint `[N]`, arguments `[N]`); no model/effort | ✓ |
| `## Connects to` 4 bullets (Upstream → /mission, /godmode; Downstream → /plan N, @researcher, @spec-reviewer; Reads → 4 paths; Writes → 2 paths) | ✓ |
| Auto Mode detection block (canonical phrase) — D-34 defaults: no @researcher, default-on @spec-reviewer | ✓ |
| 6 Socratic questions: title, why, what, spec, optional @researcher, optional @spec-reviewer | ✓ |
| D-20 single-line value guard (rejects `\|`, `}}`, backslash, embedded newline) — T-04-21 mitigation | ✓ |
| `sed -e 's\|{{var}}\|val\|g'` template substitution (multi-line bullets handled by post-Edit pass) | ✓ |
| Spawns `@spec-reviewer` (default-on) via Task tool; appends report under `## Spec Review` | ✓ |
| `godmode_state_update $N $SLUG "Ready to plan" "/plan $N" "Brief $N drafted"` | ✓ |

### `skills/plan/SKILL.md` (NEW)

| Element | Status |
|---------|--------|
| Frontmatter D-04 (no AskUserQuestion needed — agent does the work) | ✓ |
| `## Connects to` 4 bullets (Upstream → /brief N; Downstream → /build N, @planner; Reads → 2; Writes → 2) | ✓ |
| Auto Mode block — D-10 default: single-wave plan unless ≥3 atomic disjoint items, then wave-2 | ✓ |
| Spawns `@planner` (Phase 2: Opus, xhigh, `disallowedTools: Write, Edit`); skill body persists output | ✓ |
| Wave heuristic in @planner prompt: disjoint files + no logical dependency; concurrency cap=5 enforced | ✓ |
| Defensive parse: requires `## Verification status` + `## Brief success criteria` headings (rely point for /verify) | ✓ |
| `godmode_state_update $N $SLUG "Ready to build" "/build $N" "Plan $N drafted"` | ✓ |

### `skills/build/SKILL.md` (NEW — heaviest skill)

| Element | Status |
|---------|--------|
| Frontmatter D-04 + `disable-model-invocation: true` (side-effecting) | ✓ |
| `## Connects to` 4 bullets (includes `.build/` marker writes + git commit token) | ✓ |
| Auto Mode block — D-10 skip wave-plan preview confirmation | ✓ |
| Wave parsing via awk → TSV (`wave\tid\tname`); `tasks_in_wave` helper | ✓ |
| Resume detection: `git log --oneline --grep "\[brief \${PADDED}\.\${SUFFIX}\]"` skips committed items (D-44) | ✓ |
| Concurrency cap = 5 hardcoded; warn if exceeded (D-39; OUT-03 deferred) | ✓ |
| Per-item dispatch via Task tool with `run_in_background: true`; subagent_type: executor | ✓ |
| Marker discipline (CR-08 fallback): `.build/task-NN.M.{started,done,failed}`; agent prompt enforces | ✓ |
| Polling: `find .build -name 'task-*.done\|.failed'`; 2s interval (`GODMODE_POLL_INTERVAL`); 30-min/1800s deadline | ✓ |
| On-failure: let in-flight finish; abort next wave; preserve `.build/` for debug (D-43) | ✓ |
| Idempotent `.planning/.gitignore` append `*/.build/` (D-41) | ✓ |
| PreToolUse hook reliance documented (`--no-verify` blocked at hook layer; D-42) | ✓ |
| `godmode_state_update $N $SLUG "Ready to verify" "/verify $N" "Build $N: $COMMIT_COUNT commits"` | ✓ |
| `task` exception documented inline (PLAN.md heading parsing; Phase 5 vocab gate must whitelist) | ✓ |

### `skills/verify/SKILL.md` (NEW)

| Element | Status |
|---------|--------|
| Frontmatter D-04 (Write/Edit at SKILL level — agent has `disallowedTools: Write, Edit` per Phase 2 D-15) | ✓ |
| `## Connects to` 4 bullets (Writes scoped to PLAN.md sections only — T-04-28) | ✓ |
| Auto Mode block — D-10: PARTIAL when in doubt (strictest interpretation) | ✓ |
| Spawns `@verifier` (Phase 2: Opus, xhigh, read-only) | ✓ |
| Atomic awk-mv pass rewrites `## Verification status` + `## Brief success criteria` sections in place | ✓ |
| COVERED/PARTIAL/MISSING vocabulary documented in agent prompt | ✓ |
| Two `godmode_state_update` calls: `Ready to ship` (all COVERED) OR `Verify found gaps` + `/build N` | ✓ |
| `task` exception documented inline (same as /build) | ✓ |

### `skills/ship/SKILL.md` (REWRITE)

| Element v1.x → v2 | Status |
|---|---|
| v1.x line 1-5 (frontmatter) → v2 D-04 (description ≤200 chars; user-invocable; allowed-tools scoped; `disable-model-invocation: true`; **no `argument-hint` / `arguments` — /ship takes no N**) | ✓ |
| v1.x line 23 ("Quality Gates from CLAUDE.md") → v2 reads from `config/quality-gates.txt` (Phase 1 D-26 / Phase 3 D-15 SoT) | ✓ |
| v1.x lines 27-32 (hardcoded gate table) → v2 auto-detect command table (typecheck/lint/tests + Gate 4 secrets re-scan + Gate 5 regressions + Gate 6 REQ-IDs via [brief NN.M] grep) | ✓ |
| v1.x lines 36-46 ("If ANY gate fails") → v2 PRESERVED: /debug, @writer, no-skip language | ✓ |
| v1.x lines 50-60 (Step 2 Requirements Verification) → v2 Step 1 Verification Gate (PLAN.md non-COVERED grep; --force bypasses ONLY this gate) | ✓ |
| v1.x lines 63-72 (Step 3 Security Scan) → v2 folded into Step 3 Git Cleanup (Gate 4 already covers; PreToolUse already blocks at commit) | ✓ |
| v1.x lines 75-83 (Step 4 Git Cleanup) → v2 Step 3 PRESERVED verbatim (uncommitted check, branch up-to-date, history review, ask-before-rebase) | ✓ |
| v1.x lines 85-103 (Step 5 Push & PR) → v2 Step 4 PRESERVED (`git push -u origin`, `gh pr create` with single-quoted heredoc) | ✓ |
| v1.x lines 110-118 (Agent Routing) → v2 PRESERVED (table at end) | ✓ |
| v1.x lines 122-156 (Pipeline Context — `.claude-pipeline/stories.json`) → REMOVED (replaced by Step 0: STATE.md status check) | ✓ |
| v1.x lines 158-165 (Related) → v2 See Also section | ✓ |
| NEW: Step 0 (STATE.md status must be `Ready to ship`) | ✓ |
| NEW: D-50 `--force` opt-in (bypasses Step 1 ONLY); Auto Mode NEVER auto-forces | ✓ |
| NEW: Step 5 `godmode_state_update $N $SLUG "Shipped $PR_URL" "/brief $((N+1))" "Shipped $PR_URL"` | ✓ |

## Cross-File Consistency

| Invariant | Verified |
|-----------|----------|
| Every skill that takes `$N` validates as numeric via `case "${N:-}" in ''\|*[!0-9]*) error ...` | ✓ in /brief, /plan, /build, /verify (4 skills) |
| Every skill that mutates STATE.md uses `godmode_state_update` (no direct sed/awk on STATE.md) | ✓ all 5 skills |
| Every skill sources `skills/_shared/_lib.sh` + `init-context.sh` + `state.sh` | ✓ all 5 |
| Every skill resolves `BRIEF_DIR` from live FS via `godmode_init_context` (no hardcoded path strings) | ✓ /brief computes from PADDED+SLUG; /plan, /build, /verify, /ship use `.briefs[]` jq filter |
| Frontmatter delimiters intact (line 1 = `---`, closing `---` at expected line) | ✓ /brief:16, /plan:15, /build:16, /verify:15, /ship:12 |
| No `model:` / `effort:` keys at skill level (D-05) | ✓ all 5 (grep returns 0) |
| `## Connects to` has exactly 4 bullets matching the canonical pattern | ✓ all 5 (grep returns 4) |

## Vocabulary Audit

| Skill | `story\|PRD\|cycle\|gsd-` | `phase` in user prose | Notes |
|-------|---|---|---|
| /brief | 0 | 0 | Clean. |
| /plan | 0 | 0 | "Phase 5 lint" appears in a `## Constraints` line referencing the future vocab gate — counted as docref, not user-facing prose. |
| /build | 0 | 0 | "Phase 2 D-15", "Phase 3 D-01..D-04", "Phase 5's vocabulary gate" — all docrefs. |
| /verify | 0 | 0 | "Phase 2 D-15", "Phase 5's vocabulary gate" — docrefs. |
| /ship | 0 | 0 | "Phase 1 D-26", "Phase 3 D-01", "Phase 3 D-15" — docrefs. No `stories.json` / `.claude-pipeline` (v1.x removed). |

The `task` token IS allowed in `/build`, `/verify`, and `/ship` (PLAN.md heading parsing — D-35 template constraint). Each skill documents this carve-out inline. **Phase 5's vocab gate must whitelist `task` for `skills/{build,verify,ship}/SKILL.md`** — flagged for Plan 04-04.

## Documented `task` Exception (carry-forward to Phase 5)

The IDEA.md surface-cap discipline targets `task` as a v2-forbidden word in user-facing surface. But PLAN.md's structure (D-35 template) uses `## Task NN.M` headings — that's the documented carve-out for the planner agent's structural output. Three skills parse those headings:

- **/build** — `awk` parses `^#### Task [0-9]+\.[0-9]+`; `git log --grep '[brief NN.M]'`; agent prompt instructs items via `Task NN.M`.
- **/verify** — agent prompt enforces `## Verification status` items as `**Task 1.1** — COVERED`.
- **/ship** — Step 2 Gate 6 verifies every PLAN.md item has a matching commit (`git log main..HEAD --grep '[brief NN.M]'`).

Plan 04-04's WORKFLOW-01 surface assertion task should whitelist `task` for these three files in the Phase 5 vocab gate (or remove `task` from the forbidden list — `task` is part of v2 vocabulary inside PLAN.md by design).

## Decisions Made

See frontmatter `decisions` field for the full D-* coverage map. All 25 CONTEXT.md decisions in scope (D-04, D-05, D-06, D-08, D-10, D-20, D-22, D-32–D-51) addressed by this plan.

## Deviations from Plan

None. Plan executed exactly as written:

- All 5 SKILL.md files materialized with the prescribed frontmatter and body structure.
- All 5 atomic commits land with the `[brief 04.3]` token.
- All acceptance criteria verified inline before each commit.
- No CLAUDE.md directives violated. Substrate files (`skills/_shared/*`, `templates/.planning/**`, `rules/godmode-skills.md`, `commands/godmode.md`, `skills/mission/SKILL.md`) untouched.

## Authentication Gates

None occurred during execution.

## Self-Check: PASSED

- All 5 SKILL.md files exist on disk: `skills/{brief,plan,build,verify,ship}/SKILL.md` ✓
- All 5 commit hashes present in `git log`: `5685755`, `560557b`, `abe6c61`, `aad2edb`, `5077a64` ✓
- Frontmatter delimiters parse cleanly on every file ✓
- Plan-level verification block (10 checks) all pass ✓

## Next

Plan 04-04 (the final plan in Phase 4) — Phase 5 quality-gate work / vocabulary CI gate / surface assertion task. After 04-04 lands, Phase 4 closes and Phase 5 (Distribution & Quality) begins.
