# Phase 4: Skill Layer & State Management - Context

**Gathered:** 2026-04-27 (auto mode — recommended defaults applied without prompts)
**Status:** Ready for planning

<domain>
## Phase Boundary

The user-facing surface ships. After Phase 4, the v2 happy path is real: a user installs the plugin, runs `/godmode`, and is told (in ≤5 lines) which command to run next. They follow the arrow chain `/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship` plus the four cross-cutting helpers (`/debug`, `/tdd`, `/refactor`, `/explore-repo`) — exactly 11 user-invocable skills, ≤12 cap, 1 reserved.

Concretely, this phase delivers:

- **Two artifact files per active brief** (`BRIEF.md` + `PLAN.md`) under `.planning/briefs/NN-name/`. No EXECUTE.md, no per-task files, no separate VERIFICATION.md / RESEARCH.md. The git log IS the execution log.
- **`/godmode`** rewritten to print a state-aware "what now?" answer in ≤5 lines, live-listing agents + skills + briefs from the filesystem (FOUND-11 substrate from Phase 1) and never printing a literal version (statusline carries it).
- **`/mission`** as a Socratic mission init writing the 5 project-level files (`PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `config.json`); idempotent on returning project.
- **`/brief N`**, **`/plan N`**, **`/build N`**, **`/verify N`**, **`/ship`** authored to the new shape — each Socratic where appropriate, each Auto-Mode-aware, each declaring its `Connects to:` chain.
- **`/build N`** runs wave-based parallel execution via `Agent(run_in_background=true)` with a file-polling fallback for stdout race corruption (CR-08), concurrency cap = 5 hardcoded, atomic commit per task.
- **Cross-cutting helpers** (`/debug`, `/tdd`, `/refactor`, `/explore-repo`) rewritten to v2 shape with auto-mode awareness — body prose modernized, frontmatter brought up to AGENT-01 convention.
- **v1.x deprecation banners** on `/prd`, `/plan-stories`, `/execute` mapping old → new commands. Banners are one-time per install (marker file gates display); SKILL bodies are otherwise preserved for v1.x users mid-migration.
- **`skills/_shared/init-context.sh`** is the bash + jq helper that replaces `gsd-sdk` for our domain. Sourced by every skill instead of re-implementing parsing of `.planning/config.json` and `STATE.md`.
- **`.planning/STATE.md`** — YAML-front-matter header block (active brief #, status, next command, last activity) plus a markdown audit log. Skills mutate by replacing the header and appending an audit line.
- **Templates** for the project-level and brief-level files ship under `templates/.planning/`. `/mission` and `/brief N` materialize from these via simple `{{var}}` substitution.

This phase does NOT ship CI gates or bats smoke (Phase 5). It does NOT change agents or hooks (Phases 2 / 3). It assumes the substrate built by Phases 1-3: PreToolUse blocks `--no-verify`, PostToolUse surfaces failed gates, SessionStart and PostCompact inject STATE.md context, agent inventory is stable and linter-clean, version SoT is live, hooks are JSON-safe under fuzzed branch names.

</domain>

<decisions>
## Implementation Decisions

### Skill file location & shape (WORKFLOW-01)
- **D-01:** The 11 user-invocable surface is split exactly: `commands/godmode.md` is the lone `commands/` entry; the other 10 live as `skills/<name>/SKILL.md`. This matches Phase 4 SC #1's verification target (`find commands skills -name '*.md' -type f | grep '^commands/godmode.md\|/SKILL.md$' | wc -l == 11`). Rationale: `/godmode` is bootstrap-shaped (it can install rules, configure statusline) and is the ONE command a user types before the plugin is "set up" — keeping it in `commands/` matches Claude Code's discovery defaults for that role.
- **D-02:** Reserved 12th slot stays empty in v2.0. Documented in `rules/godmode-skills.md` (touched in this phase) as: "Slot 12 is reserved. Adding a 12th skill is a v2.x decision requiring an explicit RFC; the cap exists to keep the surface scannable."
- **D-03:** v1.x skills (`skills/{prd,plan-stories,execute}/SKILL.md`) stay on disk during v2.0 with deprecation banners (D-23). They are NOT counted toward the 11-cap because `user-invocable: true` is REPLACED by a one-line redirect; their bodies remain for users mid-migration. CI vocab gate (Phase 5) treats their headers as exempt; their bodies are still subject to no-`phase`/`task` leakage rules.

### Skill frontmatter convention (WORKFLOW-01, WORKFLOW-11)
- **D-04:** Every v2 user-invocable skill declares — in this exact order:
  1. `name:` (lowercase, hyphens, mirrors directory name; or filename for `commands/`)
  2. `description:` (one stated goal, ≤200 chars; affects discovery)
  3. `user-invocable: true`
  4. `allowed-tools:` (scoped per skill — never the wildcard set)
  5. `argument-hint: "[N]"` for the four parameterized skills (`/brief`, `/plan`, `/build`, `/verify`)
  6. `arguments: [N]` declared on the same four — so the body reads `$N` (not `$ARGUMENTS[0]`)
  7. `disable-model-invocation: true` for side-effecting skills (`/build`, `/ship`) — the user must invoke explicitly
  8. Body opens with `## Connects to` section (parsed by `/godmode`'s renderer, AGENT-08 + WORKFLOW-02)
- **D-05:** `model:` and `effort:` keys are OMITTED from skill frontmatter. Per Phase 2's locked policy, model + effort are owned by the agent the skill spawns; double-controlling at skill level creates drift. Documented in `rules/godmode-skills.md`.

### `Connects to:` chain in skills (WORKFLOW-09, AGENT-08)
- **D-06:** Each skill has a `## Connects to` section near the top of its body (after the H1 title), structurally identical to the agent convention from Phase 2 D-07. Bullets:
  - `**Upstream:** <previous skill in arrow chain or "(entry point)">`
  - `**Downstream:** <next skill or agent it spawns>`
  - `**Reads from:** <files it consumes>`
  - `**Writes to:** <files it produces>`
- **D-07:** `/godmode` renders this section by `grep -A 20 '^## Connects to' commands/godmode.md skills/*/SKILL.md` and assembling the chain at runtime. No registry, no hardcoded list — drift impossible. Rendering format is documented in WORKFLOW-02 implementation in `commands/godmode.md`.

### Auto-Mode detection (WORKFLOW-11)
- **D-08:** Canonical detection: case-insensitive substring search for the literal string `"Auto Mode Active"` in the most recent system reminder. Implementation pattern (documented in `rules/godmode-skills.md`):
  ```
  Detect Auto Mode by scanning system reminders for "Auto Mode Active" (case-insensitive).
  When detected:
   - Auto-approve routine decisions (e.g., file overwrite confirms in `/mission`).
   - Pick recommended defaults for ambiguity (don't ask).
   - Never enter plan mode unless the user explicitly asked.
   - Course corrections from the user are normal input — handle without complaint.
  ```
- **D-09:** Detection is per-skill responsibility — each skill's body opens with an "Auto Mode check" instruction block referencing `rules/godmode-skills.md`. No shared helper detects it (skills can't introspect prior reminders portably; the convention is "check at top of every Socratic skill"). The 6 workflow skills (`/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`) MUST include this block; the 4 helpers SHOULD include it. Phase 5's vocabulary gate also greps `commands/` + `skills/*/SKILL.md` for the canonical detection phrase to enforce the contract.
- **D-10:** Recommended-default policy when Auto Mode is active:
  - `/mission`: scaffold all 5 project files using sensible defaults; if the user later objects, `/mission` is idempotent enough to re-run.
  - `/brief N`: pick the first plausible interpretation of the user's intent; surface assumptions inline in the BRIEF.md so they can be edited.
  - `/plan N`: produce a single-wave plan unless 3+ atomic tasks exist that don't depend on each other — then promote to wave-2.
  - `/build N`: skip the "preview wave plan" confirmation; proceed.
  - `/verify N`: report COVERED/PARTIAL/MISSING without asking for clarification.
  - `/ship`: run the 6 gates; refuse on PARTIAL/MISSING; never auto-`--force`.

