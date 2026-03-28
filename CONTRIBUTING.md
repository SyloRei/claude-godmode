# Contributing to Claude God-Mode

Thanks for your interest in improving Claude God-Mode. This project grows through community contributions -- new agents, skills, hooks, rules, and refinements to existing ones.

## Contribution Paths

### New Agent

1. Create `agents/<name>.md` with a system prompt
2. Define the agent's model, permissions, and purpose in the frontmatter
3. Add `memory:` to the frontmatter -- choose the appropriate scope:
   - **user** -- cross-project learnings (e.g., `@researcher`, `@architect`). Use when findings benefit the user regardless of which project they're in.
   - **project** -- team-shareable context (e.g., `@reviewer`, `@writer`, `@executor`). Use when learnings are specific to the current codebase and useful for the whole team.
   - **local** -- sensitive or private findings (e.g., `@security-auditor`). Use when memory may contain credentials, vulnerability details, or other data that should not be shared.
4. Add a routing entry in `rules/godmode-routing.md` under "When to Use What"

### New Skill

1. Create `skills/<name>/SKILL.md` with the skill definition
2. Include: trigger command, description, step-by-step workflow, and quality gate requirements
3. Add a routing entry in `rules/godmode-routing.md` under "When to Use What"

### Adding Rules

Rule files configure Claude's behavior and are installed to `~/.claude/rules/`.

1. Create `rules/godmode-<concern>.md` (e.g., `rules/godmode-security.md`)
2. Follow the naming convention: `godmode-{concern}.md` -- lowercase, hyphenated concern name
3. Keep each file focused on a single concern (target under 80 lines)
4. No YAML frontmatter -- global rules don't need it
5. The installer copies all `rules/godmode-*.md` files to `~/.claude/rules/` automatically

Existing rule files and their concerns:

| File | Concern |
|------|---------|
| `godmode-identity.md` | Agent identity and response style |
| `godmode-workflow.md` | Workflow phases and feature pipeline |
| `godmode-coding.md` | Coding standards, auto-detection, security |
| `godmode-quality.md` | Quality gates (single source of truth) |
| `godmode-git.md` | Git discipline |
| `godmode-testing.md` | Testing, debugging, refactoring protocols |
| `godmode-context.md` | Context management and continuous learning |
| `godmode-routing.md` | Agent/skill routing and model selection |

### New Hook

1. Add your hook script to `hooks/` (e.g., `hooks/my-hook.sh`)
2. Register the hook in `hooks/hooks.json` with the appropriate trigger event
3. Keep hooks fast -- they run on every matching event

## File Structure (v1.4)

```
claude-godmode/
  agents/           # Agent definitions (*.md with frontmatter)
  commands/         # Slash commands (e.g., /godmode)
  config/           # Settings template and statusline
    settings.template.json
    statusline.sh
  hooks/            # Hook scripts and hooks.json
  rules/            # Rule files (godmode-*.md) -> ~/.claude/rules/
  skills/           # Skill definitions (SKILL.md per directory)
  install.sh        # Installer (plugin-mode + manual-mode)
  uninstall.sh      # Clean removal of godmode artifacts
```

## Conventions

### Naming

- Agents: lowercase, hyphenated (e.g., `security-auditor.md`)
- Skills: lowercase, hyphenated directory with `SKILL.md` inside (e.g., `skills/plan-stories/SKILL.md`)
- Hooks: lowercase, hyphenated shell scripts (e.g., `session-start.sh`)
- Rules: `godmode-{concern}.md` (e.g., `godmode-coding.md`)

### Model Selection

- **Opus** -- for agents that write code or make decisions (`@writer`, `@executor`, `@reviewer`, `@architect`)
- **Sonnet** -- for read-only or research-oriented agents (`@researcher`, `@doc-writer`)

### Quality

- Every agent should have a clear, single responsibility
- Skills should enforce quality gates before completing
- Hooks should be idempotent and fail gracefully
- Rule files should cover exactly one concern

## PR Process

1. Fork the repository
2. Create a feature branch (`git checkout -b add-my-agent`)
3. Make your changes
4. Test locally:
   - **Plugin mode:** Install as a Claude Code plugin and verify your component works
   - **Manual mode:** Run `./install.sh` and verify rules are copied to `~/.claude/rules/`
5. Confirm rule files, hooks, and JSON pass quality checks (`shellcheck`, `jq`)
6. Submit a pull request with a clear description of what you added and why

## Bug Reports

Found a bug? Open an issue at [github.com/sylorei/claude-godmode/issues](https://github.com/sylorei/claude-godmode/issues) with:

- What you expected to happen
- What actually happened
- Steps to reproduce
- Your Claude Code version and OS

## Questions?

Open a discussion or issue on GitHub. We're happy to help you get started.
