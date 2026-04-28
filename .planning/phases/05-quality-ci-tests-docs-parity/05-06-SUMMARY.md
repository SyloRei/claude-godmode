---
phase: 05-quality-ci-tests-docs-parity
plan: 06
subsystem: tests
tags: [tests, hooks, bats, regression, security, json-construction, CR-03]
gap_ids: [CR-03]
requirements: [QUAL-02, QUAL-07]
dependency_graph:
  requires:
    - hooks/session-start.sh (canonical branch-emission code path under test)
    - tests/fixtures/branches/{quote,backslash,newline,apostrophe}.json (existing fixtures, reused)
  provides:
    - Tests/install.bats Tests 7-10 now actually exercise the FOUND-04 / CONCERNS #6 regression class
  affects:
    - .github/workflows/ci.yml bats job (will exercise the new helpers on next run)
tech-stack:
  added: []
  patterns:
    - PATH-shim of `git` via per-test mktemp -d for hermetic command-substitution
    - BATS helper functions invoked from each @test block (DRY without external libs)
    - "jq -e --arg lit '... | contains($lit)' for round-trip assertion against JSON-decoded value"
key-files:
  created: []
  modified:
    - tests/install.bats
decisions:
  - "Drove session-start.sh (not post-compact.sh) — it owns the production branch-derivation code path; teaching post-compact.sh to read branch_hint would invent a non-production contract"
  - "Stub fake-git via PATH prepend (not GIT_EXEC_PATH or alias) — bash 3.2 portable, per-test isolated, no global state mutation"
  - "Used env BRANCH_LITERAL=... rather than baking the literal into the stub script — keeps one stub binary across all 4 fixtures"
  - "Kept Tests 1-6 untouched (pure additive change to Tests 7-10 + 2 helpers)"
metrics:
  duration_minutes: 6
  completed_date: "2026-04-29"
  tasks_completed: 1
  tasks_total: 1
  files_modified: 1
  commits: 1
---

# Phase 05 Plan 06: CR-03 Closure — Adversarial Branch Tests Now Exercise Real Code Path Summary

**One-liner:** Tests 7-10 in `tests/install.bats` now PATH-shim a fake `git` and drive `hooks/session-start.sh`, asserting each adversarial branch literal (quote, backslash, newline, apostrophe) survives the JSON round-trip into `.hookSpecificOutput.additionalContext` — closing the FOUND-04 / CONCERNS #6 regression class for real.

## Goal

Close CR-03 from `05-VERIFICATION.md`: the 4 adversarial-branch fixture tests were decorative — they piped 4 different fixtures into `hooks/post-compact.sh`, but that hook reads only `.cwd` from stdin and ignores `branch_hint`. All 4 collapsed into a single 'stdin parses, stdout is JSON' check executed four times. The QUAL-02 / QUAL-07 / FOUND-04 / CONCERNS #6 regression class was NOT actually being guarded.

## What Was Done

### Task 1: Rewrote Tests 7-10 in tests/install.bats (commit `49cb45f`)

