#!/usr/bin/env bash
set -euo pipefail

# claude-godmode installer v2
# Installs rules/ files to ~/.claude/rules/ (never touches CLAUDE.md)
# Supports plugin-mode (CLAUDE_PLUGIN_ROOT) and manual-mode (backward compat)

VERSION="1.4.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backups/godmode-$TIMESTAMP"
VERSION_FILE="$CLAUDE_DIR/.claude-godmode-version"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

# --- Preflight ---
command -v jq >/dev/null 2>&1 || error "jq is required but not installed. See: https://jqlang.github.io/jq/download/"
[ -d "$CLAUDE_DIR" ] || error "~/.claude/ directory not found. Is Claude Code installed?"

# --- Mode detection ---
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  MODE="plugin"
else
  MODE="manual"
fi

echo ""
echo "  Claude God-Mode Installer v${VERSION}"
echo "  ===================================="
echo ""
info "Mode: ${MODE}"
echo ""

# --- Backup (rules/ and settings.json only) ---
info "Creating backup at $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

if [ -d "$CLAUDE_DIR/rules" ]; then
  cp -r "$CLAUDE_DIR/rules" "$BACKUP_DIR/rules"
fi
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  cp "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/settings.json"
fi

info "Backup complete"

# --- v1.x migration check ---
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  if grep -q "Quality Gates (Canonical" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
    echo ""
    warn "Found godmode v1.x CLAUDE.md"
    warn "Your rules are now in ~/.claude/rules/godmode-*.md"
    echo ""
    read -rp "  Remove the old CLAUDE.md? (backed up first) [y/N] " migrate_confirm || migrate_confirm=""
    echo ""
    if [[ "$migrate_confirm" == [yY] ]]; then
      # Back up the old CLAUDE.md before removing
      cp "$CLAUDE_DIR/CLAUDE.md" "$BACKUP_DIR/CLAUDE.md.v1-backup"
      rm "$CLAUDE_DIR/CLAUDE.md"
      info "Old CLAUDE.md backed up and removed"
    else
      info "Keeping old CLAUDE.md (you can remove it manually later)"
    fi
  fi
fi

# Also check for stale INSTRUCTIONS.md from v1.x
if [ -f "$CLAUDE_DIR/INSTRUCTIONS.md" ]; then
  if grep -q "Claude Code God-Mode System" "$CLAUDE_DIR/INSTRUCTIONS.md" 2>/dev/null; then
    cp "$CLAUDE_DIR/INSTRUCTIONS.md" "$BACKUP_DIR/INSTRUCTIONS.md.v1-backup"
    rm "$CLAUDE_DIR/INSTRUCTIONS.md"
    info "Removed stale v1.x INSTRUCTIONS.md (backed up)"
  fi
fi

# --- Rules ---
RULES_SRC="$SCRIPT_DIR/rules"
if [ -d "$RULES_SRC" ]; then
  RULES_COUNT=$(find "$RULES_SRC" -maxdepth 1 -name "godmode-*.md" | wc -l | tr -d ' ')
  info "Installing rules (${RULES_COUNT} files)"
  mkdir -p "$CLAUDE_DIR/rules"
  cp "$RULES_SRC"/godmode-*.md "$CLAUDE_DIR/rules/"
else
  warn "No rules/ directory found in source — skipping rules install"
fi

# --- Settings merge ---
info "Merging settings.json"
SETTINGS="$CLAUDE_DIR/settings.json"
TEMPLATE="$SCRIPT_DIR/config/settings.template.json"

if [ -f "$SETTINGS" ]; then
  if [ "$MODE" = "plugin" ]; then
    # Plugin mode: only merge permissions (hooks + statusLine handled by plugin loader)
    MERGED=$(jq -s '
      .[0] as $existing |
      .[1] as $template |
      $existing * {
        permissions: (($existing.permissions // {}) * {
          allow: (
            ($existing.permissions.allow // []) +
            ($template.permissions.allow // []) |
            unique
          )
        })
      }
    ' "$SETTINGS" "$TEMPLATE")
  else
    # Manual mode: merge permissions, hooks, and statusLine
    MERGED=$(jq -s '
      .[0] as $existing |
      .[1] as $template |
      $existing * {
        statusLine: $template.statusLine,
        hooks: (
          $existing.hooks // {} |
          to_entries + ($template.hooks | to_entries) |
          group_by(.key) |
          map({key: .[0].key, value: (.[0].value)}) |
          from_entries
        ),
        permissions: (($existing.permissions // {}) * {
          allow: (
            ($existing.permissions.allow // []) +
            ($template.permissions.allow // []) |
            unique
          )
        })
      }
    ' "$SETTINGS" "$TEMPLATE")
  fi
  echo "$MERGED" | jq '.' > "$SETTINGS"
else
  if [ "$MODE" = "manual" ]; then
    cp "$TEMPLATE" "$SETTINGS"
  else
    # Plugin mode fresh install: only permissions
    jq '{permissions: .permissions}' "$TEMPLATE" > "$SETTINGS"
  fi
fi

# --- Manual-mode extras (agents, skills, hooks) ---
if [ "$MODE" = "manual" ]; then
  # Agents
  AGENT_COUNT=$(find "$SCRIPT_DIR/agents" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  info "Installing agents (${AGENT_COUNT})"
  mkdir -p "$CLAUDE_DIR/agents"
  cp "$SCRIPT_DIR/agents/"*.md "$CLAUDE_DIR/agents/"

  # Skills
  SKILL_COUNT=$(find "$SCRIPT_DIR/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  info "Installing skills (${SKILL_COUNT})"
  mkdir -p "$CLAUDE_DIR/skills"
  for skill_dir in "$SCRIPT_DIR/skills/"*/; do
    skill_name="$(basename "$skill_dir")"
    mkdir -p "$CLAUDE_DIR/skills/$skill_name"
    cp -r "$skill_dir"* "$CLAUDE_DIR/skills/$skill_name/"
  done

  # Hooks
  info "Installing hooks (3)"
  mkdir -p "$CLAUDE_DIR/hooks"
  cp "$SCRIPT_DIR/hooks/session-start.sh" "$CLAUDE_DIR/hooks/"
  cp "$SCRIPT_DIR/hooks/post-compact.sh" "$CLAUDE_DIR/hooks/"
  cp "$SCRIPT_DIR/config/statusline.sh" "$CLAUDE_DIR/hooks/"
  chmod +x "$CLAUDE_DIR/hooks/"*.sh
fi

# --- Version file ---
echo "$VERSION" > "$VERSION_FILE"

# --- Done ---
echo ""
info "Installation complete! (v${VERSION})"
echo ""
echo "  Installed:"
if [ -d "$RULES_SRC" ]; then
  echo "    - ${RULES_COUNT} rules (godmode-*.md in ~/.claude/rules/)"
fi
echo "    - Settings merged (permissions, hooks, statusline)"

if [ "$MODE" = "manual" ]; then
  echo "    - ${AGENT_COUNT} agents"
  echo "    - ${SKILL_COUNT} skills"
  echo "    - 3 hooks (session-start, post-compact, statusline)"
  echo ""
  echo "  Mode: manual (agents, skills, hooks copied to ~/.claude/)"
else
  echo ""
  echo "  Mode: plugin (agents, skills, hooks served by plugin loader)"
fi

echo ""
echo "  Backup saved to: $BACKUP_DIR"
echo "  Version written to: $VERSION_FILE"
echo ""
echo "  Start a new Claude Code session to activate."
echo ""
