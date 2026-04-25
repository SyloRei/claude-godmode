# Stack Research — claude-godmode v2

**Domain:** Claude Code plugin (Bash + Markdown + JSON, no compiled artifacts).
**Milestone:** v2 — polish mature version (brownfield maturation of shipped v1.x).
**Researched:** 2026-04-26.
**Overall confidence:** HIGH for the Claude Code authoring surface (verified against live `code.claude.com` docs); HIGH for dev-time tool versions (GitHub releases verified); MEDIUM only where noted.

This file is the prescriptive stack reference for the v2 roadmap. v1.x baseline is in `.planning/codebase/STACK.md` — that's the factual snapshot; this file says **what changes**.

---

## Summary: What v2 Adds vs v1.x

v1.x is a valid baseline. v2 adds **nothing at runtime** — `jq` remains the only mandatory dependency. Changes fall into four buckets:

1. **Authoring surface uplift.** Adopt the post-2025 plugin manifest fields (`userConfig`, `${CLAUDE_PLUGIN_DATA}`, `bin/`), the modern agent frontmatter (`effort`, `memory`, `isolation`, `maxTurns`, `background`, `color`), and the four new hook events that close v1.x's gaps (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionEnd`).
2. **Model-alias discipline.** Every agent frontmatter declares `model: opus|sonnet|haiku` (never pinned IDs) and explicit `effort:`. Code-touching agents use `effort: high` (`xhigh` on Opus 4.7 is documented to skip rules — locked into `rules/godmode-routing.md`, not just frontmatter).
3. **Dev-time CI guardrails.** Add `shellcheck` (v0.11.0), `bats-core` (v1.13.0), inline JSON Schema validation in `jq` (no Node), a pure-Bash frontmatter linter, and a GitHub Actions matrix (`macos-latest` + `ubuntu-latest`). All dev-time only — zero runtime impact, zero new mandatory deps.
4. **Single source of truth for the public surface.** `.claude-plugin/plugin.json` is the canonical version. `install.sh` reads it via `jq`. Skills/agents are enumerated by scanning the filesystem at hook execution time, not from hardcoded lists.

---

## Recommended Stack

### Runtime (unchanged — listed for completeness)

| Technology | Version | Purpose | Notes |
|---|---|---|---|
| Bash | 3.2+ | hooks, installer, statusline, `init-context` helper | macOS default. No 4.x-only constructs (`mapfile`, associative arrays in some forms, `${var,,}`). |
| jq | 1.6+ | every JSON read/write/merge | Only mandatory runtime tool. **All** generated JSON uses `jq -n --arg`/`--argjson` (never string interpolation). |
| Markdown + YAML frontmatter | — | rules, agents, skills, commands | Native Claude Code format. No build step. |
| JSON | — | `plugin.json`, `hooks.json`, `settings.template.json`, hook stdin/stdout | Claude Code's IO contract. |

**Confidence:** HIGH. Same as v1.x. **Constraint enforced:** no Node, no Python, no Ruby, no compiled binary in the runtime path.

### Authoring surface — Claude Code primitives v2 must adopt

#### Plugin manifest (`.claude-plugin/plugin.json`)

Verified against `https://code.claude.com/docs/en/plugins-reference` (2026-04-26).

