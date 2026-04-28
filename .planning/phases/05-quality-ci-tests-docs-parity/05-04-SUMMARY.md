---
phase: 05-quality-ci-tests-docs-parity
plan: 04
subsystem: ci-vocab-gate
tags: [vocab, ci-gate, skill-prose, allowlist, closure, CR-01]
gap_ids: [CR-01]
requirements: [QUAL-01, QUAL-04]
dependency_graph:
  requires:
    - "scripts/check-vocab.sh (existing CI gate)"
    - "skills/{build,mission,plan,ship,tdd,verify}/SKILL.md (existing v2 skill bodies)"
  provides:
    - "vocab gate exits 0 on the corpus (was: 18 violations)"
    - "scoped milestone allowlist for skills/mission/SKILL.md only"
  affects:
    - ".github/workflows/ci.yml vocab job (now green on first push to main)"
tech-stack:
  added: []
  patterns:
    - "per-file scoped allowlist via case-statement (bash 3.2 compatible)"
    - "inline rationale comments on allowlist entries"
key-files:
  created: []
  modified:
    - "skills/build/SKILL.md (6 substitutions)"
    - "skills/plan/SKILL.md (1 substitution)"
    - "skills/ship/SKILL.md (2 substitutions)"
    - "skills/tdd/SKILL.md (1 substitution)"
    - "skills/verify/SKILL.md (4 substitutions)"
    - "skills/mission/SKILL.md (1 substitution)"
    - "scripts/check-vocab.sh (allowlist extension + 4-line rationale)"
decisions:
  - "Split-strategy: scrub `Phase N` cross-references from skill bodies (they leaked from internal context); allowlist `milestone` for mission/SKILL.md only (legitimate v2 chain word)"
  - "Allowlist scope kept tight — milestone allowed for skills/mission/SKILL.md ONLY, preserving discipline elsewhere"
metrics:
  duration_minutes: 6
  completed_date: 2026-04-28
  tasks_completed: 3
  files_modified: 7
  vocab_violations_before: 18
  vocab_violations_after: 0
---

# Phase 05 Plan 04: Close CR-01 — vocabulary gate exits 0 on the working tree

One-liner: scrubbed 15 dev-side `Phase N D-NN` cross-references from 6 shipped SKILL.md bodies and added a scoped `milestone` allowlist for `skills/mission/SKILL.md` so `bash scripts/check-vocab.sh` now exits 0 on the post-plan corpus, closing CR-01 and re-affirming QUAL-01 SC #1 / QUAL-04 SC #4.

## What Was Done

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Scrubbed 6 `Phase N` cross-references from `skills/build/SKILL.md` (lines 34, 115, 207, 212, 241, 246) | `2d5f1ea` | skills/build/SKILL.md |
| 2 | Scrubbed 9 `Phase N` cross-references from plan/ship/tdd/verify/mission skill bodies (8 sites + 1 contract-rename) | `7b306db` | skills/plan/SKILL.md, skills/ship/SKILL.md, skills/tdd/SKILL.md, skills/verify/SKILL.md, skills/mission/SKILL.md |
| 3 | Extended `scripts/check-vocab.sh` allowlist with `milestone` scoped to `skills/mission/SKILL.md` only, with inline rationale | `4b9673b` | scripts/check-vocab.sh |

## Per-file substitution counts

| File | Substitutions | Token(s) Removed | Result |
|------|---------------|------------------|--------|
| skills/build/SKILL.md | 6 | `Phase 3 D-01`, `Phase 2`, `Phase 3`, `Phase 2 D-15`, `Phase 3 D-01..D-04`, `Phase 5's vocabulary gate` | 0 violations |
| skills/plan/SKILL.md | 1 | `Phase 5 lint` | 0 violations |
| skills/ship/SKILL.md | 2 | `Phase 3 D-01`, `Phase 1 D-26 / Phase 3 D-15` | 0 violations |
| skills/tdd/SKILL.md | 1 | `phase` (in "GREEN phase") | 0 violations |
| skills/verify/SKILL.md | 4 | `Phase 2 D-15`, `Phase 2 contract change` (×2), `Phase 5's vocabulary gate` | 0 violations |
| skills/mission/SKILL.md | 1 | `Phase 5 CI` | 0 `phase` violations; 3 `milestone` mentions retained (allowlisted) |
| scripts/check-vocab.sh | +8 LOC (allowlist case + 4-line rationale comment) | n/a | gate exits 0 on whole corpus |

