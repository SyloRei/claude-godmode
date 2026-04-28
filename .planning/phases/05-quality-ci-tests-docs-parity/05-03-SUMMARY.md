---
phase: 05-quality-ci-tests-docs-parity
plan: 03
subsystem: docs-marketplace
tags:
  - docs
  - changelog
  - readme
  - marketplace
  - release
  - quality
  - phase-5

requires:
  - .claude-plugin/plugin.json (existing — version SoT shipped Phase 1)
  - CHANGELOG.md (existing — Keep-a-Changelog preamble + Phase 1-4 bullets)
  - CONTRIBUTING.md (existing — v1.x dev manual, line 133 baseline)

provides:
  - README.md (v2 marketing front door, 115 lines, 9-section skeleton, vocab-clean)
  - CHANGELOG.md (dated v2.0.0 entry, Keep-a-Changelog 5-section taxonomy, v1.x compressed)
  - .claude-plugin/plugin.json (version 2.0.0, locked v2 description 157 chars, v2 keywords 8)
  - CONTRIBUTING.md (top README pointer + ### Tag protection H3 release-process note)

affects:
  - GitHub marketplace listing (description + keywords drive discovery)
  - GitHub Releases (CHANGELOG v2.0.0 entry auto-renders on tag push)
  - scripts/check-version-drift.sh (now reports clean across README/CHANGELOG/plugin.json)

tech-stack:
  added: []
  patterns:
    - "Keep-a-Changelog v1.1.0 (Added/Changed/Fixed/Removed/Security taxonomy)"
    - "Locked tagline + arrow chain (Unicode U+2192) — single source IDEA.md / D-19"
    - "jq pipeline for JSON mutation preserving non-named fields"
    - "Light-touch CONTRIBUTING insertion (no rewrite of v1.x dev manual)"

key-files:
  created: []
  modified:
    - README.md
    - CHANGELOG.md
    - .claude-plugin/plugin.json
    - CONTRIBUTING.md

decisions:
  - "CHANGELOG heading uses '## v2.0.0 — 2026-04-28' (no brackets) per D-23 + version-drift contract; matches `^## v[0-9]+\\.[0-9]+\\.[0-9]+` regex."
  - "README total 115 lines — well under 500-line cap; tutorial-first, no v1.x vocabulary."
  - "plugin.json description 157 chars (≤200 marketplace cap); arrow rendered with Unicode U+2192."
  - "userConfig.model_profile NOT added — was absent in pre-state (Phase 1 gap, OUT OF SCOPE per D-26)."
  - "v2.0.0 git tag deferred per D-27: cut from main AFTER Phase 5 PR merges and CI is green."

metrics:
  duration_minutes: ~18
  completed_at: "2026-04-28T19:34:37Z"
  files_modified: 4
  files_created: 0
  commits: 4
---

# Phase 5 Plan 3: Docs Polish + Marketplace Metadata Summary

**One-liner:** Polished the v2.0.0 release surface — rewrote README to the locked 9-section skeleton (424→115 lines, vocab-clean), authored a dated CHANGELOG v2.0.0 entry summarizing 5 milestone areas in Keep-a-Changelog format, bumped plugin.json to v2.0.0 with locked v2 description and keywords, and inserted a README pointer + tag-protection note into CONTRIBUTING.md.

## What Shipped

| File | Before (lines) | After (lines) | Role |
|------|----------------|---------------|------|
| README.md | 424 | 115 | v2 marketing front door (rewrite) |
| CHANGELOG.md | 230 | 81 | Dated v2.0.0 entry + compressed v1.x block |
| .claude-plugin/plugin.json | 26 | 22 | Marketplace metadata polish (jq mutation) |
| CONTRIBUTING.md | 133 | 144 | Light-touch insertions only |

**Total commits:** 4 (one per task — atomic per workflow gate).
**Verification:** `bash scripts/check-version-drift.sh` exits 0 across all 4 files.

## plugin.json — sample diff

| Key | Before | After |
|-----|--------|-------|
| `description` | "Production-grade engineering workflow for Claude Code: 8 specialized agents, 8 skills, rules-based configuration, quality gates, and a full feature pipeline. Language-agnostic." (185 chars) | "Senior engineering team, in a plugin. One arrow chain (/godmode → /mission → /brief → /plan → /build → /verify → /ship), 11 skills, mechanical quality gates." (157 chars) |
| `version` | `1.6.0` | `2.0.0` |
| `keywords` (12) | workflow, agents, skills, hooks, **pipeline**, **engineering**, quality-gates, **code-review**, **tdd**, **refactoring**, **prd**, claude-code | workflow, agents, skills, hooks, **planning**, quality-gates, **auto-mode**, claude-code (8) |
| `name` | claude-godmode | _(unchanged)_ |
| `author`, `homepage`, `repository`, `license` | preserved | preserved |
| `userConfig` | _(absent — Phase 1 gap)_ | _(still absent — see below)_ |

Bold tokens removed/added.

## Tag Step (Hand-off — D-27)

The v2.0.0 git tag is **NOT** cut by this plan. Per D-27, after the Phase 5 PR (the `repo-polish` branch) merges to `main` and CI is green, run:

```bash
git checkout main
git pull
git tag v2.0.0
git push --tags
```

GitHub Releases auto-renders the v2.0.0 entry from `CHANGELOG.md`. The marketplace re-indexes within hours. Verify post-tag:

```bash
test "$(jq -r '.version' .claude-plugin/plugin.json)" = "2.0.0"
git describe --tags  # → v2.0.0
```

## Phase 1 Gap Flagged

**`userConfig.model_profile` is NOT in `.claude-plugin/plugin.json`.**

The plan's D-26 says: "Polish must preserve `userConfig.model_profile` — the single user-tunable knob. Don't strip it; it's not metadata." However, inspection of the pre-state plugin.json shows `userConfig` was never added. This is a Phase 1 gap (Foundation milestone was supposed to ship this — see `.planning/research/STACK.md` "Plugin manifest" section: `userConfig` listed as "**NEW in v2.** Single key: `model_profile` (string, default `\"balanced\"`, options `quality|balanced|budget`)").

Per D-26 ("PRESERVE if present"), this plan is correct to leave it absent — adding new functionality is out of scope. README.md's Customization section still references `userConfig.model_profile` as the documented user knob, so when Phase 1 ships the field (or a v2.0.x hotfix adds it), the README copy already aligns.

**Recommendation:** Open a hotfix item to add the field to `.claude-plugin/plugin.json`:

```json
"userConfig": {
  "model_profile": {
    "type": "string",
    "default": "balanced",
    "options": ["quality", "balanced", "budget"],
    "description": "Quality vs cost tradeoff for agent model selection"
  }
}
```

This can land in v2.0.1 or as a final Phase 5 cleanup commit before the tag — does not require a re-spin of any Phase 5 plan.

## Decisions Made

1. **CHANGELOG heading style** — used `## v2.0.0 — 2026-04-28` (no brackets, em-dash separator, ISO date). The plan's D-23 example showed `## [v2.0.0] - 2026-04-DD` but `scripts/check-version-drift.sh` line 60 enforces regex `^## v[0-9]+\.[0-9]+\.[0-9]+` (no `[`). The interfaces block in 05-03-PLAN.md noted this conflict and resolved to no-bracket — followed exactly.
2. **README length** — 115 lines, well under the 500-line cap. The 9-section skeleton in D-19 was followed verbatim; prose is tight. Kept terminal-cast GIF deferred per D-20 (optional; defer if production cost > marginal install-rate gain).
3. **Description char count** — 157 chars rather than the plan's stated 197 chars. The locked verbatim string (D-25) is what landed; my count via `jq -r '.description | length'` confirms 157 (Unicode arrow is one character per `jq`'s string-length semantics, not 3 bytes). Well under the 200-char marketplace cap, so this is a non-issue — possibly the plan's "197 chars" was a byte-count from a draft editor.
4. **CONTRIBUTING — strictly light touch** — only the two D-29 insertions landed. Lines 5-46 (v1.x Contribution Paths still mentioning `@executor`, `@reviewer`, `/prd`, `stories.json`) were NOT updated. CONTRIBUTING is internal-docs (vocab gate exempts it per D-12); cleanup deferred to v2.x per CONTEXT § Out of scope, OUT-05.
5. **No README terminal-cast GIF** — deferred per D-20 (optional). README ships as text-only; v2.x can add an animated demo if the install-rate metric warrants it.

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written, with the documented D-23 conflict resolved as the plan itself prescribed.

