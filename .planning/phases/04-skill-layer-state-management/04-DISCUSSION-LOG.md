# Phase 4: Skill Layer & State Management - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-27
**Phase:** 04-skill-layer-state-management
**Mode:** `--auto` (recommended defaults applied without prompts; single pass; no AskUserQuestion calls)
**Areas discussed:** Skill file location, Frontmatter convention, Connects-to chain, Auto-mode detection, init-context.sh shape, STATE.md format, Templates, v1.x deprecation banners, /godmode orient, /mission flow, /brief flow, /plan structure, /build wave dispatch, /verify mutation discipline, /ship gate sequence, Cross-cutting helpers, State helper organization

---

## Skill file location & shape (WORKFLOW-01)

| Option | Description | Selected |
|--------|-------------|----------|
| All 11 skills under `commands/` | Mirror Anthropic's default discovery shape; keep flat | |
| All 11 skills under `skills/<name>/SKILL.md` | Uniform layout; commands/ becomes redundant | |
| `/godmode` in `commands/`, the other 10 in `skills/<name>/SKILL.md` | Matches Phase 4 SC #1 verification target; preserves bootstrap role of `/godmode`; aligns with v1.x layout post-modernization | ✓ |

**Auto-mode choice:** Split layout (recommended default). Captured as D-01.
**Notes:** SC #1 explicitly asserts the count formula `commands/godmode.md + 10 skills/*/SKILL.md == 11`. Anything else fails the gate.

---

## Reserved slot policy (WORKFLOW-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Stay empty + documentation | Hard cap at 11; 12th slot reserved by doctrine in `rules/godmode-skills.md` | ✓ |
| Add a sentinel `_reserved-slot.md.example` | File with `user-invocable: false` documenting the cap | |
| Allow 12 with future-RFC carve-out | No reservation discipline | |

**Auto-mode choice:** Documentation-only reservation. Sentinel file deferred to v2.x. Captured as D-02.

---

## Skill frontmatter convention (WORKFLOW-01, WORKFLOW-11)

| Option | Description | Selected |
|--------|-------------|----------|
| Inherit v1.x convention verbatim | Just `name`, `description`, `user-invocable`, `allowed-tools` | |
| Extend with v2 fields where they apply | Add `argument-hint`, `arguments`, `disable-model-invocation`; require `## Connects to` body section | ✓ |
| Mirror agent frontmatter (`model`, `effort`) at skill level | Double-control model + effort at skill level | |

**Auto-mode choice:** Extend with v2 fields; OMIT model/effort (owned by agent). Captured as D-04, D-05.
**Notes:** Double-controlling model + effort creates drift; Phase 2 already locked this at agent level.

---

## Connects to chain in skills (WORKFLOW-09)

| Option | Description | Selected |
|--------|-------------|----------|
| Body section parsed by grep | `## Connects to` H2 with `**Upstream:** / **Downstream:** / **Reads from:** / **Writes to:**` bullets | ✓ |
| YAML frontmatter structured field | `connects: { upstream: ..., downstream: ... }` | |
| Free-form first paragraph | No structure; rely on prose | |

**Auto-mode choice:** Body section, mirroring Phase 2 D-07 agent convention. Captured as D-06, D-07.

---

## Auto-Mode detection (WORKFLOW-11)

| Option | Description | Selected |
|--------|-------------|----------|
| Case-insensitive substring match on "Auto Mode Active" | Per session reminder shape; documented in `rules/godmode-skills.md` | ✓ |
| Regex anchored to start of line | More fragile to reminder format drift | |
| Per-skill custom heuristic | No shared discipline; risks drift | |

**Auto-mode choice:** Substring match — single canonical phrase. Captured as D-08, D-09.
**Notes:** Phase 5 vocabulary gate also greps for the canonical detection phrase to enforce contract.

---

## Auto-Mode default policy (WORKFLOW-11)

| Option | Description | Selected |
|--------|-------------|----------|
| Skip ALL prompts including destructive ones | Maximum autonomy; risks rubber-stamp drift (CR-06) | |
| Skip routine prompts; never auto-`--force` | Per-skill recommended-default policy; never bypass safety | ✓ |
| No auto-mode — always prompt | Defeats Auto Mode | |

**Auto-mode choice:** Per-skill recommended defaults; safety overrides preserved (`/ship --force` still requires user). Captured as D-10.

---

## init-context.sh shape (WORKFLOW-12)

| Option | Description | Selected |
|--------|-------------|----------|
| Pure bash + jq, single function `godmode_init_context()`, JSON stdout | Replaces gsd-sdk for our domain | ✓ |
| Helper binary in Go / Rust | Violates PROJECT.md "bash + jq only" | |
| Inline parsing per skill | No shared helper; duplicates logic | |

