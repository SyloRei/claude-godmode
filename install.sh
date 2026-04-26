#!/usr/bin/env bash
set -euo pipefail

# claude-godmode installer v2
# Installs rules/ files to ~/.claude/rules/ (never touches CLAUDE.md)
# Supports plugin-mode (CLAUDE_PLUGIN_ROOT) and manual-mode (backward compat)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

# --- Customization preservation (FOUND-01) ---
ALL_REPLACE=0
KEEP_ALL=0

# Usage: prompt_overwrite SRC_FILE DEST_FILE TARGET_LABEL
# Returns: 0 = replace, 1 = skip
# Modifies session globals: ALL_REPLACE, KEEP_ALL
prompt_overwrite() {
  local src="$1" dest="$2" label="$3"

  # New file (no dest yet) → always copy, no prompt (no customization to lose)
  [ -f "$dest" ] || return 0

  # No diff → no prompt needed
  if diff -q "$src" "$dest" >/dev/null 2>&1; then
    return 0
  fi

  # Session-wide flags short-circuit
  [ "$ALL_REPLACE" -eq 1 ] && return 0
  [ "$KEEP_ALL" -eq 1 ] && return 1

  # Non-TTY: default to keep (safety bias)
  if [ ! -t 0 ]; then
    warn "[non-TTY] keeping customizations in $label: $(basename "$dest")"
    return 1
  fi

  # Interactive prompt loop
  while true; do
    echo ""
    warn "$label customized: $(basename "$dest")"
    read -rp "  [d]iff / [s]kip / [r]eplace / [a]ll-replace / [k]eep-all [k]: " choice || choice=""
    case "${choice:-k}" in
      d|D)
        diff -u "$dest" "$src" || true
        ;;
      s|S)
        info "  skipped"
        return 1
        ;;
      r|R)
        info "  replaced"
        return 0
        ;;
      a|A)
        ALL_REPLACE=1
        info "  replacing all customized files for the rest of this run"
        return 0
        ;;
      k|K|"")
        KEEP_ALL=1
        info "  keeping all customizations for the rest of this run"
        return 1
        ;;
      *)
        warn "  invalid choice; pick one of d/s/r/a/k"
        ;;
    esac
  done
}

# --- Backup rotation (FOUND-10: keep last 5) ---
# Bash 3.2 portable: alphabetical sort = chronological since timestamps are zero-padded.
prune_backups() {
  local dir="$1" keep="$2" count=0 excess=0
  [ -d "$dir" ] || return 0
  for d in "$dir"/godmode-*; do
    [ -d "$d" ] || continue
    count=$((count + 1))
  done
  [ "$count" -le "$keep" ] && return 0
  excess=$((count - keep))
  local i=0
  for d in "$dir"/godmode-*; do
    [ -d "$d" ] || continue
    i=$((i + 1))
    [ "$i" -gt "$excess" ] && break
    rm -rf "$d"
  done
}

# --- Preflight ---
command -v jq >/dev/null 2>&1 || error "jq is required but not installed. See: https://jqlang.github.io/jq/download/"

# --- Version single source of truth (FOUND-02) ---
PLUGIN_JSON="$SCRIPT_DIR/.claude-plugin/plugin.json"
[ -f "$PLUGIN_JSON" ] || error "plugin.json not found at $PLUGIN_JSON — install aborted"
VERSION="$(jq -r .version "$PLUGIN_JSON")"
[ -n "$VERSION" ] && [ "$VERSION" != "null" ] || error "plugin.json:.version is empty or null"

CLAUDE_DIR="$HOME/.claude"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backups/godmode-$TIMESTAMP"
VERSION_FILE="$CLAUDE_DIR/.claude-godmode-version"

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

# --- v1.x detection (FOUND-09: detection-only, never destructive) ---
if [ -f "$CLAUDE_DIR/CLAUDE.md" ] && grep -q "Quality Gates (Canonical" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
  warn "Detected v1.x CLAUDE.md — run /mission to migrate to the v2 workflow. (No files were changed.)"