### `init-context.sh` shared helper (WORKFLOW-12)
- **D-11:** File path: `skills/_shared/init-context.sh`. Pure bash 3.2 + jq 1.6+. No Node, no Python, no helper binary. `source`d by every skill at the top of its body via:
  ```bash
  source "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/skills/_shared/init-context.sh"
  CTX=$(godmode_init_context "${PWD}")
  ```
  After sourcing, `godmode_init_context()` is the single entry point. Skills consume the JSON via `printf '%s' "$CTX" | jq -r '.path.to.field // "default"'`.
- **D-12:** JSON output schema (single source of truth, validated by `tests/fixtures/init-context.bats` in Phase 5):
  ```json
  {
    "schema_version": 1,
    "project_root": "/abs/path",
    "planning": {
      "exists": true,
      "config_path": ".planning/config.json",
      "state_path": ".planning/STATE.md",
      "briefs_dir": ".planning/briefs"
    },
    "state": {
      "exists": true,
      "active_brief": 4,
      "active_brief_slug": "skill-layer",
      "active_brief_dir": ".planning/briefs/04-skill-layer",
      "status": "Ready to plan",
      "next_command": "/plan 4",
      "last_activity": "2026-04-27 — context captured"
    },
    "config": {
      "exists": true,
      "model_profile": "balanced",
      "auto_advance": false
    },
    "briefs": [
      { "n": 1, "slug": "foundation", "dir": ".planning/briefs/01-foundation", "has_brief": true, "has_plan": true }
    ],
    "v1x_pipeline_detected": false
  }
  ```
  Missing fields default via `jq` `// empty` or `// "default"` — never null. When `.planning/` doesn't exist, `planning.exists: false` and only `project_root` + `schema_version` are populated.
- **D-13:** All JSON construction inside `init-context.sh` uses `jq -n --arg KEY "$VAL"` (NEVER heredoc interpolation — CR-02). All input parsing of STATE.md uses `awk` for the YAML front matter block, then `jq -r` to project values. Stdin tolerance per Phase 1 D-08: `cat > /dev/null || true`.
- **D-14:** Performance: `godmode_init_context()` MUST run in under 100ms p99 on a project with ≤50 briefs. Target single `find` invocation for the briefs list, single `awk` pass over STATE.md, single `jq` invocation to assemble. No subshell loops over briefs (use `find -print` piped to `jq -Rs '. | split("\n")'`).
- **D-15:** Error mode: when `.planning/` is malformed (e.g., STATE.md missing front matter), emit a valid JSON blob with `state.exists: false` and an `errors: ["…"]` array. NEVER exit non-zero from `init-context.sh` — sourcing it must not abort the calling skill.

### `.planning/STATE.md` format (WORKFLOW-14)
- **D-16:** STATE.md is a hybrid: a YAML front-matter block (machine-mutated) followed by a markdown audit log (append-only).
  ```markdown
  ---
  godmode_state_version: 1
  active_brief: 4
  active_brief_slug: skill-layer
  status: Ready to plan
  next_command: /plan 4
  last_activity: "2026-04-27 — context captured"
  ---

  # Audit Log

  - 2026-04-27 — `/brief 4` completed. Brief at .planning/briefs/04-skill-layer/BRIEF.md.
  - 2026-04-27 — `/plan 4` started.
  ```
  Front-matter key set is FIXED at v1: `godmode_state_version` (always `1`), `active_brief` (integer), `active_brief_slug` (kebab-case string), `status` (free-form string), `next_command` (string starting with `/`), `last_activity` (string).
