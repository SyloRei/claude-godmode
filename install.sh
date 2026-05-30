#!/usr/bin/env bash
set -euo pipefail

# claude-godmode installer v2
# Installs rules/ files to the PRIVATE ~/.claude/godmode/rules/ (read by the
# SessionStart hook, NOT auto-loaded by Claude Code). Never touches CLAUDE.md.
# Supports plugin-mode (CLAUDE_PLUGIN_ROOT) and manual-mode (backward compat)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backups/godmode-$TIMESTAMP"

# --- Persistent install data (survives plugin updates) ---
# CLAUDE_PLUGIN_DATA (~/.claude/plugins/data/<id>/) persists across plugin
# updates, unlike CLAUDE_PLUGIN_ROOT which resets on every bump. The install
# marker and last-version-seen live here so they outlive upgrades. In manual
# mode the env var is unset, so we derive the canonical per-installation path.
PLUGIN_DATA_DIR="${CLAUDE_PLUGIN_DATA:-$CLAUDE_DIR/plugins/data/claude-godmode}"
VERSION_FILE="$PLUGIN_DATA_DIR/version"
INSTALL_MARKER="$PLUGIN_DATA_DIR/installed"
# Prior (pre-v2) version-marker location to migrate from, if present.
LEGACY_VERSION_FILE="$CLAUDE_DIR/.claude-godmode-version"

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
[ -d "$CLAUDE_DIR" ] || error "$HOME/.claude/ directory not found. Is Claude Code installed?"

# --- Version (single source of truth: .claude-plugin/plugin.json) ---
PLUGIN_MANIFEST="$SCRIPT_DIR/.claude-plugin/plugin.json"
[ -f "$PLUGIN_MANIFEST" ] || error "Plugin manifest not found: $PLUGIN_MANIFEST"
VERSION="$(jq -r '.version' "$PLUGIN_MANIFEST")"
[ -n "$VERSION" ] && [ "$VERSION" != "null" ] || error "No version found in $PLUGIN_MANIFEST"

# --- Persistent data dir + legacy marker migration ---
mkdir -p "$PLUGIN_DATA_DIR"
if [ -f "$LEGACY_VERSION_FILE" ] && [ ! -f "$VERSION_FILE" ]; then
  mv "$LEGACY_VERSION_FILE" "$VERSION_FILE"
  info "Migrated version marker to persistent data dir ($PLUGIN_DATA_DIR)"
elif [ -f "$LEGACY_VERSION_FILE" ] && [ -f "$VERSION_FILE" ]; then
  # Both present (e.g. legacy file reappeared from a checkout). The data-dir
  # copy is canonical; remove the stale legacy marker so it cannot confuse
  # future migrations.
  rm -f "$LEGACY_VERSION_FILE"
  info "Removed stale legacy version marker ($LEGACY_VERSION_FILE)"
fi

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

# --- Backup (settings.json only) ---
# Rules are no longer copied to ~/.claude/rules/, so there is nothing global to
# back up there; the private ~/.claude/godmode/rules/ copy is regenerated from
# source on every install and is never user-customized.
info "Creating backup at $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

if [ -f "$CLAUDE_DIR/settings.json" ]; then
  cp "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/settings.json"
fi

info "Backup complete"

# --- v1.x migration check ---
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  if grep -q "Quality Gates (Canonical" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
    echo ""
    warn "Found godmode v1.x CLAUDE.md"
    warn "Rules are now injected by the SessionStart hook (private copy in ~/.claude/godmode/rules/)"
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
    warn "Found stale v1.x INSTRUCTIONS.md (content now lives in rules/)"
    read -rp "  Remove it? (backed up first) [y/N] " instructions_confirm || instructions_confirm=""
    if [[ "$instructions_confirm" == [yY] ]]; then
      cp "$CLAUDE_DIR/INSTRUCTIONS.md" "$BACKUP_DIR/INSTRUCTIONS.md.v1-backup"
      rm "$CLAUDE_DIR/INSTRUCTIONS.md"
      info "Old INSTRUCTIONS.md backed up and removed"
    else
      info "Keeping old INSTRUCTIONS.md (you can remove it manually later)"
    fi
  fi
fi