**Auto-mode choice:** Pure bash + jq, sourced helper. Captured as D-11..D-15.
**Notes:** Schema documented in D-12, locked at `schema_version: 1`. Performance target <100ms p99.

---

## STATE.md format (WORKFLOW-14)

| Option | Description | Selected |
|--------|-------------|----------|
| YAML front matter + markdown audit log | Machine-mutated header + append-only body; both human- and machine-readable | ✓ |
| Pure JSON file | Easy to parse; loses readability and audit log | |
| Pure markdown body (key-value lines) | Readable; harder to parse safely | |

**Auto-mode choice:** Hybrid — YAML front matter + audit log. Captured as D-16, D-17.
**Notes:** Front-matter key set fixed at v1; D-18 documents `gsd_state_version` → `godmode_state_version` forward-migration.

---

## Templates location & substitution (WORKFLOW-13)

| Option | Description | Selected |
|--------|-------------|----------|
| `templates/.planning/` with `{{var}}` mustache substitution | Unambiguous; no shell-expansion conflict | ✓ |
| `templates/` flat with `${var}` substitution | Conflicts with shell expansion if sourced | |
| Inline templates in skill bodies | Drifts; templates can't be linted independently | |

**Auto-mode choice:** Dedicated `templates/.planning/` with mustache. Captured as D-20.

---

## v1.x deprecation banners (WORKFLOW-10)

| Option | Description | Selected |
|--------|-------------|----------|
| Banner block prepended to v1.x SKILL.md bodies, gated by marker file | One-time per install; v1.x bodies preserved verbatim for users mid-migration | ✓ |
| Hard-redirect (delete v1.x bodies) | Breaks users mid-migration | |
| Inline note only (no marker, shown every invocation) | Annoying; users can't dismiss | |

**Auto-mode choice:** Banner + marker (`~/.claude/.claude-godmode-v1-banner-shown`). Captured as D-23, D-24, D-25.
**Notes:** Marker lives outside `${CLAUDE_PLUGIN_ROOT}` so it survives plugin updates.

---

## /godmode ≤5-line orient (WORKFLOW-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Strictly ≤5 lines, branch on `state.exists` | Hard SC #2 constraint; truncate `last_activity` if needed | ✓ |
| ≤10 lines with optional inventory expansion | Verbose; fails SC #2 | |
| Multi-section dashboard | Closer to GSD's `/gsd-status`; not in our shape | |

**Auto-mode choice:** ≤5-line answer + below-the-fold inventory. Captured as D-26..D-28.
**Notes:** Bootstrap behavior (rules check + `/godmode statusline`) preserved verbatim from v1.x.

---

## /mission Socratic flow (WORKFLOW-03)

| Option | Description | Selected |
|--------|-------------|----------|
| 5-question Socratic flow → materialize 5 templates | Idempotent on re-run | ✓ |
| Single mega-prompt | Less interactive; harder to audit | |
| Inherit `/gsd-new-project` shape | Wrong vocabulary; wrong file count | |

**Auto-mode choice:** 5-question flow, idempotent. Captured as D-29..D-31.

---

## /brief N flow (WORKFLOW-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Socratic 6-step flow with optional researcher + spec-reviewer | Single BRIEF.md output; matches IDEA two-files-per-brief locked decision | ✓ |
| Multi-file output (BRIEF + RESEARCH + SPEC) | Violates two-files-per-brief locked decision | |
| Skip Socratic; require pre-written BRIEF | Less accessible | |

**Auto-mode choice:** Socratic + optional spawns. Captured as D-32..D-34.
**Notes:** `@spec-reviewer` defaults to spawning in Auto Mode (D-34).

---

## /plan N PLAN.md structure (WORKFLOW-05)

| Option | Description | Selected |
|--------|-------------|----------|
| Wave-grouped task headings + in-place verification status section | Folds verification into PLAN.md; matches F-05 locked shape | ✓ |
| Separate VERIFICATION.md / TASK.md files | Violates two-files-per-brief | |
| Free-form prose plan | Hard to parallelize | |

**Auto-mode choice:** Wave-grouped tasks with in-place verification section. Captured as D-35..D-37.
**Notes:** Wave heuristic = disjoint file sets + no logical dependency = same wave (D-36).

---

## /build wave dispatch mechanism (WORKFLOW-06)

| Option | Description | Selected |
|--------|-------------|----------|
| `Agent(run_in_background=true)` + file-polling fallback markers | Closes CR-08 (foreground/background race) | ✓ |
| Plain `Agent()` parallel | Hits CR-08 stdout race | |
| Sequential within wave | Defeats parallelism | |

