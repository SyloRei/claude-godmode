---
phase: 04-skill-layer-state-management
plan: 04
subsystem: skill-layer
tags: [skills, helpers, deprecation, surface-count, vocabulary]
requires: [04-01, 04-02, 04-03]
provides:
  - 4 cross-cutting helpers modernized to v2 (D-04 frontmatter + D-06 Connects-to + D-08 Auto Mode block)
  - 3 v1.x deprecation banners with one-time marker mechanic (D-23, D-24)
  - rules/godmode-routing.md aligned to v2 chain (no v1.x leakage in user-facing prose)
  - WORKFLOW-01 surface-count audit document with refined find recipe (count = 11)
  - Phase 5 hand-off contract: vocab gate `task` whitelist + deprecated-skill path allow-list
affects:
  - skills/debug/SKILL.md
  - skills/tdd/SKILL.md
  - skills/refactor/SKILL.md
  - skills/explore-repo/SKILL.md
  - skills/prd/SKILL.md
  - skills/plan-stories/SKILL.md
  - skills/execute/SKILL.md
  - rules/godmode-routing.md
tech-stack:
  added: []
  patterns:
    - "v2 skill frontmatter convention (D-04): name, description, user-invocable, allowed-tools (no model/effort)"
    - "Connects-to body section (D-06) — Upstream/Downstream/Reads from/Writes to bullets"
    - "Auto Mode detection block per-skill (D-08, D-09) referencing rules/godmode-skills.md"
    - "Deprecation banner one-time mechanic (D-24): marker at \$HOME/.claude/.claude-godmode-v1-banner-shown (NOT CLAUDE_PLUGIN_DATA — user-scoped, persists across plugin reinstalls)"
    - "Surface-count `find` recipe with prune of `_shared`, `prd`, `plan-stories`, `execute` (refines naive ROADMAP SC#1 expression)"
key-files:
  created:
    - .planning/phases/04-skill-layer-state-management/04-04-SURFACE-AUDIT.md
  modified:
    - skills/debug/SKILL.md
    - skills/tdd/SKILL.md
    - skills/refactor/SKILL.md
    - skills/explore-repo/SKILL.md
    - skills/prd/SKILL.md
    - skills/plan-stories/SKILL.md
    - skills/execute/SKILL.md
    - rules/godmode-routing.md
decisions:
  - "Replace TDD vocabulary `cycle` with `iteration` in /tdd to clear forbidden-vocabulary list (CLAUDE.md). The Red-Green-Refactor cadence is preserved semantically; only the noun changed."
  - "Rename Phase 1..4 → Step 1..4 in /debug body (the `phase` token is forbidden in user-facing prose per CLAUDE.md vocab discipline; the underlying REPRODUCE/HYPOTHESIZE/ISOLATE/FIX protocol is unchanged)."
  - "Strip Pipeline Context sections + Saving Results / Archiving / .claude-pipeline references from all 4 helpers per D-53 (helpers preserved semantically; the v1.x pipeline-state machinery is dead weight under v2)."
  - "Deprecated-skill frontmatter trimmed to {name, description, user-invocable} only — drop v1.x model/effort/allowed-tools. Banner exits early; if user proceeds past the banner, tools are inherited from session defaults (the v1.x body still works on the v1.x layout, with session-default tools)."
  - "rules/godmode-routing.md updated minimally (8 lines changed) — replace v1.x chain in `When to Use What` table; add `See rules/godmode-skills.md` companion pointer; preserve Phase 2 Effort Tier Policy and subagent_type mapping tables verbatim."
metrics:
  duration: ~25 minutes
  completed: 2026-04-27
  tasks_completed: 7
  files_modified: 8
  commits: 7
---

# Phase 04 Plan 04: Helpers + Deprecation + Surface Audit Summary

Modernized the 4 cross-cutting helpers to v2 shape, prepended v1.x deprecation banners on the 3 renamed skills with a one-time marker-file mechanic, lightly aligned `rules/godmode-routing.md` to the v2 chain, and produced the canonical surface-count audit asserting WORKFLOW-01 SC #1 (count = 11).

After 04-04 ships, the v2 user-facing surface is complete and counted: `commands/godmode.md` plus 10 `skills/<name>/SKILL.md` files, ≤12 cap, 1 reserved.

---

## What Shipped

### Modernized helpers (4 files)

