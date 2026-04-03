# Contributing to Claude God-Mode

Thanks for your interest in improving Claude God-Mode. This project grows through community contributions -- new agents, skills, hooks, rules, and refinements to existing ones.

## Contribution Paths

### New Agent

1. Create `agents/<name>.md` with a system prompt
2. Define the agent's model, permissions, and purpose in the frontmatter
3. Add `memory:` to the frontmatter -- choose the appropriate scope:
   - **project** -- the default for most agents. Codebase patterns, conventions, and findings are project-specific and useful for the whole team. Used by all current godmode agents.
   - **user** -- cross-project learnings. Use only when findings genuinely benefit the user regardless of which project they're in. Currently unused in godmode (all agents use project).
   - **local** -- sensitive or private findings. Use when memory may contain credentials, vulnerability details, or other data that should not be committed. Currently unused in godmode.
4. Consider additional frontmatter fields:
   - `effort: high` -- for agents where thoroughness is critical (reviewers, security, architecture)
   - `maxTurns: N` -- safety valve for agents that write code (prevents runaway token burn)
   - `disallowedTools: Write, Edit` -- enforce read-only mechanically on read-only agents
   - `background: true` -- for agents typically spawned for non-blocking parallel work
5. Add a routing entry in `rules/godmode-routing.md` under "When to Use What"

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

### Model Selection (Four-Tier Strategy)

Agents are assigned to one of four tiers based on task complexity and cost:

- **Opus + high effort** -- High-stakes read-only analysis requiring maximum thoroughness. These agents evaluate architecture and security where missed issues are costly.
  - `@architect`, `@security-auditor`
- **Opus + default effort** -- Code-writing agents that need Opus-level reasoning to produce correct implementations but don't need the thoroughness overhead.
  - `@writer`, `@executor`
- **Sonnet + high effort** -- Structured analysis and generation tasks. Sonnet handles these well when given high effort to be thorough.
  - `@reviewer`, `@test-writer`, `@doc-writer`
- **Sonnet + default effort** -- Background research and information gathering where speed and cost matter more than deep reasoning.
  - `@researcher`

**Decision tree for placing future agents:**

1. Does the agent write or modify code? -> Opus + default effort
2. Does the agent perform high-stakes read-only analysis (security, architecture)? -> Opus + high effort
3. Does the agent produce structured output (reviews, tests, docs)? -> Sonnet + high effort
4. Is the agent primarily research or information gathering? -> Sonnet + default effort

> **Note:** `effort: max` is an Opus-exclusive setting. Do not assign it to Sonnet agents. Most agents should use `high` or omit the field (default). Reserve `max` for edge cases where Opus needs to exhaust all reasoning before responding.

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
