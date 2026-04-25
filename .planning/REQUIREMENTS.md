# Requirements: claude-godmode v2 — polish mature version

**Defined:** 2026-04-26 (re-init)
**Core Value:** A single, clear workflow where every agent, skill, and tool is connected and named for the user's intent — best-in-class capability behind the simplest possible surface.

**Vocabulary used throughout:** Project → Mission → Brief → Plan → Commit. User-facing slash commands: `/godmode`, `/mission`, `/brief N`, `/plan N`, `/build N`, `/verify N`, `/ship` + helpers (`/debug`, `/tdd`, `/refactor`, `/explore-repo`). No reference-plugin vocabulary (`phase`, `task`, `/discuss-phase`, `/plan-phase`, `/execute-phase`).

## v1 Requirements

Requirements for the v2.0 release. Each maps to exactly one brief in ROADMAP.md.

### Workflow model (WORKFLOW) — locked workflow shape, surface area, artifact set

- [ ] **WORKFLOW-01**: User-facing slash command surface is exactly 11 commands — `/godmode`, `/mission`, `/brief N`, `/plan N`, `/build N`, `/verify N`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`. No more. The 12th slot under the ≤12 cap is reserved.
- [ ] **WORKFLOW-02**: Two artifact files per active brief — `.planning/briefs/NN-name/BRIEF.md` (why + what + spec + research summary) and `PLAN.md` (tactical plan + verification status). No `EXECUTE.md`, no per-task `TASK.md`. The git log IS the execution log.
- [ ] **WORKFLOW-03**: No external CLI dependency at runtime — bash 3.2+ and `jq` only. No Node, no Python, no helper binary. Skill orchestrators read state via `skills/_shared/init-context.sh` (pure bash + jq).
- [ ] **WORKFLOW-04**: Live filesystem indexing — `/godmode`, `PostCompact`, statusline scan `agents/`, `skills/`, `commands/`, `.planning/briefs/` at runtime. No hardcoded inventories anywhere.
- [ ] **WORKFLOW-05**: Single happy path documented in `/godmode` output and README — answers "what now?" within 5 lines, project-state-aware. Path is `/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship`.

### Foundation (FOUND) — version SoT, hook safety, installer hardening

- [ ] **FOUND-01**: Single source of truth for plugin version — `.claude-plugin/plugin.json` is canonical. `install.sh` reads it via `jq -r .version` at runtime; `commands/godmode.md` drops literal version (statusline carries it from runtime context); README and CHANGELOG only mention version in release headings, validated by CI.
- [ ] **FOUND-02**: CI gate prevents version drift — GitHub Actions step asserts every advertised version string in install.sh / commands/godmode.md / README / CHANGELOG matches `plugin.json`'s version. PR fails on drift.
- [ ] **FOUND-03**: Hooks emit valid JSON under adversarial inputs — branch names, commit messages, paths containing `"`, `\`, or newlines are properly escaped via `jq -n --arg ctx "$CONTEXT" '{...}'`. No string concatenation into JSON output.
- [ ] **FOUND-04**: Hooks resolve project root from stdin's `cwd` field, not `pwd` — works when invoked from any subdirectory.
- [ ] **FOUND-05**: Hooks tolerate stdin drain failure under `set -euo pipefail` — `cat > /dev/null || true` pattern in every hook.
- [ ] **FOUND-06**: Statusline does a single `jq` invocation per render (down from four). Optional debug log to `/tmp/godmode-statusline.log` on parse failure (without breaking the line).
- [ ] **FOUND-07**: Installer prompts per-file (`[d]iff / [s]kip / [r]eplace / [a]ll-replace / [k]eep-all`) before overwriting customized rules / agents / skills / hooks / statusline. Non-interactive default (stdin not TTY) = keep customizations. Backup taken regardless of choice.
- [ ] **FOUND-08**: Backup rotation in `~/.claude/backups/` — keep last 5; prune older at install time.
- [ ] **FOUND-09**: v1.x migration is detection-only, never destructive — `install.sh` detects `.claude-pipeline/` and emits a one-line note pointing to the new workflow. Archive happens only on explicit user request. v1.x command names ship one-time deprecation banners (`/prd`, `/plan-stories`, `/execute`) pointing to new commands; banners removed in v2.x.
- [ ] **FOUND-10**: Uninstaller detects version mismatch — reads `~/.claude/.claude-godmode-version`; if it doesn't match the script's known version, warn loudly and require explicit `--force`. Prevents an old uninstaller from leaving newer files orphaned.
- [ ] **FOUND-11**: `shellcheck` clean across every `*.sh` in the repo (CI-enforced, see QUAL-02).

