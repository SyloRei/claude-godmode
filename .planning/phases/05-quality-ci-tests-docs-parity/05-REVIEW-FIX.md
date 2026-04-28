---
phase: 05-quality-ci-tests-docs-parity
fixed_at: 2026-04-29T00:00:00Z
review_path: .planning/phases/05-quality-ci-tests-docs-parity/05-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-04-29
**Source review:** .planning/phases/05-quality-ci-tests-docs-parity/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (warnings; blockers=0)
- Fixed: 5
- Skipped: 0
- Status: all_fixed

Info-level findings (IN-01..IN-04) were not in scope for this fix pass (`fix_scope: critical_warning`); they remain documented in REVIEW.md for a future cleanup pass.

## Fixed Issues

### WR-01: `tests/install.bats` — `INPUT_JSON` is single-quoted into `bash -c` without sanitization

**Files modified:** `tests/install.bats`
**Commit:** bf6ab78
**Applied fix:** Replaced single-quote interpolation of `$INPUT_JSON` into `bash -c` with a here-string (`<<< "$INPUT_JSON"`). This eliminates the implicit "no single quote in mktemp path" contract and matches how production session-start.sh consumes input (stdin). Bash 3.2 supports `<<<`.

### WR-02: `tests/install.bats` — fake-git stub silently exits 1 on any unhandled subcommand

**Files modified:** `tests/install.bats`
**Commit:** a31151b
**Applied fix:** Added a stub-contract comment in the `*)` default case enumerating the three subcommands the stub is responsible for, plus a stderr diagnostic (`echo "fake-git: unhandled subcommand $1" >&2`) before the `exit 1`. If hooks/session-start.sh is later extended to call a new git subcommand, the bats test surfaces the drift in the failure message instead of silently failing the round-trip assertion.

### WR-03: `CONTRIBUTING.md` — rule-file inventory table at lines 47-57 omits `godmode-skills.md`

**Files modified:** `CONTRIBUTING.md`
**Commit:** ce2291c
**Applied fix:** Added a row to the inventory table for `godmode-skills.md` (skill frontmatter contract, Connects-to layout, Auto Mode detection, vocabulary discipline). Also tightened the `godmode-routing.md` row description from "Agent/skill routing and model selection" to "Agent routing (which agent does what); model-selection summary" so the two rule files' concerns are clearly separated.

### WR-04: `CONTRIBUTING.md` — `shellcheck $(find …)` recipe breaks on filenames with whitespace

**Files modified:** `CONTRIBUTING.md`
**Commit:** e75e2fc
**Applied fix:** Replaced `shellcheck $(find . -name '*.sh' -not -path './.git/*')` with `find . -name '*.sh' -not -path './.git/*' -exec shellcheck {} +`. The new form is POSIX, bash 3.2 portable, and survives whitespace in filenames; it also avoids documenting an unsafe word-splitting pattern that contributors might copy-paste into other contexts.

### WR-05: `tests/install.bats` — newline fixture relies on undocumented `env` newline-passthrough behavior

**Files modified:** `tests/install.bats`
**Commit:** 315ddc7
**Applied fix:** Implemented the preferred option (option 1 from REVIEW.md). `_make_fake_git` now takes a file path argument and copies the adversarial literal into the stub's directory as `branch_literal`. The stub `cat`s that sidecar file instead of reading `$BRANCH_LITERAL` from env. The `_run_adversarial_branch_test` helper writes the literal to a tempfile, hands it to `_make_fake_git`, and drops `BRANCH_LITERAL=…` from the `env` invocation. The env-passthrough roundtrip is eliminated entirely — the test no longer relies on `env(1)` preserving embedded newlines.

## Skipped Issues

None — all in-scope findings were fixed.

## Verification

After each fix, the relevant project gates were re-run with no regressions:

- `bash scripts/check-vocab.sh` — clean (surface count = 11) after every commit
- `bash scripts/check-frontmatter.sh` — clean (12 agents) after WR-05 (the only fix that touched a frontmatter-relevant file pattern)
- `shellcheck -s bash tests/install.bats` — only pre-existing SC2030/SC2031 informational warnings (bats subshell false-positives), no new findings

`bats` itself is not installed in this environment; the install.bats round-trip suite was not executed end-to-end here. The next `/gsd-verify-work` pass (or CI on push) will exercise the tests in their full matrix.

---

_Fixed: 2026-04-29_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
