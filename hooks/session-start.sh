#!/usr/bin/env bash
# Session start hook: inject project context so Claude starts with awareness.
# Detects project type, recent activity, and available toolchain.

set -euo pipefail

# Read stdin (hook input JSON) — consume it
cat > /dev/null || true

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

# Surface recorded workflow state from .planning/STATE.md via bin/godmode-state.
# Resolve the helper from the plugin root, then ~/.claude, then the repo.
STATE_HINT=""
STATE_BIN=""
for cand in "${CLAUDE_PLUGIN_ROOT:-}/bin/godmode-state" "$HOME/.claude/bin/godmode-state" "bin/godmode-state"; do
  if [ -x "$cand" ]; then STATE_BIN="$cand"; break; fi
done
if [ -n "$STATE_BIN" ] && [ -f .planning/STATE.md ]; then
  ACTIVE=$("$STATE_BIN" get active_unit 2>/dev/null || true)
  STATUS=$("$STATE_BIN" get status 2>/dev/null || true)
  NEXT=$("$STATE_BIN" get next_command 2>/dev/null || true)
  if [ -n "$ACTIVE" ] || [ -n "$STATUS" ] || [ -n "$NEXT" ]; then
    STATE_HINT="Workflow: unit ${ACTIVE:-?} (${STATUS:-unknown})"
    [ -n "$NEXT" ] && STATE_HINT="${STATE_HINT}. Next: ${NEXT}"
  fi
fi

# Resolve the rules concatenator and capture the shipped godmode-*.md rules.
# Same resolution order as godmode-state: plugin root, ~/.claude, then the repo.
RULES=""
RULES_BIN=""
for cand in "${CLAUDE_PLUGIN_ROOT:-}/bin/godmode-rules" "$HOME/.claude/bin/godmode-rules" "bin/godmode-rules"; do
  if [ -x "$cand" ]; then RULES_BIN="$cand"; break; fi
done
if [ -n "$RULES_BIN" ]; then
  RULES=$("$RULES_BIN" 2>/dev/null || true)
fi

# Build context body (real newlines; jq -n encodes them safely below).
CONTEXT=""
[ -n "$PROJECT_INFO" ] && CONTEXT="Project: ${PROJECT_INFO}"
if [ -n "$GIT_RECENT" ]; then
  [ -n "$CONTEXT" ] && CONTEXT="${CONTEXT}
"
  CONTEXT="${CONTEXT}${GIT_RECENT}"
fi
if [ -n "$STATE_HINT" ]; then
  [ -n "$CONTEXT" ] && CONTEXT="${CONTEXT}
"
  CONTEXT="${CONTEXT}${STATE_HINT}"
fi

# Only inject if we detected something
if [ -n "$CONTEXT" ]; then
  BODY="${CONTEXT}

Workflow spine: /godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship
Run /godmode to orient. See rules/godmode-routing.md for skill/agent selection."
  if [ -n "$RULES" ]; then
    BODY="${BODY}

# Godmode rules
${RULES}"
  fi
  jq -n --arg ctx "$BODY" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $ctx
    }
  }'
else
  echo '{}'
fi