### Agents (AGENT) — modernized layer, two-stage review

- [ ] **AGENT-01**: Every agent file uses current model aliases (`opus`, `sonnet`, `haiku`) — never pinned numeric IDs.
- [ ] **AGENT-02**: Every agent declares `effort` explicitly — code-writing agents (`@executor`, `@writer`, `@test-writer`) use `effort: high` to avoid rule-skipping (PITFALLS); design/audit agents (`@architect`, `@security-auditor`, `@planner`, `@verifier`) use `effort: xhigh`.
- [ ] **AGENT-03**: Every code-writing agent declares `isolation: worktree` (`@executor`, `@writer`, `@test-writer`); persistent learners declare `memory: project` (`@executor`, `@researcher`, `@reviewer`).
- [ ] **AGENT-04**: Every agent declares `maxTurns` defensively and a `Connects to: <upstream> → <self> → <downstream>` line in its system prompt.
- [ ] **AGENT-05**: New `@planner` agent — Opus, `effort: xhigh`, read-mostly. Reads `BRIEF.md` and writes `PLAN.md` with atomic, parallelizable tasks, parallelism boundaries (waves), and per-task verification criteria.
- [ ] **AGENT-06**: New `@verifier` agent — Opus, `effort: xhigh`, `disallowedTools: Write, Edit`. Reads BRIEF.md success criteria, walks working tree + git log, reports COVERED / PARTIAL / MISSING per criterion. Updates PLAN.md verification-status section.
- [ ] **AGENT-07**: `@reviewer` split into `@spec-reviewer` (read-only, reads BRIEF.md, sanity-checks scope coherence + measurable success criteria) and `@code-reviewer` (read-only, reads diff, catches code-quality issues). Both `disallowedTools: Write, Edit`.
- [ ] **AGENT-08**: Frontmatter linter — pure-Bash script (`scripts/lint-frontmatter.sh`) validates every agent file's frontmatter against a known schema; exits non-zero on violations. CI-enforced (see QUAL-04).

### Hooks (HOOK) — mechanical enforcement, expanded events

- [ ] **HOOK-01**: New `PreToolUse` hook blocks `Bash(git commit --no-verify*)` and similar quality-gate-bypass patterns (`--no-gpg-sign`, `-c commit.gpgsign=false`, `git push --force` to main/master). Refuses with clear error pointing to the rules file. Uses new hook output shape (`hookSpecificOutput.permissionDecision: "deny"`).
- [ ] **HOOK-02**: New `PreToolUse` hook scans tool input for hardcoded secret patterns (AWS keys, GitHub PATs, generic `(api_key|secret|password)\s*=\s*['"][^'"]+['"]` heuristic). False-positive tolerant; refuses with clear error suggesting env var or `.env`.
- [ ] **HOOK-03**: New `PostToolUse` hook detects failed quality-gate exit codes (typecheck / lint / test / shellcheck) and surfaces them in next assistant turn via `additionalContext`.
- [ ] **HOOK-04**: `SessionStart` hook reads `.planning/STATE.md` if it exists and injects active-brief context — current brief number + name + suggested next command (`/plan`, `/build`, `/verify`, `/ship`).
- [ ] **HOOK-05**: `PostCompact` hook reads agent + skill + brief lists from live filesystem (`find agents/ -name '*.md'`, etc.) — no hardcoded list.
- [ ] **HOOK-06**: Quality gates list moved to a single source — `config/quality-gates.txt` (or one rule file with parseable section). `PostCompact` reads from it; rules render from it; CI lint asserts no other file embeds the gate list.

### Skills (SKILL) — workflow consolidation, the 11-command surface

