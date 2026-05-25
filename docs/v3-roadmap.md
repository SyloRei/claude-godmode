# claude-godmode v2 → v3: Improvement Plan, Competitive Positioning & Technical Spec

**TL;DR**
- **claude-godmode v2.0.0 is architecturally the best-in-class spec-first workflow plugin for Claude Code today** — its 11-command spine (`/godmode → /mission → /brief → /plan → /build → /verify → /ship` + 4 helpers), enforced via PreToolUse/PostToolUse hooks and a CI matrix with `shellcheck`, parity, vocab, and surface-count gates, is materially more disciplined than wshobson/agents, VoltAgent/awesome-claude-code-subagents, and Anthropic's own `feature-dev`. Its weakness is **breadth of specialists, discoverability, and ecosystem leverage** (3 GitHub stars, no MCP servers, no LSP servers, no output styles, model_profile not yet wired).
- **Do not chase wshobson/VoltAgent on agent count.** Their 191 and 100+ agents win on SEO but lose on coherence — godmode's bet on a "team of 12 + one workflow" is the correct opinionated stance. The right v3 move is to **double down on the spine** (add a `/triage` incident skill, an MCP-aware `/onboard`, off-spine `/adr`, `/changelog`, `/pr-describe`, `/release`, and an output style) and **deepen the agents** (split `reviewer` into 5 parallel lenses, add `debugger`, `perf-engineer`, `incident-responder`, `migration-engineer`, `release-manager`) — not to add 80 language specialists.
- **The single highest-ROI improvement is wiring `userConfig.model_profile` to actually switch models and effort at runtime** — without it, the manifest field is dead documentation, and the "balanced/quality/budget" promise in the README is unfulfilled. This is a 1-day fix that closes the most embarrassing gap in v2 and unlocks the Haiku-tier cost story that competitors don't have.

---

## Key Findings

1. **The v2.0.0 architecture is unusually mature for a 3-star repo.** PR #9 (46 commits, 7 review waves, dated 2026-05-24) replaces v1's `/prd → /plan-stories → /execute` pipeline with a single legible spine, ships 12 agents on a "2026 contract" (alias models, explicit effort/maxTurns, worktree isolation, read-only enforcement, `memory: project`), wires PreToolUse blocks for `--no-verify` and `core.hooksPath` escape hatches, adds secret-scan, and runs an Ubuntu+macOS CI matrix with shellcheck pinned to v0.11.0 and bats pinned to v1.13.0. The discipline visible in PR #9's commit log (per-wave `@reviewer` + `@security-auditor` checkpoints, goal-backward FR verification, vocab/parity/surface-count gates that catch v1 leakage) exceeds what most plugins in the ecosystem demonstrate.

2. **Five concrete weaknesses vs. the field.** (a) `userConfig.model_profile` is exposed but **not wired** — per the wave-B reviewer fix in commit `ee30273`, it does not switch models/effort at runtime; (b) **no MCP servers bundled** (Context7 for live docs, Playwright for browser verification, GitHub for PR ops are table stakes in 2026); (c) **no LSP servers** despite Anthropic's official marketplace shipping 12 LSP plugins as a category; (d) **no output styles**, which the official manifest schema explicitly supports; (e) **agent roster has a single `reviewer` for code, security, architecture review** when the dominant pattern (Anthropic's `code-review` plugin, which runs 5 parallel Sonnet agents for CLAUDE.md compliance, bug detection, historical context, PR history, and code comments with confidence-based scoring) is to fan out lens-specific reviewers in parallel.

3. **The competitive landscape splits into 3 distinct strategies.** wshobson/agents and VoltAgent compete on breadth (191 and 100+ agents respectively, organized by domain). Anthropic's official plugins (`feature-dev`, `code-review`) and zhsama/claude-sub-agent compete on workflow rigor (7-phase spec-first state machines). davila7/claude-code-templates competes on distribution (968+ components installable a la carte via npx CLI). **godmode is currently the strongest workflow-rigor plugin outside Anthropic itself**, and should position there — not pivot to breadth.

