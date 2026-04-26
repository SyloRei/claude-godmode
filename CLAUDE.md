# claude-godmode

This repo is the `claude-godmode` plugin for Claude Code — a packaged set of rules, agents, skills, hooks, statusline, and permissions installed into a user's `~/.claude/` so Claude Code itself behaves like a senior engineering team. v1.x is shipped; we are currently building **v2 — polish mature version**.

## Guiding principle (locked 2026-04-26 re-init)

Reference plugins (GSD/Get Shit Done, Superpowers, everything-claude-code) are **inspiration sources only, not adoption targets**. We read them freely to learn validated patterns and avoid known pitfalls. We do **not** vendor their code, adopt their directory shapes, mirror their command surfaces, or borrow their vocabulary. Output is ours.

If you're tempted to type `/discuss-phase`, `/plan-phase`, `/execute-phase`, `/gsd-*`, or use the words "phase" or "task" in workflow contexts — stop. Use the project's own naming (below).

## Two workflow shapes (dev vs product — don't confuse them)

This repo ships a **plugin** for end users; we (developers) **build** that plugin under a different process. Two different shapes:

| Concern | Shape | Lives in |
|---|---|---|
| **Dev process** (how we build v2) | GSD phases — `/gsd-discuss-phase`, `/gsd-plan-phase`, `/gsd-execute-phase`, `/gsd-verify-work` | `.planning/phases/N-name/{CONTEXT.md, PLAN.md, …}` |
| **Plugin product** (what we ship) | Briefs — `/brief N`, `/plan N`, `/build N`, `/verify N` | (consumer's `.planning/briefs/NN-name/{BRIEF.md, PLAN.md}`) |

The plugin's user-facing vocabulary stays brief-shaped — that's locked. The dev-side `.planning/` uses GSD's phase shape because we adopted GSD as our dev toolchain on 2026-04-26 (Path A re-bootstrap). When you're working in `.planning/`, think phases. When you're authoring `commands/` / `skills/` / `agents/` content for the plugin, think briefs.

The bespoke v1 planning shape (briefs at the dev level too) is archived at `.planning-archive-v1/` (gitignored); it's preserved if we ever need to reference the prior thinking.

## Plugin's user-facing workflow model: Project → Mission → Brief → Plan → Commit

| Concept | Lives in (consumer's repo) | Command |
|---|---|---|
| Project | `.planning/PROJECT.md` (persistent) | implicit |
| Mission | section of PROJECT.md + `.planning/ROADMAP.md` | `/mission` |
| Brief | `.planning/briefs/NN-name/BRIEF.md` (why + what + spec) | `/brief N` |
| Plan | `.planning/briefs/NN-name/PLAN.md` (tactical + verification) | `/plan N` |
| Commit | git log (atomic, gated) | `/build N` |

**Two artifact files per active brief: BRIEF.md and PLAN.md.** No EXECUTE.md, no TASK.md. The git log IS the execution log. This is the contract the plugin exposes to its users.

## Plugin's user-facing slash commands (locked at 11, ≤12 cap, 1 reserved)

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

- **Plugin source.** `rules/`, `agents/`, `skills/`, `commands/`, `hooks/`, `config/`, `install.sh`, `uninstall.sh`, `.claude-plugin/plugin.json`. This is what gets installed to a user's `~/.claude/`.
- **Bespoke v1 codebase audit.** `.planning-archive-v1/codebase/` — STACK, ARCHITECTURE, STRUCTURE, CONVENTIONS, INTEGRATIONS, TESTING, CONCERNS. Factual analysis of v1.x baseline (preserved gitignored across the re-bootstrap).
- **Dev planning (GSD shape).** `.planning/PROJECT.md`, `REQUIREMENTS.md` (46 reqs), `ROADMAP.md` (5 phases), `STATE.md`, `research/` (5 files), `config.json`. Per-phase artifacts will land at `.planning/phases/NN-name/` once `/gsd-discuss-phase` runs.
- **`.planning/` is tracked** (commit_docs=true in config.json) so the dev-side roadmap is auditable in git history. The bespoke `.planning-archive-v1/` and `.claude-pipeline/` (v1.x runtime) remain gitignored.

## How to work in this repo

The plugin's user-facing slash commands are still being built (that's the v2 milestone). Use GSD's dev toolchain to build them:

1. **Orient** — `/gsd-progress` (or read `.planning/STATE.md`) to find the active phase.
2. **Discuss** — `/gsd-discuss-phase N` to gather context and clarify approach.
3. **Plan** — `/gsd-plan-phase N` to produce the tactical breakdown.
4. **Build** — `/gsd-execute-phase N` to run plans with wave-based parallelism, atomic commit per task.
5. **Verify** — `/gsd-verify-work` to check each success criterion COVERED/PARTIAL/MISSING.
6. **Ship** — `/gsd-ship` to gate, push, and open a PR.

(Once Phase 4 lands and the plugin's own slash commands ship, future development *of* the plugin can dogfood `/godmode → /mission → /brief → /plan → /build → /verify → /ship` instead of GSD's `/gsd-*` chain. Until then we're on GSD.)

Reference plugins (GSD, Superpowers, everything-claude-code) are running in this session for tooling. **Do not adopt their vocabulary into the plugin we're building.** Use them as inspiration; ship our own shape.

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

After Phase 3, gates are mechanically enforced by `PreToolUse` hook on `Bash(git commit *)` and `PostToolUse` surfacing of failed exit codes. Gates list lives in a single source (`config/quality-gates.txt`) — not duplicated across rules + post-compact.

## Current focus

See `.planning/STATE.md`. As of 2026-04-26 (re-bootstrap onto GSD shape): **Phase 1 — Foundation & Safety Hardening** is next. 11 requirements (FOUND-01..FOUND-11). Run `/gsd-discuss-phase 1 --auto` to begin.

## Two things never to do

1. **Never edit `~/.claude/settings.json` directly while developing this repo.** It's the user's, not the plugin's. The plugin merges into it via `install.sh`. Test changes via `./install.sh` into a temporary `$HOME` instead.
2. **Never commit `.claude/`, `.claude-pipeline/`, or `.planning-archive-v1/`.** All three are runtime/agent state and gitignored. `.planning/` IS tracked (commit_docs=true under our GSD config) — that's deliberate so the dev roadmap is auditable.

---

For everything else, the rules in `rules/godmode-*.md` are canonical. They are loaded into every session by Claude Code's rules system; you do not need to re-read them inline.

<!-- GSD:project-start source:PROJECT.md -->
## Project

**claude-godmode**

`claude-godmode` is a Claude Code plugin that ships rules, agents, skills, hooks, statusline, and permissions to make Claude Code behave like a senior engineering team out of the box. v1.x is shipped (8 agents, 8 skills, `/prd → /plan-stories → /execute → /ship` pipeline, plugin+manual install). This milestone — **v2: polish mature version** — replaces the v1.x pipeline with a single clear workflow, hardens every defect surfaced by the v1.x audit, modernizes the agent layer to the Claude Code 2026 capability surface (Opus 4.7, `effort: xhigh`, auto mode, plugin marketplace, native skills/agents/hooks), and incorporates the strongest patterns from three reference plugins (GSD, Superpowers, everything-claude-code) without becoming a clone of any of them.

The audience is solo developers and small engineering teams who want production-grade Claude Code behavior without assembling parts from multiple plugins, without learning a six-level vocabulary, and without feeling like they bought a kit.

**Core Value:** **A single, clear workflow where every agent, skill, and tool is connected and named for the user's intent — best-in-class capability behind the simplest possible surface.**

If everything else fails, this must hold: a user installs `claude-godmode`, runs `/godmode`, and within five lines of output knows what to do next. They follow one obvious arrow chain to ship a feature. Every agent has one stated goal, every skill has one trigger, every hook has one safety contract. The chain is visible end-to-end, rendered from the live filesystem (no hardcoded lists, no registry edits to upgrade).

### Constraints

- **Tech stack**: Bash 3.2+ and `jq` 1.6+ only at runtime. No Node, Python, helper binary, or SDK dependency.
- **Portability**: macOS + Linux. WSL2 for Windows. Bash 3.2-compatible patterns only (no `mapfile`, `[[ -v ]]`, `${var,,}`, associative arrays, GNU-only `head -n -N`).
- **Command surface**: Exactly 11 user-facing slash commands in v2. ≤12 cap. One reserved slot. Every command has one stated goal and one output artifact.
- **Atomic commits**: Per workflow gate (per-task in `/build`, per-step in installer). Never `--no-verify`. Never bypass quality gates.
- **Plugin-mode == manual-mode**: Hook bindings, permissions, timeouts must agree across both install paths. CI parity gate enforces.
- **License**: MIT, no copyleft deps. No telemetry. No network calls outside user-authorized tools.
- **Version single source of truth**: `.claude-plugin/plugin.json:.version` is canonical; everything else reads from it via `jq` at runtime.
- **Reference scope**: Read references freely; copy nothing structural. No vocabulary, directory shapes, or command names borrowed.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Runtime (locked, unchanged from v1.x — listed for completeness)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Bash | 3.2+ | hooks, installer, statusline, `bin/` helpers | macOS default shell. No 4.x-only constructs. |
| jq | 1.6+ | every JSON read/write/merge in shell | Only mandatory runtime tool. All emitted JSON via `jq -n --arg`/`--argjson` (never heredoc interpolation). |
| Markdown + YAML frontmatter | — | rules, agents, skills, commands | Native Claude Code authoring format. |
| JSON | — | `plugin.json`, `hooks.json`, `settings.template.json`, hook stdin/stdout | Claude Code's IO contract. |
### Authoring Surface (v2 — what to adopt)
#### Plugin manifest — `.claude-plugin/plugin.json`
| Field | Type | v2 use |
|---|---|---|
| `name` | string (kebab-case) | `"claude-godmode"` |
| `version` | string (semver) | **Single source of truth.** `install.sh`, `commands/godmode.md`, `README.md`, `CHANGELOG.md` all read from here at runtime via `jq -r '.version' .claude-plugin/plugin.json`. CI gate (`scripts/check-version-drift.sh`) refuses commits where any other file disagrees. Without `version`, Claude Code falls back to git SHA — we want explicit semver. |
| `description` | string | "Senior engineering team, in a plugin." Marketplace-shaped. |
| `author` | object `{name,email,url}` | required for marketplace listing. |
| `homepage` | string | repo URL. |
| `repository` | string | repo URL. |
| `license` | string | `"MIT"`. Hard requirement — copyleft is out of scope. |
| `keywords` | array | `["workflow","agents","skills","hooks","planning","quality-gates"]`. Affects discovery. |
| `skills` | string\|array | `"./skills/"` (default; can be omitted). |
| `commands` | string\|array | `"./commands/"` (default; can be omitted). |
| `agents` | string\|array | `"./agents/"` (default). |
| `hooks` | string\|array\|object | `"./hooks/hooks.json"` (default). |
| `userConfig` | object | **NEW in v2.** Single key: `model_profile` (string, default `"balanced"`, options `quality\|balanced\|budget`). One user-tunable knob. Substituted as `${user_config.model_profile}` in hook commands; exported as `CLAUDE_PLUGIN_OPTION_MODEL_PROFILE` to subprocesses. |
| Field | Why not |
|---|---|
| `mcpServers` | "no bundled MCP server" is project Out-of-Scope. |
| `lspServers` | not a language-tool plugin. |
| `outputStyles` | adds surface area; not in scope. |
| `themes` | aesthetic only; not core value. |
| `monitors` | requires a long-running shell process per session; statusline already covers cost/context. Telemetry-adjacent — out of scope per PROJECT.md. |
| `channels` | MCP-server-bound; we have no server. |
| `dependencies` | no plugin-to-plugin deps; we are self-contained. |
#### `${CLAUDE_PLUGIN_ROOT}` vs `${CLAUDE_PLUGIN_DATA}` — survival semantics
- **`${CLAUDE_PLUGIN_ROOT}`** = absolute path to the plugin's installed directory. **Resets on plugin update** (marketplace plugins are cached under `~/.claude/plugins/cache/<id>/<version>/`; old version directories are marked orphaned and pruned 7 days later). Use for: scripts bundled with the plugin, `bin/` helpers, read-only configs.
- **`${CLAUDE_PLUGIN_DATA}`** = `~/.claude/plugins/data/<id>/`. **Survives updates and is per-installation persistent.** Use for: install marker, last-version-seen, backup-rotation cursor, anything that should survive a plugin bump.
#### Hook contract — stdin/stdout JSON shapes
- Claude Code does **NOT** validate JSON the hook emits. Malformed JSON is treated as plain-text additional context (silent corruption — this is exactly what CONCERNS #6 hit when branch names contained quotes).
- No stdin sanitization: hook receives verbatim event data. Hook owns input validation.
- `additionalContext`/`systemMessage`/plain stdout combined are capped at **10,000 characters** before being injected. Excess is saved to a file with preview + path. Important for `PostCompact`'s skill list + quality gates (well under cap, but worth knowing).
- Exit 0: stdout parsed as JSON if valid, else added as plain context.
- Exit 2: blocking. Stdout/JSON ignored. Stderr fed back.
#### Subagent contract — `agents/*.md` frontmatter
| Field | Required | v2 policy |
|---|---|---|
| `name` | yes | kebab-case, lowercase, hyphens only. Mirrors filename. |
| `description` | yes | Reads as a delegation prompt: "Use this when X." NOT a job title. |
| `model` | recommended | **`opus`/`sonnet`/`haiku` aliases ONLY.** Never pinned IDs. The full ID `claude-opus-4-7` works but creates manual upgrade burden. |
| `effort` | yes (per v2 policy) | Explicit on every agent. Code-touching → `high`. Design/audit/read-only → `xhigh`. (See "Effort policy" below.) |
| `maxTurns` | yes (per v2 policy) | Defensive ceiling. Stops runaway agents. Per-agent — not session-wide. |
| `tools` | optional | Allowlist when read-only is critical. |
| `disallowedTools` | optional | Denylist preferred when "inherit minus" is the natural shape (e.g., read-only agents that shouldn't `Write`/`Edit`). |
| `skills` | optional | Preload skills into the subagent's context (full content injected, not just available). Use for `@verifier` (preload `verify`), `@planner` (preload `plan`). |
| `memory` | optional | `project` (default for persistent learners — `.claude/agent-memory/<name>/`), `user`, or `local` (gitignored). v2 uses `project` for `@researcher`. **Requires Claude Code v2.1.33+.** Memory is read at startup as the first 200 lines or 25KB of `MEMORY.md` (whichever first), with a curation instruction in the system prompt if larger. Read/Write/Edit auto-enabled. |
| `background` | optional | `true` for read-only suspendable subagents (`@researcher`). |
| `isolation` | optional | Only valid value: `"worktree"`. v2 declares on every code-writing agent (`@executor`, `@writer`, `@test-writer`). Worktree is auto-cleaned if no changes. Eliminates parallel-execution file-conflict class. |
| `color` | optional | One of `red, blue, green, yellow, purple, orange, pink, or cyan`. Cosmetic — assign for `/agents` UI legibility. |
| Agent | model | effort | Why |
|---|---|---|---|
| `@architect`, `@security-auditor`, `@planner`, `@verifier` | `opus` | `xhigh` | Design/audit work benefits from depth. Read-only or read-mostly. |
| `@executor`, `@writer`, `@test-writer` | `opus` | `high` | Code-touching. **`xhigh` skips rules on Opus 4.7 per Anthropic-documented behavior** (locked into PROJECT.md Key Decisions). `high` is the safe default. |
| `@reviewer`, `@spec-reviewer`, `@code-reviewer`, `@researcher`, `@doc-writer` | `sonnet` | `high` | Sonnet's strength profile fits review/research. |
| Trivially-bounded helpers (classifiers, format checkers) | `haiku` | (default) | Speed > depth. |
#### Skill contract — `skills/<name>/SKILL.md` frontmatter
| Field | Required | v2 use |
|---|---|---|
| `name` | optional (defaults to dir name) | Lowercase letters, numbers, hyphens, max 64 chars. v2 sets explicitly so it survives a directory rename. |
| `description` | recommended | What + when. Front-load the key use case — combined `description + when_to_use` is truncated at **1,536 characters** in the skill listing. |
| `when_to_use` | optional | Trigger phrases / example requests, appended to description. |
| `argument-hint` | optional | Shown in `/` autocomplete. v2: `[N]` for `/brief N`, `/plan N`, `/build N`, `/verify N`. |
| `arguments` | optional | Named positional args. With `arguments: [issue, branch]`, `$issue` = first arg, `$branch` = second. v2: declare on `/brief`, `/plan`, `/build`, `/verify` so the substitution reads `$N` instead of `$ARGUMENTS[0]`. |
| `disable-model-invocation` | optional (default false) | Set `true` for skills the user must trigger explicitly (e.g., `/build`, `/ship` — side-effecting, dangerous to auto-invoke). |
| `user-invocable` | optional (default true) | Set `false` for background-knowledge skills (none in v2 baseline). |
| `allowed-tools` | optional | Pre-approves listed tools while skill is active. v2: scope per skill (`/build` allows `Bash(git *)`, `/verify` allows only `Read, Grep, Glob`). |
| `model` | optional | Overrides session model for this skill's turn. v2: leave to agent frontmatter; do not double-control. |
| `effort` | optional | Same as model — leave to agent frontmatter. |
| `context: fork` | optional | Runs the skill in a forked subagent context. **v2 uses `context: fork` + `agent: Plan` for `/explore-repo`** (read-only research agent). |
| `agent` | optional | When `context: fork`, names the subagent. |
| `hooks` | optional | Skill-scoped hooks. v2 doesn't use — keep hooks in `hooks/hooks.json` for one source. |
| `paths` | optional | Glob patterns that limit auto-activation. v2 unused. |
| `shell` | optional | `bash` (default) or `powershell`. Always `bash`. |
- `$ARGUMENTS` — full string as typed.
- `$ARGUMENTS[N]` or `$N` — 0-based index (shell-style quoting; `/skill "hello world" two` makes `$0 = "hello world"`, `$1 = "two"`).
- `$<name>` — when `arguments: [name1, name2]` is declared.
- `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}` — built-in.
#### Slash command files — `commands/*.md`
#### Statusline contract
#### Memory system
- **Locations** (per-agent name, scope decides path):
- **Initial read:** first 200 lines OR 25 KB of `MEMORY.md` (whichever first), prepended to system prompt with a curation instruction if exceeded.
- **When to write:** at the end of an agent's turn, when discovered patterns/conventions/gotchas would help next time. Agent prompt should include explicit memory-update instructions ("Save what you learned to MEMORY.md").
- **When to read:** at agent spawn (automatic). Agent can also Read/Write/Edit additional files in its memory directory mid-turn (Read/Write/Edit tools auto-enabled when memory is set).
#### Auto Mode — detection contract for skills
## Auto Mode Active
- `/build`, `/ship`: skip confirmation prompts; proceed on default choices; treat course-corrections as normal input.
- `/brief`, `/plan`: pick reasonable defaults rather than asking clarifying questions; surface assumptions inline.
- `/debug`, `/refactor`, `/tdd`, `/explore-repo`: same — no clarifying-question loops.
#### Plugin `bin/` directory
- `bin/godmode-state` — reads/writes `.planning/STATE.md` from skills (one place to update active-brief number, status, next-command pointer).
- `bin/godmode-hash-rules` — emits a stable hash of the rules directory for the installer to detect customizations.
### Bash 3.2 portability — what to use, what to avoid
| Construct | Why | Use instead |
|---|---|---|
| `mapfile` / `readarray` | bash 4.0+ | `while IFS= read -r line; do ARR+=("$line"); done < file` |
| `[[ -v VAR ]]` | bash 4.2+ | `[[ -n "${VAR+x}" ]]` (true if VAR set, even to empty) |
| `${var,,}` / `${var^^}` (case conversion) | bash 4.0+ | `echo "$var" \| tr '[:upper:]' '[:lower:]'` |
| Associative arrays `declare -A` | bash 4.0+ | parallel indexed arrays, OR `key=value` lines through grep |
| `${var/pattern/repl}` with regex `+`/`?` | bash extended-regex differences | `sed` for regex replacement |
| `coproc` | bash 4.0+ | named pipes (`mkfifo`) or temp files |
| `&>>` (append both streams) | bash 4.0+ | `>>file 2>&1` |
| `${BASH_REMATCH[*]}` after function-call boundaries | reliability differences | capture and pass explicitly |
| `head -n -N` (negative count) | GNU-only, fails on macOS | `tail -r \| sed '1,N d' \| tail -r` or use `awk` |
| `sed -i` (no extension) | GNU-only, fails on BSD/macOS | `sed -i '' 'expr' file` (BSD) — actually portability requires `sed -i.bak 'expr' file && rm file.bak` |
| `date -d "..."` (GNU date arithmetic) | GNU-only | `date -j -v` on BSD/macOS, OR ship both branches |
| `seq -f` (printf format) | GNU-only | bash arithmetic loop |
| `getopt --long` (long options) | GNU-only, BSD getopt is short-only | hand-roll arg parsing or use `getopts` (POSIX, short-only but portable) |
- `[[ ... ]]` conditionals (bash-since-2.0).
- `set -euo pipefail` (works in 3.2; **but** see CONCERNS #18: `cat > /dev/null` can fail under `pipefail` if stdin closes early — write `cat > /dev/null || true`).
- Indexed arrays with `+=`.
- Process substitution `<(cmd)` (3.2+).
- Brace expansion `{a,b,c}` and `{1..10}` (3.2+; **but** dynamic ranges like `{$start..$end}` don't expand in 3.2 — use `seq` or arithmetic loop).
- `printf` for formatting (POSIX, portable).
- `local` variables in functions (since 2.0).
- `trap` for cleanup.
### `jq` patterns — what's idiomatic, what's wrong
#### JSON construction (NEVER string-interpolate)
# WRONG — breaks on quotes, backslashes, newlines in $CONTEXT
#### Batched field extraction (`@tsv`)
#### Defaults: `// empty` vs `// "default"`
| Pattern | Behavior |
|---|---|
| `.field // empty` | absent/null → the value is *omitted* from output (jq filter sees `empty`, not `null`). Useful when chaining filters: `jq -r '.rate_limits.five_hour.used_percentage // empty'` produces no output if rate limits are absent. |
| `.field // "default"` | absent/null → string `"default"`. Good for variable-assignment paths in bash. |
| `.field // 0` | absent/null → number 0. Good for percentages/counts. |
| `.field // false` | absent/null → boolean false. |
#### Reading hook stdin safely
#### Validation in `jq` (for CI lint)
# Required field presence + type check
# Enum check
## Dev-time tooling (CI-only — zero runtime impact)
| Tool | Version | Purpose | Why this version |
|---|---|---|---|
| **shellcheck** | 0.11.0 | static analysis for shell — catches CONCERNS #6, SC2086 unquoted vars, SC2155 declare-and-assign, the SC2064-class trap fragility | Released 2025-08-04. |
| **bats-core** | 1.13.0 | TAP-compliant Bash test runner. Covers install → uninstall → reinstall round trip, hook adversarial fixtures | Released 2024-11-07. Bash 3.2 compatible (works on macOS default shell). |
| **jq** (CI) | 1.6+ | inline `jq -e` schema assertions in `scripts/lint-json.sh` | Already a runtime dep — extending to CI keeps the dep budget at one. |
| **GitHub Actions** | `actions/checkout@v4`, `ludeeus/action-shellcheck@master` | matrix `[ubuntu-latest, macos-latest]`, four steps: shellcheck, lint-json, lint-frontmatter, bats | Standard 2026 actions. |
| Tool | Why not | Use instead |
|---|---|---|
| `shfmt` | reformats; would churn the codebase for no v2 win | shellcheck for correctness only; manual style |
| `ajv-cli` / `markdownlint-cli2` / `remark-lint-frontmatter-schema` | adds Node.js as a CI dep — violates the dep budget even at CI time | inline `jq -e` for JSON; pure-bash + awk for frontmatter |
| `jsonschema` (Python) / `yamllint` | adds Python as a CI dep | same — `jq -e` and `awk` |
| `sourcemeta/jsonschema` | AGPL; 30 MB single-platform binary | inline `jq -e` (~150 LOC total covers our four schemas) |
| `pre-commit` framework | Python dep | native git hooks if needed; CI is the primary gate anyway |
| Docker-based jobs | install.sh modifies `$HOME`, smoke tests need a real home | `bats` in `mktemp -d` as `$HOME` |
## Installation
# Runtime — no install required if user has bash 3.2+ and jq 1.6+
# Plugin install:
# Manual install (parity path):
## Version compatibility floor
| Feature | Min Claude Code | v2 action |
|---|---|---|
| `memory: project` agent frontmatter | v2.1.33 (Feb 2026) | declared in README |
| Auto Mode (`permission_mode: "auto"`) | v2.1.83 | declared in README |
| `monitors` plugin manifest | v2.1.105 | not used |
| Opus 4.7 (`opus` alias resolves to 4-7) | v2.1.111 | recommended floor |
| Default effort `xhigh` on Opus | v2.1.117 | overridden per-agent in frontmatter |
## Alternatives Considered
| Category | Recommended | Alternative | Why not |
|---|---|---|---|
| Schema validation | inline `jq -e` | `ajv-cli` (Node) | adds Node CI dep; violates spirit of dep constraint |
| Schema validation | inline `jq -e` | `sourcemeta/jsonschema` (C++ binary) | AGPL; 30 MB binary |
| Frontmatter linter | pure-bash + awk + jq | `markdownlint-cli2` | Node dep; checks Markdown formatting, not semantic frontmatter |
| Test runner | `bats-core` v1.13.0 | `shunit2` | no TAP, no fixture support |
| Test runner | `bats-core` v1.13.0 | original `sstephenson/bats` | archived, bash 4+ only |
| Static analysis | `shellcheck` only | `shellcheck` + `shfmt` | shfmt churns; shellcheck alone covers correctness |
| Memory | per-agent `memory: project` | global plugin memory file | Claude Code only supports per-agent memory |
| Hook JSON construction | `jq -n --arg`/`--argjson` | heredoc string interpolation | adversarial-unsafe (CONCERNS #6) |
| Effort on code-writing agents | `effort: high` | `effort: xhigh` | `xhigh` documented to skip rules on Opus 4.7 (PROJECT.md) |
| Worktree isolation | `isolation: worktree` per agent | shared cwd | parallel execution produces file conflicts |
| Model field | `opus`/`sonnet`/`haiku` aliases | pinned IDs (`claude-opus-4-7`) | manual upgrade burden |
| Backup-rotation cursor | `${CLAUDE_PLUGIN_DATA}` | under `${CLAUDE_PLUGIN_ROOT}` | ROOT resets on plugin update; DATA persists |
| User config | `userConfig.model_profile` (one knob) | hand-edit `settings.json` | UX win for plugin-mode users |
| LSP / MCP / monitors / themes | none | bundled | out of scope per PROJECT.md |
| Native Windows | none | PowerShell port | maintenance burden disproportionate; WSL2 covers |
## What NOT to Add (explicit)
| Avoid | Why | Instead |
|---|---|---|
| Node, Python, Ruby anywhere in runtime path | violates jq-only constraint | bash + jq |
| Bundled MCP server | out of scope | recommend Context7 etc. in README |
| `agent` or `prompt` hook types | LLM call per hook event = unacceptable latency | `command` only |
| Pinned model IDs in frontmatter | manual upgrade burden | aliases |
| Hardcoded skill/agent lists in any file | drifts as repo evolves | live filesystem scan via `` !`ls ${CLAUDE_PLUGIN_ROOT}/skills/` `` in `/godmode`; `find` in `post-compact.sh` |
| `--no-verify` on `git commit` | bypasses quality gates | PreToolUse hook blocks; if a hook truly must skip, use a separate documented escape hatch |
| Heredoc JSON construction | adversarial-unsafe | `jq -n --arg`/`--argjson` |
| String interpolation of branch names / commit messages into JSON | same | same |
| `cat > /dev/null` under `set -euo pipefail` (without `\|\| true`) | aborts on early stdin closure | `cat > /dev/null \|\| true` |
| Reading `pwd` in hooks | fragile to subdirectory invocation | read `.cwd` from stdin JSON |
| Multiple `jq` invocations per statusline render | wasteful | one `jq -r '... \| @tsv'` |
| `pre-commit` framework | Python dep | native git hooks for git lifecycle if needed |
| `Dockerfile` for development | install.sh modifies `$HOME` | `bats` in `mktemp -d` |
| `make`-based build | nothing to build | `./install.sh` is the entry point |
| Telemetry of any shape | trust is the brand | none, ever |
## Where each v2 addition lives
| Addition | Path | Notes |
|---|---|---|
| Canonical version | `.claude-plugin/plugin.json:.version` | every other file reads via `jq` at runtime |
| User config | `.claude-plugin/plugin.json:.userConfig` | single key `model_profile` |
| New agents | `agents/{planner,verifier,spec-reviewer,code-reviewer}.md` | + modernization of existing 8 |
| New hooks | `hooks/{pre-tool-use,post-tool-use,user-prompt-submit,session-end}.sh` | + hardened `session-start.sh`, `post-compact.sh` |
| Hook bindings (plugin) | `hooks/hooks.json` | every event, explicit `"timeout": 10` |
| Hook bindings (manual) | `config/settings.template.json` | identical event set, identical timeout |
| Quality gates source | `config/quality-gates.txt` | one gate per line; `post-compact.sh` reads it |
| `bin/` helpers | `bin/godmode-state`, `bin/godmode-hash-rules` | bare commands while plugin enabled |
| shellcheck config | `.shellcheckrc` | repo root |
| JSON schema lint | `scripts/lint-json.sh` | inline `jq -e` |
| Frontmatter lint | `scripts/lint-frontmatter.sh` | pure bash + awk + jq |
| Version drift check | `scripts/check-version-drift.sh` | reads canonical, compares everywhere |
| bats tests | `tests/{install,uninstall,hooks,statusline}.bats` | each in `mktemp -d` `$HOME` |
| CI workflow | `.github/workflows/ci.yml` | `[ubuntu-latest, macos-latest]` matrix; 4 steps |
| Plugin-mode/manual-mode parity gate | step in CI workflow | asserts hook event sets and timeouts agree |
| Vocabulary CI gate | step in CI workflow | greps for `phase`/`task` in user-facing surface (commands/, skills/) — must be empty |
| `${CLAUDE_PLUGIN_DATA}` use | `install.sh`, `hooks/session-end.sh` | install marker, last-version-seen, rotation cursor |
## Confidence assessment
| Area | Confidence | Source |
|---|---|---|
| Plugin manifest schema (`userConfig`, `${CLAUDE_PLUGIN_DATA}`, `bin/`, `dependencies`) | HIGH | full schema fetched from plugins-reference doc 2026-04-26 |
| Plugin agent restrictions (`hooks`/`mcpServers`/`permissionMode` forbidden) | HIGH | verbatim from plugins-reference |
| Hook stdin/stdout JSON shapes (per-event) | HIGH | full per-event schemas fetched from hooks doc 2026-04-26 |
| Hook timeout default (600s for `command`, 30s for `prompt`, 60s for `agent`) | HIGH | hooks doc, verbatim |
| Hook runtime guarantees (no JSON validation, no stdin sanitization, 10K char cap) | HIGH | hooks doc, verbatim |
| Subagent frontmatter set + memory/isolation/background semantics | HIGH | sub-agents doc, verbatim |
| Agent type matchers (subagent name) | HIGH | sub-agents doc |
| Skill frontmatter set (incl. `arguments`, `argument-hint`, `disable-model-invocation`, `paths`, `context: fork`) | HIGH | skills doc, verbatim |
| Skill argument substitution (`$ARGUMENTS`, `$N`, named) | HIGH | skills doc |
| Skill content lifecycle (5K tokens after compaction, 25K total budget) | HIGH | skills doc, verbatim |
| Statusline stdin JSON shape (full) | HIGH | statusline doc, full schema fetched |
| Statusline stdout (plain text + ANSI + OSC 8 hyperlinks) | HIGH | statusline doc |
| Statusline update cadence (after assistant message + permission/vim mode change, 300ms debounce) | HIGH | statusline doc |
| Memory contract (per-agent, 200 lines OR 25KB read at start) | HIGH | sub-agents doc |
| Auto Mode permission mode (`auto`) | HIGH | permission-modes doc |
| Auto Mode reminder string `## Auto Mode Active` | MEDIUM | observed in current session; not contractually documented |
| Bash 3.2 portability constructs to avoid | HIGH | well-documented bash version differences |
| `jq` patterns (`-n --arg`, `@tsv`, `// empty` vs `// "default"`, `-e` for assertions) | HIGH | jq 1.6 manual |
| Effort `xhigh` skips rules on Opus 4.7 | MEDIUM externally / HIGH as project policy | locked in PROJECT.md Key Decisions |
| shellcheck v0.11.0 release date | HIGH | GitHub releases verified |
| bats-core v1.13.0 release date | HIGH | GitHub releases verified |
| Inline `jq -e` covers our schema needs (vs JSON-Schema-2020-12) | MEDIUM | tradeoff: dependency cleanliness over conformance |
## Sources
- `https://code.claude.com/docs/en/plugins-reference` — full plugin manifest schema, agent frontmatter restrictions for plugin-shipped agents, `${CLAUDE_PLUGIN_DATA}` semantics, `userConfig` schema, `bin/` directory behavior, monitor minimum version, plugin caching and orphan-prune. **HIGH** (full doc fetched).
- `https://code.claude.com/docs/en/hooks` — full per-event input/output JSON shapes, deprecated `decision: approve|block` shape, `command`/`prompt`/`agent` hook timeout defaults (600/30/60s), 10,000-character context cap, runtime guarantees (no JSON validation, no stdin sanitization). **HIGH**.
- `https://code.claude.com/docs/en/sub-agents` — agent frontmatter fields (`model`, `effort`, `isolation: worktree`, `maxTurns`, `memory`, `background`, `color`, `skills`, `initialPrompt`), memory location/lifecycle (200 lines or 25KB read at start), permission mode behavior. **HIGH**.
- `https://code.claude.com/docs/en/skills` — skill frontmatter (full set incl. `arguments`, `argument-hint`, `disable-model-invocation`, `user-invocable`, `paths`, `context: fork`, `agent`, `hooks`, `shell`), argument substitution rules (`$ARGUMENTS`, `$N`, named), inline shell substitution (`` !`...` ``), content lifecycle, 1,536-char description cap, 5K-token-per-skill compaction budget. **HIGH**.
- `https://code.claude.com/docs/en/statusline` — full stdin JSON schema (every field, including `effort`, `thinking`, `rate_limits`, `worktree`), stdout (plain text + ANSI + OSC 8), update cadence, debounce. **HIGH**.
- `https://code.claude.com/docs/en/permission-modes` — Auto Mode requirements, classifier behavior, allow/deny defaults, subagent classification, fallback thresholds. **HIGH**.
- `https://github.com/koalaman/shellcheck/releases` — v0.11.0, 2025-08-04. **HIGH**.
- `https://github.com/bats-core/bats-core/releases` — v1.13.0, 2024-11-07. **HIGH**.
- `.planning-archive-v1/codebase/STACK.md`, `.planning-archive-v1/codebase/CONCERNS.md`, `.planning-archive-v1/research/STACK.md` — v1.x baseline + prior research pass. **HIGH** (factual codebase + cross-checked research).
- `.planning/PROJECT.md`, `IDEA.md` — project policy locks (effort, vocabulary, dep budget, surface area). **HIGH** (project-internal contracts).
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