fi
if [ -f "$CLAUDE_DIR/INSTRUCTIONS.md" ] && grep -q "Claude Code God-Mode System" "$CLAUDE_DIR/INSTRUCTIONS.md" 2>/dev/null; then
  warn "Detected v1.x INSTRUCTIONS.md — content lives in rules/. Remove manually if no longer needed."
fi
if [ -d "$CLAUDE_DIR/.claude-pipeline" ] || [ -d "./.claude-pipeline" ]; then
  warn "Detected .claude-pipeline/ — run /mission to migrate to the v2 brief workflow. (No files were changed.)"
fi

# --- Rules (FOUND-01: per-file prompt_overwrite) ---
RULES_SRC="$SCRIPT_DIR/rules"
if [ -d "$RULES_SRC" ]; then
  RULES_COUNT=$(find "$RULES_SRC" -maxdepth 1 -name "godmode-*.md" | wc -l | tr -d ' ')
  info "Installing rules (${RULES_COUNT} files)"
  mkdir -p "$CLAUDE_DIR/rules"
  for rule in "$RULES_SRC"/godmode-*.md; do
    [ -f "$rule" ] || continue
    rule_name="$(basename "$rule")"
    dest="$CLAUDE_DIR/rules/$rule_name"
    if prompt_overwrite "$rule" "$dest" "rules"; then
      cp "$rule" "$dest"
    fi
  done
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

# --- Manual-mode extras (agents, skills, hooks) — per-file prompt_overwrite (FOUND-01) ---
if [ "$MODE" = "manual" ]; then
  # Agents
  AGENT_COUNT=$(find "$SCRIPT_DIR/agents" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  info "Installing agents (${AGENT_COUNT})"
  mkdir -p "$CLAUDE_DIR/agents"
  for agent in "$SCRIPT_DIR/agents/"*.md; do
    [ -f "$agent" ] || continue
    agent_name="$(basename "$agent")"
    dest="$CLAUDE_DIR/agents/$agent_name"
    if prompt_overwrite "$agent" "$dest" "agents"; then
      cp "$agent" "$dest"
    fi
  done

  # Skills (directories — walk each file inside)
  SKILL_COUNT=$(find "$SCRIPT_DIR/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  info "Installing skills (${SKILL_COUNT})"
  mkdir -p "$CLAUDE_DIR/skills"
  for skill_dir in "$SCRIPT_DIR/skills/"*/; do
    skill_name="$(basename "$skill_dir")"
    mkdir -p "$CLAUDE_DIR/skills/$skill_name"
    for f in "$skill_dir"*; do
      [ -f "$f" ] || continue
      f_name="$(basename "$f")"
      dest="$CLAUDE_DIR/skills/$skill_name/$f_name"
      if prompt_overwrite "$f" "$dest" "skills/$skill_name"; then
        cp "$f" "$dest"
      fi
    done
  done

  # Hooks (3 files: session-start.sh, post-compact.sh, statusline.sh)
  info "Installing hooks (3)"
  mkdir -p "$CLAUDE_DIR/hooks"
  for hook_pair in \
    "$SCRIPT_DIR/hooks/session-start.sh:$CLAUDE_DIR/hooks/session-start.sh" \
    "$SCRIPT_DIR/hooks/post-compact.sh:$CLAUDE_DIR/hooks/post-compact.sh" \
    "$SCRIPT_DIR/config/statusline.sh:$CLAUDE_DIR/hooks/statusline.sh"; do
    src="${hook_pair%%:*}"
    dest="${hook_pair##*:}"
    [ -f "$src" ] || continue
    if prompt_overwrite "$src" "$dest" "hooks"; then
      cp "$src" "$dest"
      chmod +x "$dest"
    fi
  done
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