| File | Frontmatter delta | Body delta |
|------|---|---|
| `skills/debug/SKILL.md` | name, description rewritten, scoped allowed-tools (Read, Grep, Glob, Bash); no model/effort | + ## Connects to (4 bullets); + Auto Mode check; – Pipeline Context section; renamed Phase 1..4 → Step 1..4 |
| `skills/tdd/SKILL.md` | name, description rewritten, scoped allowed-tools (Read, Write, Edit, Bash, Task) | + ## Connects to; + Auto Mode check; – Pipeline Context; replaced "cycle" with "iteration" |
| `skills/refactor/SKILL.md` | name, description rewritten, scoped allowed-tools (Read, Write, Edit, Bash, Task) | + ## Connects to; + Auto Mode check; – Pipeline Context |
| `skills/explore-repo/SKILL.md` | name, description rewritten, scoped allowed-tools (Read, Grep, Glob, Bash) — read-only | + ## Connects to; + Auto Mode check; – Pipeline Context; – v1.x Saving Results/exploration-file persistence (was tied to .claude-pipeline) |

**Each helper now passes the canonical D-04/D-06/D-08 conformance checks.** Pipeline-context vestiges (`.claude-pipeline/stories.json`, exploration archiving) are gone — these were v1.x scaffolding that have no analog under the v2 brief-shaped workflow.

### Deprecation banners (3 files)

| File | Banner H1 | Frontmatter description |
|------|---|---|
| `skills/prd/SKILL.md` | `# ⚠ Deprecated — use /brief N instead` | `[Deprecated v2.0] Renamed to /brief N. See migration note below. …` |
| `skills/plan-stories/SKILL.md` | `# ⚠ Deprecated — use /plan N instead` | `[Deprecated v2.0] Renamed to /plan N. …` |
| `skills/execute/SKILL.md` | `# ⚠ Deprecated — use /build N instead` | `[Deprecated v2.0] Renamed to /build N. …` |

Each banner contains:
- The marker-file gate (`$HOME/.claude/.claude-godmode-v1-banner-shown`) — display once per install, idempotent re-display via `rm` (D-24).
- A migration TABLE listing all 3 mappings (cross-discovery: a user typing any deprecated command learns the renames for the others).
- The `--- v1.x body below ---` separator, below which the v1.x body is preserved verbatim.

`user-invocable: true` is retained so the slash command resolves; the banner is the user's first encounter. Per D-25 the banners are removed in v2.x.

### Routing alignment (1 file)

`rules/godmode-routing.md` — 8-line delta. Replaced the `Plan a feature → /prd → /plan-stories → /execute → /ship` line with the v2 chain `/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship`. Updated the `@executor (stories.json-aware, used by /execute)` row to `@executor (PLAN.md-aware, used by /build)`. Added a `See rules/godmode-skills.md` companion pointer near the top. Phase 2's Effort Tier Policy and subagent_type mapping tables are preserved verbatim.

### Surface audit (1 new doc)

`.planning/phases/04-skill-layer-state-management/04-04-SURFACE-AUDIT.md` — the WORKFLOW-01 SC #1 verification trail. Documents:

- The canonical 11 v2 user-facing skills with source plans.
- The 3 deprecated v1.x skills excluded from the count.
- The `skills/_shared/*` exclusion (helper sources, not user-invocable).
- The refined `find` recipe (the naive ROADMAP SC#1 expression over-counts by 3).
- The Phase 5 hand-off contract for the vocab gate (`task` whitelist for `skills/{build,verify,ship}/SKILL.md`; deprecated-skill path allow-list).
- The Phase 5 hand-off contract for the surface-count CI gate.

**Live count (2026-04-27): 11. WORKFLOW-01 SC#1 COVERED.**

---

## Tasks completed

| # | Task | Commit |
|---|------|--------|
| 1 | Modernize skills/debug/SKILL.md | `9639c9b` |
| 2 | Modernize skills/tdd/SKILL.md | `990cc6a` |
| 3 | Modernize skills/refactor/SKILL.md | `c6dc463` |
| 4 | Modernize skills/explore-repo/SKILL.md | `ade5b01` |
| 5 | Prepend deprecation banners on /prd /plan-stories /execute | `ecf1c8f` |
| 6 | Align rules/godmode-routing.md to v2 chain | `dde1e57` |
| 7 | Write surface-count audit document | `68d057e` |

All commits use the `[brief 04.4]` token per D-38 commit format convention.

---

## Plan-level verification

| Check | Outcome |
|---|---|
| 1. Helpers have Auto Mode + Connects-to | PASS (4/4) |
| 2. Deprecation banners + marker mechanic | PASS (3/3) |
| 3. Surface count == 11 | PASS (live recipe asserted) |
| 4. No vocabulary leakage (`story`/`PRD`/`cycle`/`gsd-`) in 11 v2 files | PASS (zero hits) |
| 5. Connects-to section in all 11 v2 files | PASS (11/11) |
| 6. Auto Mode block in all 11 v2 files | PASS (11/11) |
| 7. Surface audit doc with refined recipe + Phase 5 contract | PASS |

---

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 — Vocabulary discipline] Replaced "cycle" with "iteration" in `/tdd`**
- **Found during:** Task 2 verification
- **Issue:** The plan's verification grep `grep -ciE '\b(story|PRD|cycle|gsd-|stories\.json|.claude-pipeline)\b'` forbids `cycle`. The v1.x `/tdd` body uses "Red-Green-Refactor cycle" pervasively — a TDD-canonical phrase but a forbidden token under v2 vocabulary discipline.
- **Fix:** Replaced every occurrence of `cycle` (4 hits in headers, prose, and the progress-report template) with `iteration`. The Red-Green-Refactor cadence is preserved semantically.
- **Rationale:** D-53 says "preserve body content semantically" — the iteration model IS the semantic content; the noun `cycle` is incidental phrasing. Vocabulary discipline takes precedence.
- **Files modified:** `skills/tdd/SKILL.md`
- **Commit:** `990cc6a`

