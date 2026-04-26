#!/usr/bin/env bash
# scripts/check-frontmatter.sh
# Linter for agents/*.md frontmatter. Pure bash + grep + jq + awk. Bash 3.2 portable.
# Exit 0 on success; exit 1 on any failure with file:rule:evidence on stderr.
# CI gate (Phase 5 wires this into GitHub Actions; Phase 3 wires it into PreToolUse hook).
# Convention authority: rules/godmode-routing.md ## Effort Tier Policy + Connects-to Convention.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$REPO_ROOT/agents"

[ -d "$AGENTS_DIR" ] || { echo "[x] agents/ directory not found at $AGENTS_DIR"; exit 1; }
command -v grep >/dev/null 2>&1 || { echo "[x] grep required"; exit 1; }
command -v awk >/dev/null 2>&1 || { echo "[x] awk required"; exit 1; }

FAILED=0
report_fail() {
  echo "[!] $1: $2: $3" >&2
  FAILED=$((FAILED + 1))
}

# Extract value of a YAML scalar key from frontmatter block.
# Usage: yaml_get FILE KEY
# Returns: the value (everything after `KEY:` until end-of-line, trimmed) or empty if not found.
yaml_get() {
  local file="$1" key="$2"
  awk -v key="$key" '
    /^---$/ { count++; if (count == 2) exit; next }
    count == 1 && match($0, "^"key"[[:space:]]*:[[:space:]]*") {
      val = substr($0, RLENGTH + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      print val
      exit
    }
  ' "$file"
}

# Lint a single agent file.
lint_agent() {
  local file="$1"
  local rel="${file#"$REPO_ROOT/"}"
  local name desc model effort tools disallowed connects_section expected_name

  # 1. name field (must match filename)
  name=$(yaml_get "$file" "name")
  expected_name="$(basename "$file" .md)"
  if [ -z "$name" ]; then
    report_fail "$rel" "missing-name" "no name: field in frontmatter"
    return
  fi
  if [ "$name" != "$expected_name" ]; then
    report_fail "$rel" "name-mismatch" "name: $name (expected $expected_name)"
  fi

  # 2. description field
  desc=$(yaml_get "$file" "description")
  [ -n "$desc" ] || report_fail "$rel" "missing-description" "no description: field"

  # 3. model field — must be alias, never pinned
  model=$(yaml_get "$file" "model")
  if [ -z "$model" ]; then
    report_fail "$rel" "missing-model" "no model: field"
  else
    case "$model" in
      opus|sonnet|haiku) ;;
      claude-*)
        report_fail "$rel" "pinned-model-id" "model: $model (use alias: opus|sonnet|haiku)"
        ;;
      *)
        report_fail "$rel" "invalid-model" "model: $model (must be opus|sonnet|haiku)"
        ;;
    esac
  fi

  # 4. effort field — must be high or xhigh
  effort=$(yaml_get "$file" "effort")
  case "$effort" in
    high|xhigh) ;;
    "")
      report_fail "$rel" "missing-effort" "no effort: field (must be high or xhigh per godmode-routing.md)"
      ;;
    *)
      report_fail "$rel" "invalid-effort" "effort: $effort (must be high or xhigh)"
      ;;
  esac

  # 5. tools field
  tools=$(yaml_get "$file" "tools")
  [ -n "$tools" ] || report_fail "$rel" "missing-tools" "no tools: field"

  # 6. effort: xhigh + Write/Edit safety check (CR-01)
  disallowed=$(yaml_get "$file" "disallowedTools")
  if [ "$effort" = "xhigh" ]; then
    case "$tools" in
      *Write*|*Edit*)
        case "$disallowed" in
          *Write*Edit*|*Edit*Write*) ;;
          *)
            report_fail "$rel" "xhigh-with-write" "effort: xhigh + Write/Edit in tools: but disallowedTools missing both (CR-01 — see rules/godmode-routing.md ## Effort Tier Policy)"
            ;;
        esac
        ;;
    esac
  fi

  # 7. ## Connects to section
  if ! grep -q '^## Connects to' "$file"; then
    report_fail "$rel" "missing-connects-to" "no '## Connects to' section in body (see rules/godmode-routing.md ## Connects-to Convention)"
  else
    connects_section=$(awk '/^## Connects to/{flag=1; next} /^## /{flag=0} flag' "$file")
    case "$connects_section" in
      *"**Upstream:**"*) ;;
      *) report_fail "$rel" "connects-no-upstream" "## Connects to section missing **Upstream:** bullet" ;;
    esac
    case "$connects_section" in
      *"**Downstream:**"*) ;;
      *) report_fail "$rel" "connects-no-downstream" "## Connects to section missing **Downstream:** bullet" ;;
    esac
  fi
}

# Walk all agent files (with optional explicit args for single-file linting).
LC_ALL=C
if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    [ -f "$arg" ] || { report_fail "$arg" "not-found" "file does not exist"; continue; }
    lint_agent "$arg"
  done
else
  for agent in "$AGENTS_DIR"/*.md; do
    [ -f "$agent" ] || continue
    case "$(basename "$agent")" in
      _*|README.md) continue ;;
    esac
    lint_agent "$agent"
  done
fi

if [ "$FAILED" -eq 0 ]; then
  if [ "$#" -gt 0 ]; then
    echo "[+] frontmatter clean ($# file(s) checked)"
  else
    COUNT=$(find "$AGENTS_DIR" -maxdepth 1 -name '*.md' -not -name '_*' -not -name 'README.md' | wc -l | tr -d ' ')
    echo "[+] frontmatter clean ($COUNT agents checked)"
  fi
  exit 0
else
  echo "[x] $FAILED frontmatter violation(s) — see above"
  exit 1
fi
