# Plan 02: Split reviewer into 5 lenses

**Updated:** 2026-05-25
**Brief:** .planning/briefs/02-split-reviewer-into-5-lenses/BRIEF.md

## Steps
Each step is mechanical, names the files it touches, and references the brief
acceptance criteria it advances by ID. Steps are partitioned so no two steps in
the same wave touch the same file (README is edited only by S2; agent files only
by S1).

### S1 — Create 3 lens agents; add finding-schema to all 5 lenses
- **dependsOn:** none
- **Files:** `agents/perf-reviewer.md` (new), `agents/convention-reviewer.md` (new), `agents/test-reviewer.md` (new), `agents/code-reviewer.md` (edit), `agents/security-auditor.md` (edit)
- **Criteria:** AC-2, AC-3, AC-4 (schema in lens prompts), AC-9
- **Change:** Use `agents/code-reviewer.md` as the structural template. Create the 3 new read-only lenses — frontmatter `model: sonnet`, `effort: high`, `memory: project`, `maxTurns: 30`, `disallowedTools: Write, Edit`; tools `Read, Grep, Glob` (test-reviewer also `Bash` for coverage-only). Each prompt declares its distinct scope (perf: complexity/allocations/n+1/hot paths; convention: naming/file structure/project conventions; test: coverage/test quality/missing cases) and instructs emitting findings in the shared schema `{lens, severity ∈ CRITICAL|WARNING|NIT, confidence ∈ HIGH|MEDIUM|LOW, file:line, note}`. Edit `code-reviewer.md` (scope = correctness/logic/edge cases) and `security-auditor.md` (scope = OWASP/secrets/authz) to instruct the same finding schema. Do NOT touch `reviewer.md` here (S2 deletes it). No resolver edit needed — `bin/godmode-model` reads frontmatter generically; new lenses are non-code-writers so quality→opus xhigh automatically.

### S2 — Retire generalist reviewer; repoint all @reviewer references
- **dependsOn:** none
- **Files:** delete `agents/reviewer.md`; edit `rules/godmode-routing.md`, `skills/refactor/SKILL.md`, `skills/tdd/SKILL.md`, `CONTRIBUTING.md`, `README.md`
- **Criteria:** AC-1, AC-8, AC-12 (README portion)
- **Change:** `git rm agents/reviewer.md`. Repoint every `@reviewer` / `claude-godmode:reviewer` reference: `rules/godmode-routing.md` routing tables + agent-type map (replace the `@reviewer` row with the 5 lens rows, and the `/refactor`/code-review rows to name the lenses or `/verify`); `skills/refactor/SKILL.md` and `skills/tdd/SKILL.md` VERIFY/REFACTOR rows → spawn the lenses (or "run `/verify`"); `CONTRIBUTING.md` agent list. In `README.md`: repoint `@reviewer` mentions (pipeline diagrams, agent table, examples) AND update the agent roster/count to 14 with the 5 lenses listed and the generalist removed (AC-12 README part). Leave `CHANGELOG.md` history untouched.

### S3 — Rewrite /verify to fan out 5 lenses + @verifier
- **dependsOn:** none
- **Files:** `skills/verify/SKILL.md`
- **Criteria:** AC-4 (schema documented in verify), AC-5, AC-6, AC-7
- **Change:** Add a parallel review phase: spawn `code-reviewer`, `security-auditor`, `perf-reviewer`, `convention-reviewer`, `test-reviewer` **+ `@verifier`** concurrently, each scoped to unit N's diff. Document the shared finding schema (AC-4). Define merge rules: dedup overlapping findings across lenses, drop LOW-confidence NITs, group by lens, order CRITICAL → WARNING → NIT. Output format = the existing AC-coverage table (COVERED/PARTIAL/MISSING) AND a new merged-findings section. Preserve goal-backward semantics and the read-only statement (only `bin/godmode-state` writes). Keep the unit-1 "Model profile" spawn note consistent (it already says resolve via `bin/godmode-model`).

### S4 — Update agent count in the manifest
- **dependsOn:** none
- **Files:** `.claude-plugin/plugin.json`
- **Criteria:** AC-12 (manifest portion)
- **Change:** Edit the `description` so it no longer says "12 specialized agents" (→ "14"). Keep JSON valid (lint-json gate).

### S5 — Update tests for the roster change
- **dependsOn:** S1
- **Files:** `tests/install.bats`, `tests/model-profile.bats`
- **Criteria:** AC-9, AC-10
- **Change:** In `install.bats`, reflect the roster: assert the 3 new agents install and remove any assertion expecting `reviewer.md` (if present). In `model-profile.bats`, add assertions for a new lens: `perf-reviewer balanced`→`sonnet high`, `perf-reviewer quality`→`opus xhigh`, `perf-reviewer budget`→`haiku default` (and optionally convention/test-reviewer). NOTE (stale-base): the worktree may lack S1's new agent files — copy them from the canonical checkout `/Users/sylorei/pet-projects/claude-godmode/agents/` for local test runs (untracked), committing only the `tests/` files.

