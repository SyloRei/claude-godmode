# Technology Stack — claude-godmode v2

**Project:** claude-godmode v2 (polish mature version)
**Researched:** 2026-04-26
**Scope of this file:** what is NEW or CHANGED in the stack vs. shipped v1.x. Inputs verified directly against `code.claude.com` docs (fetched 2026-04-26). v1.x baseline lives at `.planning-archive-v1/codebase/STACK.md`; the prior re-init pass at `.planning-archive-v1/research/STACK.md` is folded in here where still correct, corrected where stale.

**Overall confidence:** HIGH for everything except the four MEDIUM items called out inline (auto-mode reminder shape, jq-in-CI tradeoff, frontmatter-linter scope, and the "rule-skipping" claim about Opus 4.7 `xhigh` which is preserved as a project policy decision).

---

## Recommended Stack

### Core Runtime (locked, unchanged from v1.x — listed for completeness)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Bash | 3.2+ | hooks, installer, statusline, `bin/` helpers | macOS default shell. No 4.x-only constructs. |
| jq | 1.6+ | every JSON read/write/merge in shell | Only mandatory runtime tool. All emitted JSON via `jq -n --arg`/`--argjson` (never heredoc interpolation). |
| Markdown + YAML frontmatter | — | rules, agents, skills, commands | Native Claude Code authoring format. |
| JSON | — | `plugin.json`, `hooks.json`, `settings.template.json`, hook stdin/stdout | Claude Code's IO contract. |

**Confidence:** HIGH. Constraint enforced: zero Node, Python, Ruby, or compiled binary in the runtime path. macOS + Linux only; WSL2 is the supported Windows path.

### Authoring Surface (v2 — what to adopt)

#### Plugin manifest — `.claude-plugin/plugin.json`

Verified against `https://code.claude.com/docs/en/plugins-reference` (fetched 2026-04-26).

**Required field:** `name` only (everything else is optional, but we declare them all for marketplace polish).

**Fields v2 USES:**

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

**Fields v2 EXPLICITLY DOES NOT use (with reason):**

| Field | Why not |
|---|---|
| `mcpServers` | "no bundled MCP server" is project Out-of-Scope. |
| `lspServers` | not a language-tool plugin. |
| `outputStyles` | adds surface area; not in scope. |
| `themes` | aesthetic only; not core value. |
| `monitors` | requires a long-running shell process per session; statusline already covers cost/context. Telemetry-adjacent — out of scope per PROJECT.md. |
| `channels` | MCP-server-bound; we have no server. |
| `dependencies` | no plugin-to-plugin deps; we are self-contained. |

**Confidence:** HIGH (full schema fetched and field-by-field verified).

#### `${CLAUDE_PLUGIN_ROOT}` vs `${CLAUDE_PLUGIN_DATA}` — survival semantics

Verified directly:

- **`${CLAUDE_PLUGIN_ROOT}`** = absolute path to the plugin's installed directory. **Resets on plugin update** (marketplace plugins are cached under `~/.claude/plugins/cache/<id>/<version>/`; old version directories are marked orphaned and pruned 7 days later). Use for: scripts bundled with the plugin, `bin/` helpers, read-only configs.
- **`${CLAUDE_PLUGIN_DATA}`** = `~/.claude/plugins/data/<id>/`. **Survives updates and is per-installation persistent.** Use for: install marker, last-version-seen, backup-rotation cursor, anything that should survive a plugin bump.

v2 places: `install.sh` writes a marker to `${CLAUDE_PLUGIN_DATA}/installed.json` (timestamp + version). `hooks/session-end.sh` reads/writes `${CLAUDE_PLUGIN_DATA}/backup-cursor` for rotation. v1.x had no concept of either; everything was under `${CLAUDE_PLUGIN_ROOT}` and lost on plugin update.

**Confidence:** HIGH. Documented behavior, including the 7-day orphan-prune window.

#### Hook contract — stdin/stdout JSON shapes

Verified directly against `https://code.claude.com/docs/en/hooks` (fetched 2026-04-26). This is the section that the prior research only sketched — full shapes below.

