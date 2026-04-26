#!/usr/bin/env bash
# Session start hook: inject project context so Claude starts with awareness.
# Detects project type, recent activity, and available toolchain.

set -euo pipefail

# Read stdin (hook input JSON) once — tolerate closure under set -e (FOUND-05)
INPUT=$(cat || true)

# Resolve project root from stdin's cwd field (FOUND-05; closes CONCERNS #7)
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$HOOK_CWD" ] && cd "$HOOK_CWD" 2>/dev/null || true

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

# .planning/STATE.md detection (HOOK-04) — supports GSD YAML front matter or markdown body
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

# v1.x .claude-pipeline/ detection — deprecation note only (HOOK-04 downgrade)
PIPELINE_HINT=""
if [ -d ".claude-pipeline" ]; then
  PIPELINE_HINT="[v1.x] .claude-pipeline/ detected. Run /mission to migrate to v2 workflow."
fi

# Build context
CONTEXT=""
[ -n "$PROJECT_INFO" ] && CONTEXT="Project: ${PROJECT_INFO}"
[ -n "$GIT_RECENT" ] && CONTEXT="${CONTEXT}
${GIT_RECENT}"
[ -n "$STATE_HINT" ] && CONTEXT="${CONTEXT}
${STATE_HINT}"
[ -n "$PIPELINE_HINT" ] && CONTEXT="${CONTEXT}
${PIPELINE_HINT}"

# Only inject if we detected something
# JSON via jq -n --arg — never heredoc + variable interpolation (FOUND-04; closes CONCERNS #6)
if [ -n "$CONTEXT" ]; then
  PIPELINE_HINT_TEXT="${CONTEXT}

Workflow: /godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship
Run /godmode anytime to orient."
  jq -n --arg ctx "$PIPELINE_HINT_TEXT" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
  echo '{}'
fi
