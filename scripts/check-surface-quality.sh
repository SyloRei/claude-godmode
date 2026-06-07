#!/usr/bin/env bash
#
# check-surface-quality.sh — dead-reference deny-list gate for every
# user-facing surface.
#
# Surface-quality convention (AC-8): no user-facing surface (a skill
# skills/*/SKILL.md, an agent agents/*.md, or a command commands/*.md) may
# cite `CLAUDE.md` as a source of quality gates or godmode protocol. Those
# citations are stale — the canonical sources are `config/quality-gates.txt`
# (the gate list) and `rules/godmode-*.md` (the protocols). A surface that
# names CLAUDE.md sends the reader to a file that no longer carries that
# authority, so the reference is a dead end.
#
# The gate scans each surface for `CLAUDE.md`. Every hit names the file and
# line and fails the run. When no surface cites CLAUDE.md, the gate exits 0
# and reports how many surfaces were checked.
#
# Carve-out: this gate denies ALL `CLAUDE.md` mentions, because today no
# surface has a legitimate reason to discuss a consumer repo's CLAUDE.md. If
# a future surface genuinely needs to (e.g. documenting how a consumer's own
# CLAUDE.md interacts with the workflow), narrow the deny pattern here to the
# stale source-citation phrasings only — do not blanket-allow CLAUDE.md.
#
# Pure bash 3.2 + grep. No Node, no Python, no other runtimes. Exit 0 clean,
# 1 on any stale reference.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
cd -- "${REPO_ROOT}"

# Stale-reference deny pattern: any mention of CLAUDE.md on a surface.
STALE_RE='CLAUDE\.md'

failures=0
checked=0
# Category header flag: the stale-reference failure header prints exactly once,
# the first time a violation fires, so all violation lines group under a single
# intro header (mirroring check-cohesion.sh's "header then violations" shape).
stale_header_shown=0

for f in skills/*/SKILL.md agents/*.md commands/*.md; do
  # Guard against a glob that matched nothing (literal pattern left intact).
  [ -e "$f" ] || continue

  checked=$((checked + 1))

  # `grep -nE` exits 1 when a surface holds no stale reference, which is the
  # clean case, not an error; swallow that so `set -e`/pipefail do not abort
  # the run on a clean surface. The `|| true` is scoped to grep ONLY.
  hits=$(grep -nE "${STALE_RE}" "$f" || true)

  if [ -z "$hits" ]; then
    # Per-surface progress line for a clean surface, mirroring cohesion.sh's
    # `cohesion: ok <path>` line on stdout.
    echo "surface-quality: ok ${f}"
    continue
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$stale_header_shown" -eq 0 ]; then
      echo "surface-quality FAILURE: surface(s) cite a stale CLAUDE.md reference (cite config/quality-gates.txt + rules/godmode-*.md instead):" >&2
      stale_header_shown=1
    fi
    printf '  [stale reference] %s:%s\n' "$f" "$line" >&2
    failures=$((failures + 1))
  done <<EOF
$hits
EOF
done

if [ "$failures" -ne 0 ]; then
  echo "surface-quality: ${failures} stale CLAUDE.md reference(s) on surfaces; cite config/quality-gates.txt + rules/godmode-*.md instead." >&2
  exit 1
fi

# A run that matched zero surfaces is a misconfiguration (wrong working dir, or
# a renamed surface tree), not a clean pass — fail loudly rather than report
# "all 0 surface(s)".
if [ "$checked" -eq 0 ]; then
  echo "surface-quality ERROR: no surfaces found under skills/, agents/, commands/." >&2
  exit 1
fi

echo "surface-quality: no stale CLAUDE.md references in ${checked} surface(s)."
exit 0
