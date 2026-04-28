---
phase: 05-quality-ci-tests-docs-parity
plan: 01
subsystem: ci-quality-gates
tags:
  - ci
  - shellcheck
  - parity
  - vocab
  - github-actions
requires:
  - .planning/phases/05-quality-ci-tests-docs-parity/05-CONTEXT.md (D-01..D-17)
  - .planning/phases/05-quality-ci-tests-docs-parity/05-PATTERNS.md
  - scripts/check-version-drift.sh (Phase 1 analog — preamble + DRIFT accumulator)
  - scripts/check-frontmatter.sh (Phase 2 analog — report_fail + per-file walk)
  - hooks/hooks.json (parity input #1)
  - config/settings.template.json (parity input #2)
  - .planning/phases/04-skill-layer-state-management/04-04-SURFACE-AUDIT.md § 4 (canonical surface-count find recipe)
provides:
  - .github/workflows/ci.yml (CI workflow — 6 jobs: 5 lint + bats matrix)
  - scripts/check-parity.sh (plugin/manual parity gate)
  - scripts/check-vocab.sh (vocabulary + surface-count gate)
affects:
  - QUAL-01 (CI workflow with independent gate signals)
  - QUAL-03 (plugin/manual parity)
  - QUAL-04 (vocabulary discipline)
tech-stack:
  added: []
  patterns:
    - "Bracket-prefix script messaging ([i]/[+]/[!]/[x]) — matches check-version-drift.sh"
    - "process substitution `<(printf '%s\\n' \"$VAR\")` for diff input — bash 3.2 portable"
    - "jq -S walk(...) gsub() for path-prefix normalization in JSON canonicalization"
    - "wc -l | tr -d ' ' BSD/GNU portable count idiom"
    - "Per-file allowlist via case-statement parallel-array (bash 3.2; no associative arrays)"
key-files:
  created:
    - .github/workflows/ci.yml (70 lines)
    - scripts/check-parity.sh (46 lines)
    - scripts/check-vocab.sh (140 lines)
  modified: []
decisions:
  - "Extended D-13 `task` allowlist from 3 SKILL files to all skills/*/SKILL.md (Rule-1 fix — every skill spawning subagents references the SDK `Task` tool by name; plan author's enumeration was incomplete)"
  - "Extended allowlist with `PRD` for skills/{prd,plan-stories,execute}/SKILL.md migration banners (the deprecation banner header above the v1.x separator legitimately cross-references `/prd` to teach the rename)"
  - "Routed surface-count failure through report_fail accumulator (matches plan AC `>=4 report_fail occurrences` and gives uniform output style)"
metrics:
  completed_date: 2026-04-28
  duration_minutes: 25
---

# Phase 5 Plan 01: Quality — CI Workflow + Parity Gate + Vocab Gate Summary

CI workflow (6 jobs: 5 lint + bats matrix) and 2 NEW lint scripts (`check-parity.sh`, `check-vocab.sh`) shipped. Each lint job invokes a shipped script (D-03), preserving local-vs-CI parity. Plugin/manual parity gate normalizes `${CLAUDE_PLUGIN_ROOT}` <-> `~/.claude` via jq `walk(...)` then byte-diffs (D-09..D-11). Vocabulary gate enforces v2 discipline (D-12..D-15) and folds the canonical 11-skill surface-count recipe inline (D-16/D-17).

## Files Shipped

| Path | Lines | Role | Commit |
|------|-------|------|--------|
| `scripts/check-parity.sh` | 46 | Plugin/manual parity gate (read 2 JSON files, normalize, diff) | `6b856d6` |
| `scripts/check-vocab.sh` | 140 | Vocabulary + surface-count gate (walk surface tree, grep tokens, find-count) | `20c3102` |
| `.github/workflows/ci.yml` | 70 | CI workflow with 6 jobs invoking shipped scripts | `92b64cc` |

Total: 3 NEW files, 256 lines, 3 commits.

## Sample Successful Run Output

### `bash scripts/check-parity.sh`

```
[i] comparing /…/hooks/hooks.json .hooks <-> /…/config/settings.template.json .hooks
[i] normalizing ${CLAUDE_PLUGIN_ROOT} -> ~/.claude in plugin-mode JSON (D-10)
[+] hooks/hooks.json and config/settings.template.json[hooks] are equivalent
```
Exit code: `0`. Drift smoke (manual `timeout: 10` -> `11` edit + revert) produced unified diff and exit `1`.

### `bash scripts/check-vocab.sh` (post-Wave-1 expected output)

```
[i] surface count: 11 (canonical recipe)
[+] vocabulary clean (15 file(s) scanned, surface count = 11)
```
Exit code: `0`. Surface-miscount smoke (`mv skills/debug /tmp` + revert) produced `[!] surface-count: expected-11: got 10` and exit `1`.

### `.github/workflows/ci.yml`

YAML parses; 6 jobs in correct order (`shellcheck`, `frontmatter`, `version-drift`, `parity`, `vocab`, `bats`). Each lint job is exactly `actions/checkout@v4` + one `bash scripts/<name>.sh` step (D-03). bats job uses OS matrix `[ubuntu-latest, macos-latest]` with `fail-fast: false` (D-08); bats installed via OS-native package manager.

## Decision Points Encountered

### Per-file allowlist encoding location
The allowlist lives inline in `lint_file()` of `check-vocab.sh` as a bash 3.2 case statement (parallel-array idiom — no associative arrays). Two case blocks: `task` granted to all `skills/*/SKILL.md` (extended from D-13's 3-file enumeration), and `PRD` granted to the 3 v1.x deprecated skills. Externalization to `config/vocab-allowlist.txt` is deferred per D-14 (~10-entry threshold; we have 4).

### Surface-count find recipe location
Inline in `check-vocab.sh` (D-17 — "if inline check exceeds ~30 lines, externalize to scripts/check-surface.sh"). Our inline block is ~10 lines; staying inline. The recipe is verbatim from `04-04-SURFACE-AUDIT.md § 4`: prune `_shared, prd, plan-stories, execute` and count files matching `godmode.md` or `SKILL.md`.

### CI job order
Followed D-04 failure-likelihood gradient: `shellcheck -> frontmatter -> version-drift -> parity -> vocab -> bats`. Reads top-down like a developer's debug session.

### bats install per runner
`brew install bats-core` on macOS, `sudo apt-get install -y bats` on Ubuntu (D-08). NOT `npm install -g bats` (would violate the no-Node CI dep budget per CLAUDE.md).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `task` allowlist too narrow in plan D-13**
- **Found during:** Task 2 (vocabulary gate authoring + dry run)
- **Issue:** D-13 enumerated `task` allowlist for only `skills/{build,verify,ship}/SKILL.md`. Running the script revealed that EVERY SKILL.md that spawns subagents (brief, plan, build, verify, ship, refactor, tdd, mission, debug, explore-repo) references the Claude Code SDK `Task` tool by name in its `allowed-tools:` frontmatter and body prose ("Use the Task tool with these arguments:"). Word-boundary regex matches `Task` (capital T) under case-insensitive search, producing false positives in 7 SKILL files the plan author didn't enumerate.
- **Fix:** Broadened `task` allowlist to `skills/*/SKILL.md` (case statement glob). The original 3 files (build/verify/ship) additionally use `task` for "Task NN.M" PLAN.md heading parsing — that's still covered. The other 7 files only need it for the SDK tool reference, which is also covered. Other forbidden tokens (`phase`, `story`, `PRD`, `cycle`, `milestone`) still hard-fail across every skill.
- **Files modified:** `scripts/check-vocab.sh` (case statement broadened; D-13 enumeration preserved in inline comment for traceability).
- **Commit:** `20c3102`

**2. [Rule 1 - Bug] `PRD` allowlist missing for v1.x deprecation banners**
- **Found during:** Task 2 dry run.
- **Issue:** D-13 said "skills/prd/SKILL.md, skills/plan-stories/SKILL.md, skills/execute/SKILL.md: body below `--- v1.x body below ---` separator EXEMPT entirely" — but the migration banner ABOVE the separator is also subject to vocab. The banner contains a markdown table mapping `v1.x | v2.0 — | `/prd` | `/brief N` |` etc. — these are user-facing CROSS-REFERENCES needed to teach the rename. They legitimately mention `/prd`. Hard-failing them would force HTML-comment escape hatches on every banner row.
- **Fix:** Extended allowlist with `PRD` for the 3 deprecated SKILLs (in addition to `task`). The migration banner can mention `/prd` without escape comments. Deprecated skills are time-bounded (will be removed in v2.x), so this allowlist is also time-bounded.
- **Files modified:** `scripts/check-vocab.sh`.
- **Commit:** `20c3102`

**3. [Rule 1 - Bug] Acceptance grep `report_fail >= 4` — surface-count was inline `FAILED++`**
- **Found during:** Task 2 acceptance check.
- **Issue:** Initial implementation incremented `FAILED` directly for surface-count miscount, only calling `report_fail` from inside `lint_file()` (3 sites: token loop, gsd-* glob, definition). Plan AC required `>= 4 report_fail occurrences`.
- **Fix:** Routed surface-count failure through `report_fail` for uniformity. Output format is now consistent across all violation classes.
- **Files modified:** `scripts/check-vocab.sh`.
- **Commit:** `20c3102` (squashed in)

### Pre-existing State Surfaced (NOT auto-fixed — out of scope)

**`bash scripts/check-vocab.sh` exits 1 on the current pre-Wave-1 repo state.**

The plan's verification expected exit-0 on the current repo ("Phase 4 vocab discipline + 11-skill surface"). Actual current state has 36 violations:

| Class | Count | Owner |
|-------|-------|-------|
| `README.md` v1.x vocabulary (PRD/story/task/prd-references) | 17 | **Plan 05-03** (parallel Wave-1 — rewrites README to v2 shape) |
| Skill body `Phase N` references in user-facing prose (build, mission, plan, ship, tdd, verify) | 16 | Phase 4 cleanup ticket — out of scope for Plan 05-01 |
| `mission/SKILL.md` `milestone` references in user-facing prose | 2 | Phase 4 cleanup ticket — out of scope for Plan 05-01 |
| Other (`story:`, `task:` in body prose) | 1 | Phase 4 cleanup ticket — out of scope for Plan 05-01 |

Per `<scope_boundary>`: only auto-fix issues directly caused by THIS task's changes. The pre-existing v1.x leakage in README and Phase-N references in skill bodies are Phase 4 deliverables that escaped vocabulary discipline. The vocab gate **correctly catches them** — that's the gate doing its job. Cleanup belongs to:
- **README** → Plan 05-03 (Wave-1 parallel; same merge)
- **SKILL prose `Phase N` / `milestone`** → follow-up cleanup ticket (logged in `.planning/phases/05-quality-ci-tests-docs-parity/deferred-items.md` if not already)

The script is correct per spec and ships in this plan. Once 05-03 lands and the SKILL prose cleanup ticket lands, the gate will pass on `main`.

### Hand-off Note for Plan 05-02

The `bats` job in `.github/workflows/ci.yml` runs `bats tests/install.bats`. That fixture file is shipped by Plan 05-02 (Wave-1 parallel). The bats job will be RED in this worktree alone but GREEN once the merge of all Wave-1 plans lands on `main`. This is the same parallel-execution shape the plan documented for the bats matrix.

## Authentication Gates

None encountered. CI scripts are pure bash + jq + grep + find with no auth surface; GitHub Actions runs are gated by repository permissions (out of plan scope).

## Self-Check: PASSED

Files created (all FOUND):
- `scripts/check-parity.sh` (FOUND, executable, shellcheck clean)
- `scripts/check-vocab.sh` (FOUND, executable, shellcheck clean)
- `.github/workflows/ci.yml` (FOUND, YAML parses with `ruby -ryaml`)

Commits (all FOUND in `git log --oneline`):
- `6b856d6` feat(05-01): add scripts/check-parity.sh
- `20c3102` feat(05-01): add scripts/check-vocab.sh
- `92b64cc` feat(05-01): add .github/workflows/ci.yml

Smoke tests run (all PASS):
- `bash scripts/check-parity.sh` → exit 0 (current repo aligned)
- Parity drift smoke (timeout 10 -> 11 edit) → exit 1 with diff (REVERTED)
- `bash scripts/check-vocab.sh` → exit 1 (pre-existing v1.x leakage; documented as deviation, NOT auto-fixed per scope)
- Surface-miscount smoke (`mv skills/debug /tmp`) → exit 1 with `got 10` (REVERTED)
- `shellcheck scripts/check-parity.sh scripts/check-vocab.sh` → exit 0
