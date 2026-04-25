# Pitfalls Research

**Domain:** Claude Code plugin — multi-agent workflow orchestrator, v1 → v2 maturation
**Researched:** 2026-04-25
**Confidence:** HIGH (hook schema from official docs, verified with GitHub issues; MEDIUM for orchestration patterns)

---

## Critical Pitfalls

### Pitfall 1: Distribution-Mode Divergence (Plugin vs Manual Drift)

**What goes wrong:**
Plugin mode and manual mode are maintained in parallel across multiple files (`hooks/hooks.json`, `config/settings.template.json`, the installer's two merge branches). When a new hook event, timeout, or settings key is added, developers update one mode and forget the other. The failure is invisible: plugin-mode users experience correct behavior; manual-mode users get stale config. No test catches this because CI doesn't smoke-test both installation paths.

**Why it happens:**
The two modes share identical _intent_ but use different _config surfaces_. It feels like one config, so developers treat it as one — and then ship only half. The `timeout: 10` already present in `hooks/hooks.json` but absent from `config/settings.template.json` (CONCERNS #12) is the existing evidence of this drift.

**How to avoid:**
- Treat `hooks/hooks.json` as the canonical hook binding source. At install time for manual mode, generate the `hooks` section of `settings.template.json` from `hooks/hooks.json` via a jq transform — one source of truth, two formats on output.
- Add a CI step that installs in both modes into temp directories, then diffs the effective settings JSON to assert they agree on hook timeouts, async flags, and event names.
- Every PR checklist: "Does this change require updating both hook configs?"

**Warning signs:**
- `hooks/hooks.json` and `config/settings.template.json` have different timeout values, event lists, or `async` settings.
- A new hook event works in plugin mode but silently does nothing for manual-mode users.
- The installer's plugin-mode and manual-mode branches have different lengths in `install.sh`.

**Phase to address:** Phase 1 (version unification and installer hardening) — this must be fixed before any new hooks are added, or every new hook will repeat the pattern.

---

### Pitfall 2: Prompt-Cache Invalidation via Dynamic Hook Output

**What goes wrong:**
Hooks inject context into sessions via `additionalContext`. If that content includes anything that changes between invocations — timestamps, recent commit hashes, branch names with ticket numbers, current context percentage — the injected text changes every session and every time PostCompact fires. This invalidates the prompt cache prefix for all subsequent content. With the cache TTL now approximately 3 minutes in practice (down from the documented 5), even a well-structured session can burn the cache multiple times per hour, multiplying token costs by 5x on long Opus 4.7 sessions.

**Why it happens:**
The cache hierarchy is `tools → system → messages`. The hook's `additionalContext` is injected into the system layer. A single character change anywhere in the prefix invalidates everything that follows it. Dynamic content (timestamps, git log output) seems harmless because it's informative — but it's poisoning the cache on every compaction cycle.

**How to avoid:**
- Separate _stable_ context (project type, tech stack, available agents/skills, quality gates) from _dynamic_ context (branch name, recent commits, context%).
- Inject stable context via rules files (loaded once at session start, cache-stable). Inject dynamic context only in the user-turn layer, not in `additionalContext`.
- Never include timestamps, cost figures, or context% in hook-injected system content.
- Verify: if two consecutive PostCompact outputs are identical byte-for-byte for a given project, the cache survives. If they differ, the cache is invalidated.

**Warning signs:**
- `cache_creation_input_tokens` is high and `cache_read_input_tokens` is near zero in session logs.
- PostCompact hook output includes `$(date)`, `$(git log --oneline -3)`, or similar.
- Statusline shows cost spiking after every compaction.

**Phase to address:** Phase 2 (PostCompact and hook hardening). Also: every future phase that adds to hook-injected content must check cache-stability before merging.

**Cross-reference:** Partially related to CONCERNS #9 (quality gates duplicated in hook). The fix is the same: make hook output structurally static by reading from stable files at runtime, not by embedding volatile data.

---

### Pitfall 3: TaskOutput/run_in_background Race Conditions and Silent Hangs

**What goes wrong:**
When `/execute` spawns parallel subagents with `run_in_background: true`, then calls `TaskOutput` with `block: true` to collect results, the session can freeze indefinitely. This happens when: (a) a background agent crashes or times out without updating its status, (b) `TaskOutput` is waiting on a condition that the crashed agent will never satisfy, or (c) output files remain empty even though the agent shows status "completed" (confirmed GitHub issue #21352). In Auto Mode, there is no human to interrupt — the session hangs silently until the overall session timeout.

**Why it happens:**
Claude Code's background agent runtime currently has no heartbeat or liveness check. A crashed agent stays listed as "running." `TaskOutput` with `block: true` is fundamentally a condition wait on a status flag that a dead agent will never flip.

**How to avoid:**
- Always pair `TaskOutput` with an explicit `timeout` parameter — never rely on the agent to signal completion.
- Design parallel agent workflows defensively: each agent writes output to a named temp file; the orchestrator polls those files with a bounded retry loop rather than blocking on TaskOutput.
- For the `/execute` skill, structure as: launch agents → wait with timeout → collect output files → if any file empty, re-run that story sequentially (fallback path).
- Document this pattern in the `@executor` agent's description so future authors don't revert to naive blocking.

**Warning signs:**
- Session stops producing output and does not error — it just waits.
- Background agents show "running" in the task panel with no activity in the transcript.
- Output files for completed agents are 0 bytes.

**Phase to address:** Phase 3 (agent modernization / parallel execution patterns). This is a new v2 capability area; the v1 pipeline is sequential and doesn't hit this pitfall, but v2 adoption of `run_in_background` will.

---

### Pitfall 4: Opus 4.7 with Extra High Effort Ignores Rules and Skills

**What goes wrong:**
Claude Opus 4.7 with `effort: xhigh` (adaptive thinking) treats `CLAUDE.md`, rules files, and skill instructions as _soft suggestions_ rather than _hard constraints_ during extended reasoning. The model's inner reasoning can override workflow instructions: it skips quality gates, contradicts explicit prohibitions in rules files, and produces code that violates style rules. This was reproduced with Opus 4.6 and adaptive thinking (GitHub issue #23936, closed as "not planned"). With Opus 4.7 as the v2 default for high-leverage agents, every `/execute` run is exposed to this.

**Why it happens:**
Extended thinking allocates a private reasoning budget that operates before the model produces its final output. During that reasoning, the model can "reason past" rule constraints as if they were guidelines rather than requirements. The constraints are in the system prompt, but the thinking layer is allowed to interrogate and override them.

**How to avoid:**
- For agents where rule compliance is non-negotiable (executor, security-auditor), set `effort: high` not `effort: xhigh`. Reserve `xhigh` for agents where creative reasoning is valued (architect, writer) and rule-following is less critical.
- Embed the most critical constraints (quality gate checklist, commit format) in the _task description_ passed to the agent at invocation time, not only in the rules files. This puts them in the user-turn layer, which is less likely to be reasoned past.
- Add a PostToolUse hook that checks whether the agent's output contains a required marker (e.g., the quality gate checklist) and exits with code 2 to block if missing.
- Test: run the executor agent on a fixture task that has an explicit rule violation in the naive solution. Verify the rule is respected.

**Warning signs:**
- Agent output violates explicit rules (missing typecheck, wrong commit format, no test coverage).
- The thinking budget is exhausted (`stop_reason: "max_tokens"`) on routine tasks.
- Rules files are loaded (confirmed by InstructionsLoaded hook) but their effects are absent in output.

**Phase to address:** Phase 2 (rules hardening and model configuration). Model selection and effort levels must be locked before agents are used in real workflows.

---

### Pitfall 5: Auto Mode / YOLO Mode Bypasses Workflow Gates

**What goes wrong:**
In Auto Mode (`--dangerously-skip-permissions` or the Shift+Tab `auto-accept` setting), `/execute`'s quality gates (typecheck, lint, tests, no-secrets, no-regressions, matches-requirements) can be bypassed in two ways: (1) the permission auto-classifier approves shell commands that run quality checks but silently swallows their non-zero exit codes; (2) the agent proceeds to the next story even when a gate fails, because nothing is blocking it. The ship hook that requires gate passage is only effective if the agent actually checks exit codes and stops. Under YOLO mode, a `rm -rf` command was confirmed to delete a home directory (documented December 2025 incident).

**Why it happens:**
Auto Mode was designed to minimize interruptions, not to enforce workflow invariants. Quality gates are enforced by the _skill's instructions_ telling the model to check — not by any mechanical enforcement. When the model reasons past the instruction (see Pitfall 4), or when a tool call returns non-zero and the permission classifier auto-approves continuation, gates are silently skipped.

**How to avoid:**
- Gate checks must be implemented as PreToolUse hooks that mechanically verify state, not as instructions that the model _might_ follow. A hook that exits code 2 when tests fail cannot be bypassed by Auto Mode.
- For `/ship` specifically: implement a PreToolUse hook on any `gh pr create` call that runs the full quality gate suite and blocks if any gate fails.
- Document in rules that `/execute` should _not_ proceed to the next story when a gate fails, even in Auto Mode — but add the hook as the backstop.
- The deny-list in `config/settings.template.json` uses pattern matching, not parsing (CONCERNS security section). Document this limitation in CONTRIBUTING.md so future additions don't over-rely on deny patterns as safety mechanisms.

**Warning signs:**
- `/execute` marks a story `passes: true` before tests pass.
- `gh pr create` runs without all quality gates reporting green.
- Story-level commits contain failing tests.

**Phase to address:** Phase 4 (quality gates mechanization). Phase 1 must include documentation of the issue so earlier phases don't create new gate violations.

---

### Pitfall 6: v1.x Migration Data Loss and Surprise Behavior

**What goes wrong:**
v1.x users have `.claude-pipeline/` directories with `prds/`, `stories.json`, and `archive/` that represent real in-progress work. A v2 installer that simply creates `.planning/` alongside these (or worse, silently abandons them) leaves users with: (a) orphaned state that no v2 skill knows how to read, (b) no clear signal that migration happened, and (c) existing `/prd`/`/plan-stories`/`/execute`/`/ship` muscle memory that now points at changed skill files.

**Why it happens:**
v2 requires `.planning/` shape (PROJECT.md, ROADMAP.md, phases/). v1 required `.claude-pipeline/` shape (stories.json). These are fundamentally different schemas. The migration path is not automatic — it requires either a conversion script or an explicit "archive the old shape, start fresh" ritual. The installer currently offers a v1.x migration for `CLAUDE.md → rules/` (CONCERNS #5) but nothing for `.claude-pipeline/ → .planning/`.

**How to avoid:**
- The v2 installer must detect `.claude-pipeline/stories.json` in any project the user runs from and emit a prominent warning: "Found v1.x pipeline state in this project. Run `/godmode-migrate` to convert it to v2, or keep v1 state alongside v2 (they don't conflict but v2 skills won't read it)."
- Provide a `/godmode-migrate` skill that: reads `stories.json`, creates `.planning/PROJECT.md` from PRD content, creates `.planning/ROADMAP.md` from story list, archives `.claude-pipeline/` to `.claude-pipeline/_archived-v1/`.
- Never delete `.claude-pipeline/` automatically — only archive it, never destructively remove it.
- The v2 skills (`/execute` etc.) must not silently fall back to reading `stories.json` as a compatibility shim — this creates ambiguity about which state is authoritative.

**Warning signs:**
- Users report "my stories are gone" after upgrading.
- `.claude-pipeline/` and `.planning/` coexist in a project with no clear owner.
- `/execute` behavior changes for existing projects without warning.

**Phase to address:** Phase 1 (installer migration) — this is a prerequisite to any user-facing v2 deployment. Must ship before any v2 skills land.

---

### Pitfall 7: Hardcoded Skill/Agent Lists Drifting from Filesystem

**What goes wrong:**
`hooks/post-compact.sh` embeds a literal list of skills and agents. `commands/godmode.md` embeds the same list. `plugin.json` embeds metadata. When a new agent or skill is added to the repo, 2-3 files must be updated manually. In practice, one is always missed. After compaction, users are told about agents that don't exist (if the list was over-eager) or miss agents that do exist (if the list was under-eager). This is already documented as CONCERNS #8.

**Why it happens:**
The list is used in human-readable text output, which makes it tempting to hand-author rather than generate. The lack of CI that validates the list against the actual filesystem means the drift is never caught automatically.

**How to avoid:**
- The PostCompact hook must generate the skills/agents list at runtime by scanning `${CLAUDE_PLUGIN_ROOT}/agents/*.md` and `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md` (plugin mode), or `~/.claude/agents/*.md` and `~/.claude/skills/*/SKILL.md` (manual mode).
- `commands/godmode.md` should include a note that the authoritative list is generated at runtime by `/godmode`; the static content in the file should be a template, not a literal list.
- CI: `diff <(ls agents/*.md | sed 's/.md//') <(grep -oP '(?<=@)\w+' commands/godmode.md)` — fail if they diverge.

**Warning signs:**
- Adding a new agent requires editing more than one file.
- PostCompact output mentions an agent that doesn't exist in `agents/`.
- A user reports "I tried `@new-agent` and Claude said it doesn't exist" after it was added.

**Phase to address:** Phase 1 (hook hardening, addresses CONCERNS #8 directly). Must be resolved before any new agents are added in v2.

---

### Pitfall 8: Multi-Plugin Namespace Collisions

**What goes wrong:**
Claude Code namespaces plugin skills as `<plugin-name>:<skill-name>` — but this behavior is not always optional. GitHub issue #15882 documents that "the namespace prefix is never optional even when you expect it to be." If a user installs claude-godmode, GSD (`/gsd-*` skills), and Superpowers simultaneously: (a) skills with the same underlying name in different plugins may be shadowed without warning; (b) the claude.ai Skills system injects `anthropic-skills:` namespaced versions of any skill that matches cloud skill names, creating a second copy that wastes tokens (GitHub issue #39686); (c) `@` agent names from multiple plugins can collide if two plugins both ship `@executor`.

**Why it happens:**
Plugin namespacing is applied at the UI display layer but the actual invocation behavior (whether `@executor` refers to godmode's executor or another plugin's) depends on load order and conflict resolution logic that is not well-documented. Users who compose multiple plugins assume additive behavior, but get shadowing.

**How to avoid:**
- Prefix all public-facing agent names with `gm-` in the agent `name` frontmatter: `gm-executor`, `gm-architect`, etc. This is unglamorous but collision-proof.
- The one user-facing command `/godmode` should remain unprefixed (it's the discovery entry point); all workflow skills should use a prefix that distinguishes them from GSD's `/gsd-*` and any Superpowers skills.
- Document explicitly in README: "claude-godmode is not designed to coexist with GSD in the same user profile. If you use GSD, install claude-godmode per-project (`local` scope) to avoid hook and rule conflicts."
- Add a SessionStart hook that detects competing plugins (by checking for `/gsd-*` skills or Superpowers signatures in `~/.claude/`) and emits a visible warning, not a silent failure.

**Warning signs:**
- User reports `@executor` doing something unexpected — it's routing to a different plugin's executor.
- PostCompact reinjects context from two different plugins, doubling the token load.
- `anthropic-skills:` namespace copies appear in `/skills` alongside godmode's skills.

**Phase to address:** Phase 1 (naming and plugin.json hardening). Agent name changes are breaking if external users reference them, so they must be decided before v2 ships publicly.

---

### Pitfall 9: SessionStart Hook Blocking Session Startup

**What goes wrong:**
`session-start.sh` runs synchronously at session open. Any slow operation inside it — a `git log` on a repo with large history, a network call, a `find` traversal on a deep tree — delays the session start for every user, every time. The hook in `hooks/hooks.json` has a `timeout: 10` (seconds) for plugin mode; manual mode has no timeout (CONCERNS #12), so it defaults to 600 seconds. A hook that hangs for 10+ seconds is nearly indistinguishable from a broken install to a new user. Claude Code released a change in early 2026 to defer SessionStart hooks by ~500ms, which helps with perceived startup time but does not address a genuinely slow hook.

**Why it happens:**
`session-start.sh` tries to be helpful by gathering all project context in one pass — tech stack detection, git branch, recent commits, pipeline state. Each of these is fast individually but they add up, and on slow machines or deep repos they can exceed the timeout.

**How to avoid:**
- Set `async: true` on the SessionStart hook binding. This was released in January 2026. Async hooks run in background and do not block session startup. The tradeoff: the hook's `additionalContext` may arrive slightly after the first user prompt. For startup context, this is acceptable.
- Bound all git operations with `--max-count` and `timeout 3 git ...` wrappers so a slow repo cannot exceed 3 seconds total.
- Manual-mode settings must explicitly add `"timeout": 10` to match plugin-mode behavior (fixes CONCERNS #12).
- Measure: add `time ./hooks/session-start.sh < /dev/null` to CI. Fail if it exceeds 2 seconds on a cold repo.

**Warning signs:**
- Session startup takes noticeably longer than `/claude` with no plugins.
- Users report "Claude Code hangs at startup" on large monorepos.
- The 10-second timeout fires and the hook is silently killed, producing no context injection.

**Phase to address:** Phase 1 (hook hardening). CONCERNS #12 is the existing ticket; `async: true` is the resolution.

---

### Pitfall 10: Statusline Invoking jq Four Times Per Render

**What goes wrong:**
`config/statusline.sh` calls `jq` four separate times to parse four different fields from the session JSON. The statusline script runs on every terminal render cycle — potentially tens of times per minute in an active session. Four process spawns per render adds up. On slow machines or in Docker containers with constrained process limits, this creates visible statusline flicker or lag. CONCERNS #19 notes this is "fine but could be collapsed."

**Why it happens:**
Each `jq` call was added independently for its field. No one profiled the aggregate cost.

**How to avoid:**
- Collapse all four `jq` calls into a single invocation that outputs a delimited string: `jq -r '[.model, .cost, .context_pct, .cwd] | @tsv'` then split on tabs in bash. One process spawn per render.
- If the statusline is triggered by Claude Code's internal render loop (not a shell prompt), verify whether `async` hooks could be used instead, reducing the criticality of per-call latency.
- Add the single-jq version as a CI fixture: `time bash config/statusline.sh < test/fixtures/session.json`. Document the expected p99 latency.

**Warning signs:**
- Statusline visibly lags or flickers on older hardware.
- `ps aux | grep jq` shows multiple concurrent jq processes during an active session.

**Phase to address:** Phase 5 (performance polish). Low severity; fix after correctness issues are resolved.

---

### Pitfall 11: Adding Skills That Make the Surface Worse

**What goes wrong:**
Every new skill added to the public surface (the set of user-invocable `/` commands) increases cognitive load for onboarding users. Skills that are "internally useful" (orchestration steps, sub-workflow helpers) but exposed as slash commands create confusion: users don't know which commands are for them vs. which are internal machinery. The v1.x surface already has 8+ commands; v2 targets ≤ 12. If each phase of v2 adds a skill "for completeness," the limit will be exceeded and the "one obvious workflow" promise breaks.

**Why it happens:**
Skills are easy to add and feel like features. Internal orchestration steps need names, and slash commands are the natural naming mechanism. There is no gate on "is this command user-facing or internal?"

**How to avoid:**
- Define a two-tier skill taxonomy in `plugin.json` or a naming convention: `skills/` contains user-facing commands; `agents/` contains internal orchestration. Never expose an agent as a skill just because it's useful.
- Any new skill must pass a justification test: "Can this be achieved by composing existing skills?" If yes, it's not a new skill — it's documentation.
- Internal orchestration steps belong as agents, not skills, because agents are invoked by other agents, not by users directly.
- Run `/godmode` after each phase transition and ask: "Does this list of commands make sense to a new user?" If any command requires knowledge of the internal workflow to understand, it is not user-facing.

**Warning signs:**
- `/godmode` output lists commands that a new user would not know when to use.
- Two skills do similar things with subtle differences (e.g. `/refactor` and `/execute --refactor-mode`).
- Total user-facing command count exceeds 12.

**Phase to address:** Must be addressed in EVERY phase. Each new skill addition must pass the ≤ 12 user-commands check before it lands.

---

### Pitfall 12: Internal Agents Leaking to User-Facing Surface

**What goes wrong:**
When plugin mode serves agents from `${CLAUDE_PLUGIN_ROOT}/agents/`, all `.md` files in that directory become visible and potentially invocable by users typing `@<agent-name>`. If orchestration-helper agents (e.g., a hypothetical `@phase-coordinator` or `@migration-runner`) are placed in `agents/`, they appear in the `/agents` UI and users can invoke them directly, bypassing the intended workflow guards. Users who invoke internal agents directly get undefined behavior — the agent's system prompt assumes it was called by an orchestrator with certain context, which won't be present in a direct user invocation.

**Why it happens:**
There is no Claude Code mechanism to mark an agent as "internal only" — all files in `agents/` are treated equally. The distinction between "user-facing agent" and "internal orchestration agent" is not enforced by the platform.

**How to avoid:**
- Use a naming convention to signal intent: user-facing agents get clean names (`executor`, `architect`); internal helpers get a `_` prefix or `internal-` prefix (`_phase-coordinator`, `internal-migration-runner`). Document in CONTRIBUTING.md that `_`-prefixed agents are not user-addressable.
- The `description` frontmatter field should be written to discourage direct invocation of internal agents: "Internal orchestration agent. Invoke via `/execute`, not directly."
- Audit the `agents/` directory before every release: any new file must be categorized as user-facing or internal and documented accordingly.

**Warning signs:**
- An agent's system prompt references variables (like `$ORCHESTRATOR_CONTEXT`) that would only be set by another agent.
- A user reports invoking an agent directly and getting confusing output.
- The `/agents` UI shows more agents than are listed in `/godmode`.

**Phase to address:** Phase 2 (agent architecture). Naming convention and audit checklist must be established before any internal agents are created.

---

### Pitfall 13: Atomic-Commit Discipline Breaking Under Phase Transitions

**What goes wrong:**
The v2 requirement is atomic commits per workflow gate. In practice, multi-step operations (run quality gates → fix issues → commit) create temptation to batch commits: "let me just fix this small thing and bundle it." Once one exception is made, the pattern erodes. The git hooks enforce `--no-verify` is never called per PROJECT.md constraints, but nothing prevents batching multiple logical changes into one commit under a broad message.

**Why it happens:**
Atomic commits require discipline at the _task_ boundary, not the _session_ boundary. When `/execute` runs multiple stories in sequence, the natural rhythm is to commit all of them at the end. The pipeline v1 did exactly this.

**How to avoid:**
- The `/execute` skill must commit after each individual story, not at the end of all stories. This is a behavioral constraint on the skill's instructions, plus a verification check in the PostToolUse hook on `git commit` calls (verify the commit message format matches story ID).
- Add a PreToolUse hook for `gh pr create` that verifies the number of commits since `origin/main` equals the number of completed stories — if they differ, block and report.
- Document: "One story = one commit" as an inviolable rule in `rules/godmode-git.md`.

**Warning signs:**
- `git log --oneline` shows a commit containing multiple story IDs.
- `/ship` runs but there are no intermediate story commits.
- Story commits have generic messages like "fix multiple issues."

**Phase to address:** Phase 3 (execute skill redesign). Must be explicit in the `/execute` skill instructions and verified by a hook.

---

### Pitfall 14: Requirements Drift Between PROJECT.md and Actual Code

**What goes wrong:**
The "goal-backward verification" requirement means every phase goal must be traceable to a requirement in PROJECT.md. In practice, PROJECT.md drifts: new requirements are added ad-hoc without IDs, old requirements are satisfied but not marked, and the "Active" section accumulates items without graduation to "Validated." Over time, PROJECT.md becomes an artifact that looks authoritative but isn't actually checked by any verification step.

**Why it happens:**
PROJECT.md updates require human judgment at phase transitions — it's not automated. Under time pressure, the update gets deferred ("we'll mark it validated after the PR merges"). Deferred updates accumulate and the document becomes historical fiction.

**How to avoid:**
- Every phase plan must include a `PROJECT.md audit` step as its last task: move satisfied requirements from Active to Validated with the phase reference.
- Every skill that completes a workflow gate (e.g. `/ship`) must output a checklist that references requirement IDs.
- The roadmap must map each phase to specific requirement IDs — so at phase-end, a human can mechanically verify that each ID moved to Validated.
- Use a lint rule (implemented as a pre-commit hook or CI check) that verifies Active requirements have IDs and Validated requirements have phase references.

**Warning signs:**
- PROJECT.md Active section grows without Validated section growing proportionally.
- A requirement in Active has been "pending validation" for more than one phase.
- A phase completes but PROJECT.md is unchanged.

**Phase to address:** Must be addressed in EVERY phase. Phase 1 must establish the requirement ID convention; every subsequent phase uses it.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoded agent/skill lists in hooks | Easy to write | Constant drift against filesystem (CONCERNS #8) | Never — generate at runtime |
| String interpolation for hook JSON | Simple to read | Breaks on any special char in branch/commit (CONCERNS #6) | Never — always use `jq -n --arg` |
| Parallel installer codepaths for plugin vs manual mode | Flexibility | Two surfaces that diverge over time (CONCERNS #11) | Never — generate one from the other |
| Static timestamp in `additionalContext` | Informative for users | Invalidates prompt cache every session | Never — put timestamps in statusline only |
| `effort: xhigh` for all agents | Maximizes reasoning quality | Rules ignored, token budget burned, runaway plans | Only for architect/writer where rule-skipping is tolerable |
| Exposing internal agents as slash commands | Discoverable | Confuses users, pollutes surface | Never — use naming convention to hide internals |
| Per-story sequential commits batched at end | Easier to implement | Violates atomic-commit discipline | Never — commit per story |
| Adding a new skill for each workflow step | Feels complete | Exceeds ≤ 12 command limit, breaks "one obvious workflow" | Only if step cannot be composed from existing skills |
| Backup accumulation without rotation | Simple to implement | Fills `~/.claude/backups/` over time (CONCERNS #13) | Acceptable for up to 5 backups; cap at 5 |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Claude Code prompt cache | Inject volatile data (git log, timestamps) into `additionalContext` | Put volatile data in statusline only; keep `additionalContext` structurally stable across sessions |
| Claude Code hooks | Use `exit 1` to signal blocking errors | Use `exit 2` — only exit code 2 is treated as a blocking error; exit 1 is non-blocking per the hook spec |
| Claude Code hooks | Omit `async: true` on SessionStart | Add `async: true` — blocking SessionStart delays every session open |
| Claude Code plugin namespacing | Expect `/execute` to work without prefix | After other plugins are installed, `/execute` may require `/claude-godmode:execute` — design for this |
| GSD coexistence | Install both GSD and claude-godmode in user scope | One or the other in user scope; the other in project/local scope — document this explicitly |
| Opus 4.7 adaptive thinking | Set `effort: xhigh` for compliance-critical agents | Use `effort: high` for agents where rule-following is required; reserve `xhigh` for creative agents |
| `run_in_background` + TaskOutput | Call `TaskOutput` with `block: true` and no timeout | Always specify a timeout; implement a file-polling fallback for empty output |
| Settings JSON merge (`jq *`) | Add a new top-level key to template without updating merge expression | Update merge expression first; add snapshot test for merge output (CONCERNS #3) |
| Plugin mode agent isolation | Set `permissionMode` in agent frontmatter | `permissionMode` is not supported for plugin-shipped agents; use `disallowedTools` instead |
| Multi-plugin install | Assume `@executor` routes to this plugin | Prefix agent names with `gm-` to guarantee routing |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Four `jq` calls per statusline render | Statusline flicker, render lag | Collapse into one `jq` call with `@tsv` output | On machines with slow process spawn (Docker, old hardware, CI) |
| `git log` in SessionStart without `--max-count` | Session startup blocked 5-30s on large repos | Add `--max-count=5` and `timeout 3` wrapper | Any repo with >10k commits |
| Backup directory accumulation | `~/.claude/backups/` grows unboundedly | Keep last 5, prune on install (CONCERNS #13) | After ~50 installs (measurable at ~2 MB each) |
| Parallel agents + synchronous TaskOutput | Session freeze, indefinite hang | Timeout + file-polling fallback | Any parallel `/execute` run with >2 agents |
| PostCompact re-injecting all context including dynamic data | Cache miss after every compaction, 5x token cost spike | Separate static from dynamic context; static → rules, dynamic → statusline only | Every session longer than cache TTL (~3 min) |
| `effort: xhigh` on routine tasks | Token budget exhausted, `stop_reason: max_tokens`, slow responses | Use `effort: high` for routine; `xhigh` only for design/architecture | Any agent handling O(n) routine stories in `/execute` |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Branch names/commit messages interpolated into hook JSON (CONCERNS #6) | Malformed JSON breaks hook contract; crafted branch names could inject into context | Always use `jq -n --arg VAR "$VALUE" '...'` — never string interpolation in JSON construction |
| Permission deny patterns are substring-matched, not parsed (CONCERNS, security section) | `rm   -rf /` bypasses `Bash(rm -rf /)` deny pattern | Document this limitation; don't rely on deny patterns as the only safety layer — use PreToolUse hooks for structural checks |
| Rule files world-readable on multi-user systems | Sensitive notes in customized rules are readable by other users on shared hosts | `chmod 600` when copying rule files (CONCERNS, security section) |
| No version/checksum verification for plugin source | A user who clones a fork of unknown provenance gets no in-repo verification | Publish `SHA256SUMS`; `install.sh` optionally verifies before copying |
| Ops 4.7 in Auto Mode with no gate hooks | Home directory deletion incident (Dec 2025) — `rm -rf ~/` executed without interruption | PreToolUse hook that pattern-matches dangerous `rm`, `git push --force`, and `DROP TABLE` patterns before they reach permission classifier |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Adding skills to solve every workflow variation | Users can't find the right command; decision paralysis | Compose with arguments (`/execute --dry-run`) rather than new commands |
| Internal agent names visible in `/agents` UI | Users invoke internal agents directly and get confusing output | Naming convention (`_` prefix or `internal-` prefix) to signal non-user-facing agents |
| Version drift across plugin.json / install.sh / godmode.md | Users see different version numbers in different places, lose trust | Single source of truth: `plugin.json` canonical; everything else reads it (CONCERNS #10) |
| PostCompact reinjects long static boilerplate every compaction | Token waste on content that was already in context before compaction | PostCompact should inject only volatile deltas; stable content belongs in rules loaded at session start |
| First-run experience requires reading README | New users don't know what to do after install | `/godmode` command should output a 5-line "what to do next" within first invocation |
| Migration warning buried in output | v1.x users miss the migration prompt and continue with orphaned state | Emit migration warning as a prominent session-start notice with a visual separator |
| Statusline shows raw cost/context figures without context | Users don't know if cost is high or expected | Add a threshold indicator (e.g., color change when context > 80% or cost > $0.50) |

---

## "Looks Done But Isn't" Checklist

- [ ] **Hook JSON safety:** Hooks produce valid JSON on branches named `feat/"quoted"/issue#123` — verify with `jq .` on hook output (CONCERNS #6).
- [ ] **Mode parity:** Plugin-mode and manual-mode effective settings agree on hook timeouts, async flags, and event list — verify with install diff CI check.
- [ ] **Agent list currency:** PostCompact output matches filesystem scan of `agents/*.md` — no hardcoded lists remain.
- [ ] **Quality gates not bypassable in Auto Mode:** A PreToolUse hook blocks `gh pr create` when any gate is red — verify by running `/ship` with a failing test.
- [ ] **Atomic commits enforced:** `/execute` produces one commit per story — verify with `git log --oneline` after a two-story run.
- [ ] **Cache stability:** Two consecutive PostCompact outputs for the same project are byte-identical — verify by running PostCompact twice and diffing output.
- [ ] **Migration path exists:** v1.x user with `.claude-pipeline/stories.json` gets a visible warning and a migration skill — verify by planting a `stories.json` and running the installer.
- [ ] **Version unified:** `plugin.json`, `install.sh`, and `commands/godmode.md` all report the same version string — verify with grep.
- [ ] **Command count:** `ls skills/ commands/` shows ≤ 12 user-facing items — verify before each release.
- [ ] **Statusline single jq:** `strace -e trace=execve bash config/statusline.sh < fixture.json` shows exactly one `jq` invocation — verify after statusline refactor.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Distribution-mode divergence discovered in production | MEDIUM | Audit both config surfaces; generate manual-mode section from hooks.json; ship patch release |
| Prompt cache invalidation (dynamic content in additionalContext) | LOW | Remove dynamic content from hook; restart session to rebuild cache from stable content |
| TaskOutput session freeze | HIGH | User must kill session; restart; file bug; move parallel story to sequential fallback |
| Opus 4.7 ignoring rules | MEDIUM | Drop agent effort level to `high`; rerun task; add explicit constraint to task description |
| Quality gate skipped in Auto Mode | HIGH | Roll back commit; add PreToolUse hook for the gate; re-run story from failed gate |
| v1.x migration data loss | HIGH | Restore from installer backup (`~/.claude/backups/godmode-<timestamp>/`); run migration skill manually |
| Multi-plugin agent collision | MEDIUM | Rename agents with `gm-` prefix; update all skill references; ship minor version bump |
| Skill count exceeds 12 | MEDIUM | Audit and merge similar skills; move internal steps to agents; document the removed commands as composable |
| Version drift across three files | LOW | Set all three to `plugin.json` value; ship patch; add CI check |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Distribution-mode divergence (Pitfall 1, CONCERNS #11, #12) | Phase 1 | CI diff of plugin vs manual effective settings |
| Prompt-cache invalidation via dynamic hooks (Pitfall 2, CONCERNS #9) | Phase 2 | Byte-diff of two consecutive PostCompact outputs |
| TaskOutput race / run_in_background hangs (Pitfall 3) | Phase 3 | Integration test: 2-agent parallel run, verify no hang |
| Opus 4.7 xhigh ignores rules (Pitfall 4) | Phase 2 | Fixture task with explicit rule — verify compliance |
| Auto Mode bypasses quality gates (Pitfall 5) | Phase 4 | Run `/ship` with failing test in Auto Mode — verify block |
| v1.x migration data loss (Pitfall 6, CONCERNS #5) | Phase 1 | Plant `stories.json`, run installer, verify warning + archive |
| Hardcoded skill/agent list drift (Pitfall 7, CONCERNS #8) | Phase 1 | Add agent to filesystem, verify PostCompact output updates |
| Multi-plugin namespace collision (Pitfall 8) | Phase 1 | Install godmode + GSD in same profile, verify no silent overrides |
| SessionStart blocking startup (Pitfall 9, CONCERNS #12) | Phase 1 | `time bash hooks/session-start.sh < /dev/null` < 2s |
| Statusline jq overhead (Pitfall 10, CONCERNS note) | Phase 5 | Single jq invocation verified by strace |
| Surface area bloat from new skills (Pitfall 11) | Every phase | Command count check ≤ 12 before each phase merges |
| Internal agents leaking to user surface (Pitfall 12) | Phase 2 | Audit `/agents` UI output vs `commands/godmode.md` public list |
| Atomic-commit discipline (Pitfall 13) | Phase 3 | Git log after two-story execute run |
| PROJECT.md drift from code (Pitfall 14) | Every phase | Requirement IDs in Active vs Validated sections audited at phase end |

### CONCERNS.md Cross-Reference Resolution Map

| CONCERNS # | Description | Resolving Phase |
|------------|-------------|-----------------|
| #1 | Local rule customizations silently overwritten | Phase 1 (installer per-file diff/skip/replace) |
| #2 | Manual-mode install overwrites agents/skills with no per-file check | Phase 1 (extend CUSTOMIZED count pattern to agents/skills) |
| #3 | Settings merge can drop keys silently | Phase 1 (snapshot regression test for merge output) |
| #4 | No version-mismatch detection in uninstall | Phase 1 (uninstall reads installed version, refuses if mismatch) |
| #5 | v1.x migration removes CLAUDE.md after one keypress | Phase 1 (require literal `yes`; add .claude-pipeline migration) |
| #6 | Branch names interpolated into hook JSON without escaping | Phase 1 (jq -n --arg pattern throughout) |
| #7 | Hooks rely on cwd being project root without fallback | Phase 1 (read cwd from stdin JSON, explicit cd) |
| #8 | Hardcoded skill/agent list in post-compact.sh | Phase 1 (generate from filesystem scan at runtime) |
| #9 | Quality gates duplicated between rules and post-compact | Phase 2 (PostCompact reads from rules file) |
| #10 | Plugin metadata version doesn't match installer version | Phase 1 (plugin.json canonical; installer reads from it via jq) |
| #11 | Manual-mode and plugin-mode hook bindings in two files | Phase 1 (generate manual-mode section from hooks.json) |
| #12 | hooks.json has timeout:10, settings.template.json does not | Phase 1 (add timeout:10 to manual-mode binding; add async:true) |
| #13 | Backup accumulation without rotation | Phase 1 (keep last 5, prune on install) |
| #14 | .claude/worktrees/ not cleaned up | Phase 3 (agent system deletes worktrees on completion; prune recipe in CONTRIBUTING.md) |
| #15 | .claude-pipeline/archive/ grows forever | Phase 1 (cap + document hygiene) |
| #16 | .DS_Store files committed | Phase 1 (git rm --cached; CI file check) |
| #17 | jq prerequisite not prominent in README | Phase 1 (README and plugin manifest top-level note) |
| #18 | set -euo pipefail + stdin consume race | Phase 1 (`cat > /dev/null || true` pattern) |
| #19 | statusline.sh swallows errors silently | Phase 5 (optional debug log to /tmp/godmode-statusline.log) |
| #20 | No automated test coverage | Phase 1 (shellcheck CI), Phase 2 (JSON schema validation), Phase 3 (smoke test round-trip) |
| #21 | README and CHANGELOG drift | Phase 1 (version audit); every phase (documentation parity check) |

---

## Sources

- Claude Code Hooks Reference (official): https://code.claude.com/docs/en/hooks
- Claude Code Plugins Reference (official): https://code.claude.com/docs/en/plugins-reference
- Prompt cache TTL silently dropped: https://dev.to/whoffagents/claudes-prompt-cache-ttl-silently-dropped-from-1-hour-to-5-minutes-heres-what-to-do-13co
- Plugin state changes cause full cache rewrite (GitHub issue #27048): https://github.com/anthropics/claude-code/issues/27048
- TaskOutput hangs after background agent completes (GitHub issue #20236): https://github.com/anthropics/claude-code/issues/20236
- Session freeze with multiple background agents + blocking TaskOutput (GitHub issue #17540): https://github.com/anthropics/claude-code/issues/17540
- Background agent output files remain empty (GitHub issue #17147): https://github.com/anthropics/claude-code/issues/17147
- Default high effort causes Opus 4.6 to ignore skills and CLAUDE.md (GitHub issue #23936, closed not-planned): https://github.com/anthropics/claude-code/issues/23936
- Plugin commands always namespaced, namespace never optional (GitHub issue #15882): https://github.com/anthropics/claude-code/issues/15882
- claude.ai skills silently injected into Claude Code context (GitHub issue #39686): https://github.com/anthropics/claude-code/issues/39686
- SessionStart hook doesn't execute on first run with GitHub marketplace plugins (GitHub issue #10997): https://github.com/anthropics/claude-code/issues/10997
- Multi-agent orchestration context window drift patterns: https://addyosmani.com/blog/code-agent-orchestra/
- Prompt caching in Claude Code — dynamic content anti-patterns: https://www.claudecodecamp.com/p/how-prompt-caching-actually-works-in-claude-code
- Opus 4.7 best practices for Claude Code (official blog): https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code
- Effort levels and token budget: https://platform.claude.com/docs/en/build-with-claude/effort
- YOLO Mode and Auto Mode security analysis (March 2026): https://gist.github.com/hartphoenix/698eb8ef8b08ad2ce6a99cf7346cd7cc
- .planning/codebase/CONCERNS.md (v1.x codebase analysis): local file

---
*Pitfalls research for: claude-godmode v2 — multi-agent workflow orchestrator for Claude Code*
*Researched: 2026-04-25*
