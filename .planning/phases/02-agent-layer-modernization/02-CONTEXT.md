# Phase 2: Agent Layer Modernization - Context

**Gathered:** 2026-04-26 (auto mode — recommended defaults applied without prompts)
**Status:** Ready for planning

<domain>
## Phase Boundary

Every shipped agent uses the v2 frontmatter convention so the skills layer (Phase 4) and hooks layer (Phase 3) can rely on consistent metadata. Four new agents (`@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer`) ship. Code-writing agents are locked at `effort: high`; design/audit agents at `effort: xhigh`. Every agent declares a `Connects to:` line that names its upstream skill and downstream consumer. A pure-bash frontmatter linter (`scripts/check-frontmatter.sh`) refuses commits with malformed agent metadata.

This phase ships **agent files + linter only.** Hooks (Phase 3) consume the agent inventory; skills (Phase 4) call agents via the `Agent` tool and render the `Connects to:` chain in `/godmode`. Phase 2 keeps the existing v1.x agent semantics — it modernizes the metadata and adds new agents, but does NOT rewrite agent body prose for v2 vocabulary (that's Phase 3 / Phase 4 vocabulary alignment).

</domain>

<decisions>
## Implementation Decisions

### Frontmatter convention (AGENT-01)
- **D-01:** Every agent file declares — in this exact order — these YAML keys in its frontmatter block: `name`, `description`, `model`, `effort`, `tools` (array or comma-list), and one of `disallowedTools` (read-only agents) OR `isolation: worktree` (code-writing agents). Plus optional `memory`, `background`, `maxTurns`. Plus the new mandatory free-form line: `Connects to: <upstream> → <self> → <downstream>`.
- **D-02:** Model field uses **aliases only**: `opus`, `sonnet`, `haiku`. Never pinned IDs (`claude-opus-4-7-20251001`, etc.). Frontmatter linter refuses any `model:` value matching `^claude-`. Locked rationale: aliases let Anthropic upgrade the model substrate without rule changes; pinned IDs decay.
- **D-03:** `Connects to:` line lives OUTSIDE the YAML frontmatter, as a separate H2 section at the top of the agent body — `## Connects to`, with one bullet per upstream + downstream relationship. Rationale: YAML doesn't render arrows nicely; a body section lets `/godmode` parse it with simple `grep` and lets humans read the chain natively. (We considered a YAML field with a structured value, but the bash parser cost is higher and the rendered output is less readable.)

### Effort tier policy (AGENT-02; closes CR-01)
- **D-04:** Agents that write code (`Write` or `Edit` tools allowed): `effort: high`. List: `@executor`, `@writer`, `@test-writer`, `@doc-writer`, `@code-reviewer` (last one may seem odd — code-reviewer reads but commits review notes; v2.1 may move it to read-only). For v2.0, `@code-reviewer` writes only to `.planning/phases/*/REVIEW.md` files, NEVER to source. Documented in its body.
- **D-05:** Agents that don't write source code (`disallowedTools: Write, Edit`): `effort: xhigh`. List: `@architect`, `@security-auditor`, `@planner`, `@verifier`, `@spec-reviewer`, `@reviewer` (the original — kept until Phase 4 deprecates it in favor of the split), `@researcher` (this one stays at `high` — research agents do many shallow lookups, not deep design; xhigh wastes tokens).
- **D-06:** Linter rule (`scripts/check-frontmatter.sh`): refuses any commit where `effort: xhigh` AND `tools:` contains `Write` or `Edit` AND `disallowedTools` does NOT contain both `Write` and `Edit`. This is the mechanical enforcement of CR-01 (Opus 4.7 `xhigh` rule-skipping pitfall).

### Connects to chain (AGENT-08)
- **D-07:** Format: each agent has a `## Connects to` section near the top of its body (after the H1 title, before the main process description). Each line is a markdown bullet of the form: `- **Upstream:** /skill-name` OR `- **Downstream:** @other-agent` OR `- **Reads from:** filesystem path or artifact`. Example for `@planner`:
  ```markdown
  ## Connects to
  - **Upstream:** /plan (the skill that spawns @planner)
  - **Downstream:** Writes PLAN.md consumed by /build → @executor
  - **Reads from:** BRIEF.md (the upstream skill's output)
  ```
- **D-08:** `/godmode` (Phase 4) renders this section by `grep -A 20 '^## Connects to' agents/*.md` — simple, robust to formatting drift. The linter (AGENT-06) asserts every agent has a `## Connects to` section with at least one `**Upstream:**` line and at least one `**Downstream:**` line.

### New agents (AGENT-03, AGENT-04, AGENT-05)
- **D-09:** `@planner` — model `opus`, `effort: xhigh`, `disallowedTools: Write, Edit` (planner writes ONLY to `.planning/phases/*/PLAN.md`, no source code). `tools: Read, Grep, Glob, Bash, WebSearch, WebFetch`. `memory: project`. `maxTurns: 60`. Spawned by `/plan N`. Produces atomic, parallelizable tasks with wave boundaries and per-task verification criteria.
- **D-10:** `@verifier` — model `opus`, `effort: xhigh`, `disallowedTools: Write, Edit` (mechanically read-only — write attempts are blocked at the agent layer, not just by convention). Writes only to PLAN.md verification section via the orchestrator (orchestrator does the actual edit; verifier returns the COVERED/PARTIAL/MISSING report inline). `tools: Read, Grep, Glob, Bash`. `memory: project`. `maxTurns: 50`. Spawned by `/verify N`. Walks back from BRIEF.md success criteria to working tree + git log.
- **D-11:** `@spec-reviewer` — model `sonnet`, `effort: high`, `disallowedTools: Write, Edit`. `tools: Read, Grep, Glob, Bash`. Spawned by `/brief N`. Reviews scope/criteria for ambiguity and over-promising before BRIEF.md is finalized. Catches issues 10× cheaper than code review.
- **D-12:** `@code-reviewer` — model `sonnet`, `effort: high`. Has `Write` (only to write its review report — see D-04 caveat — actually let's lock this one stricter: `disallowedTools: Edit` and `tools: Read, Write, Grep, Glob, Bash`. Write is allowed for the report file only; the agent body documents this as the only legal Write target). `memory: project`. Spawned per-task by `/build N`. Reviews each completed task atomically.

### Modernize v1.x agents (AGENT-07)
- **D-13:** `@architect` — bump `effort: high` → `effort: xhigh` (already read-only). Add `Connects to:` block (Upstream: any skill that spawns design work — currently `/refactor`; Downstream: writes design notes to `.planning/spikes/` or BRIEF.md). Keep model `opus`.
- **D-14:** `@security-auditor` — bump `effort: high` → `effort: xhigh`. Add `Connects to:` block. Keep model `opus`.
- **D-15:** `@executor` — add `effort: high` (currently missing — defaults to medium). Add `Connects to:` block (Upstream: `/build N`; Downstream: per-task SUMMARY.md). Keep model `opus`. Already has `isolation: worktree` and `maxTurns: 100`. Add explicit `tools:` listing if missing.
- **D-16:** `@writer` — add `effort: high`. Add `Connects to:` block. Keep `isolation: worktree`, `maxTurns: 100`. Note: `@writer` and `@executor` overlap heavily — `@writer` is general-purpose, `@executor` is task-from-PLAN.md-aware. Phase 4 may merge them; for Phase 2 we keep both, modernized.
- **D-17:** `@test-writer` — `effort: high` already set. Add `Connects to:` block (Upstream: `/tdd` or `/build N`; Downstream: writes test files alongside source).
- **D-18:** `@doc-writer` — `effort: high` already set. Add `Connects to:` block.
- **D-19:** `@reviewer` — keep as-is in Phase 2 (v1.x compatibility). Phase 4 deprecates it via skill-level alias once `@spec-reviewer` and `@code-reviewer` ship. Add `Connects to:` block noting "Deprecated — split into @spec-reviewer and @code-reviewer in v2.0; kept for v1.x skill compatibility until Phase 4."
- **D-20:** `@researcher` — keep `effort: high` (NOT xhigh — research is shallow-many, not deep). Add `Connects to:` block. `background: true` already set; keep.

### Frontmatter linter (AGENT-06)
- **D-21:** `scripts/check-frontmatter.sh` ships as pure bash + jq. Walks `agents/*.md`, parses frontmatter via awk-extracted YAML block + `yq` if available OR a simple grep-based parser as fallback. **Use grep parser** — adding `yq` as a dependency violates PROJECT.md "bash + jq only at runtime" constraint. CI environment may have `yq`, but the script must work without it.
- **D-22:** Linter checks (in this order):
  1. Required fields present: `name`, `description`, `model`, `effort`, `tools`, `Connects to` section
  2. `model:` value is one of `opus | sonnet | haiku` (regex: `^(opus|sonnet|haiku)$`); fail on `^claude-`
  3. `effort:` value is `high | xhigh` (refuse `medium`, `low`, blank)
  4. `effort: xhigh` + `Write` or `Edit` in `tools:` + missing `disallowedTools` containing both → REFUSE (CR-01 enforcement)
  5. `## Connects to` section has at least one `**Upstream:**` and one `**Downstream:**` bullet
  6. `name:` matches the filename (e.g., `agents/planner.md` declares `name: planner`)
- **D-23:** Linter exits 0 on success. On any failure, prints `[!] <file>: <rule>: <evidence>` and exits non-zero. Designed to run in CI (Phase 5 wires it into GitHub Actions) AND as a pre-commit-style check via the PreToolUse hook (Phase 3).

### Out of scope for Phase 2 (mapped elsewhere)
- **OUT-01:** Vocabulary alignment in agent body prose (replacing `/prd` / `/plan-stories` / `/execute` references with v2 chain) — Phase 4 (WORKFLOW-09 / WORKFLOW-10).
- **OUT-02:** PreToolUse hook calls the frontmatter linter — Phase 3 (HOOK-01 wiring; the linter SHIPS in Phase 2).
- **OUT-03:** `/godmode` rendering of the `Connects to` chain — Phase 4 (WORKFLOW-02).
- **OUT-04:** Merging `@writer` and `@executor` — Phase 4 or v2.1 (skill-driven question; not a Phase 2 decision).
- **OUT-05:** D-17 prompt-cache-aware structure for agent prompts — touched in Phase 2 (frontmatter is upstream of cache structure) but the actual cache-key tuning is Phase 4 / v2.1.

### Claude's Discretion
- Exact wording of `description:` fields in modernized agents — keep current v1.x wording unless it references vocabulary that's been deprecated. Light prose edits acceptable; major rewrites are Phase 4.
- Exact `maxTurns` values for new agents — D-09/D-10/D-11/D-12 propose 60/50/30/40 respectively; planner can adjust ±20 based on task complexity expectations.
- Whether `@code-reviewer` writes its report to `.planning/phases/*/REVIEW.md` directly or returns inline (D-12 picks direct write; if planner finds a cleaner pattern, override).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project context
- `.planning/PROJECT.md` — Active section "Agent layer modernization" subsection (the 8 AGENT-NN bullets); Key Decisions row on effort tiers
- `.planning/REQUIREMENTS.md` — AGENT-01..AGENT-08 (the 8 requirements this phase delivers)
- `.planning/ROADMAP.md` § Phase 2 — Goal, Success Criteria, Plans (3 plans)

### Prior phase
- `.planning/phases/01-foundation-safety-hardening/01-CONTEXT.md` — Phase 1 decisions, especially D-23 (shellcheck-clean) which Phase 2 inherits for `scripts/check-frontmatter.sh`
- `.planning/phases/01-foundation-safety-hardening/01-VERIFICATION.md` — Phase 1 closure proof (substrate is solid)

### Research (current pass)
- `.planning/research/STACK.md` § "Subagents" — full Claude Code 2026 frontmatter contract (model aliases, effort field, isolation, memory, maxTurns, background, disallowedTools)
- `.planning/research/PITFALLS.md` § CR-01 (xhigh + Write/Edit pitfall — drives D-06 enforcement) and § HI-07 (frontmatter typos)
- `.planning/research/ARCHITECTURE.md` § "Five layers" — agents are atomic labor; skills are the only fan-out point that calls Agent tool
- `.planning/research/FEATURES.md` § F-17, F-18, F-19, F-20, F-21, F-22 — the agent-layer feature catalog

### v1.x baseline
- `agents/architect.md`, `agents/security-auditor.md` — design/audit agents to bump to xhigh
- `agents/executor.md`, `agents/writer.md`, `agents/test-writer.md`, `agents/doc-writer.md` — code-writing agents (lock at high)
- `agents/reviewer.md` — to keep as v1.x compat shim; the split goes into new files
- `agents/researcher.md` — keep at high
- `.planning-archive-v1/codebase/CONVENTIONS.md` — v1.x agent conventions for reference

### Source files this phase touches
- `agents/*.md` — all 8 modernized; 4 new added (planner.md, verifier.md, spec-reviewer.md, code-reviewer.md)
- `scripts/check-frontmatter.sh` (new) — frontmatter linter
- `rules/godmode-routing.md` (touched lightly to document the new effort policy and Connects-to convention; full rewrite is Phase 4)

### New files this phase creates
- `agents/planner.md`
- `agents/verifier.md`
- `agents/spec-reviewer.md`
- `agents/code-reviewer.md`
- `scripts/check-frontmatter.sh`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (v1.x baseline)
- **All 8 v1.x agents have parseable YAML frontmatter** with `name`, `description`, `model`, `tools`. Most have `memory: project`. Half have `isolation: worktree`. Only some have `effort:` set explicitly.
- **`agents/reviewer.md`** is the closest analog for `@code-reviewer` — same role, narrower scope.
- **`agents/architect.md`** is the closest analog for `@planner` — Opus, design work, read-mostly.
- **`scripts/` directory exists** (Phase 1 added `check-version-drift.sh`). New `check-frontmatter.sh` lands alongside.
- **Phase 1's `prompt_overwrite()` and `prune_backups()` helpers** in install.sh are good examples of pure-bash + portable patterns. The frontmatter linter follows the same style.

### Established Patterns
- `set -euo pipefail` at top of every shell script
- `info()/warn()/error()` color helpers (in install.sh — frontmatter linter can lift these)
- `[ -f "$file" ] && ...` style guards (POSIX, bash 3.2 compatible)
- Glob + counter loops instead of GNU-only `find -print0 | sort -z`
- `# shellcheck disable=SC<NNNN>` directives must include rationale comment

### Integration Points (downstream)
- **Phase 3** (`hooks/pre-tool-use.sh`) calls `scripts/check-frontmatter.sh` when an agent file is being committed. Phase 2 ships the linter; Phase 3 wires it into the hook.
- **Phase 4** (`/godmode` skill) reads agent frontmatter for the live indexer. Phase 2's frontmatter convention IS the contract `/godmode` consumes.
- **Phase 5** (CI) runs the frontmatter linter as one of 5 lint gates. Phase 2 ships the linter; Phase 5 wires the workflow.

### Anti-pattern: agent → agent fan-out
Agents must NOT spawn other agents via the `Agent` tool. Only skills do that. Linter rule for v2.1: refuse if any agent's `tools:` includes `Agent` or `Task`. Phase 2 documents the convention in agent body prose; mechanical enforcement deferred (no agent currently has `Agent` in tools).

</code_context>

<specifics>
## Specific Ideas

- **Effort tier signal in agent body.** Each modernized agent gets a one-line note near the top documenting its effort tier and the rationale (e.g., `**Effort:** xhigh — design work, read-only.`). Helps reviewers see the choice at a glance without reading frontmatter.
- **Linter UX matches install.sh:** color-coded output, `[+]/[!]/[x]` prefixes, fail with `exit 1` and clear remediation pointer ("see rules/godmode-routing.md for the convention").
- **`@spec-reviewer` checks BRIEF.md's success criteria** for falsifiability — every criterion must be answerable with a CLI command, file presence test, or grep match. Subjective criteria ("looks good", "is consistent") are flagged.
- **`@code-reviewer` writes to `.planning/phases/NN/<task>-REVIEW.md`** — one review file per task, kept alongside the per-plan SUMMARY.md. Cleanup is `rm -rf .planning/phases/NN/*-REVIEW.md` once the phase ships.

</specifics>

<deferred>
## Deferred Ideas

- **Merging `@writer` and `@executor`** into a single code-writing agent (they overlap in v1.x). Out of scope for Phase 2 — the merge is a Phase 4 skill-design question (do `/build` and `/refactor` need different agents, or one parameterized one?). Phase 2 keeps both.
- **Frontmatter linter rule "no Agent/Task in agent tools:"** — mechanical agent → agent fan-out prevention. Currently no agent has it; convention enforced in body prose. Add to linter in v2.1 if drift observed.
- **Pinned model fallback for offline / air-gapped use** — if a user pins `model: claude-opus-4-7-20251001` for reproducibility (e.g., regulated environment), the linter should refuse but with an opt-in `# shellcheck disable=`-style escape comment. Not needed for v2.0; deferred.
- **Agent prompt-cache-aware structure** (D-17 from research) — moving static preamble first, dynamic context after. Improvement, hard to measure win directly. Defer to v2.1 once we have telemetry on cache hit rate.
- **`@researcher` at xhigh for deep dives** — currently kept at high. If Phase 2 verification finds research output quality lacking, bump to xhigh in v2.1.

</deferred>

---

*Phase: 2-Agent Layer Modernization*
*Context gathered: 2026-04-26*
