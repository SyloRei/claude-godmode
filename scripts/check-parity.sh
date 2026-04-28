#!/usr/bin/env bash
# scripts/check-parity.sh
# Asserts hooks/hooks.json[hooks] and config/settings.template.json[hooks] are
# byte-equivalent after path-prefix normalization (${CLAUDE_PLUGIN_ROOT}/... -> ~/.claude/...).
# CI gate (Phase 5 wires this into GitHub Actions). Exits non-zero on drift with diff output.
# Bash 3.2 + jq + diff only.
# Convention authority: .planning/research/ARCHITECTURE.md § 5; 05-CONTEXT.md D-09..D-11.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_HOOKS="$REPO_ROOT/hooks/hooks.json"
TEMPLATE="$REPO_ROOT/config/settings.template.json"

[ -f "$PLUGIN_HOOKS" ] || { echo "[x] hooks.json not found at $PLUGIN_HOOKS"; exit 1; }
[ -f "$TEMPLATE" ] || { echo "[x] settings.template.json not found at $TEMPLATE"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[x] jq required but not installed"; exit 1; }
command -v diff >/dev/null 2>&1 || { echo "[x] diff required but not installed"; exit 1; }

echo "[i] comparing $PLUGIN_HOOKS .hooks <-> $TEMPLATE .hooks"
echo "[i] normalizing \${CLAUDE_PLUGIN_ROOT} -> ~/.claude in plugin-mode JSON (D-10)"

DRIFT=0

# Normalize: replace ${CLAUDE_PLUGIN_ROOT} prefix with ~/.claude in plugin-mode JSON,
# then sort keys (-S) for stable comparison. Path-prefix divergence is EXPECTED (D-10) —
# every other field (matcher, type, timeout) must be byte-identical.
PLUGIN_NORMALIZED=$(jq -S '
  .hooks |
  walk(if type == "string" then gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; "~/.claude") else . end)
' "$PLUGIN_HOOKS")

TEMPLATE_NORMALIZED=$(jq -S '.hooks' "$TEMPLATE")

if ! diff -u <(printf '%s\n' "$PLUGIN_NORMALIZED") <(printf '%s\n' "$TEMPLATE_NORMALIZED"); then
  DRIFT=1
fi

if [ "$DRIFT" -eq 0 ]; then
  echo "[+] hooks/hooks.json and config/settings.template.json[hooks] are equivalent"
  exit 0
else
  echo "[x] plugin/manual parity drift — see diff above"
  echo "[x] fix: align hook bindings, timeouts, matchers across hooks/hooks.json and config/settings.template.json"
  exit 1
fi