### Out-of-scope items NOT touched (deliberate)

- CONTRIBUTING.md lines 5-46 (v1.x Contribution Paths referencing `@writer`, `@executor`, `@reviewer`, `/prd`, `stories.json`) — Phase 4-shaped, vocab gate exempts CONTRIBUTING. Deferred to v2.x per OUT-05.
- CONTRIBUTING.md line 57 "File Structure (v1.4)" stale heading — same scope reasoning. Not required by plan.
- New scripts (`check-parity.sh`, `check-vocab.sh`) — these are Plan 05-01's deliverables (parallel wave executor); this plan's vocab verification used the fallback inline grep checks documented in the plan's acceptance criteria.

## Verification Evidence

```text
$ bash scripts/check-version-drift.sh
[i] canonical version: 2.0.0
[+] no version drift
exit=0

$ wc -l README.md CHANGELOG.md CONTRIBUTING.md
     115 README.md
      81 CHANGELOG.md
     144 CONTRIBUTING.md

$ jq -r '.version, (.description | length), (.keywords | length), .license' .claude-plugin/plugin.json
2.0.0
157
8
MIT

$ grep -cE '^## ' README.md      # 9 H2 sections + 1 (License) = 10
10

$ grep -cE '^### (Added|Changed|Fixed|Removed|Security)' CHANGELOG.md
5

$ grep -cE '^#### (Foundation|Agents|Hooks|Skills|Quality)' CHANGELOG.md
5

$ grep -cE '\(FOUND-[0-9]+\)|\(AGENT-[0-9]+\)|\(HOOK-[0-9]+\)|\(WORKFLOW-[0-9]+\)|\(QUAL-[0-9]+\)' CHANGELOG.md
29

$ grep -cF 'For installation and usage, see [README.md](README.md)' CONTRIBUTING.md
1

$ grep -cE '^### Tag protection' CONTRIBUTING.md
1
```

