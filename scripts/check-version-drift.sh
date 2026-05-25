#!/usr/bin/env bash
set -euo pipefail

# check-version-drift.sh
# Verifies the canonical plugin version (.claude-plugin/plugin.json:.version)
# is the single source of truth: no other tracked file may hardcode a
# DIFFERENT *plugin* version string.
#
# Why context-scoped matching: README/CHANGELOG/install.sh legitimately
# reference many NON-plugin versions (Claude Code >= v2.1.33, git >= 2.20,
# jq, shellcheck 0.11.0, a "$0.45" cost example). A naive "any X.Y.Z" scan
# false-positives on all of them. So we only inspect contexts that can only
# mean the plugin's own version:
#   - install.sh : a hardcoded VERSION= assignment (should read via jq instead)
#   - README.md  : a STATIC shields version badge `badge/version-X.Y.Z`
#                  (the dynamic `github/v/release` badge carries no literal)
#   - CHANGELOG  : the canonical version MUST appear as a release entry
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

VER_CORE='[0-9]+\.[0-9]+\.[0-9]+'
drift=0

# install.sh: flag a hardcoded VERSION= assignment that differs from canonical.
# (install.sh should read the version via `jq -r '.version' ...` — no literal.)
inst="$REPO_ROOT/install.sh"
if [ -f "$inst" ]; then
  while IFS= read -r found; do
    [ -n "$found" ] || continue
    normalized="${found#v}"
    if [ "$normalized" != "$CANONICAL" ]; then
      echo "drift: install.sh hardcodes VERSION='$found' (canonical is '$CANONICAL')" >&2
      drift=1
    fi
  done < <(grep -oE "VERSION=[\"']?v?${VER_CORE}" "$inst" 2>/dev/null \
            | grep -oE "v?${VER_CORE}" || true)
fi

# README.md: only a STATIC version badge encodes a literal plugin version.
readme="$REPO_ROOT/README.md"
if [ -f "$readme" ]; then
  while IFS= read -r found; do
    [ -n "$found" ] || continue
    normalized="${found#v}"
    if [ "$normalized" != "$CANONICAL" ]; then
      echo "drift: README.md static version badge shows '$found' (canonical is '$CANONICAL')" >&2
      drift=1
    fi
  done < <(grep -oE "badge/version-v?${VER_CORE}" "$readme" 2>/dev/null \
            | grep -oE "v?${VER_CORE}" || true)
fi

# CHANGELOG.md: historical entries allowed, but canonical MUST appear.
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
