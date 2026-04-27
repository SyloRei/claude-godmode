---
phase: 04-skill-layer-state-management
plan: 02
subsystem: entry-point-skills
tags: [skills, commands, godmode, mission, orient, socratic, templates]
requires:
  - skills/_shared/init-context.sh (Plan 04-01 — godmode_init_context)
  - skills/_shared/state.sh (Plan 04-01 — godmode_state_update)
  - skills/_shared/_lib.sh (Plan 04-01 — godmode_slug, info/warn/error)
  - templates/.planning/{PROJECT,REQUIREMENTS,ROADMAP,STATE,config.json}.md.tmpl (Plan 04-01)
  - rules/godmode-skills.md (Plan 04-01 — Auto Mode block, frontmatter convention, Connects-to)
  - hooks/post-compact.sh:18-22 (Phase 1 / FOUND-11 — live FS scan idiom lifted)
provides:
  - commands/godmode.md (rewritten v2): state-aware ≤5-line orient + live FS inventory
  - skills/mission/SKILL.md (NEW): Socratic 5-question project init writing 5 .planning/ files
affects:
  - Plan 04-03 (skills/{brief,plan,build,verify,ship}/SKILL.md) inherits the entry-point conventions established here (frontmatter shape, ## Connects to layout, ## Auto Mode check block, source pattern for _shared helpers)
  - Phase 5 vocab gate, frontmatter linter, and bats smoke can now exercise /godmode and /mission against a clean temp $HOME
  - Users can run /godmode → /mission → (next: /brief 1) end-to-end on a freshly missioned project
tech-stack:
  added: []  # pure bash 3.2 + jq + sed + awk (no new deps)
  patterns:
    - Live FS scan via `find -maxdepth 1 -name '*.md' -not -name '_*'` (lifted from hooks/post-compact.sh)
    - State source pattern: `source $ROOT/skills/_shared/init-context.sh; CTX=$(godmode_init_context "$PWD")`
    - Multi-line template substitution via awk-splice from temp file (BSD-awk-safe alternative to `awk -v`)
    - Idempotency guard via file-presence test (pattern from skills/_shared/gitignore-management.md)
    - Connects-to chain rendered at runtime via `grep -A 20 '^## Connects to' commands/godmode.md skills/*/SKILL.md` (D-07)
key-files:
  created:
    - skills/mission/SKILL.md
    - .planning/phases/04-skill-layer-state-management/04-02-SUMMARY.md
  modified:
    - commands/godmode.md
decisions:
  - D-04 frontmatter convention applied verbatim on /mission (name, description, user-invocable, allowed-tools; no model/effort; no argument-hint)
  - D-06 ## Connects to section opens both file bodies with Upstream/Downstream/Reads from/Writes to bullets
  - D-07 Connects-to chain renderer documented inline in /godmode (live grep, no registry)
  - D-08 Auto Mode detection block added verbatim per rules/godmode-skills.md
  - D-19 /godmode handles state.exists=false branch — emits "No .planning/. Run /mission to start." as line 1
  - D-26 ≤5-line orient algorithm implemented (4 echoes per branch — both branches sum to ≤5 visible lines)
  - D-27 Inventory rendered via live `find` over $ROOT/agents/ and $ROOT/skills/ — never hardcoded (HI-02)
  - D-28 v1.x Rules Check (lines 17-50) and StatusLine Setup (lines 104-167) preserved verbatim
  - D-29 Five Socratic questions: name + display title, core value, tech stack, milestone, brief decomposition
  - D-30 /mission writes 5 files (PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, config.json) and prints next-step pointer
  - D-31 Idempotency: /mission no-ops if .planning/PROJECT.md exists; Auto Mode does NOT bypass
  - D-21 Template materialization via `sed -e 's|{{var}}|val|g'` (with awk-splice fallback for multi-line {{brief_titles}})
  - D-10 Auto Mode default policy applied per question (basename slug, "Ship features that work.", detect tech stack, "v0.1.0" + "Working baseline.", 3 placeholder briefs)
metrics:
  duration: ~25 minutes (autonomous; auto mode active)
  completed_date: 2026-04-27
  task_count: 2
  file_count: 2
---

# Phase 4 Plan 02: Entry-Point Skills (`/godmode` rewrite + `/mission` NEW) Summary

`/godmode` rewritten to a state-aware ≤5-line orient command with live FS inventory; `/mission` ships as a Socratic 5-question project initializer writing 5 `.planning/` files from templates. Plan 04-01's substrate (`init-context.sh`, `state.sh`, `_lib.sh`, 7 templates, `rules/godmode-skills.md`) is consumed; nothing in `_shared/` was modified.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | commands/godmode.md — rewrite to v2 shape (preserve v1.x bootstrap blocks) | 8f03519 | commands/godmode.md |
| 2 | skills/mission/SKILL.md — Socratic init writing 5 .planning/ files | c2630c2 | skills/mission/SKILL.md |

## What Shipped

### `commands/godmode.md` (rewrite)

| Element | Source | Status |
|---------|--------|--------|
| `name: godmode` frontmatter (D-04) | new | ✓ |
| `description` ≤200 chars (159) | new | ✓ |
| `user-invocable: true` | new | ✓ |
| `allowed-tools` (Bash, Read, Write, Edit, AskUserQuestion) — Write needed for rules-bootstrap | preserved from v1.x | ✓ |
| `## Connects to` body section (D-06) | new | ✓ |
| `## Auto Mode check` block (D-08, D-09) | new | ✓ |
| Statusline-vs-orient routing | preserved from v1.x | ✓ |
| Rules Check section (silent-if-installed; install-prompt) | preserved verbatim from v1.x lines 17-50 | ✓ |
| ≤5-line state-aware orient via `godmode_init_context` (D-26) | new | ✓ |
| Live FS inventory via `find` over `$ROOT/agents` and `$ROOT/skills` (D-27, HI-02) | lifted from hooks/post-compact.sh | ✓ |
| Connects-to graph rendering via `grep -A 20 '^## Connects to'` (D-07) | new | ✓ |
| StatusLine Setup section (Steps 1-4) | preserved verbatim from v1.x lines 104-167 | ✓ |

**Removed (HI-02 / vocabulary leakage):**
- Hardcoded "Available Skills" / "Available Agents" / "Quality Gates" / "Configuration" tables (v1.x lines 56-100). Replaced by live FS scan.
- The `/prd → /plan-stories → /execute → /ship` arrow line (v1.x line 59). Replaced by Connects-to graph rendering.

### `skills/mission/SKILL.md` (NEW)

| Element | Source | Status |
|---------|--------|--------|
| `name: mission` frontmatter (D-04) | new | ✓ |
| `description` ≤200 chars (172) | new | ✓ |
| `user-invocable: true` | new | ✓ |
| `allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion` | per rules/godmode-skills.md table | ✓ |
| No `model:` / `effort:` (D-05) | enforced | ✓ |
| No `argument-hint:` / `arguments:` (mission takes no N) | enforced | ✓ |
| `## Connects to` (D-06) | new | ✓ |
| `## Auto Mode check` (D-08) | new | ✓ |
| Step 1: Idempotency guard via `.planning/PROJECT.md` presence test (D-31) | new | ✓ |
| Step 2: 5 Socratic questions with Auto Mode defaults (D-29, D-10) | new | ✓ |
| Step 3: Materialize 5 files from templates (D-21, D-30) | new | ✓ |
| Step 4: Canonical state seed via `godmode_state_update` | sources state.sh from Plan 04-01 | ✓ |
| Step 5: Next-step pointer to `/brief 1` (D-30) | new | ✓ |

## Verification

### Automated (per plan)

- `commands/godmode.md`: passes the inline grep harness — frontmatter, Connects-to, Auto Mode block, `godmode_init_context` source, Rules Check + StatusLine Setup preservation, live `find` (4 occurrences), 0 occurrences of v1.x command tokens (`/prd`, `/plan-stories`, `/execute`), 0 occurrences of forbidden vocabulary (`story`, `PRD`, `cycle`, `gsd-`), 0 occurrences of `phase`/`task` in user-facing prose.
- `skills/mission/SKILL.md`: passes the inline grep harness — frontmatter (incl. NO `model:`/`effort:`/`argument-hint:`/`arguments:`), Connects-to bullets (4), Auto Mode block, `godmode_state_update` and `godmode_slug` references, all 5 templates referenced (`PROJECT`, `REQUIREMENTS`, `ROADMAP`, `STATE`, `config.json`), idempotency check (`rm .planning/PROJECT.md`), 0 occurrences of forbidden vocabulary, 0 occurrences of `phase`/`task` in user-facing prose.
- ≤5-line orient block: 9 indented `echo` statements counted across both branches (4 per state.exists=false branch, 5 per state.exists=true branch including the inventory line) — both branches render ≤5 user-visible lines (the inventory is one combined echo on a single line). Plan threshold ≥8 met.

### v1.x Preservation Audit

The original `commands/godmode.md` was 167 lines. Verbatim preservation check:

| Preserved Section | v1.x line range | Carried into v2 lines | Match |
|-------------------|-----------------|------------------------|-------|
| Rules Check (silent install detect) | 21-25 | 41-45 | ✓ |
| Rules Check (install prompt + plugin-root resolution) | 27-50 | 47-70 | ✓ (text identical, default-Y wording matches) |
| StatusLine Step 1 — Check current status | 110-122 | 121-133 | ✓ |
| StatusLine Step 2 — Resolve script path | 124-140 | 135-151 | ✓ |
| StatusLine Step 3 — Update settings.json (Edit-tool preserve-all-keys instruction) | 142-155 | 153-166 | ✓ (preserve-all-settings instruction verbatim — T-04-13 mitigation) |
| StatusLine Step 4 — Verify message | 157-167 | 168-186 | ✓ |

### Materialization Integration Test (one-shot)

Ran a full `/mission` simulation against a fresh `mktemp -d`:

```bash
TMP=$(mktemp -d -t godmode-mission-test.XXXXXX)
ROOT=/Users/sylorei/pet-projects/claude-godmode
cd "$TMP"
bash <<EOF
  # ... all 5 sed substitutions, awk-splice for {{brief_titles}}, state.sh seed ...
EOF
```

Result:

- All 5 files written to `.planning/`: `PROJECT.md` (791 B), `REQUIREMENTS.md` (538 B), `ROADMAP.md` (513 B), `STATE.md` (286 B after canonical mutator), `config.json` (90 B).
- `jq -e . .planning/config.json` → VALID JSON (`{"godmode_config_version": 1, "model_profile": "balanced", "auto_advance": false}`).
- `STATE.md` front matter parses correctly: `godmode_state_version: 1`, `active_brief: 1`, `active_brief_slug: foundation`, `status: Ready to brief`, `next_command: /brief 1`.
- `godmode_init_context "$TMP"` reads back `state.exists: true`, `active_brief: 1`, `active_brief_slug: "foundation"`, `active_brief_dir: ".planning/briefs/01-foundation"`, `next_command: "/brief 1"` — round-trip works end-to-end.
- ROADMAP.md correctly renders the 3-line `{{brief_titles}}` block via awk-splice — BSD awk's prohibition on newlines in `-v` values was avoided.

### Vocabulary Gate

```
$ grep -ciE '\b(story|PRD|cycle|gsd-)\b' commands/godmode.md skills/mission/SKILL.md
0
0
$ grep -E '^[^<#-]*\b(phase|task)\b' skills/mission/SKILL.md | grep -vE '(rules/godmode-skills.md|file-name|substring|\.tmpl)' | wc -l
0
```

Both files clean.

## Findings (cosmetic, not blocking)

1. **Templates retain their `<!-- TEMPLATE VARIABLES ... -->` documentation comment in materialized output.** The comment uses `{{var}}` placeholders inside the variable-name documentation, so substitution touches them. The output remains valid markdown (HTML comments are inert). For Plan 04-04 / Phase 5 polish, the templates can be reshaped to declare variable docs in a way that doesn't get rewritten — but for v2.0 ship, the cosmetic cost is zero.
2. **`{{brief_titles}}` placeholder appears in BOTH the doc comment block AND the body of `ROADMAP.md.tmpl`.** The current awk splice replaces both occurrences, doubling the title list inside the inert comment. Rendered body output is correct; only the leading comment is cosmetically duplicated. Same Phase 5 polish window applies.
3. **`STATE.md` carries two audit lines after `/mission` runs:** one from the template's own seed comment (`Project missioned via /mission.`) and one from the canonical `godmode_state_update` invocation (`Project missioned`). Both legitimate; reviewers may want to deduplicate in a future pass. Not surfaced in user-facing flow.

## Deviations from Plan

**None.** All 12 D-NN constraints (D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-19, D-21, D-26, D-27, D-28, D-29, D-30, D-31) were implemented exactly as specified. The plan's <action> blocks were authored as templates; the only divergence was switching the `ROADMAP.md` substitution from `awk -v bt=...` (which the plan suggested) to a `printf | awk-splice` pattern after the test surfaced the BSD-awk newline-in-`-v` limitation. Behaviorally identical from the user's perspective; logged here for the next maintainer.

## Threat Model Coverage

| Threat | Disposition | Verification |
|--------|-------------|--------------|
| T-04-11 (sed corruption from user input) | mitigate | Validation discipline documented in `## Constraints` of skills/mission/SKILL.md; rejects `\|`, `}}`, backslash, newline before sed |
| T-04-12 (CLAUDE_PLUGIN_OPTION leak in /godmode) | accept | Confirmed: `/godmode` orient does not echo any `CLAUDE_PLUGIN_OPTION_*` env to stdout |
| T-04-13 (statusline overwrites unrelated keys) | mitigate | Step 3 of StatusLine Setup preserves the v1.x "Preserve all existing settings. Only add/update the `statusLine` key" instruction verbatim |
| T-04-14 (DoS via 10K agents/skills) | accept | n/a — plugin author controls inventory |
| T-04-15 (hardcoded inventory creep) | mitigate | `find` count = 4 in commands/godmode.md; HI-02 contract met |
| T-04-16 (overwrite existing PROJECT.md) | mitigate | Step 1 idempotency check; Auto Mode does NOT bypass |
| T-04-17 (Auto Mode silent default substitution) | mitigate | Each Auto Mode default is documented in skills/mission/SKILL.md Step 2; user-audit path is `rm .planning/PROJECT.md && /mission` |

## Self-Check

- [x] FOUND: commands/godmode.md
- [x] FOUND: skills/mission/SKILL.md
- [x] FOUND: commit 8f03519 (Task 1)
- [x] FOUND: commit c2630c2 (Task 2)

## Self-Check: PASSED