4. **The "skills vs commands" boundary is currently violated.** v2 puts `/godmode` in `commands/` and the other 10 in `skills/`. This is incoherent against the May 2026 Anthropic plugin schema, where commands are flat `.md` files invoked explicitly and skills are progressive-disclosure directories invoked by description match. The right model: keep all 11 user-facing entry points as skills (directories with `SKILL.md` + bundled scripts/references) and let `/godmode` be the only true command (it doesn't need progressive disclosure — it's a 5-line orient). This also lets each skill bundle deterministic scripts under `scripts/`, which is the documented Anthropic best practice: per their official Skill authoring guide, "Prefer scripts for deterministic operations: Write validate_form.py rather than asking Claude to generate validation code."

5. **The "rules" hack is technical debt that should be retired in v3.** v2's `~/.claude/rules/` mechanism exists because Claude Code's plugin system doesn't natively support a `rules` directory (tracking issue #14200 referenced in the README). But the same effect is now achievable via the official `SessionStart` hook's `additionalContext` field. The hooks reference documents this verbatim: `{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "Project uses TypeScript strict mode"}}`. Migrating rules from a side-channel install to a session-start injection eliminates the `/godmode` rule-install dance, the install/uninstall asymmetry risk, and the entire "rules vs CLAUDE.md" footgun.

---

## Details

### A. Current state of claude-godmode v2.0.0 (verbatim from PR #9 and the manifest)

**Manifest (`.claude-plugin/plugin.json`)** — declares `name: claude-godmode`, `version: 2.0.0`, MIT, and a `userConfig.model_profile` with options `["quality", "balanced", "budget"]` exposed to hooks as `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE}`. **Per commit `ee30273`, this is documentation-only in v2 — agents apply effort/model via their own frontmatter; the profile is not consumed at runtime.**

**12 agents** (alias models, `memory: project`, code-writers in worktrees with `maxTurns` 80–100, read-only agents enforced mechanically):
- Opus, effort high/xhigh: `writer`, `executor`, `architect`, `security-auditor`, `planner`, `verifier`
- Sonnet, effort high: `reviewer`, `test-writer`, `doc-writer`, `researcher`, `spec-reviewer`, `code-reviewer`

**11 commands/skills**: `/godmode` (orient, the only true command), `/mission`, `/brief N`, `/plan N`, `/build N` (wave-based parallel execution, atomic commit per step, worktree merge-back), `/verify N` (goal-backward COVERED/PARTIAL/MISSING), `/ship` (gates + push + PR), and 4 helpers `/debug /tdd /refactor /explore-repo`. Surface-count gate caps at ≤12.

**Hooks** (`timeout: 10`, plugin/manual parity, all JSON via `jq -n --arg`/`--argjson`):
- `PreToolUse(Bash)` → `pre-tool-use.sh` blocks `git commit --no-verify`, `--no-verify=*`, and `git -c core.hooksPath=… commit`
- `PreToolUse` → `pre-tool-use-secrets.sh` secret-scan on staged diffs
- `PostToolUse(Bash)` → `post-tool-use.sh` surfaces non-zero exit codes from tracked quality-gate commands
- `UserPromptSubmit` → `user-prompt-submit.sh` injects session context
- `SessionStart` → `session-start.sh` reads `.planning/STATE.md` via `bin/godmode-state`, emits v2 spine
- `SessionEnd` → `session-end.sh` writes install marker + last-version-seen to `${CLAUDE_PLUGIN_DATA}`
- `PostCompact` → `post-compact.sh` restores quality gates + skill/agent lists (live-scanned, reads 6 gates from `config/quality-gates.txt`)
- Statusline: single-jq `config/statusline.sh` (project | branch | model | context % | cost)

**8 rules** in `~/.claude/rules/` (installed via `/godmode` first-run): `godmode-identity`, `godmode-workflow`, `godmode-coding`, `godmode-quality`, `godmode-git`, `godmode-testing`, `godmode-context`, `godmode-routing`.

**State**: `bin/godmode-state` reads/writes `.planning/STATE.md` (current mission, brief number, plan number, current wave); `bin/godmode-hash-rules` detects rule drift.

**CI** (Ubuntu+macOS, no Node/Python/Ruby): `shellcheck` v0.11.0 → JSON lint → frontmatter lint → version-drift (scoped to plugin version, no longer false-positives on tool versions) → plugin/manual parity gate → vocab gate (full installed surface, guards removed v1 names `/prd /plan-stories /execute`, `stories.json`, `.claude-pipeline`) → surface-count gate (≤12, current=11) → `bats tests/` (41 tests pinned to bats v1.13.0).

