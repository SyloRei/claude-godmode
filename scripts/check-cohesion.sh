#!/usr/bin/env bash
#
# check-cohesion.sh — enforce the onward-pointer convention on every
# user-facing surface.
#
# Workflow cohesion (AC-4): each surface must end with a section that points
# the reader onward to the next step in the workflow, so no surface is a
# dead end. A surface is any skill (skills/*/SKILL.md), agent (agents/*.md),
# or command (commands/*.md).
#
# The accepted section heading is `## Related` OR `## Handoffs` (AC-6):
# agents use Handoffs to name the agents they pass work to, while skills and
# commands use Related to point at sibling skills/commands. Either satisfies
# the gate. Headings match `^#{2,} *(Related|Handoffs) *$` — two or more `#`,
# optional surrounding spaces, nothing else on the line.
#
# A surface missing the section names the file and fails (AC-4). When every
# surface carries the section, the gate exits 0 and reports each one.
#
# Pure bash 3.2 + grep. No Node, no Python, no other runtimes. Exit 0 clean,
# 1 on any violation.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
cd -- "${REPO_ROOT}"

# Onward-pointer heading: either Related (skills/commands) or Handoffs (agents).
SECTION_RE='^#{2,} *(Related|Handoffs) *$'

failures=0
checked=0

for f in skills/*/SKILL.md agents/*.md commands/*.md; do
  # Guard against a glob that matched nothing (literal pattern left intact).
  [ -e "$f" ] || continue

  checked=$((checked + 1))

  if grep -E "${SECTION_RE}" "$f" >/dev/null 2>&1; then
    echo "cohesion: ok ${f}"
  else
    if [ "$failures" -eq 0 ]; then
      echo "cohesion FAILURE: surface(s) missing an onward-pointer section (## Related or ## Handoffs):" >&2
    fi
    printf '  [missing section] %s\n' "$f" >&2
    failures=$((failures + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "cohesion: ${failures} surface(s) missing the onward-pointer section." >&2
  exit 1
fi

# A run that matched zero surfaces is a misconfiguration (wrong working dir, or
# a renamed surface tree), not a clean pass — fail loudly rather than report
# "all 0 surface(s)".
if [ "$checked" -eq 0 ]; then
  echo "cohesion ERROR: no surfaces found under skills/, agents/, commands/." >&2
  exit 1
fi

echo "cohesion: onward-pointer section present on all ${checked} surface(s)."
exit 0
