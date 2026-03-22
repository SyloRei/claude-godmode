#!/usr/bin/env bash
set -euo pipefail

# claude-godmode uninstaller
# Restores from the most recent godmode backup

CLAUDE_DIR="$HOME/.claude"
BACKUP_BASE="$CLAUDE_DIR/backups"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

echo ""
echo "  Claude God-Mode Uninstaller"
echo "  ==========================="
echo ""

# Find most recent backup
LATEST_BACKUP=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "godmode-*" 2>/dev/null | sort -r | head -1)

if [ -z "$LATEST_BACKUP" ]; then
  error "No godmode backup found in $BACKUP_BASE/. Cannot uninstall without a backup."
fi

info "Found backup: $LATEST_BACKUP"
echo ""
read -rp "  Restore from this backup? This will overwrite current config. [y/N] " confirm
echo ""

if [[ "$confirm" != [yY] ]]; then
  info "Cancelled."
  exit 0
fi

# --- Restore ---
for item in agents skills hooks CLAUDE.md INSTRUCTIONS.md settings.json; do
  src="$LATEST_BACKUP/$item"
  dest="$CLAUDE_DIR/$item"
  if [ -e "$src" ]; then
    info "Restoring $item"
    rm -rf "$dest"
    cp -r "$src" "$dest"
  else
    warn "No backup for $item — skipping (may not have existed before install)"
  fi
done

echo ""
info "Uninstall complete. Config restored from $LATEST_BACKUP"
echo ""
echo "  Start a new Claude Code session to activate restored config."
echo ""
