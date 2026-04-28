# claude-godmode

## What This Is

`claude-godmode` is a Claude Code plugin that ships rules, agents, skills, hooks, statusline, and permissions to make Claude Code behave like a senior engineering team out of the box. v1.x is shipped (8 agents, 8 skills, `/prd → /plan-stories → /execute → /ship` pipeline, plugin+manual install). This milestone — **v2: polish mature version** — replaces the v1.x pipeline with a single clear workflow, hardens every defect surfaced by the v1.x audit, modernizes the agent layer to the Claude Code 2026 capability surface (Opus 4.7, `effort: xhigh`, auto mode, plugin marketplace, native skills/agents/hooks), and incorporates the strongest patterns from three reference plugins (GSD, Superpowers, everything-claude-code) without becoming a clone of any of them.

The audience is solo developers and small engineering teams who want production-grade Claude Code behavior without assembling parts from multiple plugins, without learning a six-level vocabulary, and without feeling like they bought a kit.

## Core Value

**A single, clear workflow where every agent, skill, and tool is connected and named for the user's intent — best-in-class capability behind the simplest possible surface.**

If everything else fails, this must hold: a user installs `claude-godmode`, runs `/godmode`, and within five lines of output knows what to do next. They follow one obvious arrow chain to ship a feature. Every agent has one stated goal, every skill has one trigger, every hook has one safety contract. The chain is visible end-to-end, rendered from the live filesystem (no hardcoded lists, no registry edits to upgrade).

## Requirements

### Validated

<!-- Inherited from claude-godmode v1.x baseline. The v2 milestone modernizes these without removing the underlying capability. -->