**Common stdin envelope (all events):**

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/dir",
  "permission_mode": "default|plan|acceptEdits|auto|dontAsk|bypassPermissions",
  "hook_event_name": "PreToolUse",
  "agent_id": "...",        // subagent only
  "agent_type": "..."       // subagent only
}
```

Critical: **`cwd` is in stdin.** v1.x hooks read from `pwd`, which is fragile when the user invokes from a subdirectory. v2 hooks resolve project root by reading `.cwd` from stdin and `cd`-ing into it before any project-marker scan. Resolves CONCERNS #7.

**Per-event additions and outputs (the ones v2 ships):**

`PreToolUse` — input adds `tool_name`, `tool_input` (per-tool object), `tool_use_id`. Output (current shape — use this; deprecated `decision: approve|block` shape is auto-mapped but should not be emitted):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask|defer",
    "permissionDecisionReason": "string",
    "updatedInput": { "command": "modified" },
    "additionalContext": "string"
  },
  "continue": true,
  "suppressOutput": false,
  "systemMessage": "string"
}
```

Precedence when multiple hooks return different decisions: `deny` > `defer` > `ask` > `allow`. Exit code 2 from the hook = blocked tool call, stderr shown to Claude.

`PostToolUse` — input adds `tool_name`, `tool_input`, `tool_response`, `tool_use_id`, `duration_ms`. Output may include `decision: "block"` with a `reason` (this one DOES still use the `decision` shape for the block path), plus `hookSpecificOutput.additionalContext`. Use this in v2 to surface failed quality-gate exit codes from `bash -e` chains.

`PostToolUseFailure` — separate event from `PostToolUse`. Fires when a tool errors out (non-zero exit, exception). Input includes `error`, `is_interrupt`, `duration_ms`. **v2 uses this** in addition to `PostToolUse` so the hook layer surfaces both successful-but-failed-gate output and outright tool errors.

`UserPromptSubmit` — input adds `prompt`. Output: plain stdout becomes context, OR JSON with `hookSpecificOutput.additionalContext` and optionally `sessionTitle`. **Exit 2 erases the prompt from context.**

`SessionStart` — input adds `source ∈ {startup, resume, clear, compact}` and `model`. **Supported types are `command` and `mcp_tool` only** — no `prompt` or `agent` types here. Plain stdout becomes context; JSON with `hookSpecificOutput.additionalContext` is the structured path.