**2. [Rule 3 — Vocabulary discipline] Renamed "Phase 1..4" → "Step 1..4" in `/debug`**
- **Found during:** Task 1 authoring
- **Issue:** The v1.x `/debug` body uses `## Phase 1: REPRODUCE`, `## Phase 2: HYPOTHESIZE`, etc. The token `phase` is in CLAUDE.md's forbidden-vocabulary list for user-facing prose.
- **Fix:** Renamed all four `## Phase N:` headers to `## Step N:` and updated the routing table column header accordingly.
- **Files modified:** `skills/debug/SKILL.md`
- **Commit:** `9639c9b`

**3. [Rule 2 — Defensive coverage] Verbatim PLAN.md banner included an `argument-hint` example for parameterized skills, but `/prd`, `/plan-stories`, `/execute` are not parameterized — frontmatter trimmed to {name, description, user-invocable}**
- **Found during:** Task 5 authoring
- **Issue:** PLAN.md spec showed only the 3 minimal frontmatter keys per banner. Confirmed against D-04 — these deprecated skills don't take an `N` argument, so no `argument-hint`/`arguments`.
- **Fix:** Frontmatter is exactly `{name, description, user-invocable}` per the spec. v1.x `model:` / `effort:` / `allowed-tools:` keys stripped (the banner exits early; if a user proceeds past, session defaults apply).
- **Rationale:** Matches Task 5 explicit instruction in PLAN.md ("Strip any v1.x `model:` / `effort:` / `allowed-tools:` keys to keep the deprecated frontmatter minimal").
- **Files modified:** `skills/prd/SKILL.md`, `skills/plan-stories/SKILL.md`, `skills/execute/SKILL.md`
- **Commit:** `ecf1c8f`

### Architectural deviations

None.

### Authentication gates

None — all 7 tasks executed in a single session under Auto Mode. No external auth required.

---

## Phase 5 hand-off contract

This plan's surface audit is the contract for two Phase 5 CI gates. Phase 5's planner MUST consume `04-04-SURFACE-AUDIT.md` as a read-first canonical reference.

### Vocabulary gate (QUAL-04)

- **Whitelist `task`** in `skills/build/SKILL.md`, `skills/verify/SKILL.md`, `skills/ship/SKILL.md`. These three skills reference PLAN.md's "Task NN.M" structure (D-35) and cannot be vocabulary-clean for `task`.
- **Path allow-list:** Exempt `skills/prd/SKILL.md`, `skills/plan-stories/SKILL.md`, `skills/execute/SKILL.md` entirely. These contain v1.x vocabulary by construction (D-23 verbatim preservation).
- **Active scan target:** the 11 v2 surface files listed in §1 of the audit.

### Surface-count gate

- Use the canonical `find` recipe from §4 of the audit. The naive ROADMAP SC #1 expression would over-count by 3.
- Refuse commits where count != 11. A 12th file under `skills/` (not in the prune list) is a v2.x decision per D-02.

---

## Self-Check: PASSED

Files asserted present:
- `skills/debug/SKILL.md` — FOUND
- `skills/tdd/SKILL.md` — FOUND
- `skills/refactor/SKILL.md` — FOUND
- `skills/explore-repo/SKILL.md` — FOUND
- `skills/prd/SKILL.md` — FOUND (banner + v1.x body preserved)
- `skills/plan-stories/SKILL.md` — FOUND (banner + v1.x body preserved)
- `skills/execute/SKILL.md` — FOUND (banner + v1.x body preserved)
- `rules/godmode-routing.md` — FOUND (v2 chain references; +5 -3 lines)
- `.planning/phases/04-skill-layer-state-management/04-04-SURFACE-AUDIT.md` — FOUND

Commits asserted in `git log`:
- `9639c9b` — FOUND (debug)
- `990cc6a` — FOUND (tdd)
- `c6dc463` — FOUND (refactor)
- `ade5b01` — FOUND (explore-repo)
- `ecf1c8f` — FOUND (deprecation banners)
- `dde1e57` — FOUND (routing alignment)
- `68d057e` — FOUND (surface audit)

Plan-level verification (1-7) all PASS as recorded above.

WORKFLOW-01 SC #1 (`find … | wc -l == 11`): COVERED.