| Field | v1.x | v2 action | Rationale |
|---|---|---|---|
| `name`, `description`, `author`, `homepage`, `repository`, `license`, `keywords` | ✓ | keep | metadata; nothing breaks. |
| `version` | ✓ but drifted (1.6.0 here, 1.4.1 in `install.sh`, 1.4.1 in `commands/godmode.md`) | **canonical** — every other file reads this at runtime via `jq`; CI gate prevents drift | resolves CONCERNS #10. |
| `skills`, `commands`, `agents`, `hooks` | ✓ | keep | components. |
| `userConfig` | ✗ | **add** — single key `model_profile` (string, default `balanced`, options `quality\|balanced\|budget`) | gives the user one knob without hand-editing `settings.json`. Substituted as `${user_config.model_profile}` in hook commands and exported as `CLAUDE_PLUGIN_OPTION_MODEL_PROFILE` in subprocesses. |
| `${CLAUDE_PLUGIN_DATA}` | ✗ | **add** — backup-rotation cursor, install marker, last-version-seen | survives plugin updates (unlike `${CLAUDE_PLUGIN_ROOT}`). Resolves to `~/.claude/plugins/data/<id>/`. |
| `bin/` directory | ✗ | **add** — internal helpers (e.g. `init-context`, `hash-rules`) become bare commands when plugin is enabled | clean way to give skills shell helpers without leaking absolute paths. |
| `monitors` | ✗ | **skip** — would require a long-running shell process; out of scope for v2. | requires Claude Code v2.1.105+; statusline is sufficient. |
| `lspServers`, `themes`, `outputStyles`, `channels`, `dependencies` | ✗ | **skip** | out of scope per PROJECT.md. |
| `mcpServers` | ✗ | **skip** | "no bundled MCP server" is in PROJECT.md Out-of-Scope. |

**Confidence:** HIGH (full manifest schema fetched directly from docs).

#### Agent frontmatter — every `agents/*.md`

Verified against `https://code.claude.com/docs/en/sub-agents` and the plugins reference (2026-04-26). The plugins reference is explicit: plugin agents support `name`, `description`, `model`, `effort`, `maxTurns`, `tools`, `disallowedTools`, `skills`, `memory`, `background`, `isolation`. Plugin agents **cannot** declare `hooks`, `mcpServers`, or `permissionMode` (security constraint).

| Field | Type | v1.x | v2 action |
|---|---|---|---|
| `name` | kebab-case string | ✓ | keep. |
| `description` | string | ✓ | rewrite each — must read like a delegation prompt ("use this when X"), not a job title. |
| `model` | `opus`, `sonnet`, `haiku`, full ID, or `inherit` | mixed | **alias only**, never pinned IDs. |
| `effort` | `low`, `medium`, `high`, `xhigh`, `max` | partial | **explicit on every agent**. Code-touching agents = `high` (avoids the `xhigh`-skips-rules failure mode); design/audit agents = `xhigh`. |
| `maxTurns` | integer | partial | **explicit on every agent** — defensive ceiling, not a soft hint. |
| `tools` / `disallowedTools` | array | ✓ | audit allowlists; prefer `disallowedTools` for read-only agents (smaller, safer surface). |
| `skills` | array of skill names | ✗ | declare for agents that should call specific skills (e.g. `@verifier` declares `verify`). |
| `memory` | `"user"` or `"project"` | ✗ | add `memory: project` to `@researcher` (persistent learnings). Requires Claude Code v2.1.33+. |
| `background` | boolean | ✗ | use for read-only researchers that can suspend (`@researcher`, optionally `@spec-reviewer`). |
| `isolation` | only valid value: `"worktree"` | ✗ | add to every code-writing agent (`@executor`, `@test-writer`, `@writer`). Resolves the parallel-execution file-conflict class. |
| `color` | hex / name | ✗ | optional — only if it materially improves the `/agents` UI. Low priority. |

**Confidence:** HIGH. The plugins reference (line 70 of the fetched doc) names the exact set verbatim.

#### Hook events — full v2 surface

Verified against `https://code.claude.com/docs/en/hooks` (2026-04-26). 24 events exist. v1.x uses two: `SessionStart`, `PostCompact`. v2 adds five.

