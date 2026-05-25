#!/usr/bin/env bash
# Post-compaction hook: re-inject critical context that Claude loses during compaction.
# This ensures quality gates, available skills/agents, and project context survive long sessions.

set -euo pipefail

# Read stdin (hook input JSON) — we don't need it but must consume it
cat > /dev/null || true

# Detect project context
CONTEXT=""

# Detect package manager and language
if [ -f "package.json" ]; then
  PKG_MGR="npm"
  [ -f "pnpm-lock.yaml" ] && PKG_MGR="pnpm"
  [ -f "yarn.lock" ] && PKG_MGR="yarn"
  [ -f "bun.lockb" ] && PKG_MGR="bun"
  CONTEXT="Project: TypeScript/JavaScript (${PKG_MGR})"
elif [ -f "Cargo.toml" ]; then
  CONTEXT="Project: Rust (cargo)"
elif [ -f "go.mod" ]; then
  CONTEXT="Project: Go (go)"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  PY_MGR="pip"
  [ -f "uv.lock" ] && PY_MGR="uv"
  CONTEXT="Project: Python (${PY_MGR})"
elif [ -f "Gemfile" ]; then
  CONTEXT="Project: Ruby (bundle)"
fi

# Resolve the plugin root the same way commands/godmode.md does:
# plugin mode sets CLAUDE_PLUGIN_ROOT; manual install lives under ~/.claude;
# repo checkout falls back to the current working tree.
ROOT=""
for cand in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" "$(pwd)"; do
  [ -n "$cand" ] || continue
  if [ -f "$cand/.claude-plugin/plugin.json" ] || [ -d "$cand/agents" ]; then
    ROOT="$cand"
    break
  fi
done

# Live filesystem scan — never hardcode the inventory (it drifts as the repo evolves).
# Each skills/ subdir (excl. `_`-prefixed helpers) is a slash command; each
# agents/*.md is an agent. Glob loops keep this shellcheck-clean and bash 3.2 safe.

# scan_skills <dir> — print "/name " for each non-`_`-prefixed subdirectory.
scan_skills() {
  local dir="$1" d name
  [ -d "$dir" ] || return 0
  for d in "$dir"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    case "$name" in _*) continue ;; esac
    printf '/%s ' "$name"
  done
}

# scan_agents <dir> — print "@name " for each *.md file.
scan_agents() {
  local dir="$1" f name
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    printf '@%s ' "$name"
  done
}

SKILLS=""
AGENTS=""
if [ -n "$ROOT" ]; then
  SKILLS=$(scan_skills "$ROOT/skills")
  AGENTS=$(scan_agents "$ROOT/agents")
fi
# Repo-relative fallback if root was unresolved or the scan came up empty.
[ -z "$SKILLS" ] && SKILLS=$(scan_skills "skills")
[ -z "$AGENTS" ] && AGENTS=$(scan_agents "agents")
# Trim the trailing space each scan leaves.
SKILLS="${SKILLS% }"
AGENTS="${AGENTS% }"

SKILLS_LINE=""
[ -n "$SKILLS" ] && SKILLS_LINE="Available Skills: ${SKILLS}"
AGENTS_LINE=""
[ -n "$AGENTS" ] && AGENTS_LINE="Available Agents: ${AGENTS}"

# Assemble the restored-context body, then emit as JSON via jq -n (never string-interpolate).
BODY="CONTEXT RESTORED AFTER COMPACTION:"
[ -n "$CONTEXT" ] && BODY="${BODY}

${CONTEXT}"
# Quality gates: read the single source (config/quality-gates.txt), never
# hardcode the list — it stays in sync with the rest of the plugin.
GATES=""
if [ -n "$ROOT" ] && [ -f "$ROOT/config/quality-gates.txt" ]; then
  while IFS= read -r gate || [ -n "$gate" ]; do
    [ -n "$gate" ] || continue
    GATES="${GATES}
- ${gate}"
  done < "$ROOT/config/quality-gates.txt"
fi
BODY="${BODY}

Quality gates (canonical, from config/quality-gates.txt — ALL must pass before completing any task):${GATES}
"
[ -n "$SKILLS_LINE" ] && BODY="${BODY}
${SKILLS_LINE}"
[ -n "$AGENTS_LINE" ] && BODY="${BODY}
${AGENTS_LINE}"
BODY="${BODY}
Workflow spine: /godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship

Refer to CLAUDE.md and rules/godmode-routing.md for the full lifecycle and coding standards."

jq -n --arg ctx "$BODY" '{
  hookSpecificOutput: {
    hookEventName: "PostCompact",
    additionalContext: $ctx
  }
}'
