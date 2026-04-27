# 04-04 Surface Audit

**Brief:** 04 — Skill Layer & State Management
**Plan:** 04 — Helpers + Deprecation Banners + Surface Count
**Audit date:** 2026-04-27
**Authority:** WORKFLOW-01 SC #1 (ROADMAP.md § Phase 4 Success Criteria)
**Status:** **COVERED — surface count = 11**

This document is the authoritative trail for the WORKFLOW-01 surface-count assertion and the Phase 5 hand-off contract for the surface-count CI gate.

---

## 1. The 11 v2 user-facing surface

These are the 11 user-invocable skills shipped in v2.0. Each has v2 frontmatter (D-04), a `## Connects to` body section (D-06), an Auto Mode detection block (D-08), and scoped `allowed-tools` (no wildcards).

| # | File | Source plan | Role |
|---|------|-------------|------|
| 1 | `commands/godmode.md` | 04-02 | Orient ("what now?" in ≤5 lines) |
| 2 | `skills/mission/SKILL.md` | 04-02 | Initialize project planning artifacts |
| 3 | `skills/brief/SKILL.md` | 04-03 | Socratic brief authoring → BRIEF.md |
| 4 | `skills/plan/SKILL.md` | 04-03 | Tactical breakdown → PLAN.md (spawns @planner) |
| 5 | `skills/build/SKILL.md` | 04-03 | Wave-based parallel execution, atomic commits per task |
| 6 | `skills/verify/SKILL.md` | 04-03 | Goal-backward verification, COVERED/PARTIAL/MISSING |
| 7 | `skills/ship/SKILL.md` | 04-03 | Quality gates → push → gh pr create |
| 8 | `skills/debug/SKILL.md` | **04-04** | Cross-cutting helper: structured debug protocol |
| 9 | `skills/tdd/SKILL.md` | **04-04** | Cross-cutting helper: red→green→refactor |
| 10 | `skills/refactor/SKILL.md` | **04-04** | Cross-cutting helper: safe refactoring |
| 11 | `skills/explore-repo/SKILL.md` | **04-04** | Cross-cutting helper: read-only repo exploration |

---

## 2. The 3 deprecated v1.x skills (NOT in the count)

These remain on disk during v2.0 with a deprecation banner prepended above their preserved v1.x bodies (D-23). They resolve when the user types the slash command (`user-invocable: true` retained), but the banner is the user's first encounter and the v1.x body is preserved verbatim below the `--- v1.x body below ---` separator. Per D-25 they are removed in v2.x.

| File | Banner-renames-to | Source plan |
|------|--------------------|-------------|
| `skills/prd/SKILL.md` | `/brief N` | 04-04 |
| `skills/plan-stories/SKILL.md` | `/plan N` | 04-04 |
| `skills/execute/SKILL.md` | `/build N` | 04-04 |

These are NOT counted toward the 11-cap because:

- The frontmatter `description:` is rewritten to `[Deprecated v2.0] …` — they are no longer the canonical "v2 user-facing surface".
- Their behavior is REPLACED by the migration banner; the v1.x body is a fallback for users mid-migration on the v1.x layout (`.claude-pipeline/`).

---

## 3. The shared (non-invocable) directory (NOT in the count)

`skills/_shared/*` is excluded by the `find` filter via the `-name '_shared' -prune` clause. These files (`init-context.sh`, `state.sh`, `_lib.sh`, helper markdown) are sourced by other skills — not directly user-invocable.

---

## 4. Counting recipe (canonical, refined from ROADMAP SC #1)

The naive expression in ROADMAP.md SC #1 (`find commands skills -name '*.md' -type f | grep '^commands/godmode.md\|/SKILL.md$' | wc -l == 11`) over-counts: it would tally 11 (v2) + 3 (deprecated) = 14. The deprecated 3 must be excluded explicitly. Also, `_shared/` markdown helpers (e.g., `gitignore-management.md`) match `*.md` and would inflate the count if not pruned.

**Canonical recipe:**

```bash
find commands skills -mindepth 1 \
  \( -name '_shared' -o -name 'prd' -o -name 'plan-stories' -o -name 'execute' \) -prune \
  -o -type f \( -name 'godmode.md' -o -name 'SKILL.md' \) -print \
  | wc -l | tr -d ' '
```

**Equivalent shell-loop form** (more readable, same result):

```bash
count=$( {
  # Include commands/godmode.md if present
  find commands -maxdepth 1 -name 'godmode.md' -type f 2>/dev/null
  # Include skills/<name>/SKILL.md where the dir is not _shared and not in the deprecated list
  for d in skills/*/; do
    name=$(basename "$d")
    case "$name" in _*|prd|plan-stories|execute) continue ;; esac
    [ -f "$d/SKILL.md" ] && printf '%s\n' "$d/SKILL.md"
  done
} | wc -l | tr -d ' ')
echo "v2 user-facing surface count: $count"
```

**Live result (2026-04-27):**

```
$ find commands skills -mindepth 1 \( -name '_shared' -o -name 'prd' -o -name 'plan-stories' -o -name 'execute' \) -prune -o -type f \( -name 'godmode.md' -o -name 'SKILL.md' \) -print | sort
commands/godmode.md
skills/brief/SKILL.md
skills/build/SKILL.md
skills/debug/SKILL.md
skills/explore-repo/SKILL.md
skills/mission/SKILL.md
skills/plan/SKILL.md
skills/refactor/SKILL.md
skills/ship/SKILL.md
skills/tdd/SKILL.md
skills/verify/SKILL.md

count: 11
```

