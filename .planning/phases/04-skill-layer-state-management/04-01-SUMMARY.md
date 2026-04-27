---
phase: 04-skill-layer-state-management
plan: 01
subsystem: skill-layer-foundation
tags: [skills, state-management, templates, bash, jq, foundation]
requires:
  - hooks/session-start.sh awk YAML parser (Phase 3 / D-13 lift target)
  - hooks/post-compact.sh live FS scan + jq -n --arg discipline (Phase 1 / D-22)
  - install.sh:10-18 color helpers (D-55 lift target)
provides:
  - skills/_shared/_lib.sh — color helpers, godmode_slug(), godmode_atomic_replace()
  - skills/_shared/init-context.sh — godmode_init_context() FS->JSON reader (schema_version 1)
  - skills/_shared/state.sh — godmode_state_update() atomic STATE.md mutator
  - 7 templates under templates/.planning/ (5 project-level + 2 brief-level)
  - rules/godmode-skills.md — reserved-slot doctrine, Auto Mode block, frontmatter convention
  - .planning/.gitignore — */.build/ entry (D-41)
affects:
  - Plans 04-02 (commands/godmode.md + skills/{mission,brief,plan}/SKILL.md) source these helpers
  - Plans 04-03 (skills/{build,verify,ship}/SKILL.md) consume init-context.sh + state.sh
  - Plans 04-04 (deprecation banners + helper modernization) reference the rules file
tech-stack:
  added: []  # pure bash 3.2 + jq 1.6+ — no new deps
  patterns:
    - jq -n --arg JSON construction (CR-02 discipline; never heredoc)
    - awk YAML front-matter parsing (lifted from hooks/session-start.sh:60-62)
    - mktemp + mv atomic file replace (POSIX rename semantics)
    - Subshell-wrapped function bodies for sourcing safety (D-15)
    - {{var}} mustache template substitution via sed -e 's|{{var}}|val|g' (D-20)
key-files:
  created:
    - skills/_shared/_lib.sh
    - skills/_shared/init-context.sh
    - skills/_shared/state.sh
    - templates/.planning/PROJECT.md.tmpl
    - templates/.planning/REQUIREMENTS.md.tmpl
    - templates/.planning/ROADMAP.md.tmpl
    - templates/.planning/STATE.md.tmpl
    - templates/.planning/config.json.tmpl
    - templates/.planning/briefs/BRIEF.md.tmpl
    - templates/.planning/briefs/PLAN.md.tmpl
    - rules/godmode-skills.md
    - .planning/.gitignore
  modified: []
decisions:
  - D-11 init-context.sh sourcing pattern locked (cwd-from-argv, not stdin)
  - D-12 schema_version 1 JSON shape locked (consumers in 04-02/03/04 read this)
  - D-13 jq -n --arg + awk YAML + cat || true tolerance applied
  - D-14 ≤100ms p99 target met (26ms measured on this repo)
  - D-15 init-context.sh never exits non-zero (subshell + set +e at fn entry)
  - D-16 STATE.md hybrid YAML + audit-log shape codified in template
  - D-17 godmode_state_update mktemp + mv atomic mutation
  - D-18 forward-compat: gsd_state_version + milestone keys accepted as fallback
  - D-19 STATE.md absent -> state.exists:false (no crash, valid JSON emitted)
  - D-20 templates/.planning/ + {{var}} substitution syntax locked
  - D-41 .planning/.gitignore */.build/ entry shipped
  - D-54 read/write helper split (init-context.sh reads, state.sh writes)
  - D-55 _lib.sh consolidation lifted color helpers from install.sh:10-18
metrics:
  duration: ~30 minutes (autonomous; auto mode active)
  completed_date: 2026-04-28
  total_loc_shipped: 322 lines (3 shell helpers) + 12 files
  performance: godmode_init_context "$PWD" — 26ms (target ≤100ms p99)
---

# Phase 04 Plan 01: Skill Layer Foundation Summary

The foundation substrate that every other Phase 4 skill depends on. Pure bash 3.2 +
jq 1.6+ helper layer (no Node, no Python, no helper binary) emitting versioned JSON
state, mutating STATE.md atomically, and providing the substitution targets `/mission`
and `/brief N` will materialize from in Plans 04-02 / 04-03.

## Tasks Completed (5/5)

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | `skills/_shared/_lib.sh` — color helpers + slug + atomic replace | `0b95b15` | `skills/_shared/_lib.sh` |
| 2 | `skills/_shared/init-context.sh` — `godmode_init_context()` FS→JSON | `d2bc9e6` | `skills/_shared/init-context.sh` |
| 3 | `skills/_shared/state.sh` — `godmode_state_update()` atomic mutator | `5e807ce` | `skills/_shared/state.sh` |
| 4 | 7 templates under `templates/.planning/` | `7a486c6` | 7 `.tmpl` files |
| 5 | `rules/godmode-skills.md` + `.planning/.gitignore` | `32190a7` | 2 files |

