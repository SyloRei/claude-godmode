# Brief 02: Split reviewer into 5 lenses

**Updated:** 2026-05-25
**Roadmap unit:** 2 — `/verify N` fans out code/security/perf/convention/test reviewers in parallel with confidence scoring

## Why
Today code review is a single generalist `@reviewer` ("the single source of truth for code review") plus a separate `@security-auditor`, while `/verify` does only goal-backward AC-coverage and spawns **no** review agents at all. One generalist pass is shallower and noisier than the dominant 2026 pattern (Anthropic's `code-review` plugin runs 5 parallel lens agents with confidence-based false-positive filtering). This unit replaces the generalist with **5 focused lenses run in parallel inside `/verify`**, each an expert in one dimension, merged with severity+confidence scoring so the user gets categorized, de-duplicated, low-noise findings alongside the existing AC verdict. Beneficiary: anyone running `/verify N` — they get real multi-perspective review, not a single best-effort sweep.

**Decisions locked (via /brief questions):** minimal-rename roster (no `security-auditor` rename, to avoid breaking the global routing rule and many references); lenses run **inside `/verify`** (no new surface); findings carry **severity + confidence** and are merged/filtered.

## What

### In scope
- **Retire** `agents/reviewer.md` (the generalist; its job is now the union of the lenses).
- **Add** three read-only lens agents: `agents/perf-reviewer.md`, `agents/convention-reviewer.md`, `agents/test-reviewer.md`.
- **Keep, as lenses:** `code-reviewer` (correctness/logic/edge cases) and `security-auditor` (security lens — name unchanged). `spec-reviewer` stays separate (spec/AC lens, not one of the 5 code lenses).
- A documented **shared finding schema** (lens, severity, confidence, `file:line`, note) used by every lens and by the `/verify` merge.
- Rewrite `skills/verify/SKILL.md`: fan out the 5 lenses **+ `@verifier`** in parallel, scoped to the unit's diff; merge findings (dedup, drop LOW-confidence NITs, group by lens, CRITICAL→WARNING→NIT); report BOTH the unchanged AC-coverage table AND the merged findings. Preserve read-only + goal-backward semantics.
- **Repoint** every `@reviewer` reference: `rules/godmode-routing.md`, `skills/refactor/SKILL.md`, `skills/tdd/SKILL.md`, `README.md`, `CONTRIBUTING.md`.
- Update agent count in `README.md` and the `plugin.json` description ("12 specialized agents" → 14).
- Update any test that enumerates agents (`tests/install.bats`); keep all gates green.

### Out of scope
- Renaming `security-auditor` → `security-reviewer` (rejected; kept to limit blast radius).
- A standalone deterministic merge/confidence **script** — the merge is orchestrated by `/verify` in-context (a `scripts/` helper is unit 9 / P2.4).
- Changing `spec-reviewer` behavior or `/verify`'s AC-coverage semantics (lenses are additive).
- Rewriting historical `CHANGELOG.md` entries that mention `@reviewer` (a new entry is added at `/ship`).
- `/build`'s own per-step review (unchanged); the lenses live in `/verify`.

## Spec — acceptance criteria
Each criterion is verifiable and carries a stable **`AC-N`** label.

- [ ] **AC-1:** `agents/reviewer.md` no longer exists, and no **live** reference to `@reviewer` or `subagent_type: claude-godmode:reviewer` remains in `agents/`, `skills/`, `rules/`, `README.md`, or `CONTRIBUTING.md` (`grep -rn "@reviewer\|claude-godmode:reviewer"` over those paths → 0 matches; `CHANGELOG.md` history excluded).
- [ ] **AC-2:** Three new files `agents/perf-reviewer.md`, `agents/convention-reviewer.md`, `agents/test-reviewer.md` exist, each with valid frontmatter: `model: sonnet`, `effort: high`, `memory: project`, `maxTurns` set, read-only tool scope (`tools:` excludes Write/Edit) with `disallowedTools: Write, Edit`. `scripts/lint-frontmatter.sh` exits 0.
- [ ] **AC-3:** Each lens declares a distinct scope in its prompt body, verifiable by grep of distinctive terms: perf-reviewer (complexity / allocations / n+1 / hot paths), convention-reviewer (naming / file structure / project conventions), test-reviewer (coverage / test quality / missing cases), code-reviewer (correctness / logic / edge cases), security-auditor (OWASP / secrets / authz).
- [ ] **AC-4:** A shared finding schema is documented in `skills/verify/SKILL.md` with fields lens, severity ∈ {CRITICAL, WARNING, NIT}, confidence ∈ {HIGH, MEDIUM, LOW}, `file:line`, note; each lens agent's prompt instructs it to emit findings in that schema.
- [ ] **AC-5:** `skills/verify/SKILL.md` instructs spawning the 5 lenses (`code-reviewer`, `security-auditor`, `perf-reviewer`, `convention-reviewer`, `test-reviewer`) **plus `@verifier`** in parallel for unit N, each scoped to the unit's diff/changes.
- [ ] **AC-6:** `skills/verify/SKILL.md` defines the merge rules — dedup overlapping findings across lenses, drop LOW-confidence NITs, group by lens, order CRITICAL → WARNING → NIT — and its output format includes BOTH the AC-coverage verdict table (COVERED/PARTIAL/MISSING) AND a merged-findings section.
- [ ] **AC-7:** `/verify` remains read-only and goal-backward: the skill still classifies every AC as COVERED/PARTIAL/MISSING and still states it performs no source writes (only `bin/godmode-state`). Verifiable by inspection.
- [ ] **AC-8:** All former `@reviewer` references are repointed to the lenses or `/verify`: `rules/godmode-routing.md` (routing tables + agent-type map), `skills/refactor/SKILL.md`, `skills/tdd/SKILL.md`, `README.md`, `CONTRIBUTING.md` each now name the lens agent(s) or `/verify` instead of `@reviewer`; no dangling pointer.
- [ ] **AC-9:** `bin/godmode-model` resolves each new lens: `... perf-reviewer balanced` → `sonnet high`; `... perf-reviewer quality` → `opus xhigh`; `... perf-reviewer budget` → `haiku default` (and same for convention-reviewer, test-reviewer).
- [ ] **AC-10:** `tests/install.bats` (and any other agent-enumerating test) reflects the roster change — install copies the 3 new agents and does not expect `reviewer.md`. `bats tests/` passes.
- [ ] **AC-11:** All CI gates pass: shellcheck, `lint-json.sh`, `lint-frontmatter.sh`, `check-version-drift.sh`, `check-parity.sh`, `check-vocab.sh`, `check-surface-count.sh` (≤12 — unaffected, counts skills/commands not agents), `bats tests/` — on Ubuntu + macOS.
- [ ] **AC-12:** Agent count is updated everywhere it is stated: `.claude-plugin/plugin.json` description no longer says "12 specialized agents", and `README.md`'s agent roster/count reflects 14 (`grep -c "12 specialized agents" .claude-plugin/plugin.json` → 0; README roster table lists the 5 lenses and omits the retired generalist).

## Assumptions
- `security-auditor` keeps its name and serves as the security lens; the naming asymmetry (four `*-reviewer` + one `*-auditor`) is accepted to avoid the rename blast radius.
- New lenses mirror `code-reviewer`'s contract: `sonnet` / `effort: high` / read-only. `test-reviewer` may include `Bash` for coverage-only commands; `perf-reviewer` and `convention-reviewer` are `Read, Grep, Glob`.
- The 5 lenses are non-code-writing, so under `quality` they resolve to `opus xhigh` (the resolver's default branch — no carve-out edit needed; verified by AC-9).
- The lens-merge is orchestrated by `/verify` in-context; no standalone script in this unit.
- `@verifier` continues to own AC-coverage; the lenses own code-quality findings. The two run in the same parallel fan-out but produce the two distinct output sections.
- README/CONTRIBUTING prose that describes "@reviewer validates each step" in `/build` examples will be repointed to the lens model or generalized (e.g., "review lenses") rather than deleted.
