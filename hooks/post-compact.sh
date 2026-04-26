#!/usr/bin/env bash
# Post-compaction hook: re-inject critical context that Claude loses during compaction.
# This ensures quality gates, available skills/agents, and project context survive long sessions.

set -euo pipefail

# Read stdin (hook input JSON) once — tolerate closure under set -e (FOUND-05)
INPUT=$(cat || true)

# Resolve plugin root BEFORE any cd — script-relative paths are unstable after cd (FOUND-11)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"

# Resolve project root from stdin's cwd field (FOUND-05; closes CONCERNS #7)
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$HOOK_CWD" ] && cd "$HOOK_CWD" 2>/dev/null || true

# Live FS scan — agents/skills enumerated at runtime, never hardcoded (FOUND-11; closes CONCERNS #8)
LC_ALL=C
AGENTS_LIST=$(find "$PLUGIN_ROOT/agents" -maxdepth 1 -name '*.md' -not -name '_*' -not -name 'README.md' -exec basename {} .md \; 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')
SKILLS_LIST=$(find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d -not -name '_*' -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')
[ -z "$AGENTS_LIST" ] && AGENTS_LIST="(none — plugin root not found)"
[ -z "$SKILLS_LIST" ] && SKILLS_LIST="(none — plugin root not found)"

# Quality gates from canonical SoT (FOUND-07; closes CONCERNS #9)
GATES_FILE="$PLUGIN_ROOT/config/quality-gates.txt"
if [ -f "$GATES_FILE" ]; then
  GATES_RENDERED=$(awk '{printf "%d. %s\n", NR, $0}' "$GATES_FILE")
else
  GATES_RENDERED="(quality-gates.txt missing — see CLAUDE.md)"
fi

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

# .planning/STATE.md detection (HOOK-05) — same parser as session-start.sh
STATE_HINT=""
if [ -f ".planning/STATE.md" ]; then
  STATE_PHASE=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^milestone:/ {sub(/^milestone:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
  STATE_STATUS=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^status:/ {sub(/^status:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
  STATE_STOPPED=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^stopped_at:/ {sub(/^stopped_at:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
  [ -z "$STATE_PHASE" ] && STATE_PHASE=$(grep -E '^Phase: ' .planning/STATE.md 2>/dev/null | head -1 | sed 's/^Phase: *//' || true)
  [ -z "$STATE_STATUS" ] && STATE_STATUS=$(grep -E '^Status: ' .planning/STATE.md 2>/dev/null | head -1 | sed 's/^Status: *//' || true)
  if [ -n "$STATE_PHASE" ] || [ -n "$STATE_STATUS" ]; then
    STATE_HINT="Active: ${STATE_PHASE:-unknown} | Status: ${STATE_STATUS:-unknown}"
    [ -n "$STATE_STOPPED" ] && STATE_HINT="${STATE_HINT} | Last: ${STATE_STOPPED}"
  fi
fi

# v1.x .claude-pipeline/ detection — deprecation note only (HOOK-05 downgrade)
PIPELINE_STATE=""
if [ -d ".claude-pipeline" ]; then
  PIPELINE_STATE="[v1.x] .claude-pipeline/ detected. Run /mission to migrate."
fi

# Build the context injection (FOUND-04; closes CONCERNS #6)
STATE_LINE_TEXT=""
[ -n "$STATE_HINT" ] && STATE_LINE_TEXT="
${STATE_HINT}"
PIPELINE_LINE_TEXT=""
[ -n "$PIPELINE_STATE" ] && PIPELINE_LINE_TEXT="
${PIPELINE_STATE}"

# Convert space-separated lists to comma-separated `/skill` / `@agent` forms (bash 3.2 portable)
SKILLS_FORMATTED="/${SKILLS_LIST// /, /}"
AGENTS_FORMATTED="@${AGENTS_LIST// /, @}"

CONTEXT_BLOCK="CONTEXT RESTORED AFTER COMPACTION:

${CONTEXT}${STATE_LINE_TEXT}${PIPELINE_LINE_TEXT}

Quality Gates (canonical, from config/quality-gates.txt — ALL must pass before completing any task):
${GATES_RENDERED}

Available Skills (from filesystem): ${SKILLS_FORMATTED}
Available Agents (from filesystem): ${AGENTS_FORMATTED}
Workflow: /godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship

Refer to CLAUDE.md for full workflow phases and coding standards."

jq -n --arg ctx "$CONTEXT_BLOCK" \
  '{hookSpecificOutput: {hookEventName: "PostCompact", additionalContext: $ctx}}'
