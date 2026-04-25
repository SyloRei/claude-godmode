# claude-godmode

## What This Is

`claude-godmode` is a Claude Code plugin that ships an opinionated, end-to-end engineering workflow — rules, agents, skills, hooks, statusline, and permissions — installed into a user's Claude Code config so Claude Code itself behaves like a senior engineering team. v1.x is shipped (8 agents, 8 skills, /prd→/plan-stories→/execute→/ship pipeline, rules-based config, SessionStart+PostCompact hooks, statusline, plugin+manual install modes). This milestone — **v2: polish mature version** — replaces the v1.x pipeline with our own opinionated workflow shape (Project → Mission → Brief → Plan → Commit), hardens hooks and the installer, and ships best-in-class capability behind a small, obvious command surface.

## Core Value

**A single, clear workflow where every agent, skill, and tool is connected and named for the user's intent — best-in-class capability behind the simplest possible surface.**

If everything else fails, this must hold: a user who installs claude-godmode gets one obvious workflow, runs it, and produces production-grade work — without assembling parts from three other plugins, without learning a six-level vocabulary, and without feeling like a kit.

## Requirements

### Validated

<!-- Inherited from existing claude-godmode v1.x baseline (see .planning/codebase/ map). -->

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
- ✓ Quality gates enforced by `/execute` — existing (typecheck / lint / tests / no-secrets / no-regressions / matches-requirements)
- ✓ MIT license, plugin metadata declared for Claude Code plugin registry — existing (`.claude-plugin/plugin.json`)

### Active

<!-- v2 milestone — re-derived from the new workflow model. Requirements get REQ-IDs in REQUIREMENTS.md. -->

**Workflow model — Project → Mission → Brief → Plan → Commit**
- [ ] User-facing surface is exactly the new arrow chain: `/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship`, plus 4 helpers (`/debug`, `/tdd`, `/refactor`, `/explore-repo`). 11 commands total, 1 reserved slot under the ≤12 cap.
- [ ] Two artifact files per active brief: `BRIEF.md` (why + what + spec, replaces GSD's CONTEXT+SPEC+RESEARCH split) and `PLAN.md` (tactical breakdown + verification status, replaces GSD's PLAN+EXECUTE+VERIFICATION+REVIEW split).
- [ ] No external CLI dependency: bash + jq only. No `gsd-sdk`, no Node, no Python.
- [ ] Live filesystem indexing: `/godmode` reads agents/, skills/, briefs/ at runtime; never hardcodes a list.
- [ ] Single happy path documented in `/godmode` output and README — answers "what now?" in five lines.

**Foundation — safety, hardening, and version single source of truth**
- [ ] `plugin.json` is the canonical version source; `install.sh` reads it via `jq` at runtime; `commands/godmode.md` drops literal version (statusline carries it).
- [ ] CI gate prevents version drift across files (greps + asserts on PR).
- [ ] Hooks emit valid JSON under adversarial branch names / commit messages / paths (`jq -n --arg`, no string interpolation).
- [ ] Hooks resolve project root from stdin's `cwd` field, not `pwd`.
- [ ] Hooks tolerate stdin drain failure (`cat > /dev/null || true`).
- [ ] Statusline does a single `jq` invocation per render.
- [ ] Installer prompts per-file (diff/skip/replace) before overwriting customized rules / agents / skills / hooks; non-interactive default = keep customizations.
- [ ] Backup rotation keeps last 5 in `~/.claude/backups/`.
- [ ] v1.x migration: detect `.claude-pipeline/` and emit a one-line note; never destructive; archive on user request only.
- [ ] Uninstaller detects version mismatch with installed `~/.claude/.claude-godmode-version`.
- [ ] `shellcheck` clean across every `*.sh` (CI-enforced).