**Assertion:** `count == 11`. **PASSED.**

---

## 5. The `task` vocabulary exception (Phase 5 hand-off)

The Phase 4 vocabulary discipline forbids `phase`, `task`, `story`, `PRD`, `gsd-`, `cycle`, `milestone` in user-facing skill bodies. Plan 04-03 documented an exception: `task` is intentionally allowed in `skills/{build,verify,ship}/SKILL.md` because PLAN.md (the v2 tactical breakdown artifact, per CONTEXT D-35) uses "Task NN.M" headings, and these skills must reference that structure to drive execution and verification.

**Phase 5 (QUAL-04, vocabulary CI gate) MUST whitelist `task`** for these three files when grepping for forbidden vocabulary. Or, equivalently, remove `task` from the forbidden list and rely on the other forbidden tokens to catch v1.x leakage.

The exception does NOT apply to:

- The 4 helpers modernized in this plan (`/debug`, `/tdd`, `/refactor`, `/explore-repo`).
- The deprecation banners on `/prd`, `/plan-stories`, `/execute` (banner header, above the `--- v1.x body below ---` separator).
- `commands/godmode.md` and `skills/{mission,brief,plan}/SKILL.md`.

In those files, `task` MUST NOT appear in user-facing prose.

---

## 6. The deprecated-skill body exemption (Phase 5 hand-off)

The v1.x bodies of `skills/prd/SKILL.md`, `skills/plan-stories/SKILL.md`, `skills/execute/SKILL.md` (below the `--- v1.x body below ---` separator) contain v1.x vocabulary (`phase`, `story`, `PRD`, `cycle`, etc.) by construction — they are PRESERVED VERBATIM per D-23. Phase 5's vocabulary gate (QUAL-04) MUST exempt these three paths from the forbidden-vocabulary scan, OR scan only the banner header (above the separator) for vocabulary cleanliness.

The migration TABLE in each banner ALSO contains the v1.x command names (`/prd`, `/plan-stories`, `/execute`) by design — these are the names users may type. The vocabulary gate must allow these specific occurrences (e.g., by scanning only between the YAML frontmatter end and the first `## v2.0 Migration Note` header — but in practice the banner is the user's only encounter with v1.x command names, and that is intended).

**Recommended Phase 5 implementation:** path allow-list. The 3 deprecated skill paths are exempt from the vocab gate entirely. The vocab gate's authority is the v2 user-facing surface (the 11 files in §1 above).

---

## 7. Phase 5 hand-off contract (surface-count CI gate)

The Phase 5 surface-count CI gate (a step in `.github/workflows/ci.yml` and/or `scripts/lint-frontmatter.sh`) MUST:

1. Use the canonical `find` recipe from §4 (NOT the naive ROADMAP SC #1 expression).
2. Refuse a commit when the count is anything other than 11.
3. Apply the path allow-list from §6 when scanning for forbidden vocabulary.
4. Apply the `task` whitelist from §5 for `skills/{build,verify,ship}/SKILL.md`.

**Failure modes the gate must catch:**

- A 12th SKILL.md added under `skills/` that is not in the prune list (count = 12 — refuse with "Surface cap is 11; slot 12 is reserved per D-02; see `rules/godmode-skills.md`").
- A v1.x deprecated skill DELETED prematurely (count = 10 — refuse with "Deprecated v1.x skill expected on disk until v2.x; see D-25").
- A new skill directory with the literal name `prd`, `plan-stories`, or `execute` (would silently be excluded; the gate should warn).

**Failure modes the gate is NOT responsible for:**

- Manual edits to skill BODIES introducing `model:` / `effort:` keys in frontmatter (the frontmatter linter QUAL-01 owns this).
- Banner content drift across the 3 deprecated skills (the migration table integrity is a one-shot Phase 4 contract, not a CI gate).

---

## 8. Verification trail

```bash
# Live assertion (run from repo root):
test "$(find commands skills -mindepth 1 \
  \( -name '_shared' -o -name 'prd' -o -name 'plan-stories' -o -name 'execute' \) -prune \
  -o -type f \( -name 'godmode.md' -o -name 'SKILL.md' \) -print \
  | wc -l | tr -d ' ')" = "11" && echo "WORKFLOW-01 SC#1: COVERED"
```

Run on 2026-04-27, post-Plan 04-04 commit: **outputs `WORKFLOW-01 SC#1: COVERED`.**

---

## 9. Cross-references

- Locked surface decision: `IDEA.md` § "Plugin's user-facing slash commands (locked at 11, ≤12 cap, 1 reserved)".
- Reserved-slot doctrine: `rules/godmode-skills.md` § "Surface Cap" (D-02).
- Frontmatter convention: `rules/godmode-skills.md` § "Frontmatter Convention" (D-04, D-05).
- Connects-to convention: `rules/godmode-skills.md` § "`Connects to` Body Section" (D-06, D-07).
- Auto Mode block: `rules/godmode-skills.md` § "Auto Mode Detection" (D-08, D-09, D-10).
- Deprecation banner: CONTEXT D-23, D-24, D-25.
- Phase 5 quality requirements: ROADMAP § Phase 5 (QUAL-01..QUAL-07).
