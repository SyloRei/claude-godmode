# External Integrations

**Analysis Date:** 2026-04-25

## APIs & External Services

**Claude Code CLI:**
- Primary integration target
- Hook points:
  - SessionStart hook - Triggered when user starts a Claude Code session
  - PostCompact hook - Triggered after context compaction in long sessions
  - StatusLine hook - Renders custom status display during session
- Communication: Shell command execution with JSON stdin/stdout
- Location: Hooks defined in `config/settings.template.json`, `hooks/hooks.json`

**GitHub CLI Integration:**
- Service: GitHub (via `gh` CLI)
- SDK/Client: GitHub CLI (`gh`)
- Usage: PR creation, repository operations
- Auth: GitHub credentials via system `gh` configuration
- Commands referenced: `gh pr create`
- Skill location: `skills/ship/SKILL.md`

## Git & Version Control

**Git:**
- Version control platform interaction
- Used by: hooks for branch detection, commit history parsing
- Commands:
  - `git log` - Retrieve recent commits for project context
  - `git branch --show-current` - Detect current branch
  - `git rev-parse --is-inside-work-tree` - Verify working directory
- Hook locations:
  - `hooks/session-start.sh` - Lines 47-51 (git history injection)
  - `hooks/post-compact.sh` - Line 36 (no direct git calls but pipeline state parsing)
  - `config/statusline.sh` - Line 31 (branch detection)

## Data Storage

**Local Pipeline Metadata:**
- Location: `.claude-pipeline/` directory
- Format: JSON
- Files:
  - `stories.json` - Feature pipeline state (stories, completion status, branch name, next story)
  - `prds/` - PRD files (feature requirements)
  - `explorations/` - Exploration reports from `/explore-repo` skill
- Access pattern: jq-based JSON parsing in hooks
- Parser examples: `hooks/session-start.sh` lines 58-96, `hooks/post-compact.sh` lines 37-60

**Configuration Storage:**
- `~/.claude/settings.json` - Merged during installation
- `~/.claude/rules/` - Rule files (godmode-*.md)
- `~/.claude/agents/` - Agent definitions (manual mode only)
- `~/.claude/skills/` - Skill definitions (manual mode only)
- `~/.claude/hooks/` - Hook scripts (manual mode only)

**File Storage:**
- Local filesystem only (no cloud storage)
- Project detection based on manifest files: `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `setup.py`, `Gemfile`

**Caching:**
- None detected
- All operations read and write files directly

## Authentication & Identity

**Git Authentication:**
- Handled by system Git configuration
- No embedded credentials

**GitHub Authentication:**
- Via `gh` CLI authentication
- Credentials managed by GitHub CLI (OAuth token stored in system credentials)
- Required for: `gh pr create` command in `/ship` skill

**Claude Code Authentication:**
- Implicit in Claude Code session context
- API keys/authentication handled by Claude Code itself

## Monitoring & Observability

**Error Tracking:**
- Not detected

**Logs:**
- Approach: Shell script echo-based logging with color codes
- Output format:
  - Info: `[+] message` (green)
  - Warning: `[!] message` (yellow)
  - Error: `[x] message` (red)
- Log location: `install.sh` lines 21-23 (logging functions)

**Session Monitoring:**
- Status line provides real-time feedback:
  - Model name
  - Context window usage percentage (with color coding: green <60%, yellow 60-80%, red 80%+)
  - Cost in USD
  - Project name
  - Git branch
- Script: `config/statusline.sh`

## CI/CD & Deployment

**Hosting:**
- GitHub - Repository hosting at https://github.com/sylorei/claude-godmode
- GitHub Releases - Distribution channel for installation

**Continuous Integration:**
- Not detected in current codebase
- GitHub issue templates present: `.github/ISSUE_TEMPLATE/` (feature_request.yml, bug_report.yml, config.yml)
- PR template: `.github/PULL_REQUEST_TEMPLATE.md` (manual workflow verification)

**Deployment Model:**
- Manual installation via `./install.sh` script
- Support for both plugin mode (served by Claude Code) and manual mode (direct copy to ~/.claude/)
- Installation creates backups before modifying existing configuration

**Version Management:**
- Semantic versioning (currently v1.4.1 for install script, v1.6.0 for plugin)
- Version tracking: `~/.claude/.claude-godmode-version` file

## Environment Configuration

**Required env vars:**
- None explicitly required for runtime
- `CLAUDE_PLUGIN_ROOT` - Optional, set by Claude Code in plugin mode (controls installation mode)

**Detected Project Variables** (in hooks):
- Package manager detection from lockfile presence: `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, `uv.lock`
- Test runner detection from `package.json` contents
- Monorepo detection from `pnpm-workspace.yaml`, `lerna.json`

**Secrets location:**
- No secrets stored in repository (per design)
- GitHub tokens: user's system `gh` credentials
- Git auth: system Git configuration
- Claude Code credentials: managed by Claude Code CLI

## Webhooks & Callbacks

**Incoming:**
- None detected

**Outgoing:**
- None detected

## Pipeline & Workflow Integration

**Claude Code Skill Interaction:**
- Skills reference GitHub CLI for PR creation: `skills/ship/SKILL.md` lines 86-103
- Skills parse `.claude-pipeline/stories.json` for workflow state
- Hooks provide context injection that skills rely on

**Pipeline Context:**
- Stored in `.claude-pipeline/stories.json`
- Fields parsed by hooks:
  - `stories` - Array of story objects
  - `passes` - Completion status per story
  - `branchName` - Feature branch name
  - `id` - Story identifier
- Shared context location: `skills/_shared/pipeline-context.md`

---

*Integration audit: 2026-04-25*
