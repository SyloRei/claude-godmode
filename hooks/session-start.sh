#!/usr/bin/env bash
# Session start hook: inject project context so Claude starts with awareness.
# Detects project type, recent activity, and available toolchain.

set -euo pipefail

# Read stdin (hook input JSON) — consume it
cat > /dev/null

# Detect project type
PROJECT_INFO=""

if [ -f "package.json" ]; then
  PKG_MGR="npm"
  [ -f "pnpm-lock.yaml" ] && PKG_MGR="pnpm"
  [ -f "yarn.lock" ] && PKG_MGR="yarn"
  [ -f "bun.lockb" ] && PKG_MGR="bun"

  # Detect test runner
  TEST_RUNNER=""
  grep -q '"vitest"' package.json 2>/dev/null && TEST_RUNNER="vitest"
  grep -q '"jest"' package.json 2>/dev/null && TEST_RUNNER="jest"

  # Detect monorepo
  MONO=""
  [ -f "pnpm-workspace.yaml" ] && MONO=" (monorepo)"
  [ -f "lerna.json" ] && MONO=" (monorepo)"

  PROJECT_INFO="TypeScript/JavaScript${MONO} | pkg: ${PKG_MGR}"
  [ -n "$TEST_RUNNER" ] && PROJECT_INFO="${PROJECT_INFO} | test: ${TEST_RUNNER}"
elif [ -f "Cargo.toml" ]; then
  PROJECT_INFO="Rust | pkg: cargo | test: cargo test"
elif [ -f "go.mod" ]; then
  PROJECT_INFO="Go | test: go test"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  PY_MGR="pip"
  [ -f "uv.lock" ] && PY_MGR="uv"
  TEST=""
  [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] && TEST=" | test: pytest"
  PROJECT_INFO="Python | pkg: ${PY_MGR}${TEST}"
elif [ -f "Gemfile" ]; then
  PROJECT_INFO="Ruby | pkg: bundle"
fi

# Get recent git activity (last 3 commits, one line each)
GIT_RECENT=""
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  GIT_RECENT=$(git log --oneline -3 2>/dev/null | tr '\n' ' | ' | sed 's/ | $//')
  BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  GIT_RECENT="Branch: ${BRANCH} | Recent: ${GIT_RECENT}"
fi

# Build context
CONTEXT=""
[ -n "$PROJECT_INFO" ] && CONTEXT="Project: ${PROJECT_INFO}"
[ -n "$GIT_RECENT" ] && CONTEXT="${CONTEXT}\\n${GIT_RECENT}"

# Only inject if we detected something
if [ -n "$CONTEXT" ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${CONTEXT}\\n\\nPipeline: /prd → /plan-stories → /execute → /ship\\nUse CLAUDE.md 'When to Use What' section for skill/agent selection."
  }
}
EOF
else
  echo '{}'
fi
