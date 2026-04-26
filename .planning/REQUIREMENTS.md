# Requirements: claude-godmode v2

**Defined:** 2026-04-26
**Core Value:** A single, clear workflow where every agent, skill, and tool is connected and named for the user's intent — best-in-class capability behind the simplest possible surface.

## v1 Requirements

Requirements for the v2.0.0 release. Each maps to exactly one phase. 46 v1 requirements total. Synthesized from `.planning/research/FEATURES.md` (F-NN catalog), `IDEA.md` (5 must-have properties), and `.planning-archive-v1/codebase/CONCERNS.md` (9 High items).

### Foundation (M1 — substrate hardening)

- [ ] **FOUND-01**: `install.sh` prompts per-file `[d]iff/[s]kip/[r]eplace/[a]ll-replace/[k]eep-all` before overwriting customized rules, agents, skills, or hooks. Non-TTY default keeps customizations. Backup always taken regardless of choice. (Closes CONCERNS #1, #2; F-11; D-15.)
- [ ] **FOUND-02**: `.claude-plugin/plugin.json:.version` is the single source of truth. `install.sh` reads it via `jq -r .version` at runtime — no `VERSION="..."` literal anywhere. `commands/godmode.md` drops the literal version (statusline carries it). `scripts/check-version-drift.sh` (new file) asserts every version mention in `install.sh`, `commands/*.md`, `README.md`, `CHANGELOG.md` matches the canonical value. (Closes CONCERNS #10; F-09; D-14.)
- [ ] **FOUND-03**: `uninstall.sh` reads `~/.claude/.claude-godmode-version`; refuses to operate if it doesn't match the script's known version (read from `plugin.json` at start). `--force` bypasses with a clear warning. (Closes CONCERNS #4; F-13.)
- [ ] **FOUND-04**: Every shipped hook (`session-start.sh`, `post-compact.sh`) emits valid JSON when invoked against a git repo whose branch name contains `"`, `\`, a literal newline, or `'`. JSON built via `jq -n --arg ctx "$CONTEXT" '{...}'` — never heredoc string interpolation. (Closes CONCERNS #6; F-10; D-12.)
- [ ] **FOUND-05**: Hooks resolve project root from stdin's `cwd` field (Claude Code hook contract), with `pwd` as fallback only when `cwd` is absent. `cat > /dev/null` stdin-drain replaced with `cat > /dev/null || true` (or `INPUT=$(cat || true)` for capture-and-reuse) so `set -euo pipefail` doesn't abort on early stdin closure. (Closes CONCERNS #7, #18; F-10.)
- [ ] **FOUND-06**: `config/statusline.sh` collapses its current four `jq -r` invocations into one `jq -r '... | @tsv'` paired with bash `IFS=$'\t' read -r`. (Closes CONCERNS #19 perf; F-38.)
- [ ] **FOUND-07**: `config/quality-gates.txt` (new file) is the single source of truth for the 6 quality gate definitions (typecheck / lint / tests / no-secrets / no-regressions / matches-requirements). One gate per line, no formatting. (F-28.)
- [ ] **FOUND-08**: `shellcheck` (v0.11.0+) over `install.sh`, `uninstall.sh`, `hooks/*.sh`, `config/statusline.sh`, and any new `scripts/*.sh` passes with zero errors. `.shellcheckrc` (new file) at repo root enumerates any intentional disables with one-line rationale comments. (Closes CONCERNS #20; F-16.)
- [ ] **FOUND-09**: `install.sh` v1.x migration is detection-only. When `.claude-pipeline/` or v1.x `CLAUDE.md` is detected, the installer emits a single non-destructive note pointing the user at `/mission` and continues. No `rm` is performed by the installer for any v1.x artifact. (Closes CONCERNS #5; F-14.)
- [ ] **FOUND-10**: `~/.claude/backups/` retains exactly the last 5 `godmode-<timestamp>/` directories — `install.sh` prunes older entries at start-of-run after the new backup directory is created. (Closes CONCERNS #13; F-12.)
- [ ] **FOUND-11**: Live filesystem indexing substrate ships in M1: PostCompact hook reads `agents/*.md` and `skills/*/SKILL.md` via `find` at runtime (no hardcoded list); the canonical glob patterns and ignored prefixes (`_*`, README, `*.tmpl`) are documented in `rules/godmode-conventions.md`. (Closes CONCERNS #8 substrate; F-15; D-04. Consumer-facing `/godmode` indexer lands in WORKFLOW-02.)

### Agents (M2 — agent layer modernization)

- [ ] **AGENT-01**: Every agent file uses the v2 frontmatter convention: `model: opus|sonnet|haiku` (alias, never numeric ID); `effort: high|xhigh`; `isolation: worktree` for code-touching OR `memory: project|user|local` for persistent learners; `maxTurns: <N>` defensively; `Connects to: <upstream> → <self> → <downstream>` line. Documented in `rules/godmode-routing.md`.
- [ ] **AGENT-02**: Code-writing agents (`@executor`, `@writer`, `@test-writer`, `@doc-writer`, `@code-reviewer`) use `effort: high` — never `xhigh`, because Opus 4.7 `xhigh` is documented to skip rules. Design / audit agents (`@architect`, `@security-auditor`, `@planner`, `@verifier`, `@spec-reviewer`) use `effort: xhigh`. Frontmatter linter (AGENT-06) refuses commits combining `effort: xhigh` with Write/Edit in `tools:`. (Closes CR-01.)
- [ ] **AGENT-03**: New `@planner` agent (Opus, `effort: xhigh`, read-mostly, writes only to PLAN.md). Spawned by `/plan N` skill. Produces atomic, parallelizable tasks with wave boundaries and per-task verification criteria. (F-18.)
- [ ] **AGENT-04**: New `@verifier` agent (Opus, `effort: xhigh`, mechanically read-only via `disallowedTools: Write, Edit`). Spawned by `/verify N` skill. Walks back from BRIEF.md success criteria to working tree + git log; reports COVERED / PARTIAL / MISSING per criterion into PLAN.md verification section. (F-19; D-07.)
- [ ] **AGENT-05**: v1.x `@reviewer` split into `@spec-reviewer` (pre-execution, spawned by `/brief N`) and `@code-reviewer` (post-execution, spawned per-task by `/build N`). Both Sonnet, `effort: high`, read-only via `disallowedTools: Write, Edit`. (F-20; D-11.)
- [ ] **AGENT-06**: `scripts/check-frontmatter.sh` (new file) — pure-Bash + jq linter. Asserts every agent has all required AGENT-01 fields, valid model alias, valid effort tier, complete `Connects to:` chain, no `xhigh + Write/Edit` combination. CI-gated in QUAL-01. (F-21.)
- [ ] **AGENT-07**: All 8 v1.x agents (`@writer`, `@executor`, `@architect`, `@security-auditor`, `@reviewer`, `@test-writer`, `@doc-writer`, `@researcher`) rewritten to AGENT-01 convention. Pinned model IDs replaced with aliases. (F-22.)
- [ ] **AGENT-08**: `Connects to:` chains across the full 12-agent set form a complete, consistent dependency graph. `/godmode` (WORKFLOW-02) renders this graph at runtime. (D-16.)

### Hooks (M3 — hook layer expansion)

- [ ] **HOOK-01**: New `hooks/pre-tool-use.sh` blocks `Bash(git commit --no-verify*)`, `git commit -n*`, `git commit --no-gpg-sign*`, `git commit -c commit.gpgsign=false*`, and `git push --force` to `main`/`master`. Refuses with clear remediation message. (F-23; D-08; closes IDEA "mechanically enforced quality".)
- [ ] **HOOK-02**: PreToolUse hook scans tool input for hardcoded secret patterns (AWS keys, GitHub PATs, common JWT shapes, generic `(api_key|secret|password)\s*=\s*['"][^'"]+['"]` heuristic). Refuses with clear remediation pointer (env var, `.env`). Exemption pattern list documented. (F-24.)
- [ ] **HOOK-03**: New `hooks/post-tool-use.sh` detects failed quality-gate exit codes (typecheck / lint / test commands returning non-zero) and surfaces them in the next assistant turn via `additionalContext` injection. (F-25.)
- [ ] **HOOK-04**: `hooks/session-start.sh` reads `.planning/STATE.md` if present and injects current-brief context (active brief #, status, next command) via `hookSpecificOutput.additionalContext`. v1.x `Pipeline: /prd → /plan-stories → /execute → /ship` line replaced with v2 chain. (F-26.)
- [ ] **HOOK-05**: `hooks/post-compact.sh` reads agent / skill lists from the live filesystem (FOUND-11 substrate consumed) and reads quality gates from `config/quality-gates.txt` (FOUND-07 consumed). No hardcoded inventories, no duplicated gates list. (Closes CONCERNS #8, #9; F-27.)
- [ ] **HOOK-06**: `hooks/hooks.json` (plugin-mode) and `config/settings.template.json[hooks]` (manual-mode) declare equivalent hook bindings, timeouts, and permission rules. Both default to `"timeout": 10` for SessionStart/PostCompact. M3 keeps them in sync; M5 (QUAL-03) asserts byte-for-byte parity in CI.

### Workflow surface (M4 — skill rebuild + state management)

- [ ] **WORKFLOW-01**: User-facing surface is exactly 11 slash commands: `/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`. ≤12 cap with 1 reserved slot. Each has one stated goal in its frontmatter `description:`. (F-01.)
- [ ] **WORKFLOW-02**: `/godmode` skill prints a state-aware "what now?" answer in ≤5 lines, reading `.planning/STATE.md` if present (or pointing at `/mission` if absent). Live-lists agents + skills + briefs from filesystem (FOUND-11 substrate). One-shot statusline setup if not enabled. Never prints a literal version. (F-02; D-01.)
- [ ] **WORKFLOW-03**: `/mission` skill is a Socratic mission init that writes `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, and `.planning/config.json` from a multi-step conversation. Idempotent on returning project (no-ops with "mission already defined; run /brief N"). (F-03.)
- [ ] **WORKFLOW-04**: `/brief N` skill is Socratic and produces a single `BRIEF.md` at `.planning/briefs/NN-name/BRIEF.md` covering why + what + spec + research summary. Optionally spawns `@researcher` and `@spec-reviewer`. Single file output — no CONTEXT.md, no SPEC.md, no RESEARCH.md. (F-04; D-02.)
- [ ] **WORKFLOW-05**: `/plan N` skill spawns `@planner` (AGENT-03) which produces `PLAN.md` at `.planning/briefs/NN-name/PLAN.md`. PLAN.md includes atomic tasks with wave boundaries, per-task verification criteria, and a "Verification status" section that `/verify` mutates in place. (F-05.)
- [ ] **WORKFLOW-06**: `/build N` skill reads `PLAN.md` and dispatches wave-based parallel execution. Within a wave: parallel via `Agent(run_in_background=true)` with file-polling fallback for stdout corruption races. Across waves: sequential. Per-task atomic commit. Concurrency cap = 5 hardcoded for v2.0; config knob deferred to v2.1. (F-06; D-10.)
- [ ] **WORKFLOW-07**: `/verify N` skill spawns `@verifier` (AGENT-04). Updates the verification section in `PLAN.md` to COVERED / PARTIAL / MISSING per BRIEF.md success criterion. Read-only — never modifies source files. (F-07; D-07.)
- [ ] **WORKFLOW-08**: `/ship` skill runs the 6 quality gates from `config/quality-gates.txt`, refuses to operate when PLAN.md verification section contains any non-COVERED items (unless `--force` with explicit warning), then sequences git operations and `gh pr create`. (F-08.)
- [ ] **WORKFLOW-09**: 4 cross-cutting helpers (`/debug`, `/tdd`, `/refactor`, `/explore-repo`) rewritten to v2 shape with auto-mode awareness and `Connects to:` chain integration. (F-31.)
- [ ] **WORKFLOW-10**: v1.x skill names (`/prd`, `/plan-stories`, `/execute`) ship with one-time deprecation banners that map old → new (e.g., `/prd` → `/brief N`, `/plan-stories` → `/plan N`, `/execute` → `/build N`). Banners removed in v2.x. (F-29.)
- [ ] **WORKFLOW-11**: Every skill detects the "Auto Mode Active" system reminder (case-insensitive substring match) and routes accordingly: auto-approves routine decisions, picks recommended defaults, minimizes interruptions, never enters plan mode unless explicitly asked. Detection regex documented in `rules/godmode-skills.md`. (F-31b; D-09.)
- [ ] **WORKFLOW-12**: `skills/_shared/init-context.sh` (new file) — pure bash + jq. Reads `.planning/config.json` and STATE.md, returns a JSON blob via stdout. Sourced by every skill instead of re-implementing parsing. Replaces `gsd-sdk` for our domain. (F-32b; D-03.)
- [ ] **WORKFLOW-13**: `.planning/` artifact templates ship with the plugin under `templates/.planning/{PROJECT,REQUIREMENTS,ROADMAP,STATE}.md.tmpl` and `templates/.planning/briefs/{BRIEF,PLAN}.md.tmpl`. `/mission` and `/brief N` materialize from these. (F-33.)
- [ ] **WORKFLOW-14**: `.planning/STATE.md` format is defined (4-line header block: active brief #, status, next command, last activity). Skills mutate by replacing the header block + appending an audit line. User can hand-edit between commands. (F-30.)

### Quality (M5 — CI, tests, parity, docs)

- [ ] **QUAL-01**: `.github/workflows/ci.yml` (new file) runs on every PR: `shellcheck` (FOUND-08), frontmatter linter (AGENT-06), version-drift check (FOUND-02), parity gate (QUAL-03), vocabulary gate (QUAL-04). Each gate is independently passing/failing. (F-34.)
- [ ] **QUAL-02**: `tests/install.bats` (new file) — bats-core smoke test of the install round-trip: install → uninstall → reinstall over a `~/.claude/` with hand-edited customizations + adversarial-input hook fixtures (branch names with quote, backslash, newline, apostrophe). Runs on `macos-latest` and `ubuntu-latest`. (F-35.)
- [ ] **QUAL-03**: `scripts/check-parity.sh` (new file) diffs derived hook bindings between `hooks/hooks.json` and `config/settings.template.json[hooks]`, asserts byte-for-byte equivalence on hook bindings, timeouts, and permission rules. CI-gated in QUAL-01. (Closes CONCERNS #11, #12; F-36; D-06.)
- [ ] **QUAL-04**: `scripts/check-vocab.sh` (new file) greps the user-facing surface (`commands/`, `skills/`, `README.md`) for forbidden tokens (`phase`, `task`, `story`, `PRD`, `gsd-*`, `cycle`, `milestone`) and fails on hits. Internal docs (`rules/`, `agents/`, `.planning/`) exempt via path allow-list. CI-gated in QUAL-01. (D-13.)
- [ ] **QUAL-05**: `README.md` is ≤500 lines, scannable, no duplication with `CONTRIBUTING.md`, with table of contents, getting-started tutorial, troubleshooting section, and FAQ. (Closes CONCERNS #21; F-37.)
- [ ] **QUAL-06**: `CHANGELOG.md` has a dated v2.0.0 release entry summarizing the 5 milestone areas. `.claude-plugin/plugin.json` description and keywords polished for marketplace SEO. (F-37.)
- [ ] **QUAL-07**: `tests/install.bats` includes a regression test for settings merge: top-level keys present in `~/.claude/settings.json` before reinstall remain present after, even when the keys are not declared in `settings.template.json`. (Closes CONCERNS #3.)

## v2 Requirements

Deferred to a future release (v2.1+). Tracked but not in current roadmap.

### Workflow polish (post-v2.0)

- **POLISH-01**: `/build N` wave-concurrency cap exposed as a `.planning/config.json` knob (currently hardcoded 5).
- **POLISH-02**: Prompt-cache-aware rule and agent prompt structure tuning (D-17 — improvement, hard to measure win directly until shipped).
- **POLISH-03**: 12th user-facing slash command using the reserved slot — exact command TBD by usage data after v2.0 ships.
- **POLISH-04**: Plugin marketplace social preview image, animated demo GIF, "built for" section in README.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep. Rationale lifted from PROJECT.md "Out of Scope" and FEATURES.md "Anti-features" (A-01..A-24).

| Feature | Reason |
|---------|--------|
| Cross-runtime support (Codex / Gemini / OpenCode adapters) | Claude Code only — adds enormous surface for fractional benefit and dilutes Opus 4.7 / hook-contract specificity (A-01) |
| Workspace / multi-repo orchestration (worktree management as user feature) | Single repo, single workflow, single mental model. Worktree isolation for agents is internal, not a user feature (A-02) |
| External CLI dependency (Node, Python, custom binary, gsd-sdk equivalent) | Bash 3.2+ + jq is the runtime budget; init-context.sh replaces the SDK (A-03) |
| Native Windows shell (cmd / PowerShell) | WSL2 is the supported path; native ports add disproportionate maintenance burden (A-04) |
| Telemetry / phone-home / opt-in metrics | Trust killer — no-network is the brand (A-05) |
| Cloud features (ultraplan-to-cloud, remote review, scheduled background agents) | The user's runtime already provides ScheduleWakeup / /schedule (A-06) |
| Copyleft dependencies | MIT-only licensing (A-07) |
| Vendored copies of reference plugin code (GSD / Superpowers / everything-claude-code) | Read freely, copy nothing structural — output is ours (A-08) |
| ≥12 user-facing slash commands | The cap IS the differentiator; every command past 12 dilutes the surface (A-09) |
| Six-level workflow vocabulary (project / milestone / roadmap / phase / plan / task) | Ours collapses to 5 (Project / Mission / Brief / Plan / Commit); two artifact files per brief (A-10) |
| Per-task artifact files (TASK.md, EXECUTE.md, equivalents) | The git log IS the execution log (A-11) |
| `/everything` mega-command running the full workflow | Hides the workflow shape; defeats Core Value (A-12) |
| v1.x backwards compatibility beyond a one-time installer migration | Old commands get deprecation banners then removed in v2.x (A-13) |
| Auto-installing required tools (`brew install jq` etc.) | Privilege escalation + package-manager assumptions; preflight check + clear error is the right call (A-14) |
| Auto-prompt-engineering of user requests (silent intent mutation) | Trust killer; explicit `/brief` Socratic discussion makes intent clarification visible and consensual (A-15) |
| Bundled MCP server | Keeps plugin shape pure; MCP servers live in their own repos (A-16) |
| Domain-specific scaffolding (Next.js starters, Rails templates) | Plugin shapes how Claude works, not what users build (A-17) |
| Graphical UI / web dashboard | Surface is the terminal; statusline is the only visual primitive (A-18) |
| Cloud sync of `.planning/` state | git is the user's sync mechanism (A-19) |
| Plugin-internal package manager / skill marketplace | Skills are markdown files; users add by editing `~/.claude/skills/` (A-20) |
| Built-in LLM proxy / model abstraction layer | Claude Code already abstracts the model; aliases are the routing primitive (A-21) |
| AI-generated commit messages by default | Claude Code already does this on request (A-22) |
| Per-skill cherry-pick installation | Plugin is opinionated and cohesive; cherry-picking turns it into a kit, which Core Value rejects (A-23) |
| Inline AI assistant for `.planning/` files | Claude Code IS the assistant (A-24) |

## Traceability

Phase mapping. Filled by roadmapper (or this file's author at re-init).

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 1 | Pending |
| FOUND-02 | Phase 1 | Pending |
| FOUND-03 | Phase 1 | Pending |
| FOUND-04 | Phase 1 | Pending |
| FOUND-05 | Phase 1 | Pending |
| FOUND-06 | Phase 1 | Pending |
| FOUND-07 | Phase 1 | Pending |
| FOUND-08 | Phase 1 | Pending |
| FOUND-09 | Phase 1 | Pending |
| FOUND-10 | Phase 1 | Pending |
| FOUND-11 | Phase 1 | Pending |
| AGENT-01 | Phase 2 | Pending |
| AGENT-02 | Phase 2 | Pending |
| AGENT-03 | Phase 2 | Pending |
| AGENT-04 | Phase 2 | Pending |
| AGENT-05 | Phase 2 | Pending |
| AGENT-06 | Phase 2 | Pending |
| AGENT-07 | Phase 2 | Pending |
| AGENT-08 | Phase 2 | Pending |
| HOOK-01 | Phase 3 | Pending |
| HOOK-02 | Phase 3 | Pending |
| HOOK-03 | Phase 3 | Pending |
| HOOK-04 | Phase 3 | Pending |
| HOOK-05 | Phase 3 | Pending |
| HOOK-06 | Phase 3 | Pending |
| WORKFLOW-01 | Phase 4 | Pending |
| WORKFLOW-02 | Phase 4 | Pending |
| WORKFLOW-03 | Phase 4 | Pending |
| WORKFLOW-04 | Phase 4 | Pending |
| WORKFLOW-05 | Phase 4 | Pending |
| WORKFLOW-06 | Phase 4 | Pending |
| WORKFLOW-07 | Phase 4 | Pending |
| WORKFLOW-08 | Phase 4 | Pending |
| WORKFLOW-09 | Phase 4 | Pending |
| WORKFLOW-10 | Phase 4 | Pending |
| WORKFLOW-11 | Phase 4 | Pending |
| WORKFLOW-12 | Phase 4 | Pending |
| WORKFLOW-13 | Phase 4 | Pending |
| WORKFLOW-14 | Phase 4 | Pending |
| QUAL-01 | Phase 5 | Pending |
| QUAL-02 | Phase 5 | Pending |
| QUAL-03 | Phase 5 | Pending |
| QUAL-04 | Phase 5 | Pending |
| QUAL-05 | Phase 5 | Pending |
| QUAL-06 | Phase 5 | Pending |
| QUAL-07 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 46 total
- Mapped to phases: 46
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-26 (Path A re-bootstrap onto GSD planning shape)*
*Last updated: 2026-04-26 after initial definition*
