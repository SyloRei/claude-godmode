#!/usr/bin/env bash
# scripts/check-version-drift.sh
# Asserts every version mention in user-facing files matches plugin.json:.version.
# CI gate (Phase 5 wires this into GitHub Actions). Exits non-zero on drift with file:line evidence.
# Bash 3.2 + grep + jq only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"

[ -f "$PLUGIN_JSON" ] || { echo "[x] plugin.json not found at $PLUGIN_JSON"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[x] jq required but not installed"; exit 1; }

CANONICAL="$(jq -r .version "$PLUGIN_JSON")"
[ -n "$CANONICAL" ] && [ "$CANONICAL" != "null" ] || { echo "[x] plugin.json:.version is empty or null"; exit 1; }

echo "[i] canonical version: $CANONICAL"

DRIFT=0

# install.sh: any line containing VERSION= other than the jq read itself
if [ -f "$REPO_ROOT/install.sh" ]; then
  while IFS= read -r line; do
    # shellcheck disable=SC2016  # case patterns below are literal-string matches, not shell expansions
    case "$line" in
      *'VERSION="$(jq'*) ;;  # the jq read itself — OK
      *'VERSION="'*'"'*)
        echo "[!] install.sh: $line"
        DRIFT=1
        ;;
    esac
  done < <(grep -n 'VERSION=' "$REPO_ROOT/install.sh" || true)
fi

# commands/*.md: any vN.N.N in heading lines
for f in "$REPO_ROOT/commands/"*.md; do
  [ -f "$f" ] || continue
  if grep -nE '^#+ .* v[0-9]+\.[0-9]+\.[0-9]+' "$f"; then
    echo "[!] $f: literal version in heading"
    DRIFT=1
  fi
done

# README.md: any vN.N.N — mentions of the canonical version are OK
if [ -f "$REPO_ROOT/README.md" ]; then
  while IFS= read -r match; do
    case "$match" in
      *"$CANONICAL"*) ;;  # mentions of the canonical version — OK
      *)
        echo "[!] README.md: $match"
        DRIFT=1
        ;;
    esac
  done < <(grep -nE 'v[0-9]+\.[0-9]+\.[0-9]+' "$REPO_ROOT/README.md" || true)
fi

# CHANGELOG.md: only the topmost ## v heading is checked against canonical
if [ -f "$REPO_ROOT/CHANGELOG.md" ]; then
  TOP_HEADING=$(grep -nE '^## v[0-9]+\.[0-9]+\.[0-9]+' "$REPO_ROOT/CHANGELOG.md" | head -1 || true)
  if [ -n "$TOP_HEADING" ]; then
    case "$TOP_HEADING" in
      *"$CANONICAL"*) ;;
      *)
        echo "[!] CHANGELOG.md top heading does not match canonical: $TOP_HEADING"
        DRIFT=1
        ;;
    esac
  fi
fi

if [ "$DRIFT" -eq 0 ]; then
  echo "[+] no version drift"
  exit 0
else
  echo "[x] version drift detected — fix the files above to match $CANONICAL"
  exit 1
fi