- **D-17:** Skills mutate STATE.md via a shared `godmode_state_update()` function in `skills/_shared/init-context.sh` (or a sibling `state.sh` — see D-25). Algorithm:
  1. `awk` extracts the YAML front-matter block.
  2. `jq -n --arg ...` constructs the new front matter.
  3. `awk` writes: new front matter, then preserves the body verbatim, then appends an audit line.
  4. `mv` the temp file atomically into place.
  Never edit in place — atomic replace prevents partial state on crash.
- **D-18:** v1.x compatibility: when STATE.md has a `gsd_state_version` key (the GSD-style format we're using during dev), `init-context.sh` reads it transparently — accept either key, normalize to `godmode_state_version` on next mutation. This buys forward-migration without a one-shot script. Documented inline; removed in v2.x.
- **D-19:** When STATE.md doesn't exist, skills emit `state.exists: false` from `init-context.sh` and surface the actionable next step ("Run `/mission` to initialize project state"). `/godmode` is the only skill that's safe to run before STATE.md exists.

### `.planning/` artifact templates (WORKFLOW-13)
- **D-20:** Templates ship under `templates/.planning/`:
  ```
  templates/.planning/PROJECT.md.tmpl
  templates/.planning/REQUIREMENTS.md.tmpl
  templates/.planning/ROADMAP.md.tmpl
  templates/.planning/STATE.md.tmpl
  templates/.planning/config.json.tmpl
  templates/.planning/briefs/BRIEF.md.tmpl
  templates/.planning/briefs/PLAN.md.tmpl
  ```
  Substitution syntax: `{{variable}}` placeholders, replaced via `sed -e 's|{{var}}|val|g'` (use `|` delimiter — variables may contain `/`). Variables documented at the top of each template as a comment block.
- **D-21:** `/mission` materializes the 5 project-level templates by reading them from `${CLAUDE_PLUGIN_ROOT}/templates/.planning/`, substituting answers from the Socratic flow, and writing into `.planning/`. Idempotency: if the target file already exists with content, `/mission` skips it (with a one-line note) and proceeds; never overwrites silently. Auto Mode applies non-destructive defaults — same skip behavior.
- **D-22:** `/brief N` and `/plan N` materialize the brief-level templates similarly. Brief directory: `.planning/briefs/NN-slug/` (zero-padded N, slug = kebab-case from brief title). Both templates carry minimum required sections — template-driven so the linter (Phase 5) can mechanically check structure.

### v1.x deprecation banners (WORKFLOW-10)
- **D-23:** `/prd`, `/plan-stories`, `/execute` SKILL.md bodies are PREPENDED with a deprecation banner block. Shape:
  ```markdown
  ---
  name: prd
  description: "[Deprecated v2.0] Renamed to /brief N. See migration note below. Old behavior preserved for v1.x users mid-migration."
  user-invocable: true
  ---

  # ⚠ Deprecated — use `/brief N` instead

  This command was renamed in v2.0:

  | v1.x | v2.0 |
  |---|---|
  | `/prd` | `/brief N` |
  | `/plan-stories` | `/plan N` |
  | `/execute` | `/build N` |

  The old body still works for projects on the v1.x layout (`.claude-pipeline/`).
  Run `/mission` to migrate to the v2 layout (`.planning/`).

  Banner shown once per install — re-display: `rm ~/.claude/.claude-godmode-v1-banner-shown`.

  --- v1.x body below ---

  [original v1.x content preserved verbatim]
  ```
- **D-24:** "One-time" mechanic: a marker file at `~/.claude/.claude-godmode-v1-banner-shown` (touched after first display). The banner block in each v1.x skill body is wrapped in a check that reads the marker; if absent, display the banner block and `touch` the marker. If present, skip the banner and proceed straight to the v1.x body. Marker lives outside `${CLAUDE_PLUGIN_ROOT}` so it survives plugin updates (per Phase 1 D-04 / `${CLAUDE_PLUGIN_DATA}` doctrine — actually the marker is genuinely user-scoped, so `~/.claude/` not `${CLAUDE_PLUGIN_DATA}` is correct).
- **D-25:** Banners are removed in v2.x (one major after v2.0). Documented in CHANGELOG (Phase 5).

### `/godmode` ≤5-line orient (WORKFLOW-02)
- **D-26:** `/godmode` body computes the ≤5-line "what now?" answer by:
  1. `source skills/_shared/init-context.sh; CTX=$(godmode_init_context "$PWD")`
  2. Branch on `state.exists`:
     - `false` → "No `.planning/`. Run `/mission` to start."
     - `true` → render: `Brief {N}: {slug}. Status: {status}. Next: {next_command}. Last: {last_activity}.`
  3. Below the 1-line answer, list (at most) 4 more lines: count of agents, count of skills, current branch, ahead/behind from main. Total ≤5 lines.
- **D-27:** `/godmode` ALSO live-lists agents + skills + briefs via `find` when invoked with no args (e.g., the user types `/godmode` mid-session for orientation). Renders three columns (agent count, skill count, brief count) plus the chain `Connects to:` graph rendered from D-07. This is the "what's installed?" view; the ≤5-line answer is the "what should I do now?" view. Default invocation shows the answer first, then the inventory.
- **D-28:** `/godmode statusline` keeps the v1.x bootstrap behavior (configure statusline). Preserved as a sub-command — same shape as v1.x, just integrated with v2's rules check (which is also already in the v1.x body).

### `/mission` Socratic init (WORKFLOW-03)
- **D-29:** `/mission` walks the user through 5 questions (each asked one at a time via AskUserQuestion in non-Auto, batched and answered with defaults in Auto):
  1. Project name (kebab-case slug + display title)
  2. One-line core value statement (the "if everything else fails this must hold" sentence)
  3. Tech stack constraints (free-form; piped into PROJECT.md `## Constraints`)
  4. Initial milestone — name + 1-3 sentence goal
  5. Initial brief decomposition — 3-5 brief titles for the milestone
- **D-30:** Output: 5 files materialized from templates (D-20). After write, prints next-step pointer: `Run /brief 1 to start the first brief.`
- **D-31:** Idempotency: if `.planning/PROJECT.md` exists, `/mission` no-ops with `Project already missioned. Run /godmode for status, or rm .planning/PROJECT.md to re-mission.` Auto Mode same — never overwrites without explicit re-mission.

### `/brief N` Socratic brief (WORKFLOW-04)
- **D-32:** `/brief N` walks the user through (per AGENT-04 / `@spec-reviewer` interaction):
  1. Brief title (slug derived)
  2. Why (1-3 sentence motivation)
  3. What (the deliverable; bulleted)
  4. Spec — falsifiable success criteria (each must be answerable with a CLI command, file presence test, or grep match — `@spec-reviewer` enforces)
  5. Optional: spawn `@researcher` for tech research summary
  6. Optional: spawn `@spec-reviewer` for criteria review (default: yes)
- **D-33:** Output: `.planning/briefs/NN-slug/BRIEF.md` (single file). Updates STATE.md: `active_brief = N`, `status = "Ready to plan"`, `next_command = "/plan N"`, audit line appended.
- **D-34:** Auto Mode: skip optional research, skip spec-reviewer prompt (default to spawning), pick first plausible interpretation of intent, surface assumptions inline.

### `/plan N` tactical breakdown (WORKFLOW-05)
- **D-35:** `/plan N` reads `BRIEF.md`, spawns `@planner` (AGENT-03) which writes `PLAN.md` at `.planning/briefs/NN-slug/PLAN.md`. PLAN.md structure (template-driven, D-22):
  ```markdown
  # Plan: {{brief_title}}

  ## Waves

  ### Wave 1 (parallel-safe)

  #### Task 1.1 — <name>
  **Verification:** <criterion answerable by CLI>
  **Files touched:** <list>
  **Steps:**
   1. ...
   2. ...

  #### Task 1.2 — <name>
  ...

  ### Wave 2 (depends on Wave 1)

  #### Task 2.1 — <name>
  ...

  ## Verification status

  - [ ] **Task 1.1** — STATUS (set by /verify)
  - [ ] **Task 1.2** — STATUS
  - [ ] **Task 2.1** — STATUS

  ## Brief success criteria

  - [ ] **SC-1** — STATUS (set by /verify)
  - [ ] **SC-2** — STATUS
  ```
- **D-36:** Wave assignment heuristic (recommended default for `@planner`): tasks that touch disjoint file sets and have no logical dependency are eligible for the same wave; otherwise they're sequential. Concurrency cap = 5 (D-39) — if a wave would have >5 parallel tasks, split into Wave Xa / Wave Xb. `@planner` documents the wave rationale inline.
- **D-37:** Updates STATE.md: `status = "Ready to build"`, `next_command = "/build N"`.

### `/build N` wave-based parallel execution (WORKFLOW-06)
- **D-38:** Within a wave: spawn `@executor` per task via `Agent(run_in_background=true)`. Across waves: orchestrator waits for all tasks in current wave to complete before starting next wave. Per-task atomic commit (one commit per task; commit message format: `<type>(<scope>): <task-name> [brief NN.M]`).
- **D-39:** Concurrency cap = 5 hardcoded. Documented in `commands/godmode.md` and `skills/build/SKILL.md`. Config knob deferred to v2.1 (per IDEA / WORKFLOW-06).
- **D-40:** File-polling fallback for stdout race corruption (CR-08). When `Agent(run_in_background=true)` is used, the orchestrator polls per-task marker files written by the agent into `.planning/briefs/NN-slug/.build/`:
  ```
  .planning/briefs/NN-slug/.build/
    task-1.1.started   (touched by agent at start)
    task-1.1.done      (touched by agent on success)
    task-1.1.failed    (touched by agent on failure; contains stderr tail)
  ```
  Polling interval: 2 seconds (configurable via `GODMODE_POLL_INTERVAL` env, undocumented in v2.0). Timeout per task: 30 minutes (defensive ceiling matching `@executor` `maxTurns: 100`).
- **D-41:** `.build/` directory is gitignored at the brief level (D-44 — `.planning/.gitignore` adds `*/.build/`). After wave completes successfully, `.build/` markers are pruned. On wave failure, `.build/` is preserved for debugging.
- **D-42:** Per-task atomic commit gate: each `@executor` calls `git commit` from inside its worktree (it has `isolation: worktree` from Phase 2 D-15). The commit goes through PreToolUse hook (Phase 3 D-01..D-04) and is rejected on `--no-verify` etc. — no special handling needed in `/build`. PostToolUse (Phase 3 D-09..D-11) surfaces failed gates into the next turn — the orchestrator inspects via `init-context.sh` (or by parsing `.build/task-X.failed`) and aborts the wave.
- **D-43:** On any task failure mid-wave: orchestrator (a) lets currently-running tasks finish (don't kill — their commits may be salvageable), (b) collects `.build/*.failed` payloads, (c) refuses to start the next wave, (d) reports failures + remediation pointer ("re-run `/build N` after fix; failed tasks will retry, completed tasks will skip via D-46").
- **D-44:** Resume / retry: `/build N` re-invocation reads `PLAN.md`'s "Verification status" section (which is mutated by `/verify N`, NOT `/build N` — D-49). To know which tasks succeeded mid-wave, `/build N` checks for the corresponding atomic commit in git log via the commit message format `[brief NN.M]`. Tasks with a matching commit are SKIPPED on resume; failed/never-attempted tasks are retried.
- **D-45:** Updates STATE.md: `status = "Ready to verify"`, `next_command = "/verify N"`. Audit line includes the commit count for the build run.

### `/verify N` read-only goal-backward verification (WORKFLOW-07)
- **D-46:** `/verify N` spawns `@verifier` (AGENT-04 — `disallowedTools: Write, Edit`). Walks back from BRIEF.md success criteria + PLAN.md task verifications to: (1) working tree state, (2) git log since brief started, (3) artifact presence. Returns a STRUCTURED REPORT (markdown) with COVERED / PARTIAL / MISSING per criterion + per task.
- **D-47:** Mutation of PLAN.md: `@verifier` is read-only — it CANNOT directly write the verification status section. Instead, `@verifier` returns the structured report inline; `/verify N` skill body (which has Write capability scoped to PLAN.md only via `allowed-tools: Read, Write, Bash, Grep, Glob`) does the actual file mutation: replace the "Verification status" section in place, append a one-line audit to STATE.md.
- **D-48:** Updates STATE.md: `status = "Ready to ship"` if all criteria COVERED; `status = "Verify found gaps"` otherwise. `next_command` becomes `/ship` if all-COVERED, else `/build N` (rebuild to fix gaps).

### `/ship` quality gates + push + PR (WORKFLOW-08)
- **D-49:** `/ship` does, in order:
  1. Verify STATE.md `status` is "Ready to ship". Refuse otherwise (with pointer to `/verify N`).
  2. Read PLAN.md verification section. If ANY non-COVERED line, refuse with `--force` opt-in (banner-style warning).
  3. Run the 6 quality gates from `config/quality-gates.txt` (Phase 1 D-26 / Phase 3 D-15). Gate #1: typecheck (`tsc --noEmit` or equivalent). #2: lint. #3: tests. #4: secret scan (delegate to PreToolUse — already enforced; `/ship` re-runs it on staged set as belt-and-suspenders). #5: regression. #6: REQ-ID coverage.
  4. `git push origin <branch>`.
  5. `gh pr create` with title + body templated from BRIEF.md (Why → "## Summary"; Spec → "## Test plan").
- **D-50:** `--force` flag: bypasses #2 (PARTIAL/MISSING refusal) ONLY. Never bypasses #3 (gates). Documented in body. Carries an explicit "[godmode] FORCE-shipped with PARTIAL/MISSING criteria — review before merge" line in the PR body.
- **D-51:** Updates STATE.md: `status = "Shipped {pr_url}"`, `next_command = "/brief {N+1}"`, audit line includes PR URL.

### Cross-cutting helpers (WORKFLOW-09)
- **D-52:** `/debug`, `/tdd`, `/refactor`, `/explore-repo` — bodies inherited from v1.x but rewritten to v2 shape:
  - Auto Mode block (D-08, D-09).
  - `## Connects to` section (D-06) — these are entry points so `**Upstream:** (entry point)`; `**Downstream:** @architect` (refactor) / `@test-writer` (tdd) / freeform (debug, explore-repo).
  - Frontmatter scoped `allowed-tools` (no wildcards).
  - `argument-hint` where parameterized.
- **D-53:** v1.x body content stays semantically identical for v2.0 — these helpers aren't the focus of v2 differentiation. Major rewrites deferred to v2.1 if user feedback warrants.

### State helper organization
- **D-54:** `skills/_shared/init-context.sh` is the read entry point. Mutations (state updates, marker writes) live in `skills/_shared/state.sh` — sourced by skills that mutate. Both files are pure-bash + jq + `set -euo pipefail` + the same patterns Phase 1 / 3 hooks established (cwd-from-stdin or explicit arg, jq -n --arg JSON, awk YAML parsing). Splitting reads from writes makes the read path safe to source from any skill (including read-only `/godmode`) without inadvertent side effects.
- **D-55:** `skills/_shared/_lib.sh` (NEW, optional consolidation) — color helpers (info/warn/error matching `install.sh`), atomic file replace helper, slug derivation helper. Sourced by both `init-context.sh` and `state.sh`. If file count grows past ~5, this is the consolidation target; v2.0 may keep it merged into `init-context.sh` if size stays small.

### Out of scope for Phase 4 (mapped elsewhere)
- **OUT-01:** CI workflow + bats smoke + parity gate + vocab gate — Phase 5 (QUAL-01..QUAL-04). Phase 4 ships the artifacts the gates lint; Phase 5 wires the workflow.
- **OUT-02:** README rewrite + CHANGELOG dating + marketplace metadata polish — Phase 5 (QUAL-05..QUAL-07). Phase 4 may touch README's "Workflow" section for v2 chain consistency, but the full ≤500-line rewrite is Phase 5.
- **OUT-03:** Concurrency cap configurability (`GODMODE_BUILD_CONCURRENCY` env or config.json knob) — v2.1. v2.0 hardcodes 5.
- **OUT-04:** Statusline rewriting for new brief-aware shape — already done in Phase 1 (FOUND-06). Phase 4 may surface STATE.md fields differently if init-context emits new keys, but no statusline changes are required.
- **OUT-05:** Merging `@writer` and `@executor` (Phase 2 deferred) — v2.1.
- **OUT-06:** `/build` config knob for `GODMODE_POLL_INTERVAL`, `GODMODE_TASK_TIMEOUT` — undocumented in v2.0. v2.1 promotes if needed.
- **OUT-07:** A 12th slash command — slot reserved; adding it requires an RFC (D-02). Don't add it casually.
- **OUT-08:** Project-state schema migrations (gsd_state_version → godmode_state_version etc.) — D-18 carries forward-migration; reverse migration (godmode → gsd) is not supported and not needed.

### Claude's Discretion
- Exact wording of the 5 Socratic questions in `/mission` (D-29) — `@planner` may rephrase based on whatever phrasing produces clearer answers; the 5 fields they fill into the templates are the contract, not the question text.
- Wave heuristic specifics in `@planner` (D-36) — the rule "disjoint file sets + no logical dependency" is the contract; `@planner` tunes the heuristic with experience.
- Whether `_lib.sh` exists separately (D-55) — if `init-context.sh` stays under ~150 lines, keep it merged.
- Exact polling interval / timeout for `.build/` markers (D-40) — recommended values; planner may shift if benchmarking suggests otherwise.
- Banner text for v1.x deprecation (D-23) — wording is illustrative; planner may adjust as long as the migration table and one-time mechanism are preserved.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project context
- `.planning/PROJECT.md` — Active section "Skill layer rebuild + state management" subsection (the 6 bullets); Constraints (≤12 cap, 1 reserved, two-files-per-brief discipline, bash + jq only)
- `.planning/REQUIREMENTS.md` — WORKFLOW-01..WORKFLOW-14 (the 14 requirements this phase delivers)
- `.planning/ROADMAP.md` § Phase 4 — Goal, Success Criteria (5 SCs), Plans (4 plans)
- `IDEA.md` — repo-root locked-decision document; the user-facing slash command surface (11 commands, ≤12 cap, 1 reserved) is locked here

### Prior phases
- `.planning/phases/01-foundation-safety-hardening/01-CONTEXT.md` — D-04 (`${CLAUDE_PLUGIN_DATA}` semantics for marker files); D-08, D-09 (jq -n --arg pattern reused in init-context.sh); D-22..D-26 (live FS scan; FOUND-11 substrate that `/godmode` consumes); D-26 (config/quality-gates.txt SoT — `/ship` reads from this)
- `.planning/phases/01-foundation-safety-hardening/01-VERIFICATION.md` — confirms version SoT, hook safety, live indexing all green
- `.planning/phases/02-agent-layer-modernization/02-CONTEXT.md` — D-01..D-08 (frontmatter convention extends to skills); D-09..D-12 (the 4 new agents that workflow skills spawn); D-21..D-23 (frontmatter linter — Phase 5 reuses for skill linting)
- `.planning/phases/02-agent-layer-modernization/02-VERIFICATION.md` — confirms agents exist, frontmatter clean, Connects-to graph complete
- `.planning/phases/03-hook-layer-expansion/03-CONTEXT.md` — D-01..D-04 (PreToolUse `--no-verify` block — `/build`'s atomic commits rely on this); D-09..D-11 (PostToolUse failed-gate surfacing — `/build` orchestrator inspects); D-12..D-14 (SessionStart STATE.md injection — same parsing logic as init-context.sh, lift if duplicated); D-15..D-17 (PostCompact STATE.md awareness)
- `.planning/phases/03-hook-layer-expansion/03-VERIFICATION.md` — confirms hook substrate is mechanically enforcing gates

### Research (current pass)
- `.planning/research/STACK.md` § "Skills" — full Claude Code 2026 skill frontmatter contract (`name`, `description`, `user-invocable`, `argument-hint`, `arguments`, `disable-model-invocation`, `allowed-tools`, `context: fork`, etc.); argument substitution rules (`$ARGUMENTS`, `$N`, named); 1,536-char description cap; 5K-token-per-skill compaction budget
- `.planning/research/STACK.md` § "Subagents" — agent frontmatter (referenced for skill→agent dispatch); `Agent(run_in_background=true)` semantics (CR-08 fallback driver)
- `.planning/research/STACK.md` § "Plugin manifest" — `${CLAUDE_PLUGIN_ROOT}` vs `${CLAUDE_PLUGIN_DATA}` semantics (drives D-24 marker location)
- `.planning/research/STACK.md` § "Auto Mode" — permission_mode auto, "Auto Mode Active" reminder shape (drives D-08 detection regex)
- `.planning/research/ARCHITECTURE.md` § Section 2 "Component Boundaries" — five-layer model; skills are the only fan-out point that calls Agent tool (D-38 wave dispatch)
- `.planning/research/ARCHITECTURE.md` § Section 3 "Data Flow" — state vehicles authority order; STATE.md mutation discipline (drives D-16, D-17)
- `.planning/research/ARCHITECTURE.md` § Section 4 "Build Order" — Phase 4 prerequisites (Phase 3 hook substrate)
- `.planning/research/PITFALLS.md` § CR-02 (jq -n --arg discipline — drives D-13); § CR-08 (foreground vs background subagent file-write race — drives D-40 file-polling fallback); § HI-01 (memory ≠ STATE.md — drives the explicit STATE.md authority); § HI-02 (hardcoded skill list in commands/godmode.md — drives D-26, D-27 live-list); § HI-06 (vocabulary leakage — `/build` etc. body must use v2 vocabulary, gated by Phase 5 vocab CI); § ME-01 (skill ignores Auto Mode — drives D-08, D-09); § ME-03 (sequential vs parallel `/build` — drives D-38 wave-based)
- `.planning/research/FEATURES.md` F-01..F-08, F-29..F-33, F-31..F-31b — the skill-layer feature catalog this phase delivers

### v1.x baseline (post-Phases-1-3 state)
- `commands/godmode.md` — current bootstrap shape (rules check, statusline setup); D-26..D-28 extend without removing the bootstrap behavior
- `skills/_shared/pipeline-context.md` — v1.x phase-detection logic (`.claude-pipeline/stories.json`-aware); referenced for parsing-pattern style in init-context.sh, but the v1.x detection itself becomes one branch in init-context.sh (`v1x_pipeline_detected` field)
- `skills/_shared/gitignore-management.md` — pattern for idempotent file-mutation (referenced for STATE.md mutation discipline; same idiom)
- `skills/{prd,plan-stories,execute,refactor,debug,tdd,explore-repo,ship}/SKILL.md` — v1.x bodies. Three deprecate (prd, plan-stories, execute → D-23), four migrate (refactor, debug, tdd, explore-repo → D-52), one rewrites (ship → D-49). Original bodies preserved for v1.x users mid-migration.
- `agents/planner.md`, `agents/verifier.md`, `agents/spec-reviewer.md`, `agents/code-reviewer.md` — Phase 2 outputs that Phase 4 skills spawn

### Source files this phase touches
- `commands/godmode.md` (rewrite — D-26..D-28; preserve statusline + rules-check bootstrap)
- `skills/mission/SKILL.md` (NEW — D-29..D-31)
- `skills/brief/SKILL.md` (NEW — D-32..D-34)
- `skills/plan/SKILL.md` (NEW — D-35..D-37)
- `skills/build/SKILL.md` (NEW — D-38..D-45)
- `skills/verify/SKILL.md` (NEW — D-46..D-48)
- `skills/ship/SKILL.md` (rewrite — D-49..D-51; preserve any v1.x assertions still applicable)
- `skills/debug/SKILL.md` (modernize — D-52, D-53)
- `skills/tdd/SKILL.md` (modernize — D-52, D-53)
- `skills/refactor/SKILL.md` (modernize — D-52, D-53)
- `skills/explore-repo/SKILL.md` (modernize — D-52, D-53)
- `skills/prd/SKILL.md` (deprecate banner — D-23, D-24)
- `skills/plan-stories/SKILL.md` (deprecate banner — D-23, D-24)
- `skills/execute/SKILL.md` (deprecate banner — D-23, D-24)
- `skills/_shared/init-context.sh` (NEW — D-11..D-15)
- `skills/_shared/state.sh` (NEW — D-17, D-54)
- `rules/godmode-skills.md` (touched — D-08, D-09 Auto Mode block; reserved-slot doctrine D-02)
- `templates/.planning/{PROJECT,REQUIREMENTS,ROADMAP,STATE,config.json}.md.tmpl` (NEW — D-20)
- `templates/.planning/briefs/{BRIEF,PLAN}.md.tmpl` (NEW — D-20)

### New files this phase creates
- `skills/{mission,brief,plan,build,verify}/SKILL.md` (5 new workflow skills)
- `skills/_shared/init-context.sh`
- `skills/_shared/state.sh`
- `templates/.planning/PROJECT.md.tmpl`
- `templates/.planning/REQUIREMENTS.md.tmpl`
- `templates/.planning/ROADMAP.md.tmpl`
- `templates/.planning/STATE.md.tmpl`
- `templates/.planning/config.json.tmpl`
- `templates/.planning/briefs/BRIEF.md.tmpl`
- `templates/.planning/briefs/PLAN.md.tmpl`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (from Phases 1-3)
- **`hooks/session-start.sh` STATE.md parsing (Phase 3 D-13)** — `awk` block extracting YAML front matter, falling back to markdown body. Lift INTO `skills/_shared/init-context.sh` so the hook and the helper share a single parser. (Phase 3 D-12 already flagged this as a likely shared helper target.)
- **`hooks/post-compact.sh` live FS scan (Phase 1 D-22)** — `find agents/ -name '*.md' \! -name '_*' -print` style; reuse for `/godmode` agent + skill enumeration (D-27).
- **`hooks/post-compact.sh` jq -n --arg JSON construction (Phase 1 D-08)** — pattern for `init-context.sh` JSON output (D-13).
- **`config/quality-gates.txt`** — 6-line SoT. `/ship` reads from it (D-49).
- **`install.sh` `info()/warn()/error()` color helpers** — lift into `skills/_shared/_lib.sh` (D-55) so skills have consistent UX with the installer.
- **`scripts/check-frontmatter.sh` (Phase 2)** — agent frontmatter linter; in Phase 5 we extend it to also lint skill frontmatter, but Phase 4 just needs to author skills that PASS the existing linter when extended.
- **v1.x `commands/godmode.md` rules-check bootstrap (lines ~17-43)** — preserve verbatim into v2 `/godmode`; the bootstrap covers users who installed manually without rules.
- **v1.x `skills/_shared/pipeline-context.md` `.claude-pipeline/` detection** — folded into `init-context.sh` as the `v1x_pipeline_detected` branch (D-12).

### Established Patterns (from Phases 1-3)
- `set -euo pipefail` at top of every shell file (`init-context.sh`, `state.sh`)
- `INPUT=$(cat || true)` for stdin tolerance under pipefail (only relevant if init-context.sh ever reads stdin; current design takes argv only — but the pattern is documented for future use)
- `jq -n --arg KEY "$VAL"` for ALL JSON construction
- `awk '/^---$/{count++; if(count==2)exit} count==1 && match(...)'` for YAML front-matter parsing (Phase 2 / Phase 3 idiom)
- `[ -f "$file" ] && ...` POSIX-style guards (bash 3.2 compatible)
- Skill frontmatter style: lowercase name, hyphens, scoped `allowed-tools` (never wildcards)
- "Connects to" body section with `**Upstream:** / **Downstream:** / **Reads from:** / **Writes to:**` bullets (extends Phase 2 D-07)

### Integration Points (downstream)
- **Phase 5** (CI) lints skill frontmatter via the extended frontmatter linter (Phase 2 D-21 + Phase 5 QUAL-01). Phase 4 skills must pass.
- **Phase 5** (vocabulary gate, QUAL-04) greps `commands/` + `skills/*/SKILL.md` + `README.md` for `phase`, `task`, `story`, `PRD`, `gsd-*`, `cycle`, `milestone`. Phase 4 ships skill bodies that already comply (use brief / build / wave / ship / verify vocabulary).
- **Phase 5** (bats smoke, QUAL-02) executes `/brief 1 → /plan 1 → /build 1` round-trip in a temp `$HOME` and asserts (a) exactly 2 files in the brief dir, (b) git log has one atomic commit per task. Phase 4 ships skills that achieve this on a clean project.
- **Phase 5** (plugin / manual parity gate, QUAL-03) — Phase 4 changes don't touch hooks; parity should hold automatically. Vigilance: if `/build`'s file-polling fallback grows env vars, document them in BOTH `hooks.json` and `settings.template.json` if they're hook-relevant (probably not).

### Anti-patterns to AVOID
- **Hardcoded skill / agent list in `commands/godmode.md`** (HI-02) — must `find` at runtime. The Phase 1 substrate (FOUND-11) makes this trivial; don't regress.
- **Heredoc + variable interpolation in `init-context.sh` JSON output** (CR-02) — same discipline Phase 1 hooks adopted; `jq -n --arg` everywhere.
- **Memory used as substitute for STATE.md** (HI-01) — STATE.md is canonical; agents may use `memory: project` for their own learnings (e.g., `@planner` notes a wave heuristic that worked) but MUST NOT mutate state via memory. State mutations go through `skills/_shared/state.sh` only.
- **Vocabulary leakage** (HI-06) — `phase` / `task` / `story` / `PRD` / `gsd-*` / `cycle` / `milestone` MUST NOT appear in user-facing skill bodies (`commands/godmode.md` + `skills/*/SKILL.md`). Internal docs (`rules/`, `agents/`) are exempt. Phase 5 enforces; Phase 4 must ship clean.
- **Auto Mode rubber-stamp drift** (CR-06) — Auto Mode default selection must match what a user would actually want (recommended-default policy in D-10). Don't auto-pick destructive options just because they're first in a list.
- **Background Agent stdout race** (CR-08) — `/build` MUST use `Agent(run_in_background=true)` with file-polling fallback (D-40), NEVER plain `Agent()` for parallel within-wave dispatch.
- **Statusline regression** — Phase 1 collapsed statusline to single jq invocation (FOUND-06). Phase 4 doesn't touch statusline; if it surfaces new STATE.md fields, do so via `init-context.sh` not by adding `jq` calls inside `config/statusline.sh`.

</code_context>

<specifics>
## Specific Ideas

- **`/godmode` ≤5-line answer is a hard constraint, not aspirational.** Counted as actual rendered lines on a 80-col terminal. If `last_activity` is too long to fit, truncate with `…`. Phase 5's bats can wc -l the output to assert.
- **`init-context.sh` returns a JSON blob, NOT prints to TTY.** Skills `source` it for the function definition, then call `godmode_init_context "$PWD"` and capture stdout. Body of the function does its work in a subshell to keep variables from leaking into the calling skill.
- **Wave parallelism marker files (D-40) are the ONLY ground truth** for `/build` orchestration. The `Agent(run_in_background=true)` return JSON is best-effort; on stdout race, marker files are authoritative. Document this discipline in `skills/build/SKILL.md` so the next maintainer doesn't add "let's just check the agent return" debug code.
- **Per-task atomic commit message format** (D-38): `<type>(<scope>): <task-name> [brief NN.M]`. The `[brief NN.M]` token (e.g., `[brief 04.3]` for Phase 4 Task 3) is what `/build` resume detection (D-44) greps. Phase 4 skills emit this format; Phase 5's bats asserts.
- **Templates use `{{var}}` not `${var}` substitution** (D-20). Reason: `${var}` would interfere with shell expansion if a template is ever sourced as a script; `{{var}}` is unambiguous and conventional (mustache-style).
- **STATE.md `audit log` body is APPEND-ONLY.** Skills mutate front matter; they NEVER edit prior audit lines. User can hand-edit between commands but skills assume body integrity. If a skill needs to "rewind", it appends a new audit line (`2026-04-27 — reverted to brief 3 status`); never deletes.
- **Phase 4 itself does NOT use the v2 `/build` to build itself.** GSD remains the dev toolchain (per CLAUDE.md "Two workflow shapes" doctrine). The Phase 4 skills are tested manually + via Phase 5's bats; we don't dogfood until Phase 4 lands and Phase 5 ships the substrate to gate it.
- **Empty reserved slot 12 has a sentinel file.** Optional polish: `commands/_reserved-slot.md.example` with frontmatter `user-invocable: false` and a body explaining the cap. Or just rely on documentation. v2.0 leans documentation; the example file is v2.x material if drift becomes a problem.

</specifics>

<deferred>
## Deferred Ideas

- **Concurrency cap configurability** (`GODMODE_BUILD_CONCURRENCY` env or config knob) — v2.1. v2.0 hardcodes 5.
- **`GODMODE_POLL_INTERVAL` / `GODMODE_TASK_TIMEOUT` config knobs** — v2.1.
- **Merging `@writer` and `@executor`** — v2.1 (carried from Phase 2 deferred list).
- **A 12th slash command** — slot reserved; adding requires an RFC.
- **`/godmode` rendering of compaction-survival hint** — currently the ≤5-line answer is brief-state-aware; v2.1 may add a 6th line on compaction-pressure events. Out of scope for v2.0.
- **`init-context.sh` schema v2** — currently locked at `schema_version: 1`. Future fields (e.g., `worktree.dirty`, `agents.unfree`) bump to v2. Out of scope for now; the schema_version field exists precisely for this future evolution.
- **Skill-level memory** (`memory: project` on a skill) — Claude Code supports it on agents only currently. If skill-level lands in 2026, `/godmode` could use it for cached agent enumeration; until then, live-listing on every invocation is fine (sub-100ms per FOUND-11).
- **A `_reserved-slot.md.example` sentinel** — v2.x polish if reserved-slot drift becomes a real problem.
- **Schema migration tool for STATE.md** (`gsd_state_version` → `godmode_state_version`) — D-18 carries forward-migration. A one-shot migration script is v2.1 if needed.
- **`/build` retry-on-flake heuristic** — currently failed tasks surface; user re-runs. Auto-retry with backoff is v2.1.
- **Per-skill telemetry** (how often invoked, success rate) — out of scope per PROJECT.md "no telemetry, ever".
- **An interactive `--dry-run` for `/build`** — show wave plan without dispatching. v2.1.
- **`/godmode --json` mode for IDE integration** — currently the orient output is for human terminals. JSON mode is v2.1.

</deferred>

---

*Phase: 04-skill-layer-state-management*
*Context gathered: 2026-04-27*
