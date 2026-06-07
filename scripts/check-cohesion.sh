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
# Beyond presence (AC-7): every onward pointer named inside the section must
# resolve to a real surface, so the section can never point the reader at a
# step that does not exist. A pointer token is `/<name>` (a skill or command)
# or `@<name>` (an agent), with `<name>` = [a-z][a-z-]*. Extraction is
# boundary-aware — the sigil must sit at a token boundary — so filesystem path
# fragments (.planning/missions/…, bin/godmode-skill) and helper names in the
# prose are not mistaken for surface pointers. `/<name>` resolves if
# skills/<name>/SKILL.md OR commands/<name>.md exists; `@<name>` resolves if
# agents/<name>.md exists. A dangling pointer names the file and the token and
# fails. A section with no pointer tokens is fine (nothing to resolve).
#
# Pure bash 3.2 + grep/sed/awk. No Node, no Python, no other runtimes. Exit 0
# clean, 1 on any violation.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
cd -- "${REPO_ROOT}"

# Onward-pointer heading: either Related (skills/commands) or Handoffs (agents).
SECTION_RE='^#{2,} *(Related|Handoffs) *$'

# Resolve a single pointer token (e.g. /build or @writer) to a surface file.
# Returns 0 if the surface exists, 1 otherwise.
resolve_pointer() {
  case "$1" in
    /*)
      name=${1#/}
      [ -f "skills/${name}/SKILL.md" ] || [ -f "commands/${name}.md" ]
      ;;
    @*)
      name=${1#@}
      [ -f "agents/${name}.md" ]
      ;;
    *)
      return 1
      ;;
  esac
}

failures=0
checked=0
# Per-category header flags: each violation category prints its failure header
# exactly once, the first time that category fires. Decoupling them from the
# shared `failures` counter means that when both categories occur in one run,
# each category's entries still appear under its own header (rather than the
# second category's entries printing headerless under the first).
missing_header_shown=0
dangling_header_shown=0

for f in skills/*/SKILL.md agents/*.md commands/*.md; do
  # Guard against a glob that matched nothing (literal pattern left intact).
  [ -e "$f" ] || continue

  checked=$((checked + 1))

  if grep -E "${SECTION_RE}" "$f" >/dev/null 2>&1; then
    echo "cohesion: ok ${f}"

    # Resolution pass (AC-7): extract the section body — lines from the first
    # Related/Handoffs heading to the next `## `-or-deeper heading (or EOF) —
    # then verify every pointer token inside it resolves to a real surface.
    # awk is scoped to the section body, so prose tokens elsewhere in the file
    # (e.g. @param in a code fence) are never scanned.
    body=$(awk '
      /^#{2,} *(Related|Handoffs) *$/ { if (inb) { exit } inb = 1; next }
      inb && /^#{2,} / { exit }
      inb { print }
    ' "$f")

    # Boundary-aware token extraction: the sigil must sit at start-of-line or
    # be preceded by a non-path char, so path fragments (/missions, /ideas) and
    # helper names (/godmode-mission) are excluded.
    # `grep -oE` exits 1 when the body holds no pointer tokens, which is a valid
    # prose-only section, not an error; swallow that so `set -e`/pipefail do not
    # abort the run on a clean surface.
    # `|| true` is scoped to grep ONLY: grep exits 1 when the body holds no
    # pointer tokens (a valid prose-only section), so we tolerate that single
    # failure inline. A genuine sed/sort failure downstream is NOT swallowed and
    # still aborts the run under `set -e`/pipefail.
    tokens=$(printf '%s\n' "$body" \
      | { grep -oE '(^|[^A-Za-z0-9._/@-])[/@][a-z][a-z-]*' || true; } \
      | sed -E 's/^[^/@]//' \
      | sort -u)

    while IFS= read -r token; do
      [ -n "$token" ] || continue
      if ! resolve_pointer "$token"; then
        if [ "$dangling_header_shown" -eq 0 ]; then
          echo "cohesion FAILURE: onward-pointer section names a surface that does not exist:" >&2
          dangling_header_shown=1
        fi
        printf '  [dangling pointer] %s -> %s\n' "$f" "$token" >&2
        failures=$((failures + 1))
      fi
    done <<EOF
$tokens
EOF
  else
    if [ "$missing_header_shown" -eq 0 ]; then
      echo "cohesion FAILURE: surface(s) missing an onward-pointer section (## Related or ## Handoffs):" >&2
      missing_header_shown=1
    fi
    printf '  [missing section] %s\n' "$f" >&2
    failures=$((failures + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "cohesion: ${failures} onward-pointer violation(s) (missing section or dangling pointer)." >&2
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
