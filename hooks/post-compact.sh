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

# Detect pipeline state
PIPELINE_STATE=""
PIPELINE_DIR=".claude-pipeline"

if [ -d "$PIPELINE_DIR" ]; then
  if command -v jq > /dev/null 2>&1; then
    STORIES_FILE="${PIPELINE_DIR}/stories.json"
    if [ -f "$STORIES_FILE" ]; then
      # Parse stories.json — fall back to generic message on malformed JSON
      TOTAL=$(jq '.stories | length' "$STORIES_FILE" 2>/dev/null) || TOTAL=""
      DONE=$(jq '[.stories[] | select(.passes == true)] | length' "$STORIES_FILE" 2>/dev/null) || DONE=""
      BRANCH_NAME=$(jq -r '.branchName // empty' "$STORIES_FILE" 2>/dev/null) || BRANCH_NAME=""
      NEXT_STORY=$(jq -r '[.stories[] | select(.passes == false)][0].id // empty' "$STORIES_FILE" 2>/dev/null) || NEXT_STORY=""

      if [ -n "$TOTAL" ] && [ -n "$DONE" ] && [ "$TOTAL" -gt 0 ] 2>/dev/null; then
        PIPELINE_STATE="Active pipeline: ${DONE}/${TOTAL} stories complete"
        [ -n "$BRANCH_NAME" ] && PIPELINE_STATE="${PIPELINE_STATE} on branch '${BRANCH_NAME}'"
        [ -n "$NEXT_STORY" ] && PIPELINE_STATE="${PIPELINE_STATE}. Next: ${NEXT_STORY}"
      else
        # jq succeeded but returned unexpected values — treat as malformed
        PIPELINE_STATE="Pipeline: .claude-pipeline/ found."
      fi
    else
      PIPELINE_STATE="Pipeline: .claude-pipeline/ found."
    fi
  else
    # jq not available — generic fallback
    PIPELINE_STATE="Pipeline: .claude-pipeline/ found (install jq for detailed status)."
  fi
fi

# Build the context injection (FOUND-04; closes CONCERNS #6)
PIPELINE_LINE_TEXT=""
[ -n "$PIPELINE_STATE" ] && PIPELINE_LINE_TEXT="
${PIPELINE_STATE}"

# Convert space-separated lists to comma-separated `/skill` / `@agent` forms (bash 3.2 portable)
SKILLS_FORMATTED="/${SKILLS_LIST// /, /}"
AGENTS_FORMATTED="@${AGENTS_LIST// /, @}"

# Substrate-version context block — gates SoT integration is the next atomic commit (D-19)
CONTEXT_BLOCK="CONTEXT RESTORED AFTER COMPACTION:

${CONTEXT}${PIPELINE_LINE_TEXT}

Quality Gates (canonical, from config/quality-gates.txt — ALL must pass before completing any task):
${GATES_RENDERED}

Available Skills (from filesystem): ${SKILLS_FORMATTED}
Available Agents (from filesystem): ${AGENTS_FORMATTED}
Feature Pipeline: /prd → /plan-stories → /execute → /ship

Refer to CLAUDE.md for full workflow phases and coding standards."

jq -n --arg ctx "$CONTEXT_BLOCK" \
  '{hookSpecificOutput: {hookEventName: "PostCompact", additionalContext: $ctx}}'