**Auto-mode choice:** Background + file-polling markers in `.planning/briefs/NN/.build/`. Captured as D-40..D-42.

---

## /build concurrency cap (WORKFLOW-06)

| Option | Description | Selected |
|--------|-------------|----------|
| Hardcoded 5 in v2.0 | Documented in skill body; config knob deferred to v2.1 | ✓ |
| Configurable via env var | Premature flexibility for v2.0 | |
| Unbounded | Risks resource exhaustion | |

**Auto-mode choice:** Hardcoded 5. Captured as D-39 + OUT-03.

---

## /build resume / retry detection (WORKFLOW-06)

| Option | Description | Selected |
|--------|-------------|----------|
| Grep git log for `[brief NN.M]` commit-message token | No new state file; reuses git as ground truth | ✓ |
| Per-task .done marker persisted across runs | Adds gitignored state | |
| Database / sqlite of build state | Violates bash + jq only | |

**Auto-mode choice:** Git-log grep on commit-message token. Captured as D-44.

---

## /verify mutation discipline (WORKFLOW-07)

| Option | Description | Selected |
|--------|-------------|----------|
| `@verifier` read-only; skill body does the PLAN.md mutation | Mechanical read-only enforcement on agent (Phase 2 D-10) | ✓ |
| `@verifier` writes directly to PLAN.md | Violates Phase 2 D-10 disallowedTools | |
| Inline rendering only (no PLAN.md mutation) | Loses persistence | |

**Auto-mode choice:** Agent read-only; skill body mutates. Captured as D-46..D-48.

---

## /ship gate sequence (WORKFLOW-08)

| Option | Description | Selected |
|--------|-------------|----------|
| State check → verification check → 6 gates → push → PR | Hard refusal on PARTIAL/MISSING; --force opt-in for verify only | ✓ |
| Skip gate re-run (rely on hooks) | Belt-and-suspenders preferred | |
| Allow --force to bypass gates | Defeats quality contract | |

**Auto-mode choice:** Full sequence; `--force` only bypasses verify check, never gates. Captured as D-49..D-51.

---

## Cross-cutting helpers (WORKFLOW-09)

| Option | Description | Selected |
|--------|-------------|----------|
| Modernize frontmatter + add Auto Mode block + Connects-to; preserve v1.x body semantically | Minimum viable v2 lift; major rewrites deferred | ✓ |
| Full rewrite of all 4 helpers | Out of scope for Phase 4 | |
| Leave verbatim | Fails frontmatter linter, vocab gate | |

**Auto-mode choice:** Frontmatter + Auto Mode + Connects-to lift. Captured as D-52, D-53.

---

## State helper organization (WORKFLOW-12)

| Option | Description | Selected |
|--------|-------------|----------|
| Split `init-context.sh` (read) + `state.sh` (write); optional `_lib.sh` | Read path safe to source from any skill including read-only `/godmode` | ✓ |
| Single mega-helper | Read/write boundary fuzzed | |
| Per-skill duplication | Drift inevitable | |

**Auto-mode choice:** Split read/write helpers. Captured as D-54, D-55.

---

## Claude's Discretion

- Exact wording of `/mission` Socratic questions (planner may rephrase as long as the 5 fields fed into templates are preserved).
- Wave heuristic specifics in `@planner` (the rule is the contract, not the heuristic).
- Whether `_lib.sh` exists separately vs merged into `init-context.sh` (size-driven decision).
- Exact `.build/` polling interval (2s) and per-task timeout (30 min) — recommended defaults; tunable.
- Banner text for v1.x deprecation (illustrative wording; the migration table and one-time mechanism are the contract).

---

## Deferred Ideas

- Concurrency cap configurability (v2.1).
- `GODMODE_POLL_INTERVAL` / `GODMODE_TASK_TIMEOUT` config knobs (v2.1).
- Merging `@writer` and `@executor` (v2.1 — carried from Phase 2).
- A 12th slash command (RFC-gated).
- `/godmode` 6th line on compaction-pressure events (v2.1).
- `init-context.sh` schema v2 (future evolution).
- Skill-level memory if Claude Code adds it (v2.x).
- `_reserved-slot.md.example` sentinel (v2.x polish).
- Schema migration tool for STATE.md (v2.1 if needed).
- `/build` retry-on-flake heuristic (v2.1).
- Per-skill telemetry (out of scope per PROJECT.md "no telemetry").
- Interactive `--dry-run` for `/build` (v2.1).
- `/godmode --json` mode for IDE integration (v2.1).

---

*Phase: 04-skill-layer-state-management*
*Discussion logged: 2026-04-27*
