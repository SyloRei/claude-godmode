#!/usr/bin/env bash
# Post-compaction hook: re-inject critical context that Claude loses during compaction.
# This ensures quality gates, available skills/agents, and project context survive long sessions.

set -euo pipefail

# Read stdin (hook input JSON) — we don't need it but must consume it
cat > /dev/null

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

# Build the context injection
PIPELINE_LINE=""
[ -n "$PIPELINE_STATE" ] && PIPELINE_LINE="\\n${PIPELINE_STATE}"
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostCompact",
    "additionalContext": "CONTEXT RESTORED AFTER COMPACTION:\n\n${CONTEXT}${PIPELINE_LINE}\n\nQuality Gates (canonical, from CLAUDE.md — ALL must pass before completing any task):\n1. Typecheck passes\n2. Lint passes\n3. All tests pass\n4. No hardcoded secrets\n5. No regressions\n6. Changes match requirements\n\nAvailable Skills: /prd, /plan-stories, /execute, /ship, /debug, /tdd, /refactor, /explore-repo\nAvailable Agents: @researcher, @reviewer, @architect, @writer, @executor, @security-auditor, @test-writer, @doc-writer\nFeature Pipeline: /prd → /plan-stories → /execute → /ship\n\nRefer to CLAUDE.md for full workflow phases and coding standards."
  }
}
EOF