### S6 — Run full quality-gate suite
- **dependsOn:** S1, S2, S3, S4, S5
- **Files:** (none — verification)
- **Criteria:** AC-11
- **Change:** Run `shellcheck` on any changed `.sh` (none expected), then `scripts/lint-json.sh`, `scripts/lint-frontmatter.sh`, `scripts/check-version-drift.sh`, `scripts/check-parity.sh`, `scripts/check-vocab.sh`, `scripts/check-surface-count.sh`, and `bats tests/`. Fix any failure before declaring done. Confirm `grep -rn "@reviewer\|claude-godmode:reviewer" agents/ skills/ rules/ README.md CONTRIBUTING.md` → 0.

## Waves (derived from dependsOn)
- **Wave 1:** S1, S2, S3, S4 (all dependsOn: none — file-disjoint, run in parallel)
- **Wave 2:** S5 (dependsOn: S1)
- **Wave 3:** S6 (dependsOn: S1, S2, S3, S4, S5)

## Verification plan
Every brief acceptance criterion, by ID, with how it is checked.

- **[AC-1]** — `test ! -e agents/reviewer.md` (gone); `grep -rn "@reviewer\|claude-godmode:reviewer" agents/ skills/ rules/ README.md CONTRIBUTING.md` → 0 matches.
- **[AC-2]** — `ls agents/perf-reviewer.md agents/convention-reviewer.md agents/test-reviewer.md` all exist; each frontmatter has `model: sonnet`, `effort: high`, `memory: project`, `maxTurns`, `disallowedTools: Write, Edit`, no Write/Edit in `tools`. `scripts/lint-frontmatter.sh` exits 0.
- **[AC-3]** — `grep -il` each lens's distinctive terms in its file: perf-reviewer (complexity/allocation/n+1/hot path), convention-reviewer (naming/structure/convention), test-reviewer (coverage/missing case), code-reviewer (correctness/edge case), security-auditor (OWASP/secret/authz).
- **[AC-4]** — `grep -n` for `severity` + `confidence` + `CRITICAL`/`HIGH` in `skills/verify/SKILL.md` and in each lens agent file → schema present in all.
- **[AC-5]** — `skills/verify/SKILL.md` names all 5 lenses + `@verifier` and the words "parallel"/"concurrently" + "diff"/"unit"; inspect.
- **[AC-6]** — `skills/verify/SKILL.md` contains merge rules (dedup, drop LOW-confidence NIT, group by lens, CRITICAL→WARNING→NIT) AND an output section showing both the AC table and merged findings; inspect.
- **[AC-7]** — `skills/verify/SKILL.md` still has the COVERED/PARTIAL/MISSING classification and a read-only statement (writes only `bin/godmode-state`); inspect/grep.
- **[AC-8]** — `grep -rn "@reviewer" rules/godmode-routing.md skills/refactor/SKILL.md skills/tdd/SKILL.md README.md CONTRIBUTING.md` → 0; the lens names or `/verify` appear in those locations instead.
- **[AC-9]** — `bin/godmode-model perf-reviewer balanced` → `sonnet high`; `... perf-reviewer quality` → `opus xhigh`; `... perf-reviewer budget` → `haiku default`; same spot-check for convention-reviewer, test-reviewer.
- **[AC-10]** — `bats tests/install.bats` and `bats tests/model-profile.bats` pass with roster assertions; `bats tests/` overall green.
- **[AC-11]** — each gate script exits 0: `lint-json.sh`, `lint-frontmatter.sh`, `check-version-drift.sh`, `check-parity.sh`, `check-vocab.sh`, `check-surface-count.sh`, `bats tests/`; shellcheck clean for any `.sh` change.
- **[AC-12]** — `grep -c "12 specialized agents" .claude-plugin/plugin.json` → 0; README agent roster table lists the 5 lenses, omits the generalist `@reviewer`, and reflects 14 agents.

## Assumptions
- `agents/code-reviewer.md` is the structural template for the new lenses (closest existing read-only reviewer contract).
- The lens merge is orchestrated by `/verify` in-context; no standalone script (deferred to unit 9).
- `security-auditor` keeps its name and frontmatter (already `opus`/`xhigh`); only its prompt gains the finding-schema instruction. NOTE its quality/budget resolution differs from the sonnet lenses (it's already opus xhigh), which is fine — AC-9 only pins the 3 new sonnet lenses.
- Repointing in README/CONTRIBUTING prose generalizes `/build`'s "@reviewer validates each step" to the lens model or `/verify`, rather than deleting the examples.
- No CI gate enumerates a fixed agent roster, so 12→14 agents needs no gate edit (confirmed: check-vocab/lint-frontmatter scan `agents/*.md` generically; surface-count counts skills+commands only).