## Commits

| # | Hash | Message |
|---|------|---------|
| 1 | `6fca0c4` | feat(05-03): rewrite README to v2 9-section skeleton (QUAL-05) |
| 2 | `63871ec` | feat(05-03): author CHANGELOG v2.0.0 dated entry; compress v1.x history (QUAL-06) |
| 3 | `16b1e83` | feat(05-03): plugin.json marketplace polish, version 2.0.0 (QUAL-06) |
| 4 | `6f505af` | docs(05-03): CONTRIBUTING pointer to README + tag-protection note (D-29) |

## Threat Flags

None. The 4 modified files reduce the surface that the threat register's T-05-12 (Spoofing — fake metadata) and T-05-13 (Tampering — README install URL) cover; no new attack surface introduced. No new network endpoints, auth paths, or schema changes at trust boundaries.

T-05-15 (userConfig stripped) — verified preserved-or-absent: `userConfig` was absent in pre-state, jq pipeline did not add it, jq pipeline did not strike anything else. `name`, `author`, `homepage`, `repository`, `license` all confirmed present post-write.

## Self-Check: PASSED

**Files claimed created/modified:**
- README.md — FOUND (115 lines)
- CHANGELOG.md — FOUND (81 lines)
- .claude-plugin/plugin.json — FOUND (valid JSON, version 2.0.0)
- CONTRIBUTING.md — FOUND (144 lines)

**Commits claimed:**
- `6fca0c4` — FOUND (`feat(05-03): rewrite README to v2 9-section skeleton (QUAL-05)`)
- `63871ec` — FOUND (`feat(05-03): author CHANGELOG v2.0.0 dated entry; compress v1.x history (QUAL-06)`)
- `16b1e83` — FOUND (`feat(05-03): plugin.json marketplace polish, version 2.0.0 (QUAL-06)`)
- `6f505af` — FOUND (`docs(05-03): CONTRIBUTING pointer to README + tag-protection note (D-29)`)

**Integration verifications:**
- `bash scripts/check-version-drift.sh` — exit 0 (verified)
- README has 10 H2 sections, 11 skill bullets, 0 forbidden vocab matches (verified)
- CHANGELOG has 5 Keep-a-Changelog sub-headings + 5 milestone-area H4s, 29 requirement-ID citations (verified)
- plugin.json valid, version 2.0.0, description 157 chars, keywords length 8, license MIT (verified)
- CONTRIBUTING has top pointer + ### Tag protection H3 (verified)

All success criteria from `<success_criteria>` block COVERED.
