# Roadmap: claude-godmode v3

**Updated:** 2026-05-25

Numbered work units, grouped by phase, in priority order. Reference an entry with `/brief N`.
Full rationale and benchmarks for each unit live in `docs/v3-roadmap.md`.

## Phase 1 — v2.1 "Fix what's promised" (2 weeks)

| # | Work unit | Outcome | Status |
|---|-----------|---------|--------|
| 1 | P1.1 Wire model_profile | quality/balanced/budget switches model tier + effort at spawn time; `model-profile.bats` proves it | active |
| 2 | P1.2 Split reviewer into 5 lenses | `/verify N` fans out code/security/perf/convention/test reviewers in parallel with confidence scoring | pending |
| 3 | P1.3 Migrate rules to SessionStart | rules injected via `additionalContext`; `/godmode` rule-install dance retired; fresh install = zero steps | pending |
| 4 | P1.4 Bundle .mcp.json (opt-in) | `.mcp.json` references Context7, GitHub, Playwright; opt-in via userConfig; never auto-installed | pending |
| 5 | P1.5 Output style godmode-terse | `outputStyles/godmode-terse.md` (BLUF, severity-labeled, no preamble); referenced in plugin.json | pending |

## Phase 2 — v2.2 "Cover the gaps" (4 weeks)

| # | Work unit | Outcome | Status |
|---|-----------|---------|--------|
| 6 | P2.1 Add 4 agents | `@debugger`, `@perf-engineer`, `@incident-responder`, `@migration-engineer` (sonnet; opus via quality profile) | pending |
| 7 | P2.2 Add 3 spine skills | `/triage`, `/profile`, `/onboard` (folds in `/explore-repo`); stay within surface cap | pending |
| 8 | P2.3 Add 3 off-spine skills | `/adr`, `/changelog`, `/pr-describe` as plain commands | pending |
| 9 | P2.4 Bundle deterministic scripts | each spine skill gets `scripts/`; start with `verify/coverage-diff.py`, `ship/gates.sh` | pending |

## Phase 3 — v3.0 "Best-in-class distribution" (6–10 weeks)

| # | Work unit | Outcome | Status |
|---|-----------|---------|--------|
| 10 | P3.1 Publish to claude-community | submitted + accepted to the Anthropic-reviewed public marketplace | pending |
| 11 | P3.2 Generate AGENTS.md | cross-tool roster export (Codex/Cursor/OpenCode) with rule context injected | pending |
| 12 | P3.3 LSP server entries | `typescript-lsp` + `python-lsp` references under `lspServers` in plugin.json | pending |
| 13 | P3.4 Cost tracking | PostToolUse reads `tool_response.usage` → `.planning/COSTS.md`; surfaced in statusline | pending |
| 14 | P3.5 Skill scaffolder | `/godmode skill add <name>` scaffolds + registers a new skill directory | pending |
| 15 | Stop hook: AC-N coverage gate | Stop hook blocks main agent if a built unit's AC-N coverage < 100% unless overridden | pending |
| 16 | /release + @release-manager | one-session signed tag + version bump + CHANGELOG entry + GitHub Release | pending |

## Phase 4 — v3.x ongoing "Stay opinionated"

| # | Work unit | Outcome | Status |
|---|-----------|---------|--------|
| 17 | Per-language sub-plugins | `claude-godmode-python`/`-typescript` opt-in packs; core stays language-agnostic | pending |
| 18 | Agent Teams architect-team | optional `@architect-team` multi-perspective review behind the experimental flag | pending |
| 19 | Quarterly vocab-gate automation | automated check that no future-version commands leak into the reserved namespace | pending |
