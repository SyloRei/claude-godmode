#!/usr/bin/env bash
set -euo pipefail

# check-version-drift.sh
# Verifies the canonical plugin version (.claude-plugin/plugin.json:.version)
# is the single source of truth: no other tracked file may hardcode a
# DIFFERENT version string.
#
# Rules:
#   - install.sh / README.md : any vX.Y.Z or X.Y.Z literal must equal canonical.
#   - CHANGELOG.md           : historical release entries are allowed, but the
#                              canonical version MUST appear (latest release).
# Exit 0 when consistent, exit 1 (with a clear message) otherwise.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/.claude-plugin/plugin.json"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "error: manifest not found: $MANIFEST" >&2; exit 1; }

CANONICAL="$(jq -r '.version' "$MANIFEST")"
if [ -z "$CANONICAL" ] || [ "$CANONICAL" = "null" ]; then
  echo "error: no .version in $MANIFEST" >&2
  exit 1
fi

# Regex matching v1.2.3 or 1.2.3 (semver core).
VER_RE='v?[0-9]+\.[0-9]+\.[0-9]+'

drift=0

# Files where ANY version literal must equal the canonical version.
for rel in install.sh README.md; do
  f="$REPO_ROOT/$rel"
  [ -f "$f" ] || continue
  while IFS= read -r found; do
    [ -n "$found" ] || continue
    normalized="${found#v}"
    if [ "$normalized" != "$CANONICAL" ]; then
      echo "drift: $rel hardcodes version '$found' (canonical is '$CANONICAL')" >&2
      drift=1
    fi
  done < <(grep -oE "$VER_RE" "$f" 2>/dev/null || true)
done

# CHANGELOG.md: historical entries allowed, but canonical must be present.
changelog="$REPO_ROOT/CHANGELOG.md"
if [ -f "$changelog" ]; then
  if ! grep -qE "\[?v?${CANONICAL}\]?" "$changelog"; then
    echo "drift: CHANGELOG.md has no entry for canonical version '$CANONICAL'" >&2
    drift=1
  fi
fi

if [ "$drift" -ne 0 ]; then
  echo "version drift detected (canonical: $CANONICAL)" >&2
  exit 1
fi

echo "version consistent: $CANONICAL"
exit 0
