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

# Build the context injection
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostCompact",
    "additionalContext": "CONTEXT RESTORED AFTER COMPACTION:\n\n${CONTEXT}\n\nQuality Gates (canonical, from CLAUDE.md — ALL must pass before completing any task):\n1. Typecheck passes\n2. Lint passes\n3. All tests pass\n4. No hardcoded secrets\n5. No regressions\n6. Changes match requirements\n\nAvailable Skills: /prd, /plan-stories, /execute, /ship, /debug, /tdd, /refactor, /explore-repo\nAvailable Agents: @researcher, @reviewer, @architect, @writer, @executor, @security-auditor, @test-writer, @doc-writer\nFeature Pipeline: /prd → /plan-stories → /execute → /ship\n\nRefer to CLAUDE.md for full workflow phases and coding standards."
  }
}
EOF
