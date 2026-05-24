#!/usr/bin/env bash
set -euo pipefail

# claude-godmode uninstaller v2
# Targeted removal of known godmode files (no backup required)
# Supports plugin-mode (CLAUDE_PLUGIN_ROOT) and manual-mode

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
BACKUP_BASE="$CLAUDE_DIR/backups"
# Legacy (pre-v2) marker, plus the v2 persistent data-dir markers written by
# install.sh. On uninstall we remove the install markers so a later reinstall
# detects a clean state. (The data dir itself is left if it holds nothing else.)
LEGACY_VERSION_FILE="$CLAUDE_DIR/.claude-godmode-version"
PLUGIN_DATA_DIR="${CLAUDE_PLUGIN_DATA:-$CLAUDE_DIR/plugins/data/claude-godmode}"
REMOVED=0

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

# Remove a file if it exists, increment counter
remove_file() {
  local file="$1"
  if [ -f "$file" ]; then
    rm -f "$file"
    info "Removed $file"
    REMOVED=$((REMOVED + 1))
  fi
}

# Remove a directory if it exists, increment counter
remove_dir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    rm -rf "$dir"
    info "Removed $dir"
    REMOVED=$((REMOVED + 1))
  fi
}

# --- Mode detection ---
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  MODE="plugin"
else
  MODE="manual"
fi

echo ""
echo "  Claude God-Mode Uninstaller"
echo "  ==========================="
echo ""
info "Mode: ${MODE}"
echo ""

# --- Primary path: targeted removal of known godmode files ---

# 1. Remove rules
info "Removing godmode rules..."
if [ -d "$CLAUDE_DIR/rules" ]; then
  for rule in "$CLAUDE_DIR"/rules/godmode-*.md; do
    [ -f "$rule" ] && remove_file "$rule"
  done
fi

# Remove rules/ dir if empty after cleanup
if [ -d "$CLAUDE_DIR/rules" ] && [ -z "$(ls -A "$CLAUDE_DIR/rules" 2>/dev/null)" ]; then
  rmdir "$CLAUDE_DIR/rules"
  info "Removed empty rules/ directory"
fi

# 2. Remove version markers (legacy + v2 persistent data-dir markers)
remove_file "$LEGACY_VERSION_FILE"
remove_file "$PLUGIN_DATA_DIR/version"
remove_file "$PLUGIN_DATA_DIR/installed"
if [ -d "$PLUGIN_DATA_DIR" ] && [ -z "$(ls -A "$PLUGIN_DATA_DIR" 2>/dev/null)" ]; then
  rmdir "$PLUGIN_DATA_DIR"
  info "Removed empty plugin data dir"
fi

