# Contributing to Claude God-Mode

> For installation and usage, see [README.md](README.md). This file is the
> developer manual: how to add agents/skills/hooks/rules, run CI locally,
> and propose changes.

Thanks for your interest in improving Claude God-Mode. This project grows through community contributions -- new agents, skills, hooks, rules, and refinements to existing ones.

## Contribution Paths

### New Agent

1. Create `agents/<name>.md` with a system prompt and YAML frontmatter
2. Set `model:` and `effort:` per the four-tier policy below (see Model Selection)
3. Add `memory:` to the frontmatter -- choose the appropriate scope:
   - **project** -- the default for most agents. Codebase patterns, conventions, and findings are project-specific and useful for the whole team. Used by all current godmode agents.
   - **user** -- cross-project learnings. Use only when findings genuinely benefit the user regardless of which project they're in. Currently unused in godmode.
   - **local** -- sensitive or private findings. Use when memory may contain credentials, vulnerability details, or other data that should not be committed. Currently unused in godmode.
4. Consider additional frontmatter fields:
   - `maxTurns: N` -- safety valve for agents that write code (prevents runaway token burn)
   - `disallowedTools: Write, Edit` -- enforce read-only mechanically on read-only agents
   - `background: true` -- for agents typically spawned for non-blocking parallel work
   - `isolation: worktree` -- required on every code-writing agent (`@executor`, `@writer`, `@test-writer`)
5. Add a routing entry in `rules/godmode-routing.md` under "When to Use What"
6. Run `bash scripts/check-frontmatter.sh` locally to confirm the linter is clean

### New Skill

1. Create `skills/<name>/SKILL.md` with the skill definition and YAML frontmatter
2. Include: `name:`, `description:` (≤1,536 chars combined with `when_to_use`), `argument-hint:` if the skill takes args, and `allowed-tools:` scoped to the minimum needed
3. Body: trigger command, description, step-by-step workflow, and quality gate requirements
4. Follow the conventions in `rules/godmode-skills.md` (frontmatter contract, Connects-to layout, Auto Mode detection, vocabulary discipline)
5. Run `bash scripts/check-vocab.sh` locally to confirm no forbidden vocabulary leaks into user-facing prose
6. Run `bash scripts/check-frontmatter.sh` locally to confirm the frontmatter linter is clean

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
| `godmode-routing.md` | Agent routing (which agent does what); model-selection summary |
| `godmode-skills.md` | Skill frontmatter contract, Connects-to layout, Auto Mode detection, vocabulary discipline |

### New Hook

1. Add your hook script to `hooks/` (e.g., `hooks/my-hook.sh`)
2. Register the hook in `hooks/hooks.json` with the appropriate trigger event
3. Keep hooks fast -- they run on every matching event

## File Structure (v2.0)

```
claude-godmode/
  .claude-plugin/        # plugin manifest (plugin.json — canonical version SoT)
  .github/workflows/     # CI (ci.yml: 5 lint gates + bats matrix on macos+ubuntu)
  agents/                # 12 v2 agents (*.md with model/effort/memory frontmatter)
  bin/                   # bare commands installed onto PATH (e.g., godmode-state)
  commands/              # /godmode entry point (single user-facing command file)
  config/                # settings template, statusline, canonical quality gates
    quality-gates.txt    #   `config/quality-gates.txt` is the single source of truth for the 6 commit-time gates
    settings.template.json #   merged into ~/.claude/settings.json on install
    statusline.sh        #   shipped statusline (cost + context + workflow status)
  hooks/                 # hook scripts + hooks.json (PreToolUse, PostToolUse,
                         #   SessionStart, PostCompact, UserPromptSubmit)
  rules/                 # godmode-*.md -> ~/.claude/rules/ (one concern per file)
  scripts/               # CI-invoked lint scripts (check-vocab/parity/version-drift/
                         #   frontmatter — same scripts run locally and in CI)
  skills/                # 11 v2 user-invocable skills + 3 v1.x deprecation banners
  templates/.planning/   # planning artifact templates (PROJECT.md, ROADMAP.md, etc.)
  tests/                 # bats-core suite + fixtures
    install.bats         #   install -> uninstall -> reinstall round-trip + adversarial
    fixtures/branches/   #   adversarial-branch JSON fixtures (FOUND-04 regression)
  CHANGELOG.md           # Keep-a-Changelog format; canonical version source: plugin.json
  CLAUDE.md              # repo conventions; loaded into every Claude Code session
  CONTRIBUTING.md        # this file
  README.md              # marketing front door (≤500 lines, vocab-clean)
  install.sh             # installer (plugin-mode + manual-mode parity)
  uninstall.sh           # clean removal; refuses on version mismatch (FOUND-03)
```

