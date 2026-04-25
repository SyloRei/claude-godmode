# Stack Research — claude-godmode v2

**Domain:** Claude Code plugin (Bash + Markdown + JSON, no compiled artifacts)
**Researched:** 2026-04-25
**Confidence:** HIGH (all Claude Code surface verified against live docs; tooling versions verified against GitHub releases)

---

## Summary: What Changes vs v1.x

v1.x stack is a valid baseline. v2 adds nothing at runtime (jq remains the only mandatory dep). Changes fall into four buckets:

1. **Agent frontmatter fields** — new fields available: `effort`, `memory`, `background`, `isolation: worktree`, `color`, `maxTurns`, `skills`. Use them in every agent `.md` file.
2. **Hook events** — 21 hook events now exist (v1.x used only `SessionStart`, `PostCompact`). Six new events are immediately useful: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `PreCompact`, `SubagentStart`, `SubagentStop`.
3. **Model lineup** — `opus` alias now resolves to Opus 4.7; `sonnet` to Sonnet 4.6; `haiku` to Haiku 4.5. New effort level `xhigh` exists only on Opus 4.7 and is the current default.
4. **Dev-time tooling** — shellcheck (v0.11.0), bats-core (v1.13.0), jsonschema CLI (v14.16.2), and a pure-Bash frontmatter linter are added as dev-time-only CI tools with no effect on runtime.

No new mandatory runtime dependencies. `gsd-sdk` is the GSD SDK and is already present on this machine — it is a dev tool for the GSD workflows that orchestrate godmode's development, not a runtime dep of godmode itself.

---

## Recommended Stack

### Core Technologies (unchanged from v1.x, documented here for completeness)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Bash | 3.2+ | Hooks, installer, statusline | Ships on every macOS/Linux; no install required. 3.2 compat keeps macOS default shell happy. |
| jq | 1.6+ | JSON parsing in all shell scripts | Only mandatory runtime dep; already required. Use `--arg` / `--argjson` for safe interpolation (never string concat). |
| Markdown + YAML frontmatter | — | Agent, skill, command, rule definitions | Claude Code's native format; no build step. |
| JSON | — | Hook config, plugin manifest, settings merge | Claude Code protocol format for all IO. |

### Claude Code Plugin Authoring Surface (v2 additions)

#### Agent Frontmatter — Full Field Set

All fields verified against `https://code.claude.com/docs/en/sub-agents` (2026-04-25).

| Field | Valid Values | v1.x Used? | v2 Action |
|-------|-------------|-----------|-----------|
| `name` | kebab-case string | Yes | Keep |
| `description` | string (triggers auto-delegation) | Yes | Rewrite — must be delegation-quality |
| `model` | `opus`, `sonnet`, `haiku`, `opus[1m]`, `sonnet[1m]`, full model ID, or `inherit` | Yes | Update to use aliases, add `xhigh` effort |
| `effort` | `low`, `medium`, `high`, `xhigh` (Opus 4.7 only), `max` | No | Add to every agent |
| `maxTurns` | integer | Partial | Add explicit limits to all agents |
| `tools` | array of tool names | Yes | Audit allowlists against current tool names |
| `disallowedTools` | array of tool names | Yes | Prefer this over `tools` for minimal-surface agents |
| `skills` | array of skill names | No | Add to agents that should invoke specific skills |
| `memory` | `"user"` or `"project"` (v2.1.33+) | No | Add to `@researcher` and `@executor` — persistent learnings |
| `background` | boolean | No | Use for long-running agents that can suspend |
| `isolation` | `"worktree"` (only valid value for plugins) | No | Add to `@executor` — isolated worktree per story |
| `color` | hex or color name | No | Add for UI identification (nice-to-have) |

**Plugin restriction:** Plugin agents cannot declare `hooks`, `mcpServers`, or `permissionMode` (security constraint). These remain user-scope only.

#### Hook Events — Full Surface (21 events as of 2026-04-25)

Verified against `https://code.claude.com/docs/en/hooks`. Previously v1.x used only `SessionStart` and `PostCompact`.

**Events v2 should adopt:**