| Event | Adopt? | v2 use |
|---|---|---|
| `SessionStart` | keep | inject project context + `.planning/STATE.md` current-brief snippet. |
| `PostCompact` | keep | re-inject quality gates and live-scanned skill/agent lists. |
| `PreToolUse` | **add** | block `Bash(git commit --no-verify*)` and similar quality-gate-bypass; refuse hardcoded-secret patterns in tool input. |
| `PostToolUse` | **add** | detect non-zero exit on test/lint/typecheck Bash calls; surface a corrective `additionalContext` in the next turn. |
| `UserPromptSubmit` | **add** | detect "Auto Mode" enable; emit a one-line note describing the brief lifecycle so /build doesn't surprise the user. |
| `SessionEnd` | **add** | rotate backups in `~/.claude/backups/` (keep last 5). Cheap, idempotent, prevents unbounded growth (CONCERNS #13). |
| `PreCompact` | skip | no clear win; manual `/compact` already covers logical breakpoints. |
| `SubagentStart` / `SubagentStop` | skip in v2 baseline | useful for telemetry; we don't ship telemetry. Reserve for a later observability brief. |
| `InstructionsLoaded` | skip | debug aid only; not user-facing. |
| `ConfigChange` / `CwdChanged` / `FileChanged` | skip | no use case in this plugin. |
| `WorktreeCreate` / `WorktreeRemove` | skip | `isolation: worktree` handles lifecycle automatically. |
| `Notification` / `Stop` / `StopFailure` | skip | no user-facing notification surface. |
| `PermissionRequest` / `PermissionDenied` / `Elicitation` / `ElicitationResult` | skip | MCP-server-specific. |
| `TaskCreated` / `TaskCompleted` / `TeammateIdle` | skip | agent-teams feature; not stable. |

**Hook output: never use the deprecated `decision: "approve"|"block"` shape.** Use `hookSpecificOutput.permissionDecision: "allow"|"deny"|"ask"` for `PreToolUse`. All decisions go through this shape.

**Hook timeouts.** The `command` hook default is **600 seconds** (verified against the hooks doc, 2026-04-26). Both `hooks/hooks.json` (plugin-mode) and `config/settings.template.json` (manual-mode) currently disagree on `timeout` — plugin-mode declares 10s, manual-mode is silent and defaults to 600s. v2 fix: declare the same explicit `"timeout": 10` in **both** files. Hooks should never run for 10 minutes.

**Hook types.** Use `command` exclusively. Reject `prompt` and `agent` hook types in v2 — they invoke the model on every event and would dwarf any per-tool latency budget. `http` and `mcp_tool` are out of scope (no server, no bundled MCP).

**Confidence:** HIGH (full event matrix verified; timeout default verified directly).

#### Skill (`SKILL.md`) frontmatter

Verified against `https://code.claude.com/docs/en/skills` (2026-04-26).

| Field | Required | v2 use |
|---|---|---|
| `name` | yes | becomes `/<name>`. kebab-case, `[a-z0-9-]+`, ≤ 64 chars. |
| `description` | yes | the auto-delegation signal. Include both **what** and **when**. ≤ 1024 chars. |
| `allowed-tools` | no | declare per skill — narrower-than-session set is the win. |
| `argument-hint` | no | shown in `/` autocomplete. Use for `/brief N`, `/plan N`, `/build N`, `/verify N`. |
| `disable-model-invocation` | no | useful for `/refactor` and other skills the user must trigger explicitly. Skip in v2 baseline; reconsider per-skill. |
| `model` | no | overrides the session model for this skill. Skip — let the agent frontmatter own model choice. |

**Confidence:** HIGH.

#### Slash commands (`commands/*.md`)

Lighter weight than skills (flat file, no SKILL.md envelope). v2 keeps `commands/godmode.md` as the entry point and adds the rest as **skills** (`/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`) so they can carry `allowed-tools` and richer instructions.

### Model lineup — `model:` aliases

Verified against the plugins reference and Anthropic model docs (2026-04-26).

| Alias | Resolves to | When |
|---|---|---|
| `opus` | claude-opus-4-7 | high-leverage agents (`@architect`, `@security-auditor`, `@planner`, `@verifier`). |
| `sonnet` | claude-sonnet-4-6 | mid-tier agents (`@reviewer`, `@spec-reviewer`, `@code-reviewer`, `@test-writer`, `@researcher`, `@doc-writer`). |
| `haiku` | claude-haiku-4-5 | fast bounded helpers (e.g. classifiers, summarizers). |
| `inherit` | session model | use **only** in third-party-runtime contexts (Bedrock/Vertex). Not in v2 frontmatter. |

**Effort assignments — locked into `rules/godmode-routing.md`, not just frontmatter:**

| Agent | Model | Effort | Why |
|---|---|---|---|
| `@architect` | opus | xhigh | design quality > rule adherence. |
| `@security-auditor` | opus | xhigh | threat modelling benefits from depth; agent is read-only so rule-skip risk is bounded. |
| `@planner` | opus | xhigh | brief → plan synthesis benefits from reasoning depth; read-mostly. |
| `@verifier` | opus | xhigh | goal-backward audit; read-only. |
| `@executor`, `@writer`, `@test-writer` | opus / sonnet | **high** | code-touching. `xhigh` on Opus 4.7 has documented rule-skip behavior — `high` is the safe default. |
| `@reviewer`, `@spec-reviewer`, `@code-reviewer`, `@researcher`, `@doc-writer` | sonnet | high | fits Sonnet's strength profile; cheaper and faster than Opus for these. |

**Confidence:** HIGH for aliases; HIGH for the effort-on-Opus-4.7 caveat (documented in PROJECT.md "Key Decisions").

### Dev-time tooling (CI-only — zero runtime cost)

#### shellcheck v0.11.0

- **What:** static analysis for shell. Catches unquoted variables, unescaped JSON interpolation, the SC2064-class trap fragility, etc.
- **Why:** v1.x has documented hook fragility under adversarial inputs (CONCERNS #6). `shellcheck` catches these statically.
- **Version:** v0.11.0, released 2025-08-04 (verified against `https://github.com/koalaman/shellcheck/releases`).
- **Install:** `brew install shellcheck` (macOS), `apt install shellcheck` (Linux), `ludeeus/action-shellcheck@master` in CI. No runtime install.
- **Config:** `.shellcheckrc` at repo root: `shell=bash`, `external-sources=true`, intentional disables enumerated (e.g. `disable=SC1091` for sourced files we know exist at install time).
- **Don't use:** `shfmt`. Reformatter; opinionated on indentation; would churn the entire codebase for no v2 win.
- **Confidence:** HIGH.

#### bats-core v1.13.0

- **What:** TAP-compliant Bash test runner. Tests `install.sh`, `uninstall.sh`, hook scripts, `statusline.sh` in a temporary `$HOME`.
- **Why:** v1.x has zero automated tests (CONCERNS #20). bats covers the install → `/godmode` → uninstall round trip required by the QUAL-05 requirement.
- **Version:** v1.13.0, released 2024-11-07 (verified against `https://github.com/bats-core/bats-core/releases`). Bash 3.2 compatible — works on macOS default shell.
- **Install (CI):** `brew install bats-core` (macOS) / `apt install bats` (Linux), companions `bats-support` and `bats-assert` from the bats-core org. No runtime install.
- **Test layout:** `tests/install.bats`, `tests/uninstall.bats`, `tests/hooks.bats`, `tests/statusline.bats`. Each test is hermetic — runs in `mktemp -d` as `$HOME`.
- **Don't use:** `sstephenson/bats` (original; archived; Bash 4+ only — would break the macOS-default-shell guarantee). Don't use `shunit2` (no TAP, no fixture support).
- **Confidence:** HIGH.

#### JSON Schema validation — pure jq, no Node

This is where the jq-only constraint forces a deliberate choice.

- **What we need:** structural checks on `plugin.json`, `hooks.json`, `settings.template.json`, and `.planning/config.json`.
- **What we don't need:** full JSON-Schema-2020-12 conformance. We need ~20 assertions per file — required keys present, types correct, hook events from the known set, `model:` from `{opus, sonnet, haiku}`.
- **Recommended:** **inline jq assertions** in `scripts/lint-json.sh`. One file per schema, each assertion a `jq -e` expression; failure is a nonzero exit and a readable error message. Example: `jq -e '.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' plugin.json`.
- **Why not ajv-cli / jsonschema (Python) / sourcemeta-jsonschema (C++ binary):** `ajv-cli` adds Node.js as a CI dep; the Python `jsonschema` adds a Python dep; `sourcemeta/jsonschema` is AGPL (using only as a CI tool doesn't trigger copyleft on our code, but it's a 30+ MB single-platform binary to manage in CI). jq is already a project requirement — extending its use to validation is the lowest-friction option and keeps the jq-only constraint clean even at CI time.
- **Cost:** ~150 lines of `jq -e` checks total across four schemas. Each check is self-documenting.
- **Confidence:** HIGH for the approach (jq is sufficient for the assertions we actually need); MEDIUM for skipping a "real" JSON Schema validator (we trade conformance for dependency-cleanliness — a deliberate, documented tradeoff).

#### Frontmatter linter — pure Bash + awk

- **What:** `scripts/lint-frontmatter.sh` extracts the YAML between `---` markers in `agents/*.md`, `skills/*/SKILL.md`, `commands/*.md` and asserts required fields per type.
- **Why:** drift between filesystem and hardcoded lists is a v1.x concern (CONCERNS #8). Catching missing `description` or invalid `model:` in CI is a one-script fix.
- **Required fields by type:**
  - **agents:** `name`, `description`, `model ∈ {opus, sonnet, haiku}`, `effort ∈ {low, medium, high, xhigh, max}`, `maxTurns` (integer).
  - **skills:** `name` (kebab-case), `description` (≤1024 chars).
  - **commands:** `description`.
- **Implementation:** awk to extract block, grep for required keys, jq to validate enums (after converting YAML to JSON via a 20-line awk filter — sufficient for our flat YAML, no nested structures used).
- **Don't use:** `markdownlint-cli2`, `remark-lint-frontmatter-schema`, `frontmatter-lint`. All Node.js. Overkill for ≤6 fields per file.
- **Confidence:** HIGH.

#### GitHub Actions workflow

- **Shape:** one workflow `.github/workflows/ci.yml` with a matrix of `[ubuntu-latest, macos-latest]`. One job, four steps: `shellcheck`, `bash scripts/lint-json.sh`, `bash scripts/lint-frontmatter.sh`, `bats tests/`.
- **`actions/checkout@v4`** for the checkout step.
- **`ludeeus/action-shellcheck@master`** for shellcheck. The action handles installing `shellcheck` on both macOS and Ubuntu runners.
- **bats install:** `brew install bats-core` on macOS; `sudo apt-get install -y bats` on Ubuntu.
- **No Node setup step.** No `actions/setup-node`. No `npm install`. The CI itself respects the runtime-dep constraint.
- **Don't use:** Docker-based jobs. `install.sh` modifies `$HOME/.claude/`; smoke tests need a real home directory, not a containerized one.
- **Don't use:** `macos-14`/M-series-only runners. Many users still run Intel macOS; `macos-latest` covers Intel today.
- **Confidence:** HIGH.

---

## Constraints (re-asserted, with the rule-out impact)

### "jq is the only mandatory runtime dep"

This rules out:

| Tool | What it would have given us | What we use instead |
|---|---|---|
| Node.js (`ajv-cli`, `markdownlint-cli2`, `remark`, `gsd-sdk`) | first-class JSON Schema validation, frontmatter linting, workflow CLI | inline `jq -e` assertions, pure-Bash awk extractor, bash + jq for any state op |
| Python (`jsonschema`, `yamllint`, `pre-commit`) | richer schema/lint surface, framework for git hooks | `jq -e` for JSON, the bash frontmatter linter for YAML, native git hooks if we ever need them |
| SQLite | structured session/agent memory | Markdown files in `.planning/` (which is what humans read anyway) |
| Compiled binary (`sourcemeta/jsonschema`, `ajv` standalone) | full JSON Schema 2020-12 conformance | targeted `jq -e` checks (we don't need conformance — we need the ~20 assertions per schema we actually care about) |
| MCP server bundled with the plugin | first-party tool surface | document recommended user-installed MCP servers (Context7, etc.) in the README |

**Workaround when something genuinely needs Node/Python:** ship as a `bin/` helper that shells out to `command -v node` first and falls back to a pure-bash path, **or** keep it dev-time-only (CI / contributor tooling) and document the workflow. v2 has zero current cases that need this — every gap above closes with bash + jq.

### "≤ 12 user-facing slash commands"

The locked v2 surface (per PROJECT.md):

```
/godmode  /mission  /brief N  /plan N  /build N  /verify N  /ship
/debug    /tdd      /refactor /explore-repo
```

11 commands. One slot reserved.

Implementation: `/godmode` stays a flat command (`commands/godmode.md`). The other 10 are skills (`skills/<name>/SKILL.md`) so they can carry `allowed-tools`, `argument-hint`, and richer system prompts. **Internal orchestrators (e.g. anything for sub-step routing) are subagents (`agents/*.md`), not user-facing commands.**

### "Plugin-mode UX == manual-mode UX"

Implications carried forward:

- `hooks/hooks.json` and `config/settings.template.json` must declare the same hook events with the same `timeout` values. CI gate: `scripts/lint-json.sh` asserts both files reference identical hook event sets.
- Both modes resolve plugin paths via `${CLAUDE_PLUGIN_ROOT}` (plugin mode) or absolute paths under `$HOME/.claude/` (manual mode). Hook scripts must work under both — never assume cwd.
- `userConfig` works only in plugin mode; manual-mode users get the default profile and can edit a single file (`~/.claude/settings.json`'s `pluginConfigs.claude-godmode.options`) by hand.

---

## Version compatibility floor

| Feature | Min Claude Code | Action |
|---|---|---|
| `memory: project` agent frontmatter | v2.1.33 (Feb 2026) | declare in README under "Requirements". |
| `monitors` plugin manifest | v2.1.105 | not used in v2. |
| Opus 4.7 (`opus` alias) | v2.1.111 | declare minimum CC version in README. |
| Default effort `xhigh` on Opus | v2.1.117 | already the session default; explicit `effort:` in agent frontmatter overrides correctly. |
| `userConfig` sensitive keychain storage | v2.1.x (current) | `model_profile` is non-sensitive; no keychain dependency. |

**Recommended floor:** Claude Code v2.1.111 (for the `opus` alias). Document in README. Don't pin tighter — plugin features beyond that are optional (`monitors`) or not used.

**Confidence:** HIGH for the specific feature → version mapping. Document the floor; don't assert features above it.

---

## Alternatives considered (and rejected)

| Recommended | Alternative | Why not |
|---|---|---|
| `shellcheck` v0.11.0 | `shfmt` formatter | reformats on save; would churn the entire codebase for no v2 win. |
| `bats-core` v1.13.0 | `shunit2` | no TAP output, no fixture support, no `bats-assert`-equivalent. |
| Inline `jq -e` assertions | `ajv-cli` | adds Node.js as a CI dep. Violates the spirit of the runtime constraint even at CI time. |
| Inline `jq -e` assertions | `sourcemeta/jsonschema` (C++ binary) | AGPL; 30+ MB single-platform binary; far more conformance than we need. |
| Pure-Bash frontmatter linter | `markdownlint-cli2` | Node.js dep; checks Markdown formatting, not the semantic frontmatter fields we care about. |
| Model aliases (`opus`/`sonnet`/`haiku`) | Pinned IDs (`claude-opus-4-7`) | manual maintenance; aliases auto-update when Anthropic ships new tier. |
| `effort: high` on code-touching agents | `effort: xhigh` | Opus 4.7's `xhigh` has documented rule-skip behavior (PROJECT.md Key Decisions). |
| `isolation: worktree` on `@executor` etc. | Shared cwd | parallel execution in v1.x produces file conflicts; worktree isolation eliminates the class. |
| Inline jq with `--arg`/`--argjson` for hook JSON | String-interpolated heredoc JSON | adversarial branch names break v1.x hooks (CONCERNS #6). |
| `${CLAUDE_PLUGIN_DATA}` for backup-rotation cursor | Writing under `${CLAUDE_PLUGIN_ROOT}` | ROOT changes on plugin update; DATA persists. The whole point of DATA is exactly this case. |

---

## What NOT to add (explicit)

| Avoid | Why | Instead |
|---|---|---|
| Any Node, Python, or Ruby in the runtime path | violates the jq-only constraint | bash + jq exclusively. |
| Bundled MCP server | out of scope per PROJECT.md | recommend Context7 etc. in the README. |
| `agent` or `prompt` hook types | LLM call per hook event = unacceptable latency | `command` only. |
| Pinned model IDs in any frontmatter | manual maintenance burden | `opus`/`sonnet`/`haiku` aliases. |
| New Claude Code experimental features (agent teams, PowerShell, channels) | unstable / out of scope | revisit in a later milestone if demand emerges. |
| `pre-commit` framework | Python dep; we have native git hooks already | `hooks.json` for Claude Code lifecycle, native git hooks (if needed) for git lifecycle. |
| `Dockerfile` for development | "install.sh modifies $HOME" makes Docker testing more pain than it's worth | bats in a temporary `$HOME` (`mktemp -d`). |
| `make`-based build | nothing to build; `bash install.sh` is the entry point | keep the installer as the single entry. |

---

## Where each v2 addition lives in the repo

| Addition | Path | Notes |
|---|---|---|
| Agent frontmatter modernization | `agents/*.md` | every agent: explicit `effort`, `maxTurns`, `isolation` (where applicable), `memory` (where applicable). |
| New hook scripts | `hooks/pre-tool-use.sh`, `hooks/post-tool-use.sh`, `hooks/user-prompt-submit.sh`, `hooks/session-end.sh` | alongside existing `session-start.sh`, `post-compact.sh`. All emit JSON via `jq -n --arg`. |
| Hook bindings (plugin mode) | `hooks/hooks.json` | every event listed; explicit `"timeout": 10`. |
| Hook bindings (manual mode) | `config/settings.template.json` | identical event set; identical `"timeout": 10`. |
| Quality gates source-of-truth | `config/quality-gates.txt` | one gate per line; `post-compact.sh` reads it. Resolves CONCERNS #9. |
| Live skill/agent enumeration | `hooks/post-compact.sh` | scan `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md` and `${CLAUDE_PLUGIN_ROOT}/agents/*.md` at runtime. Resolves CONCERNS #8. |
| Backup rotation | `hooks/session-end.sh` | keep last 5 in `~/.claude/backups/`. Resolves CONCERNS #13. |
| `${CLAUDE_PLUGIN_DATA}` use | `install.sh`, `hooks/session-end.sh` | install marker, last-version-seen, rotation cursor. |
| Version SOT | `.claude-plugin/plugin.json` `version` field | `install.sh` reads via `jq`; `commands/godmode.md` drops the literal version (statusline carries it). |
| `userConfig` block | `.claude-plugin/plugin.json` | single key `model_profile` (default `balanced`). |
| `bin/` helpers | `bin/init-context`, `bin/hash-rules` (if needed) | exposes shell helpers as bare commands when plugin is enabled. |
| shellcheck config | `.shellcheckrc` | repo root. |
| JSON schema lint | `scripts/lint-json.sh` | inline `jq -e` per file. |
| Frontmatter lint | `scripts/lint-frontmatter.sh` | pure Bash + awk + jq. |
| bats tests | `tests/install.bats`, `tests/uninstall.bats`, `tests/hooks.bats`, `tests/statusline.bats` | each runs in `mktemp -d` as `$HOME`. |
| CI workflow | `.github/workflows/ci.yml` | matrix `[ubuntu-latest, macos-latest]`; four steps. |

---

## Confidence assessment per recommendation

| Area | Confidence | Note |
|---|---|---|
| Plugin manifest fields (`userConfig`, `${CLAUDE_PLUGIN_DATA}`, `bin/`) | HIGH | full schema fetched from `code.claude.com/docs/en/plugins-reference`. |
| Agent frontmatter set (`effort`, `memory`, `isolation`, `background`, `color`, `skills`) | HIGH | plugins reference enumerates the exact set; restriction on `hooks`/`mcpServers`/`permissionMode` is verbatim. |
| Hook event matrix | HIGH | full 24-event table fetched from `code.claude.com/docs/en/hooks`; deprecated output shape verified. |
| Hook `command` default timeout = 600s | HIGH | verified directly against the hooks doc — corrects the CONCERNS-implied assumption of 60s. |
| Model aliases | HIGH | matches Anthropic's documented alias semantics; `opus[1m]` 1M-context variant exists for Opus. |
| `effort: xhigh` rule-skip behavior on Opus 4.7 | HIGH (per PROJECT.md Key Decisions); MEDIUM externally | locked into our routing rule regardless. |
| shellcheck v0.11.0 | HIGH | release verified Aug 2025. |
| bats-core v1.13.0 | HIGH | release verified Nov 2024; Bash 3.2 compatibility documented. |
| Inline jq for JSON schema (vs ajv/sourcemeta) | HIGH on the choice; MEDIUM on covering every future schema need | deliberate tradeoff: dependency cleanliness > full conformance. Documented. |
| Pure-Bash frontmatter linter | HIGH | scope is small (≤6 fields per type); awk + jq is sufficient. |
| GitHub Actions matrix shape | HIGH | both `actions/checkout@v4` and `ludeeus/action-shellcheck@master` are current standards. |

---

## Sources

- `https://code.claude.com/docs/en/plugins-reference` — plugin manifest schema, agent frontmatter restrictions for plugin-shipped agents, `${CLAUDE_PLUGIN_DATA}` semantics, `userConfig` schema, `bin/` directory behavior, monitor minimum version. **HIGH** confidence (full doc fetched).
- `https://code.claude.com/docs/en/hooks` — full 24-event matrix, deprecated `decision: approve|block` shape, `command`/`prompt`/`agent` hook timeout defaults (600 / 30 / 60 seconds). **HIGH**.
- `https://code.claude.com/docs/en/sub-agents` — agent frontmatter fields (`model`, `effort`, `isolation: worktree`, `maxTurns`, `memory`, `background`). **HIGH**.
- `https://code.claude.com/docs/en/skills` — skill frontmatter (`name`, `description`, `allowed-tools`, `argument-hint`, `disable-model-invocation`). **HIGH**.
- `https://github.com/koalaman/shellcheck/releases` — v0.11.0, released 2025-08-04. **HIGH**.
- `https://github.com/bats-core/bats-core/releases` — v1.13.0, released 2024-11-07. **HIGH**.
- `https://github.com/ludeeus/action-shellcheck` — current GitHub Action; works on macOS and Ubuntu runners. **HIGH**.
- v1.x baseline: `.planning/codebase/STACK.md`, `STRUCTURE.md`, `CONCERNS.md` (this repo). **HIGH** (factual analysis of shipped code).

---

*Stack research for: claude-godmode v2 — polish mature version.*
*Researched: 2026-04-26.*