- [ ] **SKILL-01**: `/godmode` orient skill — does three things only: prints the canonical 5-line "what now?" given current `.planning/STATE.md`, lists live agent/skill/brief inventory by filesystem scan, offers one-shot statusline setup if not enabled. Never shows version (statusline does); never page-dumps docs.
- [ ] **SKILL-02**: `/mission` skill — Socratic mission discussion that initializes `.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `config.json`. On returning project, no-op orient pointing to `/brief N`.
- [ ] **SKILL-03**: `/brief N` skill — Socratic brief discussion against user intent, optionally spawns `@researcher` for ecosystem questions, optionally spawns `@spec-reviewer` for sanity check. Writes one file: `.planning/briefs/NN-name/BRIEF.md` combining why + what + spec + research summary.
- [ ] **SKILL-04**: `/plan N` skill — reads `BRIEF.md`, spawns `@planner`, writes `.planning/briefs/NN-name/PLAN.md` with atomic tasks, parallelism waves, per-task verification criteria, and reserved verification-status section.
- [ ] **SKILL-05**: `/build N` skill — reads `PLAN.md`, executes tasks in waves (parallel within wave, sequential across waves), commits atomically per task, updates verification-status as it goes. Uses `run_in_background` plus file-polling fallback for output races. Concurrency cap per wave: 5.
- [ ] **SKILL-06**: `/verify N` skill — spawns `@verifier`, reports COVERED / PARTIAL / MISSING per BRIEF.md success criterion, writes result into PLAN.md verification-status section.
- [ ] **SKILL-07**: `/ship` skill — refuses to operate if PLAN.md verification status not all-COVERED. On clean state, sequences git operations (squash, push, `gh pr create`). No magic prompt mutation.
- [ ] **SKILL-08**: v1.x skills (`/prd`, `/plan-stories`, `/execute`) ship one-time deprecation banner pointing to new commands; banners removed in v2.x. `/debug`, `/tdd`, `/refactor`, `/explore-repo` retained — frontmatter aligned to v2 conventions.
- [ ] **SKILL-09**: Auto Mode awareness in every skill — detects "Auto Mode Active" system reminder and routes accordingly: minimize interruptions, prefer reasonable assumptions, never enter plan mode unless explicitly asked.
- [ ] **SKILL-10**: Every public skill declares `Connects to: <upstream> → <this> → <downstream>` in its description. `/godmode` renders the chain.

### State (STATE) — `.planning/` artifact set for consumer projects

- [ ] **STATE-01**: `.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `config.json` templates ship with the plugin and are initialized by `/mission` on first use.
- [ ] **STATE-02**: `.planning/briefs/NN-name/{BRIEF.md, PLAN.md}` templates ship — `/brief` and `/plan` populate them.
- [ ] **STATE-03**: `init-context` shared helper — `skills/_shared/init-context.sh` reads `.planning/config.json` and `STATE.md`, returns a JSON blob with current project + mission + active-brief context. Pure bash + jq. No Node, no Python.
- [ ] **STATE-04**: `.planning/config.json` schema documented in CONTRIBUTING.md and validated in CI (see QUAL-03).

### Quality (QUAL) — CI, tests, docs parity, cache-aware rules

- [ ] **QUAL-01**: GitHub Actions workflow runs on every PR — macOS + Linux matrix.
- [ ] **QUAL-02**: CI runs `shellcheck` (v0.11.0) on every `*.sh` (FOUND-11 dependency).
- [ ] **QUAL-03**: CI runs JSON schema validation on `plugin.json`, `hooks/hooks.json`, `config/settings.template.json`, `.planning/config.json` schema. Implemented with inline `jq -e` assertions (~20 checks per schema), not external validator (jq-only constraint).
- [ ] **QUAL-04**: CI runs frontmatter linter on `agents/*.md`, `skills/*/SKILL.md`, `commands/*.md` (AGENT-08 dependency).
- [ ] **QUAL-05**: CI runs `bats-core` (v1.13.0) smoke test of install → `/godmode` → uninstall round trip in temporary `$HOME`.
- [ ] **QUAL-06**: CI vocabulary gate — greps agent prompts, skill bodies, rule files for forbidden vocabulary (`/discuss-phase`, `/plan-phase`, `/execute-phase`, "phase" in workflow contexts, "task" as artifact). PR fails on hits.
- [ ] **QUAL-07**: CI parity check — asserts plugin-mode (`hooks/hooks.json`) and manual-mode (`config/settings.template.json`) hook bindings agree on hook events, scripts, and timeouts. PR fails on drift.
- [ ] **QUAL-08**: README, CHANGELOG, and `/godmode` agree exactly on the public surface — agent list, skill list, version string, jq-only runtime claim, plugin/manual-mode parity claim, deny-pattern caveat. CI gate compares `/godmode`'s live indexer output against README and CHANGELOG sections.
- [ ] **QUAL-09**: CONTRIBUTING.md adds hygiene recipes — backup rotation policy (keep last 5), worktree prune recipe (`git worktree prune`), frontmatter field conventions, per-file diff/skip/replace guidance, command-count check (≤12) as pre-release gate.
- [ ] **QUAL-10**: All High-severity items from `.planning/codebase/CONCERNS.md` resolved with explicit traceability table at the bottom of this REQUIREMENTS.md (see "CONCERNS.md Traceability" section).
- [ ] **QUAL-11**: Prompt-cache-aware rule structure — static preamble first; no dates/branches/dynamic content in rule bodies; volatile content moves to statusline or hook-injected `additionalContext`. Verified by two consecutive `PostCompact` outputs being byte-identical for the same project state.

