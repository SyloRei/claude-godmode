# claude-godmode

This repo is the `claude-godmode` plugin for Claude Code — a packaged set of rules, agents, skills, hooks, statusline, and permissions installed into a user's `~/.claude/` so Claude Code itself behaves like a senior engineering team. v1.x is shipped; we are currently building **v2 — polish mature version**.

## Where things live

- **Source.** `rules/`, `agents/`, `skills/`, `commands/`, `hooks/`, `config/`, `install.sh`, `uninstall.sh`. The full layout is documented in `.planning/codebase/STRUCTURE.md`.
- **Codebase map.** `.planning/codebase/` — STACK, ARCHITECTURE, STRUCTURE, CONVENTIONS, INTEGRATIONS, TESTING, CONCERNS. Read these before making structural changes.
- **Project planning.** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, `.planning/research/`, `.planning/config.json`. Every phase mutates exactly one artifact, then commits atomically.

## How to work in this repo

GSD (Get Shit Done) is the structural reference. Use it.

1. **Start sessions with `/gsd-progress`** — get oriented to current phase, status, next action.
2. **Discuss a phase before planning.** `/gsd-discuss-phase N` runs Socratic context-gathering and writes `.planning/phases/<N>-<slug>/DISCUSS.md`.
3. **Plan a phase.** `/gsd-plan-phase N` produces an atomic, parallelizable task list with goal-backward verification in `PLAN.md`.
4. **Execute a phase.** `/gsd-execute-phase N` runs tasks (parallel where independent), commits per task atomically.
5. **Verify a phase.** `/gsd-verify-work N` reads the goal and reports COVERED / PARTIAL / MISSING per success criterion.
6. **Ship.** `/gsd-ship` only after verification is clean.

## Hard constraints (from PROJECT.md)

- **≤ 12 user-facing slash commands** in the published v2 surface. Internal orchestrators stay as subagents.
- **`jq` is the only mandatory runtime dependency.** Anything else is dev-time.
- **Plugin-mode == manual-mode UX.** Hook bindings, permissions, and the user experience must agree across both install paths.
- **Atomic commits per workflow gate.** Never use `--no-verify`; never bypass quality gates.
- **macOS + Linux portability.** Bash 3.2+ compatible. WSL2 for Windows.
- **No new mandatory runtime deps.** No telemetry. No network calls outside user-authorized tools.

## Default model assignments (v2 — see `.planning/research/STACK.md`)

- `opus` (= 4.7) — `@architect`, `@security-auditor`, `@planner`, `@verifier`. Effort: `xhigh` for design / `high` for code-touching work.
- `sonnet` (= 4.6) — `@reviewer`, `@spec-reviewer`, `@code-reviewer`, `@test-writer`, `@researcher`, `@doc-writer`. Effort: `high`.
- `haiku` (= 4.5) — fast, trivially-bounded helpers (e.g. classifiers).
- **Use aliases, not pinned IDs.** Listed in `agents/*.md` frontmatter.

## Quality gates (canonical — every commit must pass)

1. Typecheck (zero errors)
2. Lint (zero errors; `shellcheck` clean for any `.sh` change)
3. All tests pass (none yet; see `.planning/codebase/TESTING.md` and Phase 5 QUAL-05)
4. No hardcoded secrets
5. No regressions
6. Changes match requirements (REQ-IDs in commit message where applicable)

These are listed in `rules/godmode-quality.md` and (after Phase 2) enforced mechanically by a `PreToolUse` hook on `Bash(git commit *)`.

## Current focus

See `.planning/STATE.md`. As of 2026-04-25: **Phase 1 — Foundation and Safety Hardening** is next. 14 requirements (FOUND-01..10, HOOK-06..09).

## Two things never to do

1. **Never edit `~/.claude/settings.json` directly while developing this repo.** It's the user's, not the plugin's. The plugin merges into it via `install.sh`. Test changes via `./install.sh` into a temporary `$HOME` instead.
2. **Never commit `.claude/` or `.claude-pipeline/`.** Both are runtime/agent state. `.claude-pipeline/` is in `.gitignore`; `.claude/` is intentionally untracked. `.planning/` IS tracked — that's the planning artifact set.

---

For everything else, the rules in `rules/godmode-*.md` are canonical. They are loaded into every session by Claude Code's rules system; you do not need to re-read them inline.