**Strengths**: workflow coherence, enforcement discipline, CI rigor, vocab/parity hygiene, install/uninstall symmetry, mechanically-enforced read-only on review agents, atomic-commit-per-wave-step. These are best-in-class.

**Gaps**: see Key Findings #2 above, plus: (f) no `skills` field in `plugin.json` pointing at `skills/`; (g) skills bundle no scripts/references — progressive disclosure under-exploited; (h) no parallel-lens code review (single `code-reviewer` vs Anthropic `code-review`'s 5 parallel Sonnet agents); (i) no `/onboard` or codebase-comprehension skill beyond `/explore-repo`; (j) no incident-response skill; (k) no migration skill; (l) no observability/perf skill; (m) no PR-template or commit-message skill that reuses `@code-reviewer`'s findings; (n) no agent-creation/skill-creation meta-skill (Anthropic ships `skill-creator`); (o) Markdown-only — no Python/TS scripts for deterministic operations even where they'd help (e.g., a `verify-coverage.py` instead of asking the verifier agent to compute coverage from test output); (p) statusline doesn't surface model_profile; (q) no analytics/telemetry hook for cost tracking via PostToolUse `tool_response.usage` fields documented in the May 2026 hooks reference.

### B. Competitive landscape (May 24, 2026)

| Plugin / Collection | Stars | Agents | Skills/Cmds | Hooks | MCP/LSP | Workflow | Strategy | Best at | Weakness vs godmode |
|---|---|---|---|---|---|---|---|---|---|
| **claude-godmode v2** | 3 | 12 | 11 | 7 | None | **Spec-first spine** | Workflow rigor + CI hygiene | Coherent end-to-end pipeline, mechanical enforcement, install discipline | **No MCP, no LSP, no output styles, model_profile not wired, single-lens review, low discoverability** |
| **wshobson/agents** | 35.1k | 191 | 102 cmds, 155 skills | — | 82-plugin marketplace bundles | "Multi-harness" (Claude Code + Codex + Cursor + OpenCode + Gemini) | Breadth + cross-tool reuse | Domain coverage, language specialists, plugin packaging | No unifying workflow; agents are catalogue items, not a pipeline; routing is the user's problem |
| **VoltAgent/awesome-claude-code-subagents** | 20.1k | 100+ | — | — | None | Category catalogue | Breadth + agent-organizer meta-pattern | Reference quality for individual agent prompts | Pure catalogue, no orchestration spine, no verification loop |
| **anthropics/claude-code (`feature-dev`)** | (official) | 3 (code-explorer, code-architect, code-reviewer) | 1 (`/feature-dev`) | None | None | **7-phase state machine** | Anthropic-blessed workflow | Single-command full-feature flow, distribution via official marketplace | Single workflow only; no `/ship`, no `/verify` as separate phase, no isolation, no multi-feature parallel execution |
| **anthropics/claude-code (`code-review`)** | (official) | 5 parallel Sonnet lenses (CLAUDE.md compliance, bug detection, historical context, PR history, code comments) | 1 (`/code-review`) | None | None | Parallel review fan-out | Authoritative review pattern | Confidence-scored findings, false-positive filtering | Review-only; no implementation, no planning, no verification |
| **anthropics/skills** (`mcp-builder`, `skill-creator`, `webapp-testing`, docx/pdf/pptx/xlsx) | 140k | 0 | 17 skills | None | None | Skill catalogue | Reference implementations of progressive disclosure | The canonical examples of bundled scripts + reference files | Not a workflow, not agents |
| **davila7/claude-code-templates** | 27.2k | 600+ | 200+ cmds, 39 hooks | 39 | 55 MCPs | a la carte CLI installer | **Distribution + discoverability** | Browsable web catalog, `npx` installer, dashboard, analytics, Docker sandboxing | No coherent workflow; pure component grab-bag; quality varies wildly across community submissions |
| **zhsama/claude-sub-agent** | 532 | 12 | 1 (`/agent-workflow`) | None | None | Orchestrator-driven spec workflow with quality gates | Spec-driven multi-agent | Closest direct competitor to godmode philosophy | Less mature CI, no worktree isolation, no PreToolUse enforcement, no hooks |

