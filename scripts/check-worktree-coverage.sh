#!/usr/bin/env bash
#
# check-worktree-coverage.sh — lock the worktree-hardening test coverage so a
# future refactor cannot silently delete the tests that hold the mission-03
# audit reproductions red.
#
# Backs unit 6, AC-7 (this deterministic CI gate exists, is bash 3.2/BSD-safe,
# lint-clean, and exits 0 against the current tree) and sets up AC-8 (the
# optional tests-dir argument + named-failure-to-stderr behaviour that unit 6
# step S5 drives against a temp fixture).
#
# It asserts two coverage families over the *.bats files in the tests dir:
#
#   1. Reproduction tokens — each audit reproduction is tagged with a literal
#      token on its `@test` description line. The four tokens
#      ([repro:stale-base], [repro:merge-hazard], [repro:cleanup-leak],
#      [repro:dash-n]) must each appear on at least one `@test` line, so the
#      red-when-broken reproductions cannot be quietly removed.
#
#   2. Subcommand / helper coverage — the worktree lifecycle helpers
#      (godmode-worktree create / mergeback / cleanup), the done-set helper
#      (godmode-state done add|has|list), and the skip-set helper
#      (godmode-skipset) must each be referenced by at least one test, so the
#      behaviours they encode keep an executable witness.
#
# A missing token or reference names exactly what is unlocked on stderr and
# exits non-zero. A clean tree exits 0 after printing `ok` lines.
#
# Optional first argument: the tests directory to scan (default
# "${REPO_ROOT}/tests"). This lets a test fixture drive the gate against a
# temp dir without mutating the real suite. A non-directory argument fails
# loudly.
#
# Pure bash 3.2 + grep. No jq, no Node, no Python, no GNU-only flags. Exit 0
# clean, 1 on any violation.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
cd -- "${REPO_ROOT}"

# Tests directory to scan: optional first arg, defaulting to the real suite.
TESTS_DIR="${1:-${REPO_ROOT}/tests}"

if [ ! -d "${TESTS_DIR}" ]; then
  echo "worktree-coverage ERROR: tests dir not found: ${TESTS_DIR}" >&2
  exit 1
fi

failures=0
checked=0

# --- Family 1: reproduction tokens (must tag at least one @test line) ---------
#
# Each token is a literal bracketed string. We require it on a `@test` line so
# the assertion tracks the reproduction's test, not an incidental prose mention
# in a header comment. grep -F keeps the brackets literal; we first restrict to
# `@test` lines, then look for the token within them.
for token in \
  '[repro:stale-base]' \
  '[repro:merge-hazard]' \
  '[repro:cleanup-leak]' \
  '[repro:dash-n]'; do
  checked=$((checked + 1))

  if grep -rhE '^@test' "${TESTS_DIR}"/*.bats 2>/dev/null \
    | grep -F "${token}" >/dev/null 2>&1; then
    echo "worktree-coverage: ok repro token ${token}"
  else
    if [ "$failures" -eq 0 ]; then
      echo "worktree-coverage FAILURE: reproduction(s)/subcommand(s) unlocked:" >&2
    fi
    printf '  [unlocked reproduction] no @test carries %s\n' "${token}" >&2
    failures=$((failures + 1))
  fi
done

# --- Family 2: subcommand / helper coverage (referenced by at least one test) -
#
# Each entry is "label::pattern". The pattern is an ERE matched across the
# tests dir's *.bats files. Patterns mirror how the helpers actually appear in
# the suite today (e.g. `"$WT" create`, `"$STATE" "done" add`,
# `godmode-skipset`) yet stay specific enough that deleting the covering test
# trips the gate. We anchor on the closing `WT"` quote + subcommand rather
# than the `$WT` expansion so the pattern carries no `$` (kept literal).
for entry in \
  'godmode-worktree create::WT" create' \
  'godmode-worktree mergeback::WT" mergeback' \
  'godmode-worktree cleanup::WT" cleanup' \
  'done-set helper (godmode-state done)::done" (add|has|list)' \
  'skip-set helper (godmode-skipset)::godmode-skipset'; do
  label="${entry%%::*}"
  pattern="${entry#*::}"
  checked=$((checked + 1))

  if grep -rhE "${pattern}" "${TESTS_DIR}"/*.bats >/dev/null 2>&1; then
    echo "worktree-coverage: ok subcommand ${label}"
  else
    if [ "$failures" -eq 0 ]; then
      echo "worktree-coverage FAILURE: reproduction(s)/subcommand(s) unlocked:" >&2
    fi
    printf '  [uncovered subcommand] no test references %s\n' "${label}" >&2
    failures=$((failures + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "worktree-coverage: ${failures} reproduction(s)/subcommand(s) unlocked." >&2
  exit 1
fi

# A run that checked nothing is a misconfiguration (wrong working dir or a
# renamed tests tree), not a clean pass — fail loudly rather than report
# "all 0 ok". The check list above is hardcoded, so a zero count means the
# loops never ran (an impossible-in-practice guard kept for symmetry with the
# sibling gates).
if [ "$checked" -eq 0 ]; then
  echo "worktree-coverage ERROR: no coverage assertions were evaluated." >&2
  exit 1
fi

echo "worktree-coverage: all ${checked} reproduction/subcommand lock(s) present in ${TESTS_DIR}."
exit 0