**Approach (per the plan's option (b)):**
1. `hooks/session-start.sh:53` derives BRANCH from `git branch --show-current`. To exercise it under adversarial input, prepend a `mktemp -d` to PATH containing a fake `git` binary that (a) responds to `rev-parse --is-inside-work-tree` with exit 0, (b) prints the adversarial literal for `branch --show-current`, (c) exits cleanly for `log`.
2. The fake-git stub reads `BRANCH_LITERAL` from its environment, so one stub serves all 4 fixtures (cheap to make, easy to read).
3. Stdin to the hook is `{"cwd": "<STUB_PROJECT>"}` where `STUB_PROJECT` contains a `package.json` — this triggers `session-start.sh`'s `PROJECT_INFO` detection so `CONTEXT` is non-empty and the `jq -n --arg ctx` JSON-emission code path actually runs.
4. After invocation, the test runs `jq -e --arg lit "$BRANCH_LITERAL" '.hookSpecificOutput.additionalContext | contains($lit)'`. This decodes the JSON value and matches it against the literal — a real round-trip assertion, not just JSON validity.

**Two helpers added:**
- `_make_fake_git()` — creates the `mktemp -d`, writes the stub script, `chmod +x`, returns the dir path. Stub script body uses a single-quoted heredoc (so `$1`/`$2` survive).
- `_run_adversarial_branch_test()` — orchestrates fixture extraction, stub project setup, fake-git creation, hook invocation via `env "PATH=..."`, cleanup, and 3 assertions (exit, valid JSON, round-trip).

**The 4 @test blocks reduce to one-line invocations of the helper, with names suffixed `(CR-03 round-trip)` to make the closure visible in bats output.

### Files Modified

| File                | Lines added | Lines removed | Notes                                                                                  |
| ------------------- | ----------- | ------------- | -------------------------------------------------------------------------------------- |
| `tests/install.bats`| 102         | 23            | Tests 7-10 + 2 helpers replace the 4 decorative tests; Tests 1-6 + setup/teardown intact |

## Verification

### Structural assertions (run locally)

| Assertion                                                                  | Expected | Actual | Pass |
| -------------------------------------------------------------------------- | -------- | ------ | ---- |
| `grep -cE '^@test ' tests/install.bats`                                    | `10`     | `10`   | yes  |
| `grep -c 'session-start.sh' tests/install.bats`                            | ≥ 1      | `10`   | yes  |
| `grep -c 'post-compact.sh' tests/install.bats`                             | `0`      | `0`    | yes  |
| `grep -c 'PATH=.*FAKE_GIT_DIR' tests/install.bats`                         | ≥ 1      | `1`    | yes  |
| `grep -c 'additionalContext.*contains' tests/install.bats`                 | ≥ 1      | `3`    | yes  |
| `grep -c '_make_fake_git' tests/install.bats`                              | ≥ 2      | `2`    | yes  |
| `grep -c '_run_adversarial_branch_test' tests/install.bats`                | `5`      | `5`    | yes  |
| `grep -c 'tests/fixtures/branches/quote.json'`                             | `1`      | `1`    | yes  |
| `grep -c 'tests/fixtures/branches/backslash.json'`                         | `1`      | `1`    | yes  |
| `grep -c 'tests/fixtures/branches/newline.json'`                           | `1`      | `1`    | yes  |
| `grep -c 'tests/fixtures/branches/apostrophe.json'`                        | `1`      | `1`    | yes  |
| `grep -cE 'bats-assert\|bats-support' tests/install.bats`                  | `0`      | `0`    | yes  |
| `grep -c 'mktemp -d' tests/install.bats`                                   | ≥ 3      | `4`    | yes  |
| `grep -c 'export HOME' tests/install.bats`                                 | ≥ 1      | `1`    | yes  |
| `grep -c 'rm -rf "$FAKE_GIT_DIR"' tests/install.bats`                      | ≥ 1      | `1`    | yes  |
| `head -1 tests/install.bats == #!/usr/bin/env bats`                        | match    | match  | yes  |
| `grep -c '^# ---- Test ' tests/install.bats` (Tests 1-6 markers preserved) | ≥ 6      | `6`    | yes  |

### Behavioral assertion (manual simulation, since `bats` isn't installed locally)

I directly emulated each test (extract fixture → write stub → run hook → assert) for all 4 fixtures:

```
quote        exit=0 valid=yes contains=yes
backslash    exit=0 valid=yes contains=yes
newline      exit=0 valid=yes contains=yes
apostrophe   exit=0 valid=yes contains=yes
```

For the `quote` fixture I also dumped the raw bytes of the hook's stdout via `xxd` to confirm `jq` produces correctly-escaped JSON: bytes `5c 22` (`\"`) and `5c 6e` (`\n`) appear in the output exactly where they should — the FOUND-04 hardening holds end-to-end. The shell's `echo "$VAR"` interpretation of those escape sequences is purely a display artifact; the bytes on disk are valid JSON. (`jq -e '.'` happily validates the file form.)

### `shellcheck` 0.11.0 (CI-equivalent)

`shellcheck --shell=bats tests/install.bats` produces only SC2030/SC2031 *info*-level notes about `$status`/`$output` in subshells — these are false positives caused by shellcheck not modelling the bats `run` macro that sets those variables in the test's parent scope. Same notes appear on Test 6 (unchanged). No errors, no warnings against the new helper code.

### `bats tests/install.bats`

`bats` is not installed in the worktree environment; the project's CI matrix (`.github/workflows/ci.yml`, ubuntu+macos with `bats-core` v1.13.0) is the authoritative behavioral runner. The structural greps + the manual end-to-end simulation above are the local proof that the regression class is genuinely exercised.

## Acceptance Criteria

- [x] Tests 7-10 in `tests/install.bats` invoke `hooks/session-start.sh` (NOT `post-compact.sh`) — the canonical branch-emission path
- [x] Tests 7-10 PATH-shim a fake `git` returning the adversarial branch literal from each fixture
- [x] Each test asserts the adversarial literal survives JSON round-trip into emitted `additionalContext`
- [x] Tests 1-6 unchanged
- [x] `mktemp -d` HOME isolation preserved (bats setup/teardown intact); fake-git and stub-project also `mktemp -d` per test
- [x] Each fixture file referenced exactly once
- [x] No new external bats helper-libs introduced
- [x] SUMMARY.md created and committed

## Deviations from Plan

None — the plan was executed exactly as written. The new_string from the plan was applied verbatim to `tests/install.bats`. All 13 structural acceptance assertions passed on the first run.

## Authentication Gates

None encountered.

## Threat Model Verification

| Threat ID    | Disposition | Status                                                                                                                                                |
| ------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| T-05-06-01   | mitigate    | Mitigated: each test uses 3 independent `mktemp -d` dirs (HOME via setup, FAKE_GIT_DIR, STUB_PROJECT) — verified by `grep -c 'mktemp -d'` = 4         |
| T-05-06-02   | mitigate    | Mitigated: stub responds only to `rev-parse --is-inside-work-tree`, `branch --show-current`, `log`; all other subcommands `exit 1`. PATH shim is per-test |
| T-05-06-03   | accept      | Accepted: literals are static fixtures committed to the repo, not secret                                                                                |
| T-05-06-04   | accept      | Accepted: stub is bounded (no loops, fixed `exit` per branch); CI bats job has implicit GH Actions timeout                                              |

No new threat surface introduced — the change reduces attack surface (decorative tests → real assertions).

## Threat Flags

None — no new network endpoints, auth paths, file-access patterns, or trust-boundary schemas introduced. Pure test-quality improvement.

## Known Stubs

None — all hardcoded values in the new code (the fake-git stub script body, the `package.json` content `'{}'`, the `.cwd` JSON shape) are intentional test fixtures, not unwired UI/data placeholders.

## TDD Gate Compliance

This plan is `type: execute` (not `type: tdd`) — gate sequence not applicable. The work is itself a regression test commitment, so it functions as a test commit that hardens the existing FOUND-04 fix.

## Self-Check

```
$ test -f tests/install.bats && echo FOUND
FOUND

$ test -f .planning/phases/05-quality-ci-tests-docs-parity/05-06-SUMMARY.md && echo FOUND
FOUND

$ git log --oneline | grep -q '49cb45f' && echo FOUND
FOUND
```

## Self-Check: PASSED

All claimed file modifications and commits exist on disk and in the git log.
