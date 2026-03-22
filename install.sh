#!/usr/bin/env bash
set -euo pipefail

# claude-godmode installer
# Copies agents, skills, hooks, and config to ~/.claude/
# Merges settings.json (additive — preserves existing entries)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backups/godmode-$TIMESTAMP"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

# --- Preflight ---
command -v jq >/dev/null 2>&1 || error "jq is required but not installed. Install it: brew install jq"
[ -d "$CLAUDE_DIR" ] || error "~/.claude/ directory not found. Is Claude Code installed?"

echo ""
echo "  Claude God-Mode Installer"
echo "  ========================="
echo ""

# --- Backup ---
info "Creating backup at $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

for item in agents skills hooks CLAUDE.md INSTRUCTIONS.md settings.json; do
  src="$CLAUDE_DIR/$item"
  if [ -e "$src" ]; then
    cp -r "$src" "$BACKUP_DIR/"
  fi
done

info "Backup complete"

# --- Agents ---
info "Installing agents (8)"
mkdir -p "$CLAUDE_DIR/agents"
cp "$SCRIPT_DIR/agents/"*.md "$CLAUDE_DIR/agents/"

# --- Skills ---
info "Installing skills (8)"
mkdir -p "$CLAUDE_DIR/skills"
for skill_dir in "$SCRIPT_DIR/skills/"*/; do
  skill_name="$(basename "$skill_dir")"
  mkdir -p "$CLAUDE_DIR/skills/$skill_name"
  cp -r "$skill_dir"* "$CLAUDE_DIR/skills/$skill_name/"
done

# --- Hooks ---
info "Installing hooks (3)"
mkdir -p "$CLAUDE_DIR/hooks"
cp "$SCRIPT_DIR/hooks/session-start.sh" "$CLAUDE_DIR/hooks/"
cp "$SCRIPT_DIR/hooks/post-compact.sh" "$CLAUDE_DIR/hooks/"
cp "$SCRIPT_DIR/config/statusline.sh" "$CLAUDE_DIR/hooks/"
chmod +x "$CLAUDE_DIR/hooks/"*.sh

# --- CLAUDE.md & INSTRUCTIONS.md ---
info "Installing CLAUDE.md and INSTRUCTIONS.md"
cp "$SCRIPT_DIR/config/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
cp "$SCRIPT_DIR/config/INSTRUCTIONS.md" "$CLAUDE_DIR/INSTRUCTIONS.md"

# --- Settings merge ---
info "Merging settings.json"
SETTINGS="$CLAUDE_DIR/settings.json"
TEMPLATE="$SCRIPT_DIR/config/settings.template.json"

if [ -f "$SETTINGS" ]; then
  # Merge permissions (union of arrays)
  # Merge hooks (add if not present)
  # Set statusLine
  # Preserve everything else
  MERGED=$(jq -s '
    .[0] as $existing |
    .[1] as $template |
    $existing * {
      statusLine: $template.statusLine,
      hooks: ($existing.hooks // {} | to_entries + ($template.hooks | to_entries) | group_by(.key) | map({key: .[0].key, value: (.[0].value)}) | from_entries),
      permissions: {
        allow: (($existing.permissions.allow // []) + ($template.permissions.allow // []) | unique)
      }
    }
  ' "$SETTINGS" "$TEMPLATE")
  echo "$MERGED" | jq '.' > "$SETTINGS"
else
  cp "$TEMPLATE" "$SETTINGS"
fi

# --- Done ---
echo ""
info "Installation complete!"
echo ""
echo "  Installed:"
echo "    - 8 agents (writer, executor, reviewer, researcher, architect, security-auditor, test-writer, doc-writer)"
echo "    - 8 skills (prd, plan-stories, execute, ship, debug, tdd, refactor, explore-repo)"
echo "    - 3 hooks (session-start, post-compact, statusline)"
echo "    - CLAUDE.md + INSTRUCTIONS.md"
echo "    - Settings merged (permissions, hooks, statusline)"
echo ""
echo "  Backup saved to: $BACKUP_DIR"
echo ""
echo "  Start a new Claude Code session to activate."
echo ""