| Event | When | Key Input Fields | Key Output | v2 Use Case |
|-------|------|-----------------|------------|-------------|
| `SessionStart` | Session begins/resumes | `source`, `model`, `agent_type` | `additionalContext` | Keep — already in v1.x |
| `PostCompact` | After compaction | (compaction context) | none | Keep — already in v1.x |
| `PreToolUse` | Before any tool call | `tool_name`, `tool_input` | `permissionDecision`, `updatedInput`, `additionalContext` | NEW: block dangerous Bash patterns (unescaped shell meta in JSON), enforce no `--no-verify` commit rule |
| `PostToolUse` | After tool call succeeds | `tool_name`, `tool_input`, `tool_response` | `decision`, `additionalContext` | NEW: detect failed quality gates, inject corrective context |
| `UserPromptSubmit` | User submits prompt | `prompt` | `decision`, `additionalContext`, `sessionTitle` | NEW: auto-set session title from project name |
| `PreCompact` | Before compaction | `reason` | `decision` | NEW: optionally block auto-compact during critical phase execution |
| `SubagentStart` | Subagent spawned | `subagent_type`, `subagent_id` | none | NEW: log/track agent invocations |
| `SubagentStop` | Subagent finishes | `subagent_type`, `subagent_id` | `decision` | NEW: detect stuck/looping agents |
| `ConfigChange` | Config file changes during session | `config_source`, `changed_keys` | `decision` | NEW: warn user if godmode rules are hot-reloaded mid-session |
| `InstructionsLoaded` | rules/*.md file loaded | `file_path`, `memory_type` | none | NEW: debug aid — log which rule files Claude actually loaded |

**Events to skip in v2** (out of scope or not useful for this plugin type):
- `WorktreeCreate` / `WorktreeRemove` — only needed if plugin manages worktree lifecycle (executor agents use `isolation: worktree` instead)
- `Elicitation` / `ElicitationResult` — only relevant for MCP servers (out of scope per PROJECT.md)
- `TeammateIdle` / `TaskCreated` / `TaskCompleted` — agent teams feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`); not stable
- `FileChanged` — no watched files needed in godmode's architecture
- `CwdChanged` — hook scripts already read `cwd` from stdin
- `StopFailure` — output and exit code ignored; not actionable
- `SessionEnd` — no cleanup needed in this plugin

**Deprecated output format:** `decision: "approve"|"block"` on `PreToolUse` is deprecated. Use `hookSpecificOutput.permissionDecision: "allow"|"deny"|"ask"|"defer"` instead.

#### Hook Types Available (v2 additions)

v1.x used only `command` type. New types:

| Type | Use Case | v2 Adopt? |
|------|----------|-----------|
| `command` | Shell script execution | Keep — primary type |
| `http` | POST event JSON to a URL | No — no server, no telemetry |
| `mcp_tool` | Call an MCP tool | Maybe — for future MCP integrations, not v2 baseline |
| `prompt` | Evaluate a prompt with an LLM | No — adds latency/cost to every hook event |
| `agent` | Run an agentic verifier | No — heavyweight; use for complex verification only, not in base hooks |

#### Plugin Manifest (`.claude-plugin/plugin.json`) — v2 Additions

| Field | v1.x | v2 Action |
|-------|------|-----------|
| `name` | Yes | Keep |
| `version` | Yes (drifted: 1.6.0 vs 1.4.1) | Fix — make single source of truth |
| `description`, `author`, `license`, `keywords` | Yes | Keep |
| `skills`, `commands`, `agents`, `hooks` | Yes | Keep |
| `monitors` | No | Consider — for statusline alternatives; requires Claude Code v2.1.105+ |
| `userConfig` | No | Add — let users set model profile preference at install time |
| `bin/` directory | No | Consider — expose `gsd-sdk`-equivalent helpers as bare commands |
| `${CLAUDE_PLUGIN_DATA}` | No | Add to hooks that need persistent state (e.g., backup rotation tracking) |
| `dependencies` | No | Skip — no plugin deps needed yet |
| `channels` | No | Skip — out of scope |

#### Skill Frontmatter — Full Field Set (verified against current docs)

| Field | Notes |
|-------|-------|
| `name` | Required, kebab-case, max 64 chars |
| `description` | Required, max 1024 chars — determines auto-delegation |
| `allowed-tools` | Optional array — restrict tools for this skill's context |
| `metadata` | Optional object — arbitrary key/value for future use |
| `argument-hint` | Optional — shown in `/` picker |
| `shell` | Optional — `"powershell"` for Windows skills (skip in godmode) |

### Model Lineup (v2)

Verified against `https://code.claude.com/docs/en/model-config` (2026-04-25).

**Model aliases (use these in frontmatter, not pinned IDs):**

| Alias | Resolves to (Anthropic API) | Effort Levels | v2 Tier |
|-------|---------------------------|---------------|---------|
| `opus` | claude-opus-4-7 | low, medium, high, xhigh, max | High-leverage agents |
| `sonnet` | claude-sonnet-4-6 | low, medium, high, max | Mid-tier agents |
| `haiku` | claude-haiku-4-5 | (inherits session effort) | Utility agents |
| `opusplan` | opus during plan mode, sonnet during execution | — | Skills that span planning+execution |

**Use aliases not pinned IDs** — aliases update automatically when Anthropic releases new models. Pin only when third-party provider requires it (Bedrock/Vertex/Foundry). For this plugin, aliases are correct.

**Default effort as of v2.1.117:** `xhigh` on Opus 4.7, `high` on Opus 4.6 and Sonnet 4.6.

**Effort in agent frontmatter:** Set `effort: xhigh` explicitly for architecture/design agents on Opus. Set `effort: high` for sonnet agents. Let haiku agents inherit session default (no explicit effort field needed).

**Effort recommendation by agent:**

| Agent | Model | Effort | Rationale |
|-------|-------|--------|-----------|
| `@architect` | `opus` | `xhigh` | Highest-leverage decisions; reasoning quality matters most |
| `@executor` | `opus` | `high` | Follows explicit plan — `xhigh` wastes tokens |
| `@security-auditor` | `opus` | `xhigh` | Threat analysis benefits from maximum reasoning depth |
| `@writer` | `opus` | `high` | Prose quality over depth of reasoning |
| `@reviewer` | `sonnet` | `high` | Review is pattern-matching, not deep architecture |
| `@test-writer` | `sonnet` | `high` | Follows test patterns; medium would suffice |
| `@doc-writer` | `sonnet` | `medium` | High volume, lower complexity |
| `@researcher` | `sonnet` | `high` | Research benefits from reasoning; haiku is too shallow |

#### Claude Code Tool Primitives — v2 Adoption

Verified against `https://code.claude.com/docs/en/tools-reference` (2026-04-25).

**Adopt in v2 skill instructions:**

| Tool | Status | v2 Role |
|------|--------|---------|
| `TaskCreate` | Stable | Replace `.claude-pipeline/stories.json` task tracking for in-session multi-task workflows |
| `TaskList` | Stable | Expose in `/godmode` quick reference as session progress view |
| `TaskUpdate` | Stable | Mark stories done in `/execute` skill |
| `TaskGet` | Stable | Retrieve full task detail for sub-agent handoff |
| `Agent` | Stable | Primary mechanism for spawning named agents |
| `AskUserQuestion` | Stable | Gate user approvals in `/execute` (replaces ad-hoc markdown prompts) |
| `EnterPlanMode` | Stable | Use at start of `/plan-stories` / `.planning` phase skills |
| `ExitPlanMode` | Stable (requires permission) | Exit after presenting plan for user approval |
| `CronCreate` | Stable | Schedule reminders for long-running phases (e.g., "check back in 10 min") |
| `Monitor` | Stable (v2.1.98+) | Watch CI output or log files during `/execute` — report failures without polling |
| `EnterWorktree` | Stable (main session only, not in subagents) | Use in `/execute` for isolated story execution |

**Do NOT reference in v2:**

| Tool | Reason |
|------|--------|
| `TaskOutput` | Deprecated — use `Read` on task output file |
| `TodoWrite` | Non-interactive / SDK mode only — not available in interactive sessions |
| `ScheduleWakeup` | Removed — use `CronCreate` instead |
| `TeamCreate` / `SendMessage` | Experimental (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) — not stable |
| `PowerShell` | Windows only / opt-in — out of scope for godmode (WSL2 path) |

### Prompt Caching — Plugin-Author Guidance

Verified against `https://code.claude.com/docs/en/model-config#prompt-caching-configuration` and community sources.

Claude Code handles prompt caching automatically. Plugin authors cannot control cache placement directly, but can maximize cache hit rates by:

1. **Rule files (`rules/godmode-*.md`):** Keep them stable between sessions. Avoid injecting dynamic content (timestamps, branch names, git status) into rule files — that content belongs in `SessionStart` hook output (`additionalContext`), not in the rules themselves.
2. **Agent system prompts:** The markdown body of each `agents/*.md` file is the system prompt. Keep it static. Dynamic context (project name, phase, task) goes into the `Task()` prompt argument, not the system prompt.
3. **Session-start `additionalContext`:** This is already correct in v1.x — dynamic context injected via hook output reaches the model's message layer, not the system prompt layer, preserving cache hits.
4. **Context window:** Sonnet 4.6 and Opus 4.7 support 1M context window (automatically activated on Max/Team/Enterprise). Plugin rules are small enough that this never becomes a constraint.
5. **Effort and caching:** Higher effort levels consume more tokens per turn but do not affect prompt cache TTL (5 min Pro/API, 1 hr Max/Team).

### GSD Plugin (`gsd-sdk`) — Stack Summary

The GSD plugin installed at `~/.claude/get-shit-done/` (version 1.38.3) provides the workflow orchestration layer for claude-godmode's own development. Understanding its stack clarifies what v2 should interoperate with vs. what it replaces.

**GSD directory shape (actual, inspected locally):**

```
~/.claude/get-shit-done/
├── workflows/          # ~70 slash commands (implemented as GSD-format markdown, not SKILL.md)
├── bin/
│   └── gsd-tools.cjs   # The SDK implementation
│   └── lib/            # 25 CJS modules (roadmap.cjs, phase.cjs, state.cjs, milestone.cjs, etc.)
├── contexts/           # Per-role agent context fragments (dev.md, research.md, review.md)
├── references/         # ~50 reference docs (model-profiles.md, planning-config.md, agent-contracts.md, etc.)
└── templates/          # Project scaffolding templates (including research STACK.md template)
```

**GSD skills (installed separately at `~/.claude/skills/`):**
GSD installs ~40+ skills into `~/.claude/skills/` including `gsd-plan-phase`, `gsd-execute-phase`, `gsd-new-project`, `gsd-discuss-phase`, `gsd-research-phase`, `gsd-autonomous`, `gsd-review`, `gsd-undo`, `gsd-ship`, and many more.

**gsd-sdk CLI (available as npm global: `gsd-sdk`):**

| Command | Purpose |
|---------|---------|
| `gsd-sdk run <prompt>` | Run a full milestone from text |
| `gsd-sdk auto` | Full autonomous lifecycle |
| `gsd-sdk init [input]` | Bootstrap project from PRD |
| `gsd-sdk query <handler>` | Query registered handlers (roadmap state, phase info, agent skills, etc.) |

Key query handlers: `init.phase-op`, `init.plan-phase`, `roadmap.get-phase`, `agent-skills <name>`, `config-get <key>`, `commit <message>`.

**GSD subagent types (exact names that skills spawn):**

| Agent Name | Role |
|-----------|------|
| `gsd-planner` | Creates PLAN.md files |
| `gsd-executor` | Executes plans |
| `gsd-phase-researcher` | Phase-scoped research |
| `gsd-project-researcher` | Project-wide research |
| `gsd-research-synthesizer` | Synthesizes parallel research |
| `gsd-roadmapper` | Creates/revises ROADMAP.md |
| `gsd-plan-checker` | Validates plan quality |
| `gsd-verifier` | Post-execution verification |
| `gsd-codebase-mapper` | Codebase analysis |
| `gsd-debugger` | Debug investigation |
| `gsd-security-auditor` | Security audit |

**GSD model profiles (defined in `references/model-profiles.md`):**

| Profile | When to use |
|---------|------------|
| `quality` | Opus everywhere; quota-unlimited situations |
| `balanced` | Default; Opus for planning, Sonnet for execution |
| `adaptive` | Role-based: Opus for plan+debug, Sonnet for exec, Haiku for audit |
| `budget` | Minimal Opus; Sonnet for code, Haiku for research |
| `inherit` | Non-Anthropic runtimes; follows session model |

**GSD `.planning/` directory shape created for consumer projects:**

```
.planning/
├── PROJECT.md          # Project definition, requirements, key decisions
├── REQUIREMENTS.md     # Numbered requirements (REQ-NNN)
├── ROADMAP.md          # Phase list with descriptions, goals, dependencies
├── STATE.md            # Running decisions log
├── codebase/           # STACK.md, ARCHITECTURE.md, STRUCTURE.md, CONCERNS.md, CONVENTIONS.md, INTEGRATIONS.md, TESTING.md
├── research/           # Per-phase or project-wide research files
└── phases/
    └── 01-<slug>/
        ├── CONTEXT.md      # Phase decisions from /gsd-discuss-phase
        ├── RESEARCH.md     # Phase research
        ├── PLAN.md         # Executor prompt
        └── SUMMARY.md      # Post-execution summary
```

**What claude-godmode v2 should adopt from GSD (ideas, not code):**
- `.planning/` directory shape and artifact set (replace `.claude-pipeline/`)
- Phase lifecycle: discuss → spec → plan → execute → verify → secure → ship
- Completion marker convention (`## RESEARCH COMPLETE`, `## PLAN COMPLETE`, etc.) for agent handoff detection
- Model profile concept — expose as `/godmode set-profile quality|balanced|budget`
- Atomic-commit discipline per workflow gate

**What NOT to adopt:**
- `gsd-sdk` as a runtime dependency of godmode — it's a development tool for GSD-using projects, not a dependency for godmode's own runtime
- GSD's 70+ workflow commands — godmode targets ≤ 12 user-facing skills
- GSD's CJS module system — godmode stays pure Bash + Markdown

### Superpowers Plugin — Pattern Audit

Source: `https://github.com/obra/superpowers` (accepted into Anthropic official marketplace Jan 15, 2026).

**Key patterns worth selective adoption:**

| Pattern | What it does | Adopt in v2? |
|---------|-------------|-------------|
| **Thin command + skill** | Commands are 1-line entry points; full logic lives in `skills/`; zero startup overhead | Yes — already aligned in v1.x; ensure commands stay minimal |
| **Git worktree per parallel agent** | Each parallel subagent gets `isolation: worktree` — prevents file conflicts | Yes — add `isolation: worktree` to `@executor` agent |
| **TDD enforcement gate** | Deletes code written before tests; hard gate before implementation | Yes — add pre-implementation test gate to `/tdd` skill |
| **Four-phase debug discipline** | Root cause before fix; prohibits speculative patching | Yes — formalize in `@researcher` agent description |
| **Spec compliance + code quality two-stage review** | Every story gets spec-compliance review, then code-quality review | Yes — aligns with v1.x `@reviewer`; split into two passes |
| **Cross-platform plugin manifests** | `.claude-plugin`, `.codex-plugin`, `.cursor-plugin` co-located | No — out of scope; godmode is Claude Code only |

**What NOT to adopt from Superpowers:**
- The 14-skill surface (godmode already has its own ≤ 12 skill discipline)
- MCP server bundling (out of scope)
- Cross-IDE portability layer (godmode is Claude Code native)

### everything-claude-code — Pattern Audit

Source: `https://github.com/affaan-m/everything-claude-code`

**Key patterns worth selective adoption:**

| Pattern | What it does | Adopt in v2? |
|---------|-------------|-------------|
| **Stop-hook pattern extraction** | `Stop` event hook harvests error solutions and idioms from session transcript; stores as timestamped "instincts" | Partial — use `Stop` hook to write a lightweight session summary to `.planning/` without SQLite |
| **Strategic compaction** | Suggest `/compact` at logical breakpoints (post-research, post-phase) rather than waiting for auto-compact at 95% | Yes — add `PreCompact` hook that warns when compaction is manual vs. automatic |
| **Secret detection hooks** | `PreToolUse` on `Bash`/`Write` to block `.env`, `*.pem`, AWS key patterns | Yes — add minimal secret detection to `PreToolUse` hook |
| **Rule organization: common/ + language-specific/** | Rules split by concern; language-specific rules loaded on detection | Partial — godmode already splits by concern; language-specific detection is already in session-start hook |
| **Package manager detection from lockfiles** | Hierarchical detection with fallback | Already in v1.x — keep |
| **AgentShield security scanning** | 102-rule static analysis for CLAUDE.md, settings.json, hooks, agent configs | No — 1282-test Node.js suite violates "no new mandatory deps" constraint; adopt the pattern (shellcheck + JSON schema validate) not the tool |

**What NOT to adopt:**
- SQLite instinct store — Node.js runtime dep, violates constraint
- 183-skill surface — scope bloat
- 48-agent roster — surface-area violation
- Cross-IDE adapters — out of scope

### Dev-Time Tooling (CI-only, zero runtime impact)

#### shellcheck v0.11.0

- **What:** Static analysis for shell scripts. Catches unquoted variables, unescaped JSON interpolation, SC2064 trap issues, etc.
- **Why:** v1.x has known hook fragility under adversarial inputs (unescaped JSON interpolation is a critical concern). shellcheck catches these statically.
- **Install (CI):** `brew install shellcheck` (macOS) / `apt install shellcheck` (Linux) / `actionshub/shellcheck-problem-matchers` in GitHub Actions.
- **Config:** `.shellcheckrc` at repo root — set `shell=bash`, `external-sources=true`, explicitly disable any rules that are intentional (e.g., SC1091 for sourced files).
- **Do NOT use:** `shellcheck` as a runtime dep — it's a linter. Do NOT use `shfmt` as a formatter enforced in CI (opinionated on indentation, breaks existing style).

#### bats-core v1.13.0

- **What:** TAP-compliant Bash testing framework. Tests `install.sh`, `uninstall.sh`, hook scripts, `statusline.sh` in isolation.
- **Why:** No automated test suite exists in v1.x. bats covers the install→use→uninstall smoke test requirement.
- **Install (CI):** `npm install --save-dev bats` or `brew install bats-core`. Companion libraries: `bats-support` and `bats-assert` from the bats-core org.
- **Test location:** `tests/` at repo root. Files: `tests/install.bats`, `tests/uninstall.bats`, `tests/hooks.bats`, `tests/statusline.bats`.
- **Do NOT use:** `sstephenson/bats` (original, archived, Bash 4+ only — breaks Bash 3.2 compat). Use `bats-core/bats-core` exclusively.
- **Bash 3.2 note:** bats-core v1.13.0 requires Bash 3.2+ — explicitly compatible with macOS default shell.

#### sourcemeta/jsonschema CLI v14.16.2

- **What:** C++ CLI for JSON Schema validation. Zero Node.js dependency. Validates `plugin.json`, `hooks.json`, `settings.template.json` against authored schemas.
- **Why:** JSON schema validation must work in a pure-shell environment without `npm` at test time. The sourcemeta CLI is a single binary — `brew install jsonschema` / GitHub releases for Linux.
- **License:** AGPL, but using as a CLI tool in CI does not trigger copyleft on the plugin's own code (confirmed in project docs).
- **Schemas to author:** `.schemas/plugin.schema.json`, `.schemas/hooks.schema.json` — written once, validate at CI time.
- **Do NOT use:** `ajv-cli` (Node.js dep), `jsonschema` Python package (Python dep) — both violate the "no new mandatory deps" principle for CI environments that must be dependency-light.

#### Frontmatter Linting — Pure Bash

- **What:** No dedicated frontmatter linter fits all constraints (most are Node.js: `markdownlint-cli2`, `remark-lint-frontmatter-schema`). Author a purpose-built `scripts/lint-frontmatter.sh` using `awk` to extract YAML between `---` delimiters and validate required fields per component type.
- **Why:** v1.x has no validation that agent/skill frontmatter has required fields (`name`, `description`, `model`, `effort`). Drift between filesystem and hardcoded lists is a known concern. A 50-line Bash script with `grep`/`awk` is sufficient and zero-dep.
- **Fields to validate per type:**
  - Agents: `name`, `description`, `model`, `effort`
  - Skills: `name`, `description`
  - Commands: `description`
- **Do NOT use:** `markdownlint-cli2` or `remark-lint-frontmatter-schema` — both require Node.js; both are overkill for checking 5 YAML fields.

#### GitHub Actions CI Workflow

- **Shape:** Two matrix jobs — `macos-latest` and `ubuntu-latest`.
- **Steps:**
  1. `shellcheck` on all `*.sh` files
  2. `jsonschema validate` on all `*.json` files with schema
  3. `bash scripts/lint-frontmatter.sh` on all `agents/*.md`, `skills/*/SKILL.md`, `commands/*.md`
  4. `bats tests/` — smoke-test install→use→uninstall
- **Do NOT add:** macOS ARM-only runner (`macos-14`/M-series) as the only macOS CI job — it does not test Intel macOS which many users still run. Use `macos-latest` (currently Intel).
- **Do NOT add:** Docker-based CI for the smoke tests — `install.sh` modifies `~/.claude/`, which requires a real home directory, not a container FS.

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| `shellcheck v0.11.0` | `shfmt` (formatter) | Formatting changes break existing indentation style; linting is the v2 need, not reformatting |
| `bats-core v1.13.0` | `shunit2` | shunit2 lacks TAP output, fixture support, and bats-assert helpers; bats-core is the community standard |
| `sourcemeta/jsonschema` (binary CLI) | `ajv-cli` (Node.js) | ajv-cli adds Node.js as a CI dep; sourcemeta ships a self-contained binary |
| Pure-Bash frontmatter linter (custom) | `markdownlint-cli2` | Node.js dep; validates Markdown formatting, not semantic frontmatter fields |
| Model aliases (`opus`, `sonnet`, `haiku`) | Pinned model IDs (`claude-opus-4-7`) | Aliases track current recommended model per provider; pinned IDs require manual bumping on each Anthropic release |
| `effort` in frontmatter | Session-level `/effort` command | Agents need per-agent effort control; session-level effort is the user's choice for their own work |
| `isolation: worktree` on `@executor` | Shared working directory | Parallel story execution in v1.x caused file conflicts; worktree isolation eliminates the class of bug |
| `.planning/` directory (GSD shape) | `.claude-pipeline/` (v1.x) | `.claude-pipeline/` is godmode-specific and not understood by GSD or other tools; `.planning/` is the emerging standard |

---

## What NOT to Add

| Avoid | Why | What Instead |
|-------|-----|-------------|
| `gsd-sdk` as runtime dep | Node.js binary; breaks pure-shell environments; gsd-sdk is for developing-with-GSD, not for plugin users | godmode uses its own Bash scripts for any state management |
| Python/Node.js scripts in hooks | Breaks macOS default Bash-only environments; violates "no new mandatory deps" | Pure jq + Bash in all hook scripts |
| MCP server bundled with plugin | Out of scope per PROJECT.md; adds Node.js server process as runtime dep | Document recommended MCP servers (Context7, etc.) in README only |
| SQLite for instinct/pattern storage | Node.js or system dep; overkill for Markdown-based plugin | Write session summaries to `.planning/` as Markdown files |
| `agent` or `prompt` hook types | Adds per-event LLM call cost; unacceptable latency in hooks that fire on every tool call | Use `command` hooks for all validation; surface findings in `additionalContext` |
| Pinned model IDs in frontmatter | Manual maintenance burden; breaks when Anthropic releases new models | Use `opus`, `sonnet`, `haiku` aliases |
| Windows PowerShell support | Out of scope per PROJECT.md; WSL2 is supported path | Document WSL2 requirement explicitly |
| `everything-claude-code` AgentShield | 1282-test Node.js suite; violates constraints | Implement equivalent checks as 50-line shellcheck + JSON schema rules |
| `markdownlint-cli2` in CI | Node.js dep; validates Markdown formatting not semantic fields | Custom pure-Bash frontmatter linter |
| Vendored copies of GSD, Superpowers, or everything-claude-code | Inverts dependency direction; license/maintenance burden | Adopt ideas, not code |

---

## Integration: Where Each v2 Addition Lives in the Repo

| Addition | Location in Repo | Notes |
|----------|-----------------|-------|
| Agent frontmatter updates | `agents/*.md` | Add `effort`, `memory`, `isolation`, `maxTurns` to each agent file |
| New hook bindings (PreToolUse, PostToolUse, etc.) | `hooks/hooks.json` (plugin mode), `config/settings.template.json` (manual mode) | Add JSON entries for each new event |
| New hook scripts | `hooks/pre-tool-use.sh`, `hooks/post-tool-use.sh`, `hooks/user-prompt-submit.sh` | New files alongside existing `session-start.sh`, `post-compact.sh` |
| `.planning/` support in session-start hook | `hooks/session-start.sh` | Detect `.planning/` alongside `.claude-pipeline/`; prefer `.planning/` if present |
| shellcheck config | `.shellcheckrc` | Repo root; checked in |
| bats tests | `tests/` | `tests/install.bats`, `tests/hooks.bats`, `tests/statusline.bats` |
| JSON schemas | `.schemas/` | `plugin.schema.json`, `hooks.schema.json` |
| Frontmatter lint script | `scripts/lint-frontmatter.sh` | Pure Bash, no deps |
| GitHub Actions CI | `.github/workflows/ci.yml` | Matrix: macos-latest + ubuntu-latest |
| Version source of truth | `.claude-plugin/plugin.json` `version` field | installer and `/godmode` command read this at runtime via `jq` |
| Model profile reference | `rules/godmode-routing.md` (or new `rules/godmode-models.md`) | Document alias→tier→effort mapping so agents self-configure |
| `userConfig` for model profile | `.claude-plugin/plugin.json` `userConfig` block | Prompt at install time: `model_profile: quality|balanced|adaptive|budget` |

---

## Version Compatibility

| Component | Minimum Claude Code Version | Notes |
|-----------|---------------------------|-------|
| `memory` frontmatter field | v2.1.33 | Feb 2026; safely gated by capability check |
| `monitor` plugin feature | v2.1.105 | Consider optional feature flag in plugin.json |
| `PreToolUse` with `defer` | v2.1.89 | Not needed in v2 baseline; skip |
| Opus 4.7 (`opus` alias) | v2.1.111 | Required for `xhigh` effort; document minimum Claude Code version |
| `xhigh` effort default | v2.1.117 | Already the session default; frontmatter `effort: xhigh` is explicit |

---

## Sources

- `https://code.claude.com/docs/en/hooks` — All 21 hook events, input/output fields, version notes. Confidence: HIGH.
- `https://code.claude.com/docs/en/plugins-reference` — Plugin manifest schema, component paths, agent frontmatter fields, `${CLAUDE_PLUGIN_DATA}`. Confidence: HIGH.
- `https://code.claude.com/docs/en/sub-agents` — Full agent frontmatter schema including `memory`, `background`, `isolation`, `color`. Confidence: HIGH.
- `https://code.claude.com/docs/en/model-config` — Model aliases, effort levels, prompt caching env vars, 1M context availability. Confidence: HIGH.
- `https://code.claude.com/docs/en/tools-reference` — Complete tool list including `CronCreate`, `Monitor`, `EnterWorktree`, `TaskOutput` deprecation. Confidence: HIGH.
- `https://github.com/gsd-build/get-shit-done` — GSD plugin overview. Local installation at `~/.claude/get-shit-done/` (v1.38.3) inspected directly. Confidence: HIGH.
- `https://github.com/obra/superpowers` — Superpowers patterns. Confidence: MEDIUM (README-level; no direct code inspection).
- `https://github.com/affaan-m/everything-claude-code` — everything-claude-code patterns. Confidence: MEDIUM (README + directory listing).
- `https://github.com/bats-core/bats-core/releases` — bats-core v1.13.0, released Nov 7 2024. Confidence: HIGH.
- `https://github.com/koalaman/shellcheck/releases` — shellcheck v0.11.0, released Aug 4 2025. Confidence: HIGH.
- `https://github.com/sourcemeta/jsonschema` — jsonschema CLI v14.16.2. Confidence: MEDIUM (version from search result; release page not directly loaded).

---

*Stack research for: claude-godmode v2 — Claude Code plugin modernization*
*Researched: 2026-04-25*