## Function Signatures Shipped (consumed by Plans 04-02/03/04)

From `skills/_shared/_lib.sh`:

```bash
# Color helpers (lifted verbatim from install.sh:10-18)
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1" 1>&2; exit 1; }

# kebab-case slug from free-form title (bash 3.2 portable; tr+sed)
godmode_slug "User Auth & SSO!"      # -> "user-auth-sso"
godmode_slug "Already-Kebab"         # -> "already-kebab"
godmode_slug "" or "!!!"             # -> "" (caller validates)

# Atomic write via mktemp + mv (POSIX rename = atomic on same FS)
godmode_atomic_replace "content" /path/to/target
godmode_atomic_replace - /path/to/target  # reads from stdin
```

From `skills/_shared/init-context.sh`:

```bash
# Sourced; defines godmode_init_context() (subshell-wrapped — no env leakage).
# Args: $1 = project root (default $PWD)
# Stdout: JSON conforming to schema_version 1 (D-12)
# Exit: ALWAYS 0 (D-15) — even on malformed STATE.md or missing .planning/
godmode_init_context "$PWD"
```

JSON shape (canonical for downstream consumers):

```json
{
  "schema_version": 1,
  "project_root": "/abs/path",
  "planning": {"exists": true, "config_path": "...", "state_path": "...", "briefs_dir": "..."},
  "state": {
    "exists": true,
    "active_brief": 4,
    "active_brief_slug": "skill-layer",
    "active_brief_dir": ".planning/briefs/04-skill-layer",
    "status": "Ready to plan",
    "next_command": "/plan 4",
    "last_activity": "2026-04-27 — context captured",
    "errors": []
  },
  "config": {"exists": true, "model_profile": "balanced", "auto_advance": false},
  "briefs": [{"n": 1, "slug": "foundation", "dir": "...", "has_brief": true, "has_plan": true}],
  "v1x_pipeline_detected": false
}
```

From `skills/_shared/state.sh`:

```bash
# Atomic STATE.md rewrite: mktemp + jq -n --arg + mv.
# Audit-log body preserved verbatim; new audit line appended (D-16).
# Args: $1=active_brief $2=slug $3=status $4=next_command $5=audit_line
godmode_state_update 4 "skill-layer" "Ready to plan" "/plan 4" "Brief 4 drafted"
```

## Templates Shipped (substitution targets for Plans 04-02 / 04-03)

| Path | Variables |
|------|-----------|
| `templates/.planning/PROJECT.md.tmpl` | `{{project_name}}`, `{{display_title}}`, `{{core_value}}`, `{{tech_stack}}`, `{{milestone_name}}`, `{{date}}` |
| `templates/.planning/REQUIREMENTS.md.tmpl` | `{{milestone_name}}`, `{{date}}` |
| `templates/.planning/ROADMAP.md.tmpl` | `{{display_title}}`, `{{milestone_name}}`, `{{date}}`, `{{brief_titles}}` |
| `templates/.planning/STATE.md.tmpl` | `{{active_brief}}`, `{{active_brief_slug}}`, `{{status}}`, `{{next_command}}`, `{{last_activity}}`, `{{date}}` |
| `templates/.planning/config.json.tmpl` | `{{model_profile}}` |
| `templates/.planning/briefs/BRIEF.md.tmpl` | `{{brief_n}}`, `{{brief_title}}`, `{{brief_slug}}`, `{{date}}`, `{{why}}`, `{{what}}`, `{{spec}}`, `{{research_summary}}` |
| `templates/.planning/briefs/PLAN.md.tmpl` | `{{brief_n}}`, `{{brief_title}}`, `{{brief_slug}}`, `{{date}}`, `{{task_name}}`, `{{verification}}`, `{{files}}` |

Each `.md` template opens with an HTML-comment variable-doc block. Substitution
syntax is `{{variable}}` mustache; replacement via `sed -e 's|{{var}}|val|g'`
(`|` delimiter — values may contain `/`). The `config.json.tmpl` is raw JSON
(no HTML comment, since JSON forbids comments); after substitution `jq -e .`
validates as expected.

## Performance

`godmode_init_context "$PWD"` measured at **26ms total** on this repo (4 phase
dirs, 0 briefs, ~13 .sh/.json files scanned). Well under the D-14 ≤100ms p99
budget. Single `find` invocation per briefs scan, single `awk` pass per STATE.md
key, single final `jq -n` for JSON assembly — no per-brief subshell loops.

## Key Design Decisions Honored