# 3. Manual-mode: also remove agents, skills, hooks installed by install.sh
if [ "$MODE" = "manual" ]; then
  info "Removing manual-mode files..."

  # Agents — read from repo source to get deterministic list
  if [ -d "$SCRIPT_DIR/agents" ]; then
    for agent in "$SCRIPT_DIR/agents/"*.md; do
      agent_name="$(basename "$agent")"
      remove_file "$CLAUDE_DIR/agents/$agent_name"
    done
  fi

  # Remove agents/ dir if empty
  if [ -d "$CLAUDE_DIR/agents" ] && [ -z "$(ls -A "$CLAUDE_DIR/agents" 2>/dev/null)" ]; then
    rmdir "$CLAUDE_DIR/agents"
    info "Removed empty agents/ directory"
  fi

  # Skills — read from repo source to get deterministic list
  if [ -d "$SCRIPT_DIR/skills" ]; then
    for skill_dir in "$SCRIPT_DIR/skills/"*/; do
      skill_name="$(basename "$skill_dir")"
      remove_dir "$CLAUDE_DIR/skills/$skill_name"
    done
  fi

  # Remove skills/ dir if empty
  if [ -d "$CLAUDE_DIR/skills" ] && [ -z "$(ls -A "$CLAUDE_DIR/skills" 2>/dev/null)" ]; then
    rmdir "$CLAUDE_DIR/skills"
    info "Removed empty skills/ directory"
  fi

  # Hooks — deterministic list matching install.sh (all 7 hook scripts + statusline)
  remove_file "$CLAUDE_DIR/hooks/session-start.sh"
  remove_file "$CLAUDE_DIR/hooks/post-compact.sh"
  remove_file "$CLAUDE_DIR/hooks/pre-tool-use.sh"
  remove_file "$CLAUDE_DIR/hooks/pre-tool-use-secrets.sh"
  remove_file "$CLAUDE_DIR/hooks/post-tool-use.sh"
  remove_file "$CLAUDE_DIR/hooks/user-prompt-submit.sh"
  remove_file "$CLAUDE_DIR/hooks/session-end.sh"
  remove_file "$CLAUDE_DIR/hooks/statusline.sh"

  # Remove hooks/ dir if empty
  if [ -d "$CLAUDE_DIR/hooks" ] && [ -z "$(ls -A "$CLAUDE_DIR/hooks" 2>/dev/null)" ]; then
    rmdir "$CLAUDE_DIR/hooks"
    info "Removed empty hooks/ directory"
  fi

  # bin/ helpers — deterministic list matching install.sh
  if [ -d "$SCRIPT_DIR/bin" ]; then
    for helper in "$SCRIPT_DIR/bin/"*; do
      remove_file "$CLAUDE_DIR/bin/$(basename "$helper")"
    done
  fi
  if [ -d "$CLAUDE_DIR/bin" ] && [ -z "$(ls -A "$CLAUDE_DIR/bin" 2>/dev/null)" ]; then
    rmdir "$CLAUDE_DIR/bin"
    info "Removed empty bin/ directory"
  fi

  # Commands — deterministic list matching install.sh
  if [ -d "$SCRIPT_DIR/commands" ]; then
    for cmd in "$SCRIPT_DIR/commands/"*.md; do
      remove_file "$CLAUDE_DIR/commands/$(basename "$cmd")"
    done
  fi
  if [ -d "$CLAUDE_DIR/commands" ] && [ -z "$(ls -A "$CLAUDE_DIR/commands" 2>/dev/null)" ]; then
    rmdir "$CLAUDE_DIR/commands"
    info "Removed empty commands/ directory"
  fi

  # Config the installer copied
  remove_file "$CLAUDE_DIR/config/quality-gates.txt"
  if [ -d "$CLAUDE_DIR/config" ] && [ -z "$(ls -A "$CLAUDE_DIR/config" 2>/dev/null)" ]; then
    rmdir "$CLAUDE_DIR/config"
    info "Removed empty config/ directory"
  fi
fi

# --- Secondary path: offer backup restoration if available ---
LATEST_BACKUP=""
if [ -d "$BACKUP_BASE" ]; then
  LATEST_BACKUP=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "godmode-*" 2>/dev/null | sort -r | head -1)
fi

if [ -n "$LATEST_BACKUP" ]; then
  echo ""
  info "Found backup: $LATEST_BACKUP"
  read -rp "  Restore settings.json from backup? [y/N] " restore_confirm || restore_confirm=""
  echo ""

  if [[ "$restore_confirm" == [yY] ]]; then
    if [ -f "$LATEST_BACKUP/settings.json" ]; then
      cp "$LATEST_BACKUP/settings.json" "$CLAUDE_DIR/settings.json"
      info "Restored settings.json from backup"
      REMOVED=$((REMOVED + 1))
    else
      warn "No settings.json in backup — skipping"
    fi

    if [ -d "$LATEST_BACKUP/rules" ]; then
      warn "Backup contains rules/ — skipping (already removed godmode rules)"
    fi
  fi
fi

# --- Summary ---
echo ""
if [ "$REMOVED" -gt 0 ]; then
  info "Uninstall complete. Removed ${REMOVED} item(s)."
else
  warn "No godmode files found to remove."
fi
echo ""
echo "  Your ~/.claude/CLAUDE.md was NOT touched."
echo "  Start a new Claude Code session to apply changes."
echo ""