**Total:** 15 in-place neutralizations across 6 SKILL.md files + 1 allowlist extension. Zero net line-count change in skill bodies (each substitution was like-for-like).

## Allowlist diff

```diff
   case "$rel" in
     skills/prd/SKILL.md|skills/plan-stories/SKILL.md|skills/execute/SKILL.md)
       allowed="$allowed PRD" ;;
   esac
+  # `milestone` is a v2 user-facing chain word ONLY for /mission (PROJECT → Mission →
+  # Brief → Plan, per CLAUDE.md). Granting it scoped to mission/SKILL.md preserves the
+  # gate's discipline elsewhere (other skills must not use the word). Lines 77/80 of
+  # skills/mission/SKILL.md surface "Initial milestone" in the Socratic flow.
+  case "$rel" in
+    skills/mission/SKILL.md)
+      allowed="$allowed milestone" ;;
+  esac
```

## Final `check-vocab.sh` output

```
[i] surface count: 11 (canonical recipe)
[+] vocabulary clean (15 file(s) scanned, surface count = 11)
```

Exit code: `0`.

Rear-guard checks:

```
$ grep -rE '\bPhase [0-9]' skills/*/SKILL.md
(no output, exit 1)

$ grep -lE '\bmilestone\b' skills/*/SKILL.md
skills/mission/SKILL.md
(only mission, as intended)

$ shellcheck scripts/check-vocab.sh
(no output, exit 0)
```

## Decisions Made

1. **Split-strategy (scrub + scoped allowlist), not all-allowlist.** `Phase N` references are NOT user-facing concepts — the v2 product talks about briefs and milestones, never phases. Allowlisting `phase` would entrench dev-side leakage in the public skill bodies. Conversely, `milestone` IS a v2 user-facing concept (CLAUDE.md "PROJECT → Mission → Brief → Plan → Commit") used legitimately in `skills/mission/SKILL.md` lines 77 and 80. A scoped allowlist matches reality without weakening the gate.

2. **Allowlist scope tight to a single file.** The new case clause matches `skills/mission/SKILL.md` exactly — other skill bodies still hard-fail on the `milestone` token. Future widening requires explicit edit.

3. **Replacement principle: contract-name only.** Each substitution replaced the bare dev-side reference (`Phase N D-NN` or `Phase N`) with the contract-name it described (`PreToolUse hook`, `@executor frontmatter`, `worktree isolation`, `quality-gates.txt`, `agent-contract change`, `CI vocabulary gate`) so the user-facing skill body describes WHAT the user sees, not WHEN we built it.

## Deviations from Plan

None — plan executed exactly as written. All 3 tasks applied the substitutions specified verbatim, acceptance criteria met for each task, and the success criteria all green.

## Threat Model Disposition

| Threat ID | Status | Notes |
|-----------|--------|-------|
| T-05-04-01 (allowlist tampering) | mitigated | scope = single file + single token; inline rationale comment |
| T-05-04-02 (Phase N info disclosure) | accepted/scrubbed | removed text was internal-context leakage; 0 secrets |
| T-05-04-03 (CI vocab DoS) | mitigated | gate now exits 0 on the working tree |

## Self-Check: PASSED

Files claimed modified — all present in git log:
- skills/build/SKILL.md @ 2d5f1ea — FOUND
- skills/plan/SKILL.md @ 7b306db — FOUND
- skills/ship/SKILL.md @ 7b306db — FOUND
- skills/tdd/SKILL.md @ 7b306db — FOUND
- skills/verify/SKILL.md @ 7b306db — FOUND
- skills/mission/SKILL.md @ 7b306db — FOUND
- scripts/check-vocab.sh @ 4b9673b — FOUND

Commits exist on the worktree branch:
- 2d5f1ea — FOUND (Task 1)
- 7b306db — FOUND (Task 2)
- 4b9673b — FOUND (Task 3)

Final closure assertion: `bash scripts/check-vocab.sh; echo $?` → `0` (verified post-task-3).
