# claude-godmode

This repo is the `claude-godmode` plugin for Claude Code — a packaged set of rules, agents, skills, hooks, statusline, and permissions installed into a user's `~/.claude/` so Claude Code itself behaves like a senior engineering team. v1.x is shipped; we are currently building **v2 — polish mature version**.

## Guiding principle (locked 2026-04-26 re-init)

Reference plugins (GSD/Get Shit Done, Superpowers, everything-claude-code) are **inspiration sources only, not adoption targets**. We read them freely to learn validated patterns and avoid known pitfalls. We do **not** vendor their code, adopt their directory shapes, mirror their command surfaces, or borrow their vocabulary. Output is ours.

If you're tempted to type `/discuss-phase`, `/plan-phase`, `/execute-phase`, `/gsd-*`, or use the words "phase" or "task" in workflow contexts — stop. Use the project's own naming (below).

## Workflow model: Project → Mission → Brief → Plan → Commit

| Concept | Lives in | Command |
|---|---|---|
| Project | `.planning/PROJECT.md` (persistent) | implicit |
| Mission | section of PROJECT.md + `.planning/ROADMAP.md` | `/mission` |
| Brief | `.planning/briefs/NN-name/BRIEF.md` (why + what + spec) | `/brief N` |
| Plan | `.planning/briefs/NN-name/PLAN.md` (tactical + verification) | `/plan N` |
| Commit | git log (atomic, gated) | `/build N` |

**Two artifact files per active brief: BRIEF.md and PLAN.md.** No EXECUTE.md, no TASK.md. The git log IS the execution log.

## User-facing slash commands (locked at 11, ≤12 cap, 1 reserved)

```
/godmode      → orient, "what now?" in 5 lines
/mission      → initialize / update PROJECT.md + ROADMAP.md
/brief N      → Socratic brief: why + what + spec → BRIEF.md
/plan N       → tactical breakdown → PLAN.md
/build N      → wave-based parallel execution, atomic commits
/verify N     → goal-backward verification, COVERED/PARTIAL/MISSING
/ship         → quality gates, push, gh pr create

Helpers (cross-cutting):
  /debug    /tdd    /refactor    /explore-repo
```

The arrow chain `/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship` is the single happy path. `/godmode` reads `.planning/STATE.md` and tells you the next command.

## Where things live

- **Source.** `rules/`, `agents/`, `skills/`, `commands/`, `hooks/`, `config/`, `install.sh`, `uninstall.sh`. Full layout: `.planning/codebase/STRUCTURE.md`.
- **Codebase map.** `.planning/codebase/` — STACK, ARCHITECTURE, STRUCTURE, CONVENTIONS, INTEGRATIONS, TESTING, CONCERNS. Factual analysis of v1.x baseline; preserved across re-init.
- **Project planning.** `.planning/PROJECT.md`, `REQUIREMENTS.md` (54 reqs), `ROADMAP.md` (5 briefs), `STATE.md`, `research/`, `config.json`. Per-brief artifacts at `.planning/briefs/NN-name/{BRIEF.md, PLAN.md}`.
- **`.planning/` is gitignored** (commit_docs=false in config.json). Already-tracked planning files stay tracked; new files force-add via `git add -f` when intentionally committing.

## How to work in this repo

This project's slash commands are still being built (that's the v2 milestone). Until then, follow the workflow shape manually:

1. **Orient** — read `.planning/STATE.md` to find the active brief.
2. **Brief** — for the active brief, read `BRIEF.md` for goal + success criteria + spec.
3. **Plan** — read `PLAN.md` for the tactical breakdown.
4. **Build** — execute one task at a time, atomic commit per task.
5. **Verify** — for each success criterion, check COVERED/PARTIAL/MISSING against the working tree + git log.
6. **Ship** — quality gates pass, all criteria COVERED, then push + PR.

Reference plugins (GSD, Superpowers, everything-claude-code) may be running in this session for tooling. **Do not adopt their vocabulary into the plugin we're building.** Use them as inspiration; ship our own shape.

## Hard constraints (from PROJECT.md)

- **Exactly 11 user-facing slash commands in v2 surface.** ≤12 cap; 1 reserved slot.
- **bash 3.2+ and `jq` only at runtime.** No Node, no Python, no helper binary, no SDK.
- **Plugin-mode == manual-mode UX parity.** Hook bindings, permissions, timeouts agree across both install paths; CI parity check enforces.
- **Atomic commits per workflow gate.** Never use `--no-verify`; never bypass quality gates.
- **macOS + Linux portability.** Bash 3.2+ compatible. WSL2 for Windows; native Windows shell out of scope.
- **No new mandatory runtime deps.** No telemetry. No network calls outside user-authorized tools.
- **MIT license, no copyleft deps.**
- **Single source of truth for version.** `.claude-plugin/plugin.json` is canonical; everything else reads from it at runtime via `jq`.
- **Reference scope.** Read references freely; copy nothing structural. No vocabulary, no directory shapes, no command names borrowed.

## Default model assignments (v2 — see `.planning/research/STACK.md`)

- `opus` (= 4.7) — `@architect`, `@security-auditor`, `@planner`, `@verifier`. Effort: `xhigh` for design / audit work.
- `opus` (= 4.7) — `@executor`, `@writer`. Effort: `high` (NOT `xhigh` — `xhigh` skips rules on Opus 4.7, see PITFALLS).
- `sonnet` (= 4.6) — `@reviewer`, `@spec-reviewer`, `@code-reviewer`, `@test-writer`, `@researcher`, `@doc-writer`. Effort: `high`.
- `haiku` (= 4.5) — fast, trivially-bounded helpers (e.g. classifiers).
- **Use aliases, not pinned IDs.** Locked in agent frontmatter and `rules/godmode-routing.md`.

## Quality gates (canonical — every commit must pass)

1. Typecheck (zero errors)
2. Lint (zero errors; `shellcheck` clean for any `.sh` change)
3. All tests pass (CI: bats-core smoke after Brief 5)
4. No hardcoded secrets (PreToolUse scan after Brief 3)
5. No regressions
6. Changes match requirements (REQ-IDs in commit message where applicable)

After Brief 3, gates are mechanically enforced by `PreToolUse` hook on `Bash(git commit *)` and `PostToolUse` surfacing of failed exit codes. Gates list moved to a single source (`config/quality-gates.txt` or one rule file) — not duplicated across rules + post-compact.

## Current focus

See `.planning/STATE.md`. As of 2026-04-26 (re-init): **Brief 1 — Foundation & Safety Hardening** is next. 11 requirements (FOUND-01..11).

## Two things never to do

1. **Never edit `~/.claude/settings.json` directly while developing this repo.** It's the user's, not the plugin's. The plugin merges into it via `install.sh`. Test changes via `./install.sh` into a temporary `$HOME` instead.
2. **Never commit `.claude/` or `.claude-pipeline/`.** Both are runtime/agent state and gitignored. `.planning/` is also gitignored (commit_docs=false) — but already-tracked planning files stay tracked; force-add new ones intentionally with `git add -f`.

---

For everything else, the rules in `rules/godmode-*.md` are canonical. They are loaded into every session by Claude Code's rules system; you do not need to re-read them inline.