# --- Rules (PRIVATE copy for the SessionStart hook) ---
# Rules are NOT copied to $CLAUDE_DIR/rules/ anymore (that path is auto-loaded
# by Claude Code and would double-inject). Instead they live in the pinned
# private path $CLAUDE_DIR/godmode/rules/, which the SessionStart hook reads via
# bin/godmode-rules. The copy is regenerated from source every install; there is
# no backup/restore or drift-detection — source is canonical.
RULES_SRC="$SCRIPT_DIR/rules"
PRIVATE_RULES_DIR="$CLAUDE_DIR/godmode/rules"
if [ -d "$RULES_SRC" ]; then
  RULES_COUNT=$(find "$RULES_SRC" -maxdepth 1 -name "godmode-*.md" | wc -l | tr -d ' ')
  info "Installing rules (${RULES_COUNT} files) to private path $PRIVATE_RULES_DIR"
  mkdir -p "$PRIVATE_RULES_DIR"
  cp "$RULES_SRC"/godmode-*.md "$PRIVATE_RULES_DIR/"
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
          (($existing.hooks // {}) | to_entries)
            + (($template.hooks // {}) | to_entries) |
          group_by(.key) |
          map({
            key: .[0].key,
            value: ([.[].value] | add | unique)
          }) |
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
  if [ -d "$CLAUDE_DIR/agents" ] || [ -d "$CLAUDE_DIR/skills" ]; then
    warn "Manual-mode will overwrite existing agents and skills in ~/.claude/"
    warn "Customizations to agent/skill files will be lost (backed up above)"
  fi

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

  # Hooks — copy the full event-set scripts so manual mode matches plugin mode.
  # 8 hook scripts + statusline.sh.
  info "Installing hooks (8)"
  mkdir -p "$CLAUDE_DIR/hooks"
  cp "$SCRIPT_DIR/hooks/session-start.sh" "$CLAUDE_DIR/hooks/"
  cp "$SCRIPT_DIR/hooks/post-compact.sh" "$CLAUDE_DIR/hooks/"
  cp "$SCRIPT_DIR/hooks/pre-tool-use.sh" "$CLAUDE_DIR/hooks/"
  cp "$SCRIPT_DIR/hooks/pre-tool-use-secrets.sh" "$CLAUDE_DIR/hooks/"
  cp "$SCRIPT_DIR/hooks/post-tool-use.sh" "$CLAUDE_DIR/hooks/"
  cp "$SCRIPT_DIR/hooks/user-prompt-submit.sh" "$CLAUDE_DIR/hooks/"
  cp "$SCRIPT_DIR/hooks/session-end.sh" "$CLAUDE_DIR/hooks/"
  cp "$SCRIPT_DIR/hooks/stop-ac-gate.sh" "$CLAUDE_DIR/hooks/"
  cp "$SCRIPT_DIR/config/statusline.sh" "$CLAUDE_DIR/hooks/"
  chmod +x "$CLAUDE_DIR/hooks/"*.sh

  # Canonical config the skills/hooks read at runtime (manual-mode path).
  info "Installing config"
  mkdir -p "$CLAUDE_DIR/config"
  cp "$SCRIPT_DIR/config/quality-gates.txt" "$CLAUDE_DIR/config/"

  # bin/ helpers — required by the workflow spine (skills + hooks call
  # godmode-state). Without these, manual-mode state tracking is broken.
  BIN_COUNT=$(find "$SCRIPT_DIR/bin" -maxdepth 1 -type f | wc -l | tr -d ' ')
  info "Installing bin helpers (${BIN_COUNT})"
  mkdir -p "$CLAUDE_DIR/bin"
  cp "$SCRIPT_DIR/bin/"* "$CLAUDE_DIR/bin/"
  chmod +x "$CLAUDE_DIR/bin/"*

  # Commands — /godmode is a command file (not a skill); copy it so the
  # orientation command is available in manual mode.
  CMD_COUNT=$(find "$SCRIPT_DIR/commands" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  info "Installing commands (${CMD_COUNT})"
  mkdir -p "$CLAUDE_DIR/commands"
  cp "$SCRIPT_DIR/commands/"*.md "$CLAUDE_DIR/commands/"
fi

# --- Persistent install marker + last-version-seen ---
echo "$VERSION" > "$VERSION_FILE"
echo "$TIMESTAMP" > "$INSTALL_MARKER"

# --- Done ---
echo ""
info "Installation complete! (v${VERSION})"
echo ""
echo "  Installed:"
if [ -d "$RULES_SRC" ]; then
  echo "    - ${RULES_COUNT} rules (godmode-*.md in ~/.claude/godmode/rules/, injected by SessionStart hook)"
fi
echo "    - Settings merged (permissions, hooks, statusline)"

if [ "$MODE" = "manual" ]; then
  echo "    - ${AGENT_COUNT} agents"
  echo "    - ${SKILL_COUNT} skills"
  echo "    - 8 hooks (session-start, post-compact, pre-tool-use, pre-tool-use-secrets, post-tool-use, user-prompt-submit, session-end, stop-ac-gate) + statusline"
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