## v2 Requirements

Deferred to a future release (v2.1+). Tracked but not in this milestone's roadmap.

### Future skills

- **FUT-01**: `/explore` — Socratic ideation before committing to a plan. Wait for demand signal.
- **FUT-02**: `/secure-brief` — retroactive threat-model verification per brief.
- **FUT-03**: `/spec-brief` — falsifiable-requirements clarification with ambiguity scoring before plan. Wait until `/brief` shows the gap.
- **FUT-04**: Stop hook for session-end learnings extraction into a markdown digest.
- **FUT-05**: `memory: user` for cross-project learnings — wait until `memory: project` (AGENT-03) proves valuable.

### Future integrations

- **FUT-06**: MCP integration recipes documented as cookbook entries (Context7, Chrome DevTools, Playwright). Out of scope for v2 surface; cookbook-only.
- **FUT-07**: Knowledge graph of briefs / decisions / requirements. Defer until usage data justifies.
- **FUT-08**: Workspace isolation (multi-feature parallel `.claude/worktrees/`). Defer until single-worktree limit is hit.
- **FUT-09**: Plan-mode integration — `EnterPlanMode` / `ExitPlanMode` natively gates `/plan` approval.
- **FUT-10**: 12th reserved slash command — wait for proven demand.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---|---|
| `/everything` mega-command | Hides workflow shape; defeats Core Value. PROJECT.md Out of Scope. |
| ≥ 12 user-facing slash commands | Cap is the differentiator. PROJECT.md Constraints. |
| Six-level workflow vocabulary (project / milestone / roadmap / phase / plan / task) | Too deep. Ours is 5-level. PROJECT.md Out of Scope. |
| Per-task artifact files (TASK.md or equivalent) | git log IS the execution log. PROJECT.md Out of Scope. |
| External CLI dependency (Node, Python, custom binary, gsd-sdk equivalent) | bash + jq is the runtime budget. PROJECT.md Out of Scope. |
| Vendored copies of reference plugins (GSD, Superpowers, everything-claude-code) | License + maintenance burden; inverts dependency direction. PROJECT.md Out of Scope. |
| Bundled MCP server | Pollutes plugin shape. PROJECT.md Out of Scope. |
| Domain-specific scaffolding (Next.js / Rails / etc.) | Plugin shapes how Claude works, not what users build. PROJECT.md Out of Scope. |
| Graphical UI / web dashboard | Surface is the terminal. PROJECT.md Out of Scope. |
| Telemetry / analytics | Trust killer. PROJECT.md Out of Scope. |
| Cloud sync of `.planning/` state | git is the user's sync mechanism. PROJECT.md Out of Scope. |
| v1.x backwards-compat beyond one-time installer migration | Removed in v2.x; deprecation banners are the bridge. PROJECT.md Out of Scope. |
| Windows-native shell (cmd / PowerShell) | WSL2 is supported path. PROJECT.md Out of Scope. |
| Auto-installing required tools (`brew install jq` etc.) | Privilege escalation; preflight check is the right call. PROJECT.md Out of Scope. |
| Auto-prompt-engineering of user requests (silent intent mutation) | Trust killer. Explicit `/brief` is the alternative. PROJECT.md Out of Scope. |
| Plugin-internal package manager / skill marketplace | Skills are markdown files; users add by editing. Not a plugin's job. |
| Built-in LLM proxy / model abstraction | Claude Code already abstracts the model. Aliases are the routing primitive. |
| AI-generated commit messages by default | Risks unhelpful messages; user/agent author writes. |
| Per-skill cherry-pick installation | Plugin is opinionated and cohesive; cherry-picking turns it into a kit. |
| Inline AI assistant for `.planning/` files | Claude Code IS the assistant. |

## Traceability

Filled by roadmapper during ROADMAP.md creation.

