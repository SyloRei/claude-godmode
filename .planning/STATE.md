# State: claude-godmode v2 — polish mature version

**Last activity:** 2026-04-26 — roadmap re-created after re-init (5 briefs, 55 requirements mapped, 0 unmapped)
**Mission:** Replace v1.x's `/prd → /plan-stories → /execute → /ship` pipeline with the v2 chain (`/godmode → /mission → /brief → /plan → /build → /verify → /ship`); harden every High-severity item in `.planning/codebase/CONCERNS.md`.
**Core value:** A single, clear workflow where every agent, skill, and tool is connected and named for the user's intent — best-in-class capability behind the simplest possible surface.

---

## Current Position

| Field | Value |
|---|---|
| Active brief | **1 — Foundation & Safety Hardening** |
| Active plan | — (not yet drafted; run `/plan 1` after `/brief 1`) |
| Status | Not started |
| Next command | `/brief 1` |
| Progress | `[░░░░░░░░░░] 0/5 briefs complete` |

The five-brief arc:
1. ⏳ Foundation & Safety Hardening — **active**
2. ⏳ Agent Layer Modernization
3. ⏳ Hook Layer Expansion
4. ⏳ Skill Layer & State Management
5. ⏳ Quality — CI, Tests, Docs Parity

---

## Performance Metrics

| Metric | Value |
|---|---|
| Briefs complete | 0 / 5 |
| Plans complete | 0 / 0 (no plans drafted yet) |
| Commits in milestone | 5 (research + requirements + initial roadmap commits) |
| Requirements mapped | 55 / 55 (100%) |
| High-severity CONCERNS resolved | 0 / 9 |
| Quality gates passing | n/a (CI not yet in place — landing in Brief 5) |

---

## Accumulated Context

### Key Decisions (carried from PROJECT.md, do not relitigate without a decision log entry)

- Workflow vocabulary: **Project → Mission → Brief → Plan → Commit**. Five concepts; only Brief and Plan get dedicated artifact files.
- User-facing surface: **11 commands** (`/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`). 12th slot reserved.
- Two artifact files per active brief: `BRIEF.md` + `PLAN.md`. No `EXECUTE.md`. No per-task files. **`git log` IS the execution log.**
- Runtime: bash 3.2+ and `jq` only. No Node. No Python. No helper binary. Skills source `skills/_shared/init-context.sh`.
- Reference plugins (GSD, Superpowers, everything-claude-code) are inspiration only — read freely, copy nothing structural. Adopting their vocabulary, directory shapes, or command names is forbidden.
- Code-writing agents use `effort: high` (not `xhigh` — Opus 4.7's `xhigh` skips rules per PROJECT.md Key Decisions). Design / audit agents use `effort: xhigh`. Locked in `rules/godmode-routing.md`, not just frontmatter.
- `.claude-plugin/plugin.json:.version` is the single source of truth for plugin version. Every other file reads it via `jq` at runtime.
- Plugin-mode UX == manual-mode UX. CI parity gate enforces it (Brief 5).

### Open Questions (deferred to per-brief discussions)

| # | Question | Brief | Recommendation |
|---|---|---|---|
| 1 | Should `pre-tool-use.sh` block `git commit -n` (short form) in addition to `--no-verify`? | 3 | Lean yes; needs care to avoid colliding with legitimate flag combinations. |
| 2 | Does `@verifier` run in `background: true`, or foreground? | 2 | Foreground — read-only-but-thorough wants completeness over speed. |
| 3 | What is `/build`'s wave-concurrency cap — hardcoded 5, or a config knob in `.planning/config.json`? | 4 | Hardcoded 5 for v2; config knob deferred to v2.1. |
| 4 | Is `STATE.md` machine-mutated only, or user-editable? | 4 | Machine-mutates, user reads — but explicit `/brief 4` validation. |
| 5 | Does the v1.x detection note suppress itself after the first session, or print until `/mission` is run? | 4 | Print until `/mission` runs; suppress via STATE.md presence flag. |
| 6 | Secret-scanning false-positive tolerance level: warn vs. block? | 3 | Block with clear bypass instructions; bias toward false positives over silent leaks. |
| 7 | Should the bats smoke test run against both install modes (plugin + manual) or manual-only first? | 5 | Both — parity is a hard claim; the test is the proof. |

### Todos / Next Actions

1. Run `/brief 1` to open the Socratic discussion for Brief 1 (Foundation & Safety Hardening). Resolve Open Question #1 there.
2. After `/brief 1` produces `.planning/briefs/01-foundation-and-safety-hardening/BRIEF.md`, run `/plan 1` to decompose into atomic, parallelizable commits.
3. Run `/build 1`. Foundation work has natural parallelism (version SOT vs. hook hardening vs. installer prompts) — wave-based execution.
4. After `/verify 1` reports all-COVERED, advance to Brief 2.

### Blockers

None.

### Decisions Log

- **2026-04-26 (re-init):** Re-initialized v2 milestone planning under "references are inspiration only" principle. Discarded prior GSD-vocabulary planning state, regenerated PROJECT.md / REQUIREMENTS.md / research / ROADMAP.md / STATE.md from scratch. Codebase map (`.planning/codebase/`) and shipped v1.x surface preserved.
- **2026-04-26 (roadmap):** Adopted 5-brief structure with non-negotiable build order (Foundation → Agents → Hooks → Skills+State → Quality). Confirmed 55 requirements all map to exactly one brief; no orphans.
- **2026-04-26 (mapping nuance):** WORKFLOW-04 (live filesystem indexing) is mapped wholly to Brief 4 (the user-facing-surface brief), with Brief 1 supplying the substrate (live FS reads in `post-compact.sh` and `statusline.sh`). The seam is documented in ROADMAP.md "Notes".

---

## Session Continuity

**On `SessionStart`:** the v2 hook (landing in Brief 3) reads this file and injects:
> Active brief: 1 — Foundation & Safety Hardening. Status: not started. Next command: `/brief 1`.

**Before then:** the v1.x SessionStart hook is in place; the user manually orients via `/godmode` (which reads this file as soon as Brief 4's `/godmode` rewrite lands).

**To resume work after a session break:** run `/godmode` (post-Brief-4) or read this STATE.md directly. The brief list is the canonical TOC.

---

## File Layout (for orientation)

```
.planning/
├── PROJECT.md           ← mission, requirements summary, key decisions, constraints
├── REQUIREMENTS.md      ← 55 v1 requirements with traceability table
├── ROADMAP.md           ← this brief structure (5 briefs, dependency-driven)
├── STATE.md             ← this file
├── config.json          ← granularity, parallelization, model_profile
├── research/            ← STACK / FEATURES / ARCHITECTURE / PITFALLS / SUMMARY
├── codebase/            ← v1.x audit (preserved across re-init)
└── briefs/              ← per-brief artifacts (BRIEF.md + PLAN.md only)
    └── (populated by /brief and /plan as we go)
```

---

*Last updated: 2026-04-26 by roadmapper. State will be machine-updated by `/brief`, `/plan`, `/build`, `/verify`, `/ship` once those skills land in Brief 4. Until then, this file is human-maintained at brief transitions.*