**Agent layer modernization**
- [ ] Every agent file uses current model aliases (`opus`, `sonnet`, `haiku` — never pinned numeric IDs).
- [ ] Code-writing agents use `effort: high` (not `xhigh`) to avoid rule-skipping behavior; design/audit agents use `effort: xhigh`.
- [ ] Code-writing agents declare `isolation: worktree`; persistent learners declare `memory: project`.
- [ ] Every agent declares `maxTurns` defensively and a `Connects to:` line (upstream/downstream).
- [ ] New `@planner` agent (brief → plan tactical breakdown).
- [ ] New `@verifier` agent (read-only goal-backward verification).
- [ ] `@reviewer` split into `@spec-reviewer` and `@code-reviewer` (two-stage read-only review).
- [ ] Frontmatter linter — pure-Bash script; CI-enforced.

**Hook layer expansion**
- [ ] `PreToolUse` hook blocks `Bash(git commit --no-verify*)` and similar quality-gate-bypass patterns.
- [ ] `PreToolUse` hook scans tool input for hardcoded secret patterns and refuses with clear error.
- [ ] `PostToolUse` hook detects failed quality-gate exit codes and surfaces them in next assistant turn.
- [ ] `SessionStart` hook reads `.planning/STATE.md` if it exists and injects current-brief context.
- [ ] `PostCompact` hook reads agent/skill lists from live filesystem (no hardcoded list).
- [ ] Quality gates list moved to a single source (`config/quality-gates.txt` or one rule file); `PostCompact` reads from it.

**Skill layer rebuild**
- [ ] All v1.x skills replaced or aliased to the new shape; v1 names (`/prd`, `/plan-stories`, `/execute`) get one-time deprecation notes pointing to new commands.
- [ ] Auto Mode awareness in every skill (detects "Auto Mode Active" system reminder, routes accordingly).
- [ ] Wave-based parallel execution in `/build` with `run_in_background` + file-polling fallback for output races.
- [ ] Every public skill declares `Connects to: <upstream> → <this> → <downstream>`; `/godmode` renders the chain.
- [ ] First-run `/godmode` answers "what now?" within five lines, project-state-aware.

**State management — `.planning/` artifact set for consumer projects**
- [ ] `.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md` templates ship with the plugin and initialize on first use.
- [ ] `.planning/briefs/NN-name/BRIEF.md` + `PLAN.md` layout standardized.
- [ ] `init-context` shell helper (`skills/_shared/init-context.sh`) — pure bash + jq, reads `.planning/config.json`, returns JSON blob to skill orchestrators (no Node).
- [ ] `.planning/config.json` schema documented and JSON-schema-validated in CI.

**Quality — CI, tests, documentation parity**
- [ ] GitHub Actions matrix (macOS + Linux) on every PR.
- [ ] `shellcheck` on every `*.sh`, JSON schema validation on every `*.json`, frontmatter linter on agents/skills/commands.
- [ ] `bats-core` smoke test of install → `/godmode` → uninstall round trip in a temporary `$HOME`.
- [ ] README, CHANGELOG, `/godmode` agree exactly on the public surface (skills/agents/version/runtime/parity claims).
- [ ] CONTRIBUTING.md adds hygiene recipes (backup rotation, worktree prune, frontmatter conventions).
- [ ] All High-severity items from `.planning/codebase/CONCERNS.md` resolved with explicit traceability.
- [ ] Prompt-cache-aware rule structure (static preamble first, no dates/branches/dynamic content in rule bodies).

### Out of Scope

<!-- Explicit boundaries. Reasoning included to prevent re-adding. -->

