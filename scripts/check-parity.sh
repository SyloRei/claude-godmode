#!/usr/bin/env bash
#
# check-parity.sh — assert plugin-mode and manual-mode hook bindings agree.
#
# The plugin ships hook bindings in two places that MUST stay in lockstep:
#   - hooks/hooks.json              (plugin-mode; paths under ${CLAUDE_PLUGIN_ROOT})
#   - config/settings.template.json (manual-mode;  paths under ~/.claude)
# Per CLAUDE.md, "plugin-mode == manual-mode": the same hook EVENT set, the
# same per-event hook COMMANDS (modulo the path prefix), and the same TIMEOUTS.
#
# This gate normalizes both files into a canonical, path-agnostic, ORDER-
# INDEPENDENT shape and diffs them. Event order and within-event ordering must
# NOT matter (a known cosmetic order difference exists between the two files);
# only a real divergence in {events, matchers, commands, timeouts} fails.
#
# Pure jq + bash 3.2. No Node, no Python, no yaml binary.
# Exit 0 on parity, exit 1 (with a diff) on real divergence.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

PLUGIN_HOOKS="${REPO_ROOT}/hooks/hooks.json"
MANUAL_SETTINGS="${REPO_ROOT}/config/settings.template.json"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 1; }
[ -f "${PLUGIN_HOOKS}" ]    || { echo "error: not found: ${PLUGIN_HOOKS}" >&2; exit 1; }
[ -f "${MANUAL_SETTINGS}" ] || { echo "error: not found: ${MANUAL_SETTINGS}" >&2; exit 1; }

# Canonicalize a hooks object into an order-independent, path-agnostic form.
#
#   - .hooks is the top-level event map in both files.
#   - For each event, sort its entries; for each entry sort its hooks.
#   - Strip the path prefix from every command so the two installs compare
#     equal: `bash ${CLAUDE_PLUGIN_ROOT}/hooks/x.sh` and `bash ~/.claude/hooks/x.sh`
#     both normalize to `bash <ROOT>/hooks/x.sh`.
#   - `--sort-keys` makes object KEY order (i.e. event order) irrelevant.
#
# The substitution is intentionally narrow (only the two known prefixes) so a
# genuinely wrong path still surfaces as a divergence.
canonicalize() {
  jq --sort-keys '
    def norm_cmd:
      gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; "<ROOT>")
      | gsub("~/\\.claude"; "<ROOT>");
    .hooks
    | with_entries(
        .value |= (
          map(
            (.hooks |= (map(.command |= norm_cmd) | sort_by(.command)))
          )
          | sort_by(tojson)
        )
      )
  ' "$1"
}

plugin_canon=$(canonicalize "${PLUGIN_HOOKS}")
manual_canon=$(canonicalize "${MANUAL_SETTINGS}")

if [ "${plugin_canon}" = "${manual_canon}" ]; then
  echo "parity: plugin and manual hook bindings agree."
  exit 0
fi

echo "parity FAILURE: hooks/hooks.json and config/settings.template.json diverge." >&2
echo "(normalized, path-agnostic, order-independent diff below)" >&2
diff <(printf '%s\n' "${plugin_canon}") <(printf '%s\n' "${manual_canon}") >&2 || true
exit 1
