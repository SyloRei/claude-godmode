# Technology Stack

**Analysis Date:** 2026-04-25

## Languages

**Primary:**
- Bash 3.2+ - Shell scripting for hooks, installation, and CLI automation
- Markdown - Documentation, rules, skills, and agent definitions
- JSON - Configuration (settings, hooks, plugin metadata)
- YAML - GitHub Actions issue templates and configuration

**Secondary:**
- jq - JSON querying in shell scripts (dependency for hooks)

## Runtime

**Environment:**
- Bash shell (Linux/macOS compatible)
- Claude Code CLI (v1.0+) - Primary target platform

**Package Manager:**
- Shell-based installation via `install.sh`
- No traditional package manager dependency

## Frameworks

**Core:**
- Claude Code Hook System - Session start, post-compaction hooks
- Claude Code Permissions Model - Capability-based security
- Claude Code Plugin Loader - Plugin-mode installation support

**Configuration:**
- JSON-based settings and hooks configuration
- Markdown-based rule documents and skill definitions

**Development Tools:**
- jq (JSON CLI tool) - Used in hooks and installation scripts for JSON parsing

## Key Dependencies

**Critical:**
- `jq` - Required for configuration merging and pipeline status parsing in hooks
- `git` - Implicit dependency for Git-based projects (detected in hooks)
- `bash` - Core runtime for all shell scripts

**Detected Language Toolchains** (hooks auto-detect):
- Node.js/npm/pnpm/yarn/bun - For JavaScript/TypeScript projects
- Python/pip/uv - For Python projects
- Rust/cargo - For Rust projects
- Go/go - For Go projects
- Ruby/bundle - For Ruby projects

## Configuration

**Environment:**
- Installation location: `~/.claude/` directory
- Mode detection:
  - Plugin mode: served by Claude Code plugin loader (CLAUDE_PLUGIN_ROOT)
  - Manual mode: directly copied to ~/.claude/

**Configuration Files:**
- `config/settings.template.json` - Base settings (permissions, hooks, statusline)
- `hooks/hooks.json` - Hook definitions for plugin mode
- `.claude-plugin/plugin.json` - Plugin metadata and registry information

**Installation & Deployment:**
- `install.sh` (v1.4.1) - Main installation script
  - Handles migration from v1.x (CLAUDE.md → godmode-*.md rules)
  - Creates backups at ~/.claude/backups/godmode-[timestamp]/
  - Supports both plugin and manual mode
  - Requires jq preflight check
- `uninstall.sh` - Removal script
- Version tracking: `~/.claude/.claude-godmode-version`

## Build & Deployment Configuration

**Installation Steps:**
1. Verify jq is installed
2. Detect installation mode (plugin vs manual)
3. Backup existing rules and settings.json
4. Install rules to `~/.claude/rules/`
5. Merge settings.json (permissions, hooks, statusline)
6. For manual mode: copy agents, skills, hooks to `~/.claude/`
7. Write version file

**Provided Shell Hooks:**
- `hooks/session-start.sh` - Injects project context at session start
  - Detects project type (JavaScript, Python, Rust, Go, Ruby)
  - Reports package manager, test runner, monorepo status
  - Parses `.claude-pipeline/stories.json` for pipeline status
  - Provides project awareness to Claude
- `hooks/post-compact.sh` - Re-injects critical context after compaction
  - Restores project context and quality gates
  - Provides pipeline state and available skills/agents
- `config/statusline.sh` - Renders session status line with context usage, cost, model, branch

## Platform Requirements

**Development:**
- macOS or Linux
- Bash shell (system default or compatible replacement)
- jq (command-line JSON processor)
- Git (for version control aware projects)
- Claude Code installed and configured at ~/.claude/

**Production:**
- Target: Claude Code CLI (official installation medium)
- Deployment: GitHub releases + installation via ./install.sh
- Compatibility: macOS 10.12+, Linux with Bash 3.2+, Windows with WSL2

## Environment Variables

**Installation Time:**
- `CLAUDE_PLUGIN_ROOT` - Set by Claude Code plugin loader in plugin mode
- Determines installation mode and configuration approach

**Runtime (Hook Scripts):**
- Status line script receives JSON via stdin with session metadata (model, cost, context usage)
- Hooks receive JSON input via stdin from Claude Code

---

*Stack analysis: 2026-04-25*