- **Adopting a reference plugin's directory shape, command surface, or vocabulary** — references (GSD, Superpowers, everything-claude-code) are inspiration sources, not adoption targets. We read freely, copy nothing structural. Specific micro-patterns may be adopted with attribution.
- **External CLI dependency (Node, Python)** — every operation is shell-native. `jq` is the only required runtime.
- **Vendored copies of GSD, Superpowers, or everything-claude-code** — license + maintenance burden; inverts the dependency direction.
- **Bundled MCP server** — keeps the plugin shape pure (rules, agents, skills, hooks, statusline, permissions). MCP servers can be referenced but live elsewhere.
- **Custom CLI tool to replace gsd-sdk** — bash + jq is the budget; no helper binaries.
- **Domain-specific scaffolding** (Next.js starters, Rails templates, etc.) — this plugin shapes how Claude works, not what users build.
- **Graphical UI / dashboard** — surface is the terminal; statusline is the only visual primitive.
- **Telemetry / analytics** — trust killer; MIT + no-network is a differentiator.
- **Cloud sync of `.planning/` state** — git is the user's sync mechanism.
- **Backwards compatibility for v1.x users beyond a one-time installer migration** — v1 → v2 will provide a one-time migration path; old `/prd` / `/plan-stories` shapes get one-time deprecation notes, then are removed in v2.x.
- **Windows-native shell support (cmd / PowerShell)** — WSL2 is the supported path; native PowerShell ports are a separate effort with no validated demand.
- **Auto-installing required tools (`brew install jq` etc.)** — privilege escalation; package-manager assumptions; preflight check is the right call.
- **A `/everything` mega-command** — hides workflow shape; defeats Core Value.
- **Six-level workflow vocabulary** — project/milestone/roadmap/phase/plan/task is too deep. Our model collapses to five with only two dedicated artifact files per brief.
- **Per-task artifact files (TASK.md)** — git history IS the execution log. EXECUTE.md is redundant with `git log`.
- **Auto-prompt-engineering of user requests** — silent intent mutation breaks trust; explicit `/brief` Socratic discussion instead.

## Context