- ✓ Rules-based configuration installed to `~/.claude/rules/godmode-*.md` — existing (8 rule files)
- ✓ 8 specialized subagents distributed (`@writer`, `@executor`, `@architect`, `@security-auditor`, `@reviewer`, `@test-writer`, `@doc-writer`, `@researcher`) — existing
- ✓ 8 user-invocable skills (`/prd`, `/plan-stories`, `/execute`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`) — existing
- ✓ `/godmode` slash command for quick reference and statusline setup — existing
- ✓ SessionStart hook injects project context — existing (`hooks/session-start.sh`)
- ✓ PostCompact hook re-injects critical context after compaction — existing (`hooks/post-compact.sh`)
- ✓ Statusline showing project / branch / model / context% / cost — existing (`config/statusline.sh`)
- ✓ Plugin-mode + manual-mode installer with backup, v1.x migration, version tracking — existing (`install.sh`)
- ✓ Targeted uninstaller with optional settings.json restore — existing (`uninstall.sh`)
- ✓ Permissions allow/deny lists merged into `~/.claude/settings.json` — existing (`config/settings.template.json`)
- ✓ Quality gates enforced by `/execute` (typecheck / lint / tests / no-secrets / no-regressions / matches-requirements) — existing
- ✓ MIT license, plugin metadata declared for Claude Code plugin registry — existing (`.claude-plugin/plugin.json`)

### Active

<!-- v2 milestone scope. Each item is a hypothesis until shipped and validated by `/gsd-verify-work`. Decomposed into 5 candidate phases below; full REQ-IDs in REQUIREMENTS.md. -->

**Workflow surface — the new arrow chain**
- [ ] User-facing surface is exactly: `/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship` plus 4 cross-cutting helpers (`/debug`, `/tdd`, `/refactor`, `/explore-repo`). 11 commands total, 1 reserved slot under a ≤12 cap.
- [ ] Two artifact files per active brief at `.planning/briefs/NN-name/{BRIEF.md, PLAN.md}`. No EXECUTE.md, no per-task files. The git log IS the execution log.
- [ ] `/godmode` answers "what now?" within five lines, project-state-aware (reads `.planning/STATE.md` if present, the live filesystem otherwise).
- [ ] Live filesystem indexing — agents, skills, briefs all enumerated at runtime; never hardcoded.

**Foundation — safety, hardening, version single source of truth**
- [ ] `.claude-plugin/plugin.json:.version` is canonical; `install.sh` reads it via `jq` at runtime; `commands/godmode.md` drops the literal version (statusline carries it).
- [ ] CI gate prevents version drift across `install.sh`, `commands/*.md`, `README.md`, `CHANGELOG.md`.
- [ ] Hooks emit valid JSON under adversarial branch names / commit messages / paths (`jq -n --arg`, no string interpolation).
- [ ] Hooks resolve project root from stdin's `cwd` field (Claude Code hook contract), not `pwd`.
- [ ] Hooks tolerate stdin drain failure under `set -euo pipefail`.
- [ ] Statusline does a single `jq` invocation per render.
- [ ] Installer prompts per-file (diff/skip/replace) before overwriting customized rules / agents / skills / hooks; non-TTY default keeps customizations.
- [ ] Backup rotation keeps last 5 in `~/.claude/backups/`.
- [ ] v1.x migration is detection-only — emits a one-line note pointing at `/mission`, never deletes user files.
- [ ] Uninstaller refuses on version mismatch unless `--force`.
- [ ] `shellcheck` clean across every shipped `*.sh` file.

**Agent layer modernization (Claude Code 2026 native)**
- [ ] Every agent uses model aliases (`opus`, `sonnet`, `haiku`) — never pinned numeric IDs.
- [ ] Code-writing agents use `effort: high` (NOT `xhigh` — Opus 4.7's `xhigh` skips rules per Anthropic's documented pitfall).
- [ ] Design / audit agents use `effort: xhigh` for deep analysis (`@architect`, `@security-auditor`, `@planner`, `@verifier`).
- [ ] Code-writing agents declare `isolation: worktree`; persistent learners declare `memory: project`.
- [ ] Every agent declares `maxTurns` defensively and a `Connects to:` line (upstream/downstream chain).
- [ ] New `@planner` agent (brief → plan tactical breakdown).
- [ ] New `@verifier` agent (read-only goal-backward verification).
- [ ] `@reviewer` split into `@spec-reviewer` (pre-execution) and `@code-reviewer` (post-execution) — two-stage read-only review.
- [ ] Frontmatter linter — pure-Bash script — runs in CI and refuses commits with malformed agent metadata.

**Hook layer expansion**
- [ ] `PreToolUse` hook blocks `Bash(git commit --no-verify*)`, `git commit -n*`, and similar quality-gate-bypass patterns.
- [ ] `PreToolUse` hook scans tool input for hardcoded secret patterns (AWS keys, GitHub PATs, common JWT shapes) and refuses with clear remediation.
- [ ] `PostToolUse` hook detects failed quality-gate exit codes from `bash -e` chains and surfaces them in the next assistant turn.
- [ ] `SessionStart` hook reads `.planning/STATE.md` if present and injects current-brief context (active brief #, status, next command).
- [ ] `PostCompact` hook reads agent / skill lists from the live filesystem (no hardcoded list) and reads quality gates from `config/quality-gates.txt`.
- [ ] Quality gates list lives in **one** source (`config/quality-gates.txt`) — not duplicated across rule files + post-compact.

**Skill layer rebuild + state management**
- [ ] All 11 user-facing skills rewritten or freshly authored to the new shape (`/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`).
- [ ] v1.x skill names (`/prd`, `/plan-stories`, `/execute`) get one-time deprecation notes that map old → new.
- [ ] Auto Mode awareness in every skill — detects "Auto Mode Active" system reminder and routes accordingly (auto-approves, picks recommended defaults, minimizes prompts).
- [ ] `/build` runs wave-based parallel execution with `run_in_background` plus a file-polling fallback for output races.
- [ ] Every public skill declares `Connects to: <upstream> → <this> → <downstream>`; `/godmode` renders the chain from frontmatter.
- [ ] State management via `.planning/STATE.md` — machine-mutated by skills, user-readable.

**Quality — CI, tests, parity, docs**
- [ ] GitHub Actions workflow runs `shellcheck`, frontmatter linter, version-drift check, plugin-vs-manual parity gate, vocabulary CI gate (no `phase`/`task` leakage in user-facing surface).
- [ ] `bats-core` smoke test exercises install → uninstall → reinstall → adversarial-input hook fixtures.
- [ ] README is under 500 lines, scannable, no duplication with CONTRIBUTING.md.
- [ ] CHANGELOG dated, with v2.0.0 release entry.
- [ ] Plugin marketplace metadata polished (description, keywords, repo links).

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- **Cross-runtime support (Codex, Gemini, OpenCode)** — Claude Code only. GSD does this; it adds enormous surface area for fractional benefit and dilutes our model-specific capabilities (Opus 4.7 `xhigh`, Claude Code hook contract).
- **Workspace / multi-repo orchestration** — single repo, single workflow, single mental model. GSD ships `/gsd-workspaces`; we don't.
- **External CLI dependency** — no `gsd-sdk`, no Node, no Python helpers. Bash 3.2+ and `jq` only at runtime. Adding any helper binary breaks the install story.
- **Native Windows shell** — WSL2 is the supported Windows path. Native Windows shell adds disproportionate maintenance burden.
- **Telemetry / phone-home / opt-in metrics** — none, ever. Trust is the brand.
- **Cloud features (ultraplan, remote review, scheduled background agents)** — out of scope. The user's runtime already provides `ScheduleWakeup` and `/schedule` if they want them.
- **Copyleft dependencies** — MIT license only.
- **Vendoring reference plugin code** — read GSD/Superpowers/everything-claude-code freely as inspiration; copy nothing structural. No vocabulary borrowed (we don't say "phase" or "task" in the user-facing surface), no directory shapes mirrored, no command names borrowed.

## Context

The v1.x baseline is a working Claude Code plugin. The codebase audit (preserved at `.planning-archive-v1/codebase/`) identified 9 High-severity defects:

1. Hand-edited customizations silently overwritten on reinstall (rules / agents / skills / hooks).
2. Hooks emit invalid JSON when branch names contain quotes, backslashes, newlines, or apostrophes.
3. The plugin advertises v1.6.0 but `install.sh` writes v1.4.1 to disk — three files claim three different versions.
4. Uninstaller doesn't compare installed version vs. script version — runs blindly.
5. Installer's v1.x migration prompts to `rm` user files (CLAUDE.md, INSTRUCTIONS.md) — destructive by default.
6. Hooks build JSON via heredoc string interpolation — not just adversarial-unsafe but also harder to debug.
7. Hooks use `cat > /dev/null` under `set -euo pipefail` — aborts on early stdin closure.
8. PostCompact hook hardcodes the agent/skill list — drifts when agents are added.
9. PostCompact hook duplicates the quality-gates list from CLAUDE.md — gates can drift between sources.

The bespoke v1 planning archive at `.planning-archive-v1/` (gitignored) holds the prior thinking from the 2026-04-26 re-init that drafted this v2 milestone in the project's own "brief" workflow. We've since adopted GSD's planning shape (this `.planning/`) for the v2 BUILD phase to leverage GSD's slash commands. **The plugin we ship still exposes briefs to its end users** — GSD's shape drives our development workflow; our brief shape drives the user-facing product. These are two different concerns.

Reference plugins running in this Claude Code session (GSD, Superpowers, everything-claude-code, plannotator, chrome-devtools-mcp, telegram, plugin-skills) are **inspiration sources**, not adoption targets. We read them freely to learn validated patterns and avoid known pitfalls. The plugin we ship is structurally independent.

## Constraints

- **Tech stack**: Bash 3.2+ and `jq` 1.6+ only at runtime. No Node, Python, helper binary, or SDK dependency.
- **Portability**: macOS + Linux. WSL2 for Windows. Bash 3.2-compatible patterns only (no `mapfile`, `[[ -v ]]`, `${var,,}`, associative arrays, GNU-only `head -n -N`).
- **Command surface**: Exactly 11 user-facing slash commands in v2. ≤12 cap. One reserved slot. Every command has one stated goal and one output artifact.
- **Atomic commits**: Per workflow gate (per-task in `/build`, per-step in installer). Never `--no-verify`. Never bypass quality gates.
- **Plugin-mode == manual-mode**: Hook bindings, permissions, timeouts must agree across both install paths. CI parity gate enforces.
- **License**: MIT, no copyleft deps. No telemetry. No network calls outside user-authorized tools.
- **Version single source of truth**: `.claude-plugin/plugin.json:.version` is canonical; everything else reads from it via `jq` at runtime.
- **Reference scope**: Read references freely; copy nothing structural. No vocabulary, directory shapes, or command names borrowed.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Adopt GSD's planning shape (this `.planning/` with `phases/` directory) for the v2 BUILD phase | User explicitly chose Path A: archive bespoke `.planning/` to `.planning-archive-v1/`, run `/gsd-new-project`, drive build via `/gsd-discuss-phase` etc. Lets us leverage GSD's tooling without forking it | — Pending |
| Bespoke v1 planning archived to `.planning-archive-v1/` (gitignored) | Preserves the 2026-04-26 re-init thinking — PROJECT.md, REQUIREMENTS.md (54 reqs), ROADMAP.md (5 briefs), STATE.md, codebase audit (7 files), research (5 files). One `mv` away from being restored if needed | — Pending |
| Plugin still ships briefs to end users (`/brief N`, `/plan N`, `/build N`) — GSD's "phase" vocabulary stays internal | The plugin we ship is structurally independent from GSD. Two different concerns: GSD's shape drives our dev workflow; our brief shape drives the user-facing product | — Pending |
| Code-writing agents use `effort: high`, design / audit at `effort: xhigh` | Opus 4.7 `xhigh` documented to skip rules — too risky for code-writing agents that need rule adherence. xhigh is fine for read-only design / audit work where rules carry less weight | — Pending |
| Reference plugins are inspiration only — copy nothing structural | Output is ours. Vendoring GSD's commands or Superpowers' shell would make us derivative; we'd compete on subset of GSD's surface area instead of focused capability | — Pending |
| 11 user-facing slash commands, ≤12 cap, 1 reserved | Surface area discipline is the design contract. Every command added is a maintenance commitment and a cognitive cost for the user | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition` or end-of-phase `/gsd-verify-work`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state (users, feedback, metrics)

---
*Last updated: 2026-04-29 — Phase 5 (Quality — CI, Tests, Docs Parity) complete. All 5 milestone phases delivered: substrate hardened, agent layer modernized, hook surface complete, user-facing skills/commands shipped, CI + bats + docs gated. Milestone v2.0.0 ready for merge → tag (D-27) → marketplace listing.*