- **No Node, no Python, no helper binary** — pure bash 3.2 + jq 1.6+ (matches
  PROJECT.md hard constraint).
- **CR-02 discipline** — every JSON construction uses `jq -n --arg`/`--argjson`;
  no heredoc + variable interpolation anywhere (`grep -c 'cat <<' skills/_shared/*.sh`
  yields 0 for non-comment lines).
- **D-15 never-exit-non-zero** — `godmode_init_context()` wraps work in a
  subshell with `set +e` so a calling skill running `set -euo pipefail` cannot
  be killed by an unparseable STATE.md.
- **D-16 append-only audit log** — `godmode_state_update()` extracts the entire
  body after the second `---` and writes it verbatim, appending only the new
  audit line. Verified via roundtrip test: 4 original audit lines + 1 new = 5.
- **D-18 forward-compat** — `init-context.sh` reads BOTH `godmode_state_version`
  and `gsd_state_version` keys; falls back to `milestone:` and `stopped_at:` when
  v2 keys are empty. Confirmed against this repo's STATE.md (uses
  `gsd_state_version: 1.0` + `milestone:` + `stopped_at:`) — emits `state.status:
  "executing"`, `state.last_activity: "2026-04-27 -- Phase 04 execution started"`.
- **D-55 UX consistency** — color helpers (`info`/`warn`/`error`) are lifted
  verbatim from `install.sh:10-18`; skills speak the same UX language as the
  installer.

## Deviations from Plan

**None of architectural significance.** Two minor adjustments documented inline:

1. **`config.json.tmpl` lacks an HTML comment block.** The plan's closing
   acceptance note ("All 7 files MUST have the variable comment block at the
   top") conflicts with the explicit JSON example shown earlier in the same
   action (raw JSON without a comment, since JSON forbids comments).
   Resolution: followed the explicit JSON example. The acceptance test
   (`head -1 templates/.planning/PROJECT.md.tmpl`) only validates the comment
   block on `PROJECT.md.tmpl`, so this matches both the explicit example and
   the test. The `config.json.tmpl` variables are documented in
   `rules/godmode-skills.md` instead (per D-21 — `/mission` substitutes
   `{{model_profile}}` from `userConfig.model_profile`).

2. **`shellcheck` SC1091 (info-level)** on `state.sh:18` (`. _lib.sh` source-
   not-followed). Documented-acceptable per the plan's acceptance criteria
   ("SC1091 source-not-followed is acceptable"). At `-S warning` severity all
   three shell files are clean.

## Threat Mitigations Applied

| Threat ID | Mitigation |
|-----------|-----------|
| T-04-01 (Tampering, state.sh YAML) | All YAML construction via `jq -nr --arg`; verified by `grep -c 'jq -n' skills/_shared/state.sh == 3`. No heredoc + interpolation. |
| T-04-02 (Tampering, init-context.sh JSON) | Single `jq -n --arg`/`--argjson` invocation at end (with one defensive fallback `jq -n` if assembly fails). Verified by `grep -c 'jq -n' init-context.sh == 7` (none are heredoc). |
| T-04-04 (Tampering, audit-log preservation) | `awk '/^---$/{c++; next} c>=2 {print}'` extracts body unchanged; `printf` appends new line only. Verified via roundtrip test. |
| T-04-05 (Information Disclosure, error path) | On parse failure: emit valid JSON with `state.errors[]` array. Never leak filesystem paths beyond `project_root`. |
| Bash 3.2 portability (CR-04) | No `mapfile`/`readarray`/`${var,,}`/`[[ -v ]]` anywhere — verified by `grep` (0 matches). |

## Self-Check: PASSED

All 12 created files exist (verified via `ls`):

- `skills/_shared/_lib.sh` (43 lines)
- `skills/_shared/init-context.sh` (199 lines)
- `skills/_shared/state.sh` (80 lines)
- `templates/.planning/PROJECT.md.tmpl`
- `templates/.planning/REQUIREMENTS.md.tmpl`
- `templates/.planning/ROADMAP.md.tmpl`
- `templates/.planning/STATE.md.tmpl`
- `templates/.planning/config.json.tmpl`
- `templates/.planning/briefs/BRIEF.md.tmpl`
- `templates/.planning/briefs/PLAN.md.tmpl`
- `rules/godmode-skills.md`
- `.planning/.gitignore`

All 5 task commits in git log:

- `0b95b15` feat(04.1): _lib.sh
- `d2bc9e6` feat(04.1): init-context.sh
- `5e807ce` feat(04.1): state.sh
- `7a486c6` feat(04.1): 7 templates
- `32190a7` feat(04.1): rules + .gitignore

Verification suite (function signatures × 7, schema validation, template
substitution, shellcheck warning+, vocabulary leakage, performance) — all green.