**Existing baseline.** v1.x is shipped (`plugin.json` claims 1.6.0, `install.sh` says 1.4.1 — version drift is one of the v2 cleanup items). The full codebase map is in `.planning/codebase/` (STACK, ARCHITECTURE, STRUCTURE, CONVENTIONS, INTEGRATIONS, TESTING, CONCERNS — preserved across the v2 re-init because it's factual analysis, not GSD planning state). Treat that as the v1 surface to mature.

**Reference plugins (inspiration only).** GSD (Get Shit Done), Superpowers, and everything-claude-code are reference sources. We read them freely to learn validated patterns, name surprising primitives, and avoid known pitfalls. We do not adopt their directory shapes, command surfaces, or vocabularies. Output is ours; influence is welcome; vendoring is forbidden.

**Current Claude Code primitives we leverage (knowledge cutoff Apr 2026).**
- Opus 4.7, Sonnet 4.6, Haiku 4.5 model lineup
- Auto Mode (continuous autonomous execution) — discoverable in our docs and respected by skills
- Effort levels: default / high / extra high
- Prompt caching (5-minute TTL) — agent prompt structure maximizes hits
- Subagent spawning with `run_in_background` + file-polling fallback for parallel work
- Hook events: SessionStart, PostCompact, PreToolUse, PostToolUse
- AskUserQuestion / EnterPlanMode / ScheduleWakeup as workflow gates
- MCP servers (Context7 in particular) as standardized capability extensions

**Known concerns (from `.planning/codebase/CONCERNS.md`).** install/uninstall safety holes, hook fragility under adversarial inputs (unescaped JSON interpolation), version drift across `plugin.json` / `install.sh` / `commands/godmode.md`, no automated test suite, hardcoded skill/agent lists that drift from filesystem, accumulating backups/worktrees with no pruning. v2 must address every High-severity item.

**This is a re-init.** The first attempt at a v2 milestone (committed 2026-04-25) used GSD's tooling and `.planning/` shape directly. We re-initialized 2026-04-26 after deciding references are inspiration-only and we build our own workflow vocabulary. The codebase map and the v1.x shipped surface carry forward; the planning artifacts (PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, config.json) are being regenerated under the new principle.

## Constraints

- **Tech stack** — Bash 3.2+, jq, Markdown, JSON, YAML. No compiled artifacts. Shell-portable across macOS and Linux. New work may add Python/Node helpers ONLY if they ship with a pure-shell fallback or are clearly optional.
- **Distribution** — must remain installable as a Claude Code plugin (plugin mode, via plugin registry) AND via direct shell install (manual mode). Both paths produce equivalent UX.
- **Dependencies** — `jq` is the only required runtime tool. Everything else (`shellcheck`, `bats`, etc.) is dev-time. No new mandatory runtime deps.
- **Surface area** — ≤ 12 user-invocable slash commands. v2 ships 11; one slot reserved.
- **Compatibility** — v1.x installs upgradable via `./install.sh` without manual intervention. v1.x command names get one-time deprecation notes pointing to new shapes; removed in next major.
- **License** — MIT, no copyleft dependencies, no vendored code from differently-licensed sources.
- **Single source of truth for version** — `.claude-plugin/plugin.json` is canonical; everything else reads from it at runtime via `jq`. CI gate prevents drift.
- **Documentation parity** — README, CHANGELOG, and `/godmode` quick reference always agree on the public surface.
- **No telemetry, no network calls at install or runtime** — except via tools the user already authorized (git, gh, MCP servers they configured).
- **Atomic commits per workflow gate** — every brief, every plan, every commit is its own commit; hooks never bypass `--no-verify`.
- **Reference scope** — read references freely, copy nothing structural. Specific micro-patterns may be adopted with attribution. No vocabulary, no directory shapes, no command names.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| **Reference plugins are inspiration sources, not adoption targets** — read freely, copy nothing structural | Re-init principle (2026-04-26): the v2 surface should be ours, not a GSD/Superpowers reskin. Adoption creates dependency-direction inversion and naming dilution. | ✓ Decided |
| **Workflow model: Project → Mission → Brief → Plan → Commit** | Five concepts; only Brief and Plan get dedicated artifact files. Lighter than GSD's six-level hierarchy; deeper than v1.x's flat PRD/stories. Intent-clear names that aren't borrowed. | ✓ Decided |
| **User-facing surface: 11 commands** (`/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship` + `/debug`, `/tdd`, `/refactor`, `/explore-repo`) | Single happy path with clear forks for helpers. One slot reserved under the ≤12 cap. | ✓ Decided |
| **Two artifact files per active brief: `BRIEF.md` + `PLAN.md`** | Less file proliferation than GSD's 5+ per phase. BRIEF.md combines context + spec + research summary; PLAN.md combines tactical plan + verification status. git log IS the execution log. | ✓ Decided |
| **No external CLI dependency — bash + jq only** | `gsd-sdk` (Node) is forbidden by the inspiration-only principle. All operations are shell-native. | ✓ Decided |
| **`.planning/` is the dev-state directory name** | Generic name (not GSD-trademarked). Decoupling from `gsd-sdk` tooling is what matters; the dirname is fine. The v1.x `.claude-pipeline/` directory remains the consumer-project runtime state — never touched destructively. | ✓ Decided |
| **`.claude-plugin/plugin.json` is the canonical version source; `install.sh` reads it via `jq` at runtime; `commands/godmode.md` drops literal version** | Eliminates the 1.6.0 / 1.4.1 / 1.4.1 drift across three files. Static markdown can't shell, so godmode.md just doesn't show the number — statusline carries it. | ✓ Decided |
| Default agent models: `opus` for `@architect`, `@security-auditor`, `@planner`, `@verifier`; `sonnet` for `@reviewer`, `@spec-reviewer`, `@code-reviewer`, `@test-writer`, `@researcher`, `@doc-writer`; `haiku` for trivially-bounded helpers | Matches Anthropic's strongest tier per role's cost / quality / latency tradeoff. Aliases (not pinned IDs) so a profile flip propagates. | ✓ Decided |
| Code-writing agents use `effort: high`, not `xhigh` | `xhigh` on Opus 4.7 historically skips rules (PITFALLS #4); design/audit agents tolerate this trade. Locked in `rules/godmode-routing.md`, not just frontmatter. | ✓ Decided |
| Treat all High-severity items in `.planning/codebase/CONCERNS.md` as v2 (this milestone) requirements | The user's goal includes "polish mature version" — concerns are precisely what polish means. | ✓ Decided |

## Evolution

This document evolves at brief transitions and milestone boundaries.

**After each brief transition:**
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with brief reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone:**
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-26 after re-initialization (claude-godmode v2 — polish mature version, new workflow model)*
