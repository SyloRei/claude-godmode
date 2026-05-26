#!/usr/bin/env bash
set -euo pipefail

# check-agents-drift.sh
# Verifies the committed AGENTS.md is current with its generator.
#
# Why this gate exists: AGENTS.md is a GENERATED artifact (bin/godmode-agents
# assembles it from agents/*.md frontmatter + rules/godmode-*.md bodies). It is
# also committed so consumers can read it without running the generator. Those
# two facts diverge the moment someone edits an agent/rule source but forgets to
# regenerate — the committed file silently goes stale. This gate makes that
# drift a hard CI failure instead of a slow-rotting doc.
#
# How it checks: it asks the generator for the canonical content via --stdout
# (which touches no file), then diffs that against the tracked AGENTS.md.
# Exit 0 when in sync, exit 1 (with the diff + a regenerate hint) otherwise.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$REPO_ROOT/bin/godmode-agents"
COMMITTED="$REPO_ROOT/AGENTS.md"

[ -x "$GENERATOR" ] || { echo "error: generator not found or not executable: $GENERATOR" >&2; exit 1; }
[ -f "$COMMITTED" ] || { echo "error: AGENTS.md not found: $COMMITTED (run 'bin/godmode-agents' to generate it)" >&2; exit 1; }

EXPECTED="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$EXPECTED'" EXIT

# Regenerate the canonical content WITHOUT clobbering the tracked file.
"$GENERATOR" --stdout > "$EXPECTED"

if diff -u "$COMMITTED" "$EXPECTED"; then
  echo "AGENTS.md up to date"
  exit 0
fi

echo "" >&2
echo "drift: committed AGENTS.md is stale (see diff above; '-' is committed, '+' is regenerated)" >&2
echo "remediation: run 'bin/godmode-agents' to regenerate AGENTS.md, then commit it" >&2
exit 1