`SessionEnd` — input adds `reason ∈ {clear, resume, logout, prompt_input_exit, bypass_permissions_disabled, other}`. v2 uses this for backup rotation (resolves CONCERNS #13).

`PostCompact` — input adds `trigger ∈ {manual, auto}`. Output is `hookSpecificOutput.additionalContext`. v2 reads quality gates from `config/quality-gates.txt` and skill/agent lists from the live filesystem inside this hook.

**Default `command` hook timeout: 600 seconds.** This is the *upper bound* — corrects a stale assumption from CONCERNS #12 that referenced 60s. Both `hooks/hooks.json` (plugin mode) and `config/settings.template.json` (manual mode) declare an explicit `"timeout": 10` in v2. CI parity gate enforces equality.

**Other timeouts:** `prompt`-type hooks default to 30s; `agent`-type hooks default to 60s. v2 uses `command` exclusively (no `prompt`, no `agent`, no `http`, no `mcp_tool` from this plugin).

**Runtime guarantees (verified verbatim):**

- Claude Code does **NOT** validate JSON the hook emits. Malformed JSON is treated as plain-text additional context (silent corruption — this is exactly what CONCERNS #6 hit when branch names contained quotes).
- No stdin sanitization: hook receives verbatim event data. Hook owns input validation.
- `additionalContext`/`systemMessage`/plain stdout combined are capped at **10,000 characters** before being injected. Excess is saved to a file with preview + path. Important for `PostCompact`'s skill list + quality gates (well under cap, but worth knowing).
- Exit 0: stdout parsed as JSON if valid, else added as plain context.
- Exit 2: blocking. Stdout/JSON ignored. Stderr fed back.

**Confidence:** HIGH (stdin/stdout shapes, timeout, and validation behavior all fetched directly).

#### Subagent contract — `agents/*.md` frontmatter

Verified against `https://code.claude.com/docs/en/sub-agents` (fetched 2026-04-26). Plugin-shipped agents support these fields verbatim:

`name`, `description`, `model`, `effort`, `maxTurns`, `tools`, `disallowedTools`, `skills`, `memory`, `background`, `isolation`, `color`, `initialPrompt`.

**Plugin agents are FORBIDDEN** to declare `hooks`, `mcpServers`, or `permissionMode`. These are silently ignored. (Security boundary: a plugin shouldn't be able to elevate its own permission mode or run arbitrary hooks scoped to itself.) v2 frontmatter linter rejects any plugin-shipped agent that declares these — saves debugging time.

**v2 frontmatter conventions per agent:**

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

**Subagent agent_type matchers** (used by `SubagentStart`/`SubagentStop` hooks): the matcher is the agent's `name` field for custom agents, or `Bash`/`Explore`/`Plan`/`general-purpose` for built-ins.

**Effort policy (locked):**

| Agent | model | effort | Why |
|---|---|---|---|
| `@architect`, `@security-auditor`, `@planner`, `@verifier` | `opus` | `xhigh` | Design/audit work benefits from depth. Read-only or read-mostly. |
| `@executor`, `@writer`, `@test-writer` | `opus` | `high` | Code-touching. **`xhigh` skips rules on Opus 4.7 per Anthropic-documented behavior** (locked into PROJECT.md Key Decisions). `high` is the safe default. |
| `@reviewer`, `@spec-reviewer`, `@code-reviewer`, `@researcher`, `@doc-writer` | `sonnet` | `high` | Sonnet's strength profile fits review/research. |
| Trivially-bounded helpers (classifiers, format checkers) | `haiku` | (default) | Speed > depth. |

**MEDIUM confidence on the `xhigh`-skips-rules claim externally** — it's a project policy lock-in (PROJECT.md), not directly fetched-from-docs evidence in this research pass. We treat it as a hard policy regardless. Verify in deeper-research if `@executor` ever exhibits anomalous rule-skipping in practice.

**Confidence:** HIGH for the field set, restrictions, and memory contract.

#### Skill contract — `skills/<name>/SKILL.md` frontmatter

Verified against `https://code.claude.com/docs/en/skills` (fetched 2026-04-26). The 2026 surface has expanded; relevant fields below.

**Frontmatter:**

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

**Argument substitutions in skill body:**

- `$ARGUMENTS` — full string as typed.
- `$ARGUMENTS[N]` or `$N` — 0-based index (shell-style quoting; `/skill "hello world" two` makes `$0 = "hello world"`, `$1 = "two"`).
- `$<name>` — when `arguments: [name1, name2]` is declared.
- `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}` — built-in.

**Inline shell substitution:**

`` !`<command>` `` is run **before** the skill body is sent to the model; output replaces the placeholder. Multi-line: triple-backtick fence opened with `` ```! ``. v2: `/godmode` uses `` !`ls ${CLAUDE_PLUGIN_ROOT}/skills/` `` and similar to render the live filesystem state directly into the response. This is the "live indexing, no drift" property in REQUIREMENTS — hardcoded lists are out, shell-rendered lists are in.

**Skill content lifecycle (verified):** When invoked, the rendered SKILL.md content enters the conversation as a single message and stays for the rest of the session. Auto-compaction carries invoked skills forward at up to 5,000 tokens each, total budget 25,000 tokens, dropping older skills first. Practical implication: don't write `/build` to do step-by-step state mutation in the SKILL body — the model has the body once, then operates from memory of it. Use the `.planning/STATE.md` file as the actual state, not the skill text.

**Skill listing budget:** All names are always loaded; descriptions are shortened at 1% of the context window (fallback 8,000 chars) when there are many skills. v2 has 11 — well under the cap. Override via `SLASH_COMMAND_TOOL_CHAR_BUDGET` env var if it ever bites.

**Confidence:** HIGH.

#### Slash command files — `commands/*.md`

Flat markdown files, same frontmatter as skills (custom-commands-merged-into-skills, per the docs note). v2 keeps **only `commands/godmode.md`** as a flat command (it's the entry point — the simplest possible surface). Every other user-facing slash is a `skills/<name>/SKILL.md` so it carries `allowed-tools`, `argument-hint`, and richer instructions. This matches the prior research's recommendation; nothing changed.

#### Statusline contract

Verified against `https://code.claude.com/docs/en/statusline` (fetched 2026-04-26).

**Setup:** `statusLine.type = "command"`, `statusLine.command = "<script-or-inline>"`, optional `statusLine.padding` (default 0) and `statusLine.refreshInterval` (seconds, minimum 1, omitted = event-driven only).

**Stdin JSON (verbatim from docs):**

```json
{
  "cwd": "...",
  "session_id": "...",
  "session_name": "...",            // absent unless --name or /rename used
  "transcript_path": "...",
  "model": { "id": "claude-opus-4-7", "display_name": "Opus" },
  "workspace": {
    "current_dir": "...",
    "project_dir": "...",
    "added_dirs": [],
    "git_worktree": "feature-x"     // absent in main worktree
  },
  "version": "2.1.90",
  "output_style": { "name": "default" },
  "cost": {
    "total_cost_usd": 0.01234,
    "total_duration_ms": 45000,
    "total_api_duration_ms": 2300,
    "total_lines_added": 156,
    "total_lines_removed": 23
  },
  "context_window": {
    "total_input_tokens": 15234,
    "total_output_tokens": 4521,
    "context_window_size": 200000,
    "used_percentage": 8,
    "remaining_percentage": 92,
    "current_usage": {              // null before first API call
      "input_tokens": 8500,
      "output_tokens": 1200,
      "cache_creation_input_tokens": 5000,
      "cache_read_input_tokens": 2000
    }
  },
  "exceeds_200k_tokens": false,
  "effort": { "level": "high" },    // absent if model doesn't support effort
  "thinking": { "enabled": true },
  "rate_limits": {                  // absent for non-Pro/Max accounts
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
  },
  "vim": { "mode": "NORMAL" },      // absent unless vim mode on
  "agent": { "name": "..." },        // absent unless --agent
  "worktree": {                     // absent unless --worktree session
    "name": "...", "path": "...", "branch": "...",
    "original_cwd": "...", "original_branch": "..."
  }
}
```

**Stdout:** plain text. Multiple `echo` lines = multiple status rows. ANSI escape codes for colors (`\033[32m` etc.) — terminal-dependent. OSC 8 for clickable links (iTerm2/Kitty/WezTerm). No timeout documented; the script just runs.

**Update cadence:** runs after each new assistant message, on permission-mode change, on vim-mode toggle. Debounced 300ms. In-flight execution cancelled on new trigger. Idle sessions can use `refreshInterval` for time-based segments. Edits to the script appear on the next interaction-triggered update.

**Resolves CONCERNS #19** (single-jq-invocation-per-render): v1.x calls `jq` four times per render; v2 collapses into one `jq` invocation that emits all needed fields TSV-style:

```bash
read -r MODEL DIR PCT COST <<< "$(jq -r '[.model.display_name, .workspace.current_dir, (.context_window.used_percentage // 0 | floor), (.cost.total_cost_usd // 0)] | @tsv')"
```

**Confidence:** HIGH (full schema fetched, including absent-vs-null distinctions).

#### Memory system

Verified against the sub-agents doc. Memory is per-agent, not per-session.

- **Locations** (per-agent name, scope decides path):
  - `memory: user` → `~/.claude/agent-memory/<name>/`
  - `memory: project` → `.claude/agent-memory/<name>/` (default; checkable into version control)
  - `memory: local` → `.claude/agent-memory-local/<name>/` (gitignored)
- **Initial read:** first 200 lines OR 25 KB of `MEMORY.md` (whichever first), prepended to system prompt with a curation instruction if exceeded.
- **When to write:** at the end of an agent's turn, when discovered patterns/conventions/gotchas would help next time. Agent prompt should include explicit memory-update instructions ("Save what you learned to MEMORY.md").
- **When to read:** at agent spawn (automatic). Agent can also Read/Write/Edit additional files in its memory directory mid-turn (Read/Write/Edit tools auto-enabled when memory is set).

v2 uses `memory: project` for `@researcher` (so research learnings are committable). All other agents are stateless — they earn their context every turn. **Requires Claude Code v2.1.33+.**

There is **no global plugin-managed memory** ("MEMORY.md index") at the plugin level. Memory is per-subagent only. Plugin-wide state lives in `.planning/STATE.md` (machine-mutated by skills) — that's our equivalent.

**Confidence:** HIGH.

#### Auto Mode — detection contract for skills

Verified against `https://code.claude.com/docs/en/permission-modes`. Auto mode is `permission_mode: "auto"` in stdin to all hooks; that's the deterministic detection signal for hooks.

**For skills**, the user-visible signal is the system reminder injected into the model context — observable in the current session's prompt as:

```
<system-reminder>
## Auto Mode Active

Auto mode is active. The user chose continuous, autonomous execution. You should:
1. Execute immediately ...
2. Minimize interruptions ...
3. Prefer action over planning ...
4. Expect course corrections ...
5. Do not take overly destructive actions ...
6. Avoid data exfiltration ...
</system-reminder>
```

**Skills detect by string-match on the marker `## Auto Mode Active`.** Each v2 skill includes a one-paragraph "If `## Auto Mode Active` appears in the conversation, do X" branch:

- `/build`, `/ship`: skip confirmation prompts; proceed on default choices; treat course-corrections as normal input.
- `/brief`, `/plan`: pick reasonable defaults rather than asking clarifying questions; surface assumptions inline.
- `/debug`, `/refactor`, `/tdd`, `/explore-repo`: same — no clarifying-question loops.

**Auto mode boundaries** (from the docs): the classifier blocks force-push, push-to-main, mass deletion, IAM grants, modifying shared infrastructure, irreversibly destroying pre-session files, downloading-and-executing code. Routine writes inside the working directory and reading `.env` for matching API are allowed. Skills should NOT try to bypass these — auto mode reduces prompts but does not remove safety classifier checks.

**MEDIUM confidence on the exact reminder string:** the literal `## Auto Mode Active` text is observed in current sessions (this very session shows it verbatim). Anthropic could change the wording. Mitigation: skill detection should match `Auto Mode Active` (case-insensitive substring) rather than the exact heading-with-`##`.

#### Plugin `bin/` directory

Verified against the plugins reference. Files in `bin/` are added to the Bash tool's `PATH` while the plugin is enabled — invokable as bare commands in any Bash tool call. v2 uses minimally:

- `bin/godmode-state` — reads/writes `.planning/STATE.md` from skills (one place to update active-brief number, status, next-command pointer).
- `bin/godmode-hash-rules` — emits a stable hash of the rules directory for the installer to detect customizations.

These are bash scripts (no Node/Python). They MUST be executable (`chmod +x`) and bash-3.2-portable.

**Confidence:** HIGH.

### Bash 3.2 portability — what to use, what to avoid

macOS ships bash 3.2 by default (frozen at GPLv2). Most developer machines either have bash 3.2 (default macOS) or bash 5.x via Homebrew. Linux usually has bash 4.x or 5.x. **We target the floor: bash 3.2 must work everywhere our scripts run.**

**Forbidden constructs (don't use):**

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

**Safe core constructs:**

- `[[ ... ]]` conditionals (bash-since-2.0).
- `set -euo pipefail` (works in 3.2; **but** see CONCERNS #18: `cat > /dev/null` can fail under `pipefail` if stdin closes early — write `cat > /dev/null || true`).
- Indexed arrays with `+=`.
- Process substitution `<(cmd)` (3.2+).
- Brace expansion `{a,b,c}` and `{1..10}` (3.2+; **but** dynamic ranges like `{$start..$end}` don't expand in 3.2 — use `seq` or arithmetic loop).
- `printf` for formatting (POSIX, portable).
- `local` variables in functions (since 2.0).
- `trap` for cleanup.

**`shellcheck` config** (`.shellcheckrc` at repo root):

```
shell=bash
external-sources=true
disable=SC1091
```

The `shell=bash` tells shellcheck to apply 3.2-aware rules (rather than POSIX-`sh` strictness). `disable=SC1091` whitelists "file not followed" for sourced files we know exist at install time.

**Confidence:** HIGH (well-documented bash version differences).

### `jq` patterns — what's idiomatic, what's wrong

#### JSON construction (NEVER string-interpolate)

This is the v1.x CONCERNS #6 fix. **Wrong:**

```bash
# WRONG — breaks on quotes, backslashes, newlines in $CONTEXT
cat <<EOF
{"hookSpecificOutput":{"additionalContext":"$CONTEXT"}}
EOF
```

**Right:**

```bash
jq -n \
  --arg ctx "$CONTEXT" \
  --arg event "SessionStart" \
  '{hookSpecificOutput:{hookEventName:$event, additionalContext:$ctx}}'
```

`--arg` ALWAYS treats the value as a string and handles all escaping. `--argjson` for non-string values (numbers, booleans, objects). `--slurpfile` for multi-line file content.

#### Batched field extraction (`@tsv`)

For statusline (CONCERNS #19) and any place we read multiple fields:

```bash
read -r MODEL DIR PCT COST <<< "$(jq -r '[.model.display_name, .workspace.current_dir, (.context_window.used_percentage // 0 | floor), (.cost.total_cost_usd // 0)] | @tsv')"
```

One `jq` invocation, four fields. The `@tsv` filter handles tab-escaping; pair with bash `read -r` to split. **Don't** use `@csv` — quoting differences make `read` fragile.

#### Defaults: `// empty` vs `// "default"`

| Pattern | Behavior |
|---|---|
| `.field // empty` | absent/null → the value is *omitted* from output (jq filter sees `empty`, not `null`). Useful when chaining filters: `jq -r '.rate_limits.five_hour.used_percentage // empty'` produces no output if rate limits are absent. |
| `.field // "default"` | absent/null → string `"default"`. Good for variable-assignment paths in bash. |
| `.field // 0` | absent/null → number 0. Good for percentages/counts. |
| `.field // false` | absent/null → boolean false. |

Pitfall: `.field // empty` inside `--arg` substitution still emits an empty string (not nothing) because shell capture happens at `$()` boundary. Use `// "fallback"` if you need a guaranteed value.

#### Reading hook stdin safely

```bash
INPUT="$(cat)"  # capture once, parse multiple times — avoids re-read race
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // "."')"
HOOK_EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty')"
```

**Don't:** `jq < /dev/stdin` then re-read — stdin is gone after first consumption. Capture once.

#### Validation in `jq` (for CI lint)

```bash
# Required field presence + type check
jq -e '.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' .claude-plugin/plugin.json >/dev/null \
  || { echo "plugin.json: .version missing or not semver"; exit 1; }

# Enum check
jq -e '.[] | select(.model | IN("opus","sonnet","haiku") | not)' agents/*.json >/dev/null \
  && { echo "agents have non-alias model values"; exit 1; }
```

`jq -e` exits non-zero if the filter result is `false`, `null`, or empty — making it a one-shot assertion.

**Confidence:** HIGH (idiomatic patterns, all verifiable from `jq` 1.6 manual).

---

## Dev-time tooling (CI-only — zero runtime impact)

Same as the prior research pass; no version drift in the year since.

| Tool | Version | Purpose | Why this version |
|---|---|---|---|
| **shellcheck** | 0.11.0 | static analysis for shell — catches CONCERNS #6, SC2086 unquoted vars, SC2155 declare-and-assign, the SC2064-class trap fragility | Released 2025-08-04. |
| **bats-core** | 1.13.0 | TAP-compliant Bash test runner. Covers install → uninstall → reinstall round trip, hook adversarial fixtures | Released 2024-11-07. Bash 3.2 compatible (works on macOS default shell). |
| **jq** (CI) | 1.6+ | inline `jq -e` schema assertions in `scripts/lint-json.sh` | Already a runtime dep — extending to CI keeps the dep budget at one. |
| **GitHub Actions** | `actions/checkout@v4`, `ludeeus/action-shellcheck@master` | matrix `[ubuntu-latest, macos-latest]`, four steps: shellcheck, lint-json, lint-frontmatter, bats | Standard 2026 actions. |

**Don't use:**

| Tool | Why not | Use instead |
|---|---|---|
| `shfmt` | reformats; would churn the codebase for no v2 win | shellcheck for correctness only; manual style |
| `ajv-cli` / `markdownlint-cli2` / `remark-lint-frontmatter-schema` | adds Node.js as a CI dep — violates the dep budget even at CI time | inline `jq -e` for JSON; pure-bash + awk for frontmatter |
| `jsonschema` (Python) / `yamllint` | adds Python as a CI dep | same — `jq -e` and `awk` |
| `sourcemeta/jsonschema` | AGPL; 30 MB single-platform binary | inline `jq -e` (~150 LOC total covers our four schemas) |
| `pre-commit` framework | Python dep | native git hooks if needed; CI is the primary gate anyway |
| Docker-based jobs | install.sh modifies `$HOME`, smoke tests need a real home | `bats` in `mktemp -d` as `$HOME` |

**MEDIUM confidence on the jq-for-CI tradeoff:** we trade JSON-Schema-2020-12 conformance for dependency cleanliness. We don't need conformance — we need ~20 assertions per schema. Documented tradeoff. If a future schema requires draft-2020-12 features (`$dynamicRef`, `unevaluatedProperties`), revisit then.

---

## Installation

```bash
# Runtime — no install required if user has bash 3.2+ and jq 1.6+
# Plugin install:
claude plugin install claude-godmode@<marketplace>

# Manual install (parity path):
git clone <repo>
cd claude-godmode
./install.sh
```

`install.sh` itself uses only `bash` and `jq`. Installation steps:

1. Verify `jq` present (fail-fast with install hint).
2. Detect mode (`CLAUDE_PLUGIN_ROOT` set = plugin, else manual).
3. Read canonical version from `.claude-plugin/plugin.json` via `jq -r '.version'`.
4. Backup existing `~/.claude/{rules,agents,skills,hooks}` to `~/.claude/backups/godmode-<ts>/`. Rotate to keep last 5.
5. Per-file diff: for each rule/agent/skill/hook the user has customized, prompt diff/skip/replace. Non-TTY default = keep customization.
6. Merge `config/settings.template.json` into `~/.claude/settings.json` via `jq` (top-level merge with explicit array-union allowlist for `permissions.allow`).
7. Write install marker to `${CLAUDE_PLUGIN_DATA}/installed.json` (timestamp + version).

`uninstall.sh`: reads `${CLAUDE_PLUGIN_DATA}/installed.json`, refuses on version mismatch unless `--force`.

---

## Version compatibility floor

| Feature | Min Claude Code | v2 action |
|---|---|---|
| `memory: project` agent frontmatter | v2.1.33 (Feb 2026) | declared in README |
| Auto Mode (`permission_mode: "auto"`) | v2.1.83 | declared in README |
| `monitors` plugin manifest | v2.1.105 | not used |
| Opus 4.7 (`opus` alias resolves to 4-7) | v2.1.111 | recommended floor |
| Default effort `xhigh` on Opus | v2.1.117 | overridden per-agent in frontmatter |

**Recommended floor:** **Claude Code v2.1.111** (for the `opus` alias). Document in README; don't pin tighter (`monitors` is the only post-v2.1.111 feature we'd want, and we deliberately don't use it).

---

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

---

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

---

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

---

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

---

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

---

*Stack research for: claude-godmode v2 — polish mature version. Researched: 2026-04-26.*
