#!/usr/bin/env bash
#
# gates.sh — canonical quality-gate runner for /ship.
#
# Reads the gate list from config/quality-gates.txt (the single source of
# truth), reports each gate's status, and exits non-zero if any gate fails.
# This is the bundled, shellcheck-clean, bats-tested replacement for the inline
# gate-running loop that ship/SKILL.md used to re-derive each run.
#
# CONFIG RESOLUTION (AC-2)
#   The gate list is resolved across the three install modes, IN ORDER:
#     1. ${CLAUDE_PLUGIN_ROOT}/config/quality-gates.txt   (plugin mode)
#     2. $HOME/.claude/config/quality-gates.txt           (manual install)
#     3. config/quality-gates.txt                         (repo-relative, dev)
#   If none exists, exit non-zero with an error on stderr naming the file.
#
# GATE LIST (AC-3)
#   Gate names are READ from the resolved file — never hardcoded here. Each
#   non-empty line is one gate. The script prints one labelled status line per
#   gate and exits non-zero if any gate fails, zero only when all pass.
#
# CALLER / TEST CONTRACT
#   The actual per-gate *command* (typecheck, lint, test, build, secret scan)
#   is project-auto-detected and lives in the calling skill's flow — gates.sh
#   does not know how to run a typecheck. Instead each gate's outcome is
#   produced by a pluggable gate-runner hook so the harness is deterministic
#   and testable:
#
#     GATES_RUNNER  An optional command (string). For each gate it is invoked
#                   as:  $GATES_RUNNER "<gate text>"
#                   Its exit status decides that gate: 0 = pass, non-zero =
#                   fail. Its stdout (if any) is shown as detail. When unset,
#                   every gate is reported UNEVALUATED and the run fails (a
#                   caller must wire real gate commands; an unevaluated gate is
#                   never a silent pass).
#
#     GATES_FILE    Optional override of the resolved config path (used by
#                   tests to point at a fixture). Bypasses resolution when set.
#
#   This lets a bats test (S7) force the three contract cases deterministically:
#     - all-pass     -> GATES_RUNNER='true'         => exit 0
#     - one-fail     -> a runner that fails for one gate name => exit non-zero
#     - missing cfg  -> point resolution at absent paths      => exit non-zero
#
# Pure bash 3.2 + find/printf. No Node, no Python.

set -euo pipefail

# --- Resolve the canonical gate list across install modes (AC-2) -------------
# A test may pin GATES_FILE directly; otherwise try each candidate in order.
if [ -z "${GATES_FILE:-}" ]; then
  GATES_FILE=""
  for cand in \
    "${CLAUDE_PLUGIN_ROOT:-}/config/quality-gates.txt" \
    "${HOME:-}/.claude/config/quality-gates.txt" \
    "config/quality-gates.txt"; do
    case "$cand" in
      /config/quality-gates.txt|/.claude/config/quality-gates.txt) continue ;;
    esac
    if [ -f "$cand" ]; then
      GATES_FILE="$cand"
      break
    fi
  done
fi

if [ -z "${GATES_FILE:-}" ] || [ ! -f "${GATES_FILE}" ]; then
  echo "gates: error: config/quality-gates.txt not found (looked in \${CLAUDE_PLUGIN_ROOT}/config, \$HOME/.claude/config, repo-relative config/)." >&2
  exit 1
fi

echo "Quality gates (from ${GATES_FILE}):"

# --- Read the gate list and evaluate each gate (AC-3) ------------------------
runner="${GATES_RUNNER:-}"
failures=0
gate_count=0

while IFS= read -r gate || [ -n "$gate" ]; do
  # Skip blank lines so trailing newlines don't create empty gates.
  [ -n "$gate" ] || continue
  gate_count=$((gate_count + 1))

  if [ -z "$runner" ]; then
    # No gate-runner wired: report unevaluated and count it as a failure so an
    # unevaluated gate can never masquerade as a pass.
    printf '  [?] %s (unevaluated: no GATES_RUNNER wired)\n' "$gate"
    failures=$((failures + 1))
    continue
  fi

  if "$runner" "$gate"; then
    printf '  [\xe2\x9c\x93] %s\n' "$gate"
  else
    printf '  [\xe2\x9c\x97] %s\n' "$gate"
    failures=$((failures + 1))
  fi
done < "${GATES_FILE}"

if [ "$gate_count" -eq 0 ]; then
  echo "gates: error: no gates found in ${GATES_FILE}." >&2
  exit 1
fi

# --- Verdict (AC-3) ----------------------------------------------------------
if [ "$failures" -gt 0 ]; then
  echo "gates: FAILURE — ${failures} of ${gate_count} gate(s) did not pass." >&2
  exit 1
fi

echo "gates: all ${gate_count} gate(s) passed."
exit 0