| Requirement | Brief | Status |
|---|---|---|
| WORKFLOW-01 | TBD | Pending |
| WORKFLOW-02 | TBD | Pending |
| WORKFLOW-03 | TBD | Pending |
| WORKFLOW-04 | TBD | Pending |
| WORKFLOW-05 | TBD | Pending |
| FOUND-01 | TBD | Pending |
| FOUND-02 | TBD | Pending |
| FOUND-03 | TBD | Pending |
| FOUND-04 | TBD | Pending |
| FOUND-05 | TBD | Pending |
| FOUND-06 | TBD | Pending |
| FOUND-07 | TBD | Pending |
| FOUND-08 | TBD | Pending |
| FOUND-09 | TBD | Pending |
| FOUND-10 | TBD | Pending |
| FOUND-11 | TBD | Pending |
| AGENT-01 | TBD | Pending |
| AGENT-02 | TBD | Pending |
| AGENT-03 | TBD | Pending |
| AGENT-04 | TBD | Pending |
| AGENT-05 | TBD | Pending |
| AGENT-06 | TBD | Pending |
| AGENT-07 | TBD | Pending |
| AGENT-08 | TBD | Pending |
| HOOK-01 | TBD | Pending |
| HOOK-02 | TBD | Pending |
| HOOK-03 | TBD | Pending |
| HOOK-04 | TBD | Pending |
| HOOK-05 | TBD | Pending |
| HOOK-06 | TBD | Pending |
| SKILL-01 | TBD | Pending |
| SKILL-02 | TBD | Pending |
| SKILL-03 | TBD | Pending |
| SKILL-04 | TBD | Pending |
| SKILL-05 | TBD | Pending |
| SKILL-06 | TBD | Pending |
| SKILL-07 | TBD | Pending |
| SKILL-08 | TBD | Pending |
| SKILL-09 | TBD | Pending |
| SKILL-10 | TBD | Pending |
| STATE-01 | TBD | Pending |
| STATE-02 | TBD | Pending |
| STATE-03 | TBD | Pending |
| STATE-04 | TBD | Pending |
| QUAL-01 | TBD | Pending |
| QUAL-02 | TBD | Pending |
| QUAL-03 | TBD | Pending |
| QUAL-04 | TBD | Pending |
| QUAL-05 | TBD | Pending |
| QUAL-06 | TBD | Pending |
| QUAL-07 | TBD | Pending |
| QUAL-08 | TBD | Pending |
| QUAL-09 | TBD | Pending |
| QUAL-10 | TBD | Pending |
| QUAL-11 | TBD | Pending |

**Coverage:**
- v1 requirements: 54 total (5 WORKFLOW + 11 FOUND + 8 AGENT + 6 HOOK + 10 SKILL + 4 STATE + 11 QUAL)
- Mapped to briefs: 0 (pending roadmapper)
- Unmapped: 0 (target after roadmapper run)

## CONCERNS.md Traceability

Maps every High-severity item from `.planning/codebase/CONCERNS.md` to the requirement that resolves it. QUAL-10 asserts this table is complete.

| CONCERNS.md item | Severity | Requirement(s) |
|---|---|---|
| #1 Local rule customizations silently overwritten | High | FOUND-07 |
| #2 Manual-mode install overwrites agents/skills with no per-file check | High | FOUND-07 |
| #3 Settings merge can drop keys silently | High | QUAL-07 (parity check), QUAL-03 (schema validation) |
| #4 No version-mismatch detection in uninstall | High | FOUND-10 |
| #5 v1.x migration removes CLAUDE.md after one keypress | High | FOUND-09 |
| #6 Branch names interpolated into hook JSON without escaping | High | FOUND-03 |
| #7 Hooks rely on `cwd` being project root with no fallback | High | FOUND-04 |
| #8 Hardcoded skill/agent lists in post-compact.sh | High | HOOK-05, WORKFLOW-04 |
| #9 Quality gates duplicated between rules and post-compact | High | HOOK-06 |
| #10 Plugin metadata version doesn't match installer | Medium | FOUND-01, FOUND-02 |
| #11 Plugin/manual hook bindings in two files | Medium | QUAL-07 |
| #12 hooks.json has timeout, settings.template.json doesn't | Medium | QUAL-07, FOUND-03 (related) |
| #13 Backup accumulation in ~/.claude/backups/ | Medium | FOUND-08 |
| #14 .claude/worktrees/ not cleaned up | Medium | QUAL-09 (CONTRIBUTING recipe) |
| #15 .claude-pipeline/archive/ unbounded growth | Medium | QUAL-09 (CONTRIBUTING recipe), FOUND-09 |
| #16 .DS_Store committed in subdirs | Low | (one-time cleanup; not a v2 req) |
| #17 install.sh requires jq but doesn't install it | Low | QUAL-08 (README parity calls this out) |
| #18 set -euo pipefail breaks on stdin closure | Low | FOUND-05 |
| #19 statusline.sh swallows all errors silently | Low | FOUND-06 |
| #20 No automated test coverage at all | Low | QUAL-01 through QUAL-08 |
| #21 README and CHANGELOG drift | Low | QUAL-08 |

All High-severity items mapped. Medium and Low items partially covered (the ones tied to maturity, not the cosmetic ones).

---
*Requirements re-defined: 2026-04-26 after re-init under "inspiration only" principle*
*54 requirements total — to be mapped to briefs by roadmapper*