Run any of these locally before opening a PR to mirror the CI gates:

```bash
bash scripts/check-version-drift.sh   # version SoT (.claude-plugin/plugin.json:.version)
bash scripts/check-frontmatter.sh     # agent + skill YAML frontmatter linter
bash scripts/check-parity.sh          # plugin-mode vs manual-mode hook bindings
bash scripts/check-vocab.sh           # forbidden vocab + 11-skill surface count
find . -name '*.sh' -not -path './.git/*' -exec shellcheck {} +
bats tests/install.bats               # install round-trip + adversarial fixtures
```

## Conventions

### Naming

- Agents: lowercase, hyphenated (e.g., `security-auditor.md`)
- Skills: lowercase, hyphenated directory with `SKILL.md` inside (e.g., `skills/plan-stories/SKILL.md`)
- Hooks: lowercase, hyphenated shell scripts (e.g., `session-start.sh`)
- Rules: `godmode-{concern}.md` (e.g., `godmode-coding.md`)

### Model Selection (v2 — three tiers, twelve agents)

Every agent declares `model:` (alias: `opus` / `sonnet` / `haiku`) and `effort:` (`high` or `xhigh`) in its frontmatter. Pinned model IDs are forbidden — aliases keep the upgrade path one config edit instead of twelve.

| Tier | Agents | Use for |
|------|--------|---------|
| `opus` + `effort: xhigh` | `@architect`, `@planner`, `@security-auditor`, `@verifier` | Design, audit, and read-only analysis where missed issues are costly. Read-only or read-mostly. |
| `opus` + `effort: high` | `@executor`, `@writer` | Code-writing. Opus-level reasoning, but `xhigh` skips rules on Opus 4.7 -- do NOT use it on `@executor` / `@writer` / `@test-writer`; use `high` there. |
| `sonnet` + `effort: high` | `@code-reviewer`, `@doc-writer`, `@researcher`, `@reviewer`, `@spec-reviewer`, `@test-writer` | Structured review, generation, and research tasks where Sonnet's strength profile fits. |

> **Pitfall:** `xhigh skips rules on Opus 4.7`. Anthropic's documented behavior makes the highest-effort tier ignore rule files on Opus 4.7 -- it is safe for read-only audit work (`@architect`, `@planner`, `@security-auditor`, `@verifier`) but unsafe for any agent that writes code. Code-writing agents must stay on `effort: high`.

**Decision tree for placing future agents:**

1. Does the agent write or modify code? -> `opus` + `effort: high` (e.g., `@executor`, `@writer`, `@test-writer` -- with `isolation: worktree`)
2. Does the agent perform high-stakes read-only analysis (architecture, security, planning, verification)? -> `opus` + `effort: xhigh`
3. Does the agent produce structured review, generation, or research output? -> `sonnet` + `effort: high`
4. Is the agent a trivially-bounded helper (classifier, format checker)? -> `haiku` (default effort)

For skill frontmatter conventions (the contract `/build`, `/plan`, etc. follow), see `rules/godmode-skills.md`. For agent routing ("which agent does what"), see `rules/godmode-routing.md`. The two rule files are split deliberately -- agent identity vs. skill plumbing.

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

### Tag protection (release process)

`v*` tags trigger marketplace re-indexing. Repository admins enable tag
protection in GitHub settings (Settings → Tags → New rule → `v*`).
Non-admin pushes of `v*` tags are rejected at the GitHub-API level. v2.0
relies on this UI setting; v2.x may add mechanical enforcement.

## Bug Reports

Found a bug? Open an issue at [github.com/sylorei/claude-godmode/issues](https://github.com/sylorei/claude-godmode/issues) with:

- What you expected to happen
- What actually happened
- Steps to reproduce
- Your Claude Code version and OS

## Questions?

Open a discussion or issue on GitHub. We're happy to help you get started.
