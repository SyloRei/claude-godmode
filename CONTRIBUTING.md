# Contributing to Claude God-Mode

Thanks for your interest in improving Claude God-Mode. This project grows through community contributions -- new agents, skills, hooks, and refinements to existing ones.

## Contribution Paths

### New Agent

1. Create `agents/<name>.md` with a system prompt
2. Define the agent's model, permissions, and purpose in the frontmatter
3. Add a routing entry in `CLAUDE.md` under "When to Use What"

### New Skill

1. Create `skills/<name>/SKILL.md` with the skill definition
2. Include: trigger command, description, step-by-step workflow, and quality gate requirements
3. Add a routing entry in `CLAUDE.md` under "When to Use What"

### New Hook

1. Add your hook script to `hooks/` (e.g., `hooks/my-hook.sh`)
2. Register the hook in `hooks/hooks.json` with the appropriate trigger event
3. Keep hooks fast -- they run on every matching event

## Conventions

### Naming

- Agents: lowercase, hyphenated (e.g., `security-auditor.md`)
- Skills: lowercase, hyphenated directory with `SKILL.md` inside (e.g., `skills/plan-stories/SKILL.md`)
- Hooks: lowercase, hyphenated shell scripts (e.g., `session-start.sh`)

### Model Selection

- **Opus** -- for agents that write code or make decisions (`@writer`, `@executor`, `@reviewer`, `@architect`)
- **Sonnet** -- for read-only or research-oriented agents (`@researcher`, `@doc-writer`)

### Quality

- Every agent should have a clear, single responsibility
- Skills should enforce quality gates before completing
- Hooks should be idempotent and fail gracefully

## PR Process

1. Fork the repository
2. Create a feature branch (`git checkout -b add-my-agent`)
3. Make your changes
4. Test locally by running `./install.sh` and verifying your component works in Claude Code
5. Submit a pull request with a clear description of what you added and why

## Bug Reports

Found a bug? Open an issue at [github.com/sylorei/claude-godmode/issues](https://github.com/sylorei/claude-godmode/issues) with:

- What you expected to happen
- What actually happened
- Steps to reproduce
- Your Claude Code version and OS

## Questions?

Open a discussion or issue on GitHub. We're happy to help you get started.