**Strategic read**: godmode's only true peer on philosophy is `zhsama/claude-sub-agent` (and godmode is materially more mature in CI, isolation, and hook enforcement); on workflow rigor, only Anthropic's `feature-dev` is comparable, and `feature-dev` is a single phase whereas godmode is the full pipeline. The right positioning is: **"What `feature-dev` is to one feature, claude-godmode is to your entire engineering org — with the enforcement and CI to make it actually work."**

---

## Strategic Roadmap

### Positioning statement (use this as the new README opener)

> *claude-godmode is the engineering-discipline plugin for Claude Code. Where most plugins give you 50 agents and hope you know which one to call, godmode gives you a single 11-command spine, 16 specialized agents that enforce their own constraints, and a CI matrix that catches drift before it ships. It's what `feature-dev` is to one feature, applied to your entire pipeline.*

### Architecture philosophy — five non-negotiables

1. **One workflow, not a buffet.** Surface-count gate ≤12 stays. New capability ships as a skill on the spine or doesn't ship.
2. **Mechanical enforcement over instruction.** Anything that can be a `PreToolUse` block, a `disallowedTools` constraint, a deterministic script, or a CI gate must be — not a sentence in a rule file.
3. **Spec-first, atomic-commit-per-step, worktree-isolated.** Already true; promote it to the README headline.
4. **Alias models, runtime-switchable.** No pinned model IDs; `model_profile` must actually switch effort and model tier at spawn time.
5. **Progressive disclosure inside every skill.** Each skill is a directory with a ≤500-line `SKILL.md`, plus bundled `scripts/`, `references/`, and `examples/`.

### Phased plan

**Phase 1 — Land v2.1 (2 weeks). "Fix what's promised."**
- **P1.1**: Wire `userConfig.model_profile`. Make `/build`, `/verify`, `/ship` and each agent's frontmatter respect `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE}` at spawn time. This closes the README's biggest credibility gap.
- **P1.2**: Split `@reviewer` into 5 parallel lenses (`code-reviewer`, `security-reviewer`, `perf-reviewer`, `convention-reviewer`, `test-reviewer`). Each runs in parallel under `/verify N`; results merged with confidence scoring.
- **P1.3**: Migrate `~/.claude/rules/` to `SessionStart` hook's `additionalContext` injection. Retire `/godmode` rule-install dance.
- **P1.4**: Add MCP server bundling. Ship a `.mcp.json` that references (does not auto-install): Context7 (live docs), GitHub MCP (PR ops for `/ship`), Playwright MCP (browser verification for `/verify`). Document opt-in.
- **P1.5**: Add `outputStyles/` with one style: `godmode-terse.md` (Bottom-Line-Up-Front, no preamble, severity-labeled). Reference it in `plugin.json`.

**Phase 2 — Land v2.2 (4 weeks). "Cover the gaps."**
- **P2.1**: Add 4 missing agents — `@debugger`, `@perf-engineer`, `@incident-responder`, `@migration-engineer`. All sonnet for cost; opus-escalation via `model_profile=quality`.
- **P2.2**: Add 3 new skills on the spine — `/triage` (incident timeline), `/profile` (perf), `/onboard` (codebase cheatsheet). Stay ≤12 by collapsing `/explore-repo` into `/onboard` or promoting surface cap to 14 with a single gate bump.
- **P2.3**: Add 3 off-spine skills as plain commands (no progressive disclosure needed) — `/adr`, `/changelog`, `/pr-describe`.
- **P2.4**: Bundle deterministic scripts. Each skill gets a `scripts/` directory with at least one Python or shell helper for the verification/computation steps Claude shouldn't be doing in tokens (e.g., `skills/verify/scripts/coverage-diff.py`, `skills/ship/scripts/gates.sh`).

**Phase 3 — Land v3.0 (6–10 weeks). "Become best-in-class on distribution."**
- **P3.1**: Publish to `claude-community` marketplace. This is the single largest discoverability lever — your competitors are all there.
- **P3.2**: Cross-tool packaging via the wshobson "multi-harness" pattern. Generate `AGENTS.md` from the agent roster so Codex CLI / Cursor / OpenCode users get the same 16-agent team with rule context injected.
- **P3.3**: Add 2 LSP plugin entries (`typescript-lsp`, `python-lsp` references in `plugin.json` under the `lspServers` field). This brings live type-checking into `@writer`/`@executor` worktrees.
- **P3.4**: Telemetry-light cost tracking. PostToolUse hook reads `tool_response.usage` and writes a per-session cost line to `.planning/COSTS.md`. Surface in statusline.
- **P3.5**: Skill marketplace within godmode — a `/godmode skill add <name>` that scaffolds a new skill directory from `anthropics/skills/template` and registers it. Lowers contribution barrier.

**Phase 4 — v3.x ongoing. "Stay opinionated."**
- Per-language depth via opt-in sub-plugins (`claude-godmode-python`, `claude-godmode-typescript`) so the core stays language-agnostic.
- Optional `@architect-team` Agent Team (Anthropic experimental `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) for multi-perspective architecture review.
- Quarterly "vocab gate" — automated check that no v3 commands have leaked into v2's reserved namespace.

### What NOT to do

- **Do not add 80+ language specialists.** Copying the breadth strategy is a value-destroying move.
- **Do not auto-install MCP servers.** OAuth flows and credential prompts are fragile in CI; ship `.mcp.json` as a reference, not a default.
- **Do not abandon the worktree isolation.** It's the single feature that makes `/build` parallel-safe.
- **Do not remove the surface-count gate.** It's load-bearing for the positioning.

---

## Recommendations (prioritized)

**Do this week (P0):**
1. **Wire `userConfig.model_profile` end-to-end.** ~1 day. Benchmark: a `quality` run is visibly more careful than `budget`; a `budget` run on a trivial feature costs <$0.10.
2. **Add the `outputStyles/` directory with `godmode-terse.md`.** Two-hour change.
3. **Migrate rules to `SessionStart.additionalContext`.** Half-day. Benchmark: fresh install reaches "rules active" in zero user steps.

**Do this month (P1):**
4. **Split `@code-reviewer` into 5 parallel lenses.** Benchmark: `/verify N` produces categorized findings with confidence scores in a single session.
5. **Bundle `.mcp.json` with Context7, GitHub, Playwright references (opt-in).** Don't auto-install.
6. **Add `@debugger`, `@perf-engineer`, `@incident-responder`, `@migration-engineer`.** All sonnet.
7. **Bundle deterministic scripts inside each spine skill.** Start with `skills/verify/scripts/coverage-diff.py` and `skills/ship/scripts/gates.sh`.

**Do this quarter (P2):**
8. **Publish to `claude-community` marketplace.**
9. **Generate `AGENTS.md` from the agent roster for cross-tool reuse.**
10. **Add Stop hook that blocks on incomplete AC-N coverage.**
11. **Add `/release` and `@release-manager`.**

**Don't do (anti-recommendations):**
- Don't add language-specialist agents to the core. Spin them out as sub-plugins.
- Don't remove the surface-count gate.
- Don't replace worktree isolation with sub-agents-only.
- Don't add a web dashboard.

**Decision thresholds (when to revisit):**
- Stars under 50 within 60 days of publication → discoverability is the bottleneck, not features.
- Users report "too many agents to remember" → pull off-spine skills back, reduce to 12 agents.
- Anthropic releases a native `rules` directory (issue #14200) → migrate immediately, ship as v3.1.
- Anthropic's `feature-dev` adds a `/ship`-equivalent → double down on multi-feature parallel execution and cross-tool `AGENTS.md`.

---

## Caveats

- Repo content access was partial when this was drafted; verify frontmatter and hook structure against the working tree before implementation.
- The `model_profile` "not wired" claim is based on commit `ee30273`. If runtime wiring has shipped since, P0 #1 is moot.
- Anthropic's plugin schema evolves frequently; the "no native rules directory" gap (issue #14200) may close at any time.
- Agent Teams is gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` as of May 2026.
- Competitor star counts are point-in-time (May 24, 2026). Position against strategies, not numbers.
- Cost tracking via `tool_response.usage` may require a Claude Code version check in `post-tool-use.sh`.
