# Feature Landscape — claude-godmode v2

**Domain:** Claude Code plugin (rules + agents + skills + hooks + statusline + permissions) shipped as a coherent senior-engineering-team workflow.
**Researched:** 2026-04-26
**Scope:** What v2 ("polish mature version") must ship on top of the v1.x baseline to be best-in-class, given the locked workflow vocabulary (Project → Mission → Brief → Plan → Commit), the ≤12 user-facing slash commands cap, and the bash + jq runtime budget.
**Vocabulary used throughout:** brief / plan / commit, `/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, plus helpers `/debug`, `/tdd`, `/refactor`, `/explore-repo`. Reference-plugin names (phase, story, PRD, milestone, task, etc.) are deliberately not used.

---

## How to read this document

Each feature lists:

| Field | Meaning |
|---|---|
| **Stage** | Which workflow stage it touches: orient / mission / brief / plan / build / verify / ship / helper / cross-cutting |
| **Complexity** | S (≤ ½ day shell work) / M (1–3 days, integration) / L (multi-day, design + integration + tests) |
| **Depends on** | Other features (in this document) it needs in place first |
| **Confidence** | HIGH (verified against v1.x code, PROJECT.md, or Claude Code docs) / MEDIUM (informed inference, validated against constraints) / LOW (speculative; flag for validation) |

Feature IDs (`F-NN`) are stable and feed REQUIREMENTS.md. Differentiators use `D-NN`; anti-features use `A-NN`.

---

## 1. Table stakes — must ship for v2 to credibly be "polish mature version"

These are not optional. v1.x has the rough shape; v2 is the credible mature shape. If we ship without these, the plugin still works but doesn't earn the maturation framing.

### Workflow surface — the single happy path

#### F-01. Locked 11-command surface with one reserved slot
**Stage:** cross-cutting
**Complexity:** M
**Depends on:** F-02, F-03, F-04, F-05, F-06, F-07, F-08
**Confidence:** HIGH

Exactly these user-invocable slash commands ship: `/godmode`, `/mission`, `/brief N`, `/plan N`, `/build N`, `/verify N`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`. No more. The 12th slot is reserved for a future helper after real demand. v1.x's `/prd`, `/plan-stories`, `/execute` are removed; one-time deprecation notes redirect users.

**Why table stakes:** The Core Value is "best-in-class capability behind the simplest possible surface." Reference plugins fail this test (≥ 30 commands is the norm). The cap is the differentiator made operational.

#### F-02. `/godmode` as orient + statusline setup + project-state-aware "what now?"
**Stage:** orient
**Complexity:** M
**Depends on:** F-15 (live filesystem indexing), F-20 (state injection)
**Confidence:** HIGH

`/godmode` does three things and only three:
1. Print the canonical 5-line "what now?" given current `.planning/STATE.md` (no state → "run /mission to start").
2. List the live agent + skill + brief inventory by scanning the filesystem at runtime (never hardcoded).
3. Offer one-shot statusline setup if the user hasn't enabled it.

It does NOT show the version number (statusline carries that — see F-09). It does NOT page-dump documentation; it answers *"what should I do right now?"* in five lines max.

**Why table stakes:** v1.x's `/godmode` is a static reference card. v2's must be the entry point; otherwise users have to read the README to find the workflow.

#### F-03. `/mission` — Socratic mission discussion that initializes `.planning/`
**Stage:** mission
**Complexity:** M
**Depends on:** F-18 (`.planning/` templates)
**Confidence:** HIGH

`/mission` runs an explicit Socratic discussion (not silent prompt-engineering) that produces `.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, and `config.json` if they don't exist. On a returning project, `/mission` is a no-op orient that says "mission already defined, run /brief N".

**Why table stakes:** Without this, the workflow has no project-level grounding and brief-level work is ungrounded. The Out of Scope item "auto-prompt-engineering of user requests" makes this command's *explicit* nature load-bearing.

#### F-04. `/brief N` — Socratic brief that produces a single `BRIEF.md`
**Stage:** brief
**Complexity:** M
**Depends on:** F-03, F-21 (@researcher), F-22 (@spec-reviewer)
**Confidence:** HIGH

`/brief N` opens a Socratic discussion against the user's intent, optionally spawns `@researcher` for ecosystem questions, optionally spawns `@spec-reviewer` for sanity-check, and writes exactly one file: `.planning/briefs/NN-name/BRIEF.md`. That file combines the why + what + spec + research summary that reference plugins split across three files.

**Why table stakes:** PROJECT.md locks two-files-per-brief. Without `/brief`, there's no upstream artifact for `/plan` to consume.

#### F-05. `/plan N` — atomic, parallelizable plan written to `PLAN.md`
**Stage:** plan
**Complexity:** M
**Depends on:** F-04, F-23 (@planner)
**Confidence:** HIGH

`/plan N` reads `BRIEF.md` and writes `.planning/briefs/NN-name/PLAN.md` containing atomic tasks, parallelism boundaries (waves), and per-task verification criteria. `@planner` does the bulk; the user reviews. The file also reserves a "Verification status" section that `/verify` mutates.

**Why table stakes:** Decouples the *what* (BRIEF.md) from the *how* (PLAN.md), which keeps both reviewable independently. Without it, briefs become essays.

#### F-06. `/build N` — wave-based parallel execution with isolated worktrees
**Stage:** build
**Complexity:** L
**Depends on:** F-05, F-25 (agent convention)
**Confidence:** HIGH

`/build N` reads `PLAN.md`, executes tasks in waves (parallel within a wave, sequential across waves), commits atomically per task, and updates the verification-status section as it goes. Uses `run_in_background` plus a file-polling fallback for output races.

**Why table stakes:** v1.x's `/execute` is the closest parallel; v2 must replace it with something that respects the new artifact shape and handles parallelism cleanly.

#### F-07. `/verify N` — read-only goal-backward verification
**Stage:** verify
**Complexity:** M
**Depends on:** F-06, F-24 (@verifier)
**Confidence:** HIGH

`/verify N` spawns `@verifier` (read-only) to walk back from the success criteria in `BRIEF.md` and report COVERED / PARTIAL / MISSING per criterion. Writes the result into `PLAN.md`'s verification-status section. The agent has `disallowedTools: Write, Edit` to make read-only-ness mechanical.

**Why table stakes:** "Atomic commits per workflow gate" requires a gate before `/ship`. Without verify-before-ship, quality is implicit and drifts.

#### F-08. `/ship` — squash, push, PR, only after verify is clean
**Stage:** ship
**Complexity:** S
**Depends on:** F-07
**Confidence:** HIGH

`/ship` refuses to operate if `PLAN.md`'s verification status is not all-COVERED. On clean state, it sequences git operations and opens a PR via `gh`. No magic prompt mutation; it just sequences the calls.

**Why table stakes:** The workflow needs an exit. Without `/ship`, users hand-craft git commands and lose the "every gate is its own commit" discipline.

### Foundation — version, hardening, parity

#### F-09. Single-source-of-truth version (`plugin.json`) read by `install.sh` via `jq`
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** —
**Confidence:** HIGH

`install.sh` reads `.claude-plugin/plugin.json` at runtime; `commands/godmode.md` removes its literal version (statusline carries it from runtime context). CI gate fails on any other file containing a version string.

**Why table stakes:** Three files currently disagree (1.6.0 / 1.4.1 / 1.4.1). A "polish mature version" cannot ship with version drift; this is the canonical example of polish.

#### F-10. Hooks emit valid JSON under adversarial inputs
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** —
**Confidence:** HIGH

All hook output built via `jq -n --arg ctx "$CONTEXT" '{...}'`, never string interpolation. Branch names with quotes, commit messages with newlines, paths with spaces all survive. Stdin drain tolerates closure (`cat > /dev/null || true`). Project root resolved from stdin's `cwd` field, not `pwd`.

**Why table stakes:** CONCERNS.md High items #6, #7, #18. A plugin whose hooks break on legal git inputs is not mature.

#### F-11. Per-file diff/skip/replace prompt in `install.sh` for customized rules/agents/skills
**Stage:** cross-cutting
**Complexity:** M
**Depends on:** —
**Confidence:** HIGH

When a target file differs from source, prompt: `[d]iff / [s]kip / [r]eplace / [a]ll-replace / [k]eep-all`. Non-interactive default (stdin not a tty) = keep customizations. Backup is always taken regardless of choice.

**Why table stakes:** CONCERNS.md High items #1, #2. Silent overwrite of user customizations is the single biggest trust killer for an installer.

#### F-12. Backup rotation — keep last 5
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** —
**Confidence:** HIGH

`install.sh` writes a new backup, then prunes `~/.claude/backups/` to the most recent 5. `uninstall.sh` already finds latest by sort+head, so the cap fits naturally.

**Why table stakes:** CONCERNS.md item #13. Unbounded growth in `~/.claude/` is sloppy.

#### F-13. Uninstaller version-mismatch detection
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** F-09
**Confidence:** HIGH

`uninstall.sh` reads `~/.claude/.claude-godmode-version`; if it doesn't match the script's known version, warn loudly and require explicit `--force`. Prevents an old uninstaller from leaving newer files orphaned.

**Why table stakes:** CONCERNS.md High item #4.

#### F-14. v1.x migration: detect `.claude-pipeline/`, emit one-line note, never destroy
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** —
**Confidence:** HIGH

`install.sh` detects v1.x state and emits a non-blocking note pointing to the new workflow. Archive happens only on explicit user request. The v1.x command names (`/prd`, `/plan-stories`, `/execute`) ship with one-time deprecation banners that point to new commands; banners are removed in v2.x.

**Why table stakes:** Soft migration is required by Compatibility constraint. Hard breaks burn user trust.

### Quality — CI, tests, docs parity

#### F-15. Live filesystem indexing in `/godmode`, `PostCompact`, statusline
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** —
**Confidence:** HIGH

`/godmode`, `hooks/post-compact.sh`, and any other surface that lists agents/skills must `find` the filesystem at runtime, not embed a hardcoded list. This eliminates CONCERNS #8 drift.

**Why table stakes:** Hardcoded lists in v1.x already drift; mature means they can't drift by construction.

#### F-16. `shellcheck` clean on every `*.sh`, JSON-schema validation on every `*.json`
**Stage:** cross-cutting (CI)
**Complexity:** M
**Depends on:** —
**Confidence:** HIGH

GitHub Actions matrix (macOS + Linux) runs on every PR: `shellcheck` over hooks/install/uninstall/statusline; JSON-schema validation over `plugin.json`, `hooks/hooks.json`, `config/settings.template.json`, `.planning/config.json`; frontmatter linter (pure-bash) over `agents/*.md`, `skills/*/SKILL.md`, `commands/*.md`.

**Why table stakes:** No automated tests today (CONCERNS #20). Mature = mechanical guardrails.

#### F-17. `bats-core` smoke test of install → `/godmode` → uninstall round trip
**Stage:** cross-cutting (CI)
**Complexity:** M
**Depends on:** F-16
**Confidence:** HIGH

Smoke test in a temporary `$HOME` exercises the manual-mode install path end-to-end. Catches regressions in the merge logic, backup rotation, and version handling.

**Why table stakes:** Without this, every release is hand-tested. Mature = automated.

### State — `.planning/` templates and helpers

#### F-18. `.planning/` artifact-set templates ship with the plugin
**Stage:** mission, brief, plan
**Complexity:** M
**Depends on:** —
**Confidence:** HIGH

`PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `config.json` templates ship in the plugin and `/mission` initializes them on first use. `briefs/NN-name/BRIEF.md` and `PLAN.md` skeletons ship as templates that `/brief` and `/plan` populate.

**Why table stakes:** Without templates, every new project reinvents the artifact shape, defeating the workflow's promise of consistency.

#### F-19. `init-context` shared helper (pure bash + jq)
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** F-18
**Confidence:** HIGH

`skills/_shared/init-context.sh` reads `.planning/config.json`, returns a JSON blob with current project + mission + active-brief context. Skill orchestrators source it instead of re-implementing parsing. Pure bash + jq — no Node, no Python, satisfies the runtime constraint.

**Why table stakes:** Without a shared helper, every skill re-implements the same `.planning/` traversal and they drift.

#### F-20. `SessionStart` hook reads `.planning/STATE.md` and injects active-brief context
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** F-18, F-19
**Confidence:** HIGH

If `.planning/STATE.md` exists, the hook reads the active brief number and name, and injects "Active brief: NN-name. Run /plan, /build, /verify, or /ship as appropriate." into session context. Project type and git context still injected as today.

**Why table stakes:** Resuming work today requires the user to remember where they were. Mature = the system reminds them.

### Agents — modernized layer

#### F-21. `@researcher` — background, read-only, ecosystem mapping
**Stage:** brief
**Complexity:** S
**Depends on:** F-25
**Confidence:** HIGH

Already exists in v1.x; v2 modernizes frontmatter (alias `sonnet`, `effort: high`, declares `Connects to:` chain). Spawned by `/brief` when ecosystem questions arise.

**Why table stakes:** Existing capability; v2 modernization is required for parity with the new agent conventions (F-25).

#### F-22. `@spec-reviewer` — read-only brief sanity check
**Stage:** brief
**Complexity:** S
**Depends on:** F-25
**Confidence:** HIGH

Split out of v1.x's `@reviewer`. Read-only (`disallowedTools: Write, Edit`). Reads BRIEF.md, asks "is this scope coherent? are success criteria measurable? are there obvious anti-features?" Produces a markdown critique appended to `BRIEF.md` under a clearly marked review section.

**Why table stakes:** Two-stage review (spec then code) is the documented PROJECT.md decision. Without spec review, briefs ship with unclear success criteria and `/verify` becomes ambiguous.

#### F-23. `@planner` — brief → atomic plan
**Stage:** plan
**Complexity:** S
**Depends on:** F-25
**Confidence:** HIGH

New agent. Opus, `effort: xhigh` (design work, not code-touching). Read-mostly, writes only to `PLAN.md`. Produces atomic, parallelizable tasks with explicit dependencies and verification criteria per task.

**Why table stakes:** PROJECT.md Active section explicitly lists `@planner`. Without it, `/plan` is hand-driven by the user model.

#### F-24. `@verifier` — read-only goal-backward verification
**Stage:** verify
**Complexity:** S
**Depends on:** F-25
**Confidence:** HIGH

New agent. Opus, `effort: xhigh`, `disallowedTools: Write, Edit`. Reads BRIEF.md success criteria, walks the working tree + git log, reports COVERED / PARTIAL / MISSING per criterion.

**Why table stakes:** PROJECT.md Active. Without it, `/verify` is hand-driven and brittle.

#### F-25. Agent frontmatter convention: aliases, effort tier, isolation, memory, maxTurns, Connects to
**Stage:** cross-cutting
**Complexity:** M
**Depends on:** —
**Confidence:** HIGH

Every agent declares: `model: opus|sonnet|haiku` (alias, never numeric), `effort: high|xhigh` (high for code-touching, xhigh for design/audit — this is the rule-skipping mitigation), `isolation: worktree` (code-touching) or `memory: project` (persistent learners), `maxTurns: <N>` defensively, and a `Connects to: <upstream> → <self> → <downstream>` line. Frontmatter linter (F-16) enforces.

**Why table stakes:** Without this, the agent layer is a grab-bag. PROJECT.md Active section makes this explicit.

### Hooks — expanded layer

#### F-26. `PreToolUse` hook blocks `Bash(git commit --no-verify*)` and quality-gate-bypass patterns
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** —
**Confidence:** HIGH

Refuses with a clear error message that points to the rules file. Patterns: `--no-verify`, `--no-gpg-sign`, `-c commit.gpgsign=false`, `git push --force` to main/master. Pattern caveat from CONCERNS #19 (substring match) is documented.

**Why table stakes:** "Atomic commits per workflow gate" + "never use --no-verify" are PROJECT.md hard constraints. Without mechanical enforcement, the rule is aspirational.

#### F-27. `PreToolUse` hook scans tool input for hardcoded secret patterns
**Stage:** cross-cutting
**Complexity:** M
**Depends on:** —
**Confidence:** MEDIUM

Pattern set covering AWS keys, GitHub PATs, generic `(api_key|secret|password)\s*=\s*['"][^'"]+['"]` heuristics. False-positive tolerant — refuses with clear error and suggests env var or `.env` instead.

**Why table stakes:** Quality gate "no hardcoded secrets" needs mechanical backing.

#### F-28. `PostToolUse` hook surfaces failed quality-gate exit codes in next assistant turn
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** —
**Confidence:** MEDIUM

When typecheck/lint/test commands return non-zero, inject a short context note into the next assistant turn: "Last quality-gate command failed: <cmd> exited <code>. Address before continuing."

**Why table stakes:** Closes the loop on the quality-gate enforcement story.

#### F-29. Single source of quality-gate definitions
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** —
**Confidence:** HIGH

`config/quality-gates.txt` (or one rule file with a parseable section) is canonical. `PostCompact` reads from it; rules render from it; CI lint asserts no other file embeds the gate list.

**Why table stakes:** CONCERNS #9 — gates duplicated between rules and post-compact today.

### Documentation — parity

#### F-30. README, CHANGELOG, `/godmode` agree on the public surface
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** F-15, F-16
**Confidence:** HIGH

CI gate compares the agent/skill list rendered by `/godmode`'s live indexer against the README's claimed list and CHANGELOG's "added/removed" sections. Mismatch → CI fails.

**Why table stakes:** PROJECT.md "documentation parity" constraint. Mature = no drift between docs and code.

---

## 2. Differentiators — what makes claude-godmode v2 better than reference plugins

These are deliberately *not* copied from any reference plugin. They emerge from the locked principles (single happy path, ≤12 commands, jq-only, two artifact files per brief, mature internals).

### D-01. Single happy path that fits in five lines
**Stage:** orient
**Complexity:** Constraint (zero implementation cost beyond F-02)
**Depends on:** F-02
**Confidence:** HIGH

`/godmode` answers "what now?" in ≤ 5 lines, project-state-aware. Reference plugins fail this — their progress commands are helpful but the surrounding command surface buries the path. Ours: orient → mission → brief → plan → build → verify → ship, full stop.

**Why differentiating:** The Core Value made operational. A user under cognitive load can read 5 lines and act; they cannot read a 30-skill catalog and act.

### D-02. Two artifact files per brief (BRIEF.md + PLAN.md), never more
**Stage:** brief, plan, verify
**Complexity:** Constraint
**Depends on:** F-04, F-05, F-07
**Confidence:** HIGH

Reference plugins ship 5+ artifact files per active phase. We collapse to two: BRIEF.md (why + what + spec + research summary) and PLAN.md (tactical plan + verification status). The git log IS the execution log — no per-task files. PROJECT.md Out of Scope explicitly forbids per-task TASK.md files.

**Why differentiating:** Less file proliferation = less cognitive context tax. Reviewers can see the full state of a brief in two files, not seven.

### D-03. Bash + jq only, no helper binary, no SDK
**Stage:** cross-cutting
**Complexity:** Constraint
**Depends on:** F-19
**Confidence:** HIGH

Reference plugins ship Node SDKs and assume user-installed helper tooling. We ship: bash 3.2+ and jq. PROJECT.md Out of Scope explicitly forbids "Custom CLI tool to replace gsd-sdk." Every operation is shell-native; the `init-context.sh` helper (F-19) is the substitute for an SDK.

**Why differentiating:** No install pain. No version mismatch between plugin and helper. Works in any shell environment Claude Code runs in. WSL2 portability is a freebie.

### D-04. Live filesystem indexing — no hardcoded inventories
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** F-15
**Confidence:** HIGH

`/godmode`, `PostCompact`, statusline all scan `agents/`, `skills/`, `commands/`, `briefs/` at runtime. Adding a new agent = drop a file, done. Reference plugins maintain hardcoded lists in multiple places.

**Why differentiating:** Eliminates a class of drift bugs by construction. CONCERNS #8 stops being possible.

### D-05. Mechanical, not aspirational, quality gates
**Stage:** cross-cutting
**Complexity:** M
**Depends on:** F-26, F-27, F-28, F-29
**Confidence:** HIGH

Most plugin rules say "don't use `--no-verify`." Ours has a `PreToolUse` hook that refuses. Most plugin rules say "don't commit secrets." Ours scans before allowing. The rule files describe intent; the hooks enforce.

**Why differentiating:** Trust comes from mechanical enforcement. A rule that's only documentation is broken under cognitive load.

### D-06. Plugin-mode == manual-mode UX parity, mechanically asserted
**Stage:** cross-cutting
**Complexity:** M
**Depends on:** F-16, F-17
**Confidence:** HIGH

Hook bindings, permissions, statusline, timeouts are derived from one source of truth and validated by CI. Today CONCERNS #11 and #12 show drift: timeout is 10s in plugin mode, default in manual mode. v2 asserts equivalence.

**Why differentiating:** Reference plugins typically ship one install path. Ours ships two and guarantees they're equivalent.

### D-07. Goal-backward verification before shipping
**Stage:** verify
**Complexity:** M
**Depends on:** F-07, F-24
**Confidence:** HIGH

`/verify` reads BRIEF.md success criteria and walks back from goal. Reference plugins typically verify by running tests; we verify by reading the brief's stated outcomes and matching them. Tests are necessary but not sufficient.

**Why differentiating:** A green test suite that doesn't address the brief's success criteria is failure dressed as success. Goal-backward catches this.

### D-08. Atomic commits per workflow gate, enforced
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** F-26
**Confidence:** HIGH

`/mission`, `/brief`, `/plan`, each task in `/build`, `/verify`, `/ship` each produce their own commit. Hooks block `--no-verify`. The git history IS the workflow audit log.

**Why differentiating:** Easy to undo any single gate. Easy to review any single gate. Reference plugins typically commit at the end of a phase, losing this granularity.

### D-09. Auto Mode awareness in every skill
**Stage:** cross-cutting
**Complexity:** S
**Depends on:** —
**Confidence:** MEDIUM

Every skill detects the "Auto Mode Active" system reminder and adjusts: minimize interruptions, prefer reasonable assumptions, never enter plan mode unless explicitly asked. Documented + tested.

**Why differentiating:** Auto Mode is a documented Claude Code primitive (knowledge cutoff Apr 2026); reference plugins haven't yet adapted to it consistently.

### D-10. Prompt-cache-aware rule and agent prompt structure
**Stage:** cross-cutting
**Complexity:** M
**Depends on:** —
**Confidence:** MEDIUM

Rule and agent system prompts start with a static preamble (no dates, no branch, no dynamic content) and put dynamic context after. This maximizes 5-minute prompt-cache hits. PROJECT.md Active section calls this out explicitly.

**Why differentiating:** Lower cost, lower latency, same quality. Most plugins haven't tuned for this.

### D-11. Wave-based parallel build with file-polling fallback
**Stage:** build
**Complexity:** M
**Depends on:** F-06
**Confidence:** MEDIUM

`/build` uses `run_in_background` for parallel agent spawning, with a documented fallback when stdout races corrupt output (write to per-agent temp files, poll). Reference plugins typically run sequentially.

**Why differentiating:** Multi-task briefs complete faster without losing the per-task atomic-commit discipline.

### D-12. Two-stage read-only review: `@spec-reviewer` then `@code-reviewer`
**Stage:** brief, build
**Complexity:** S
**Depends on:** F-22, plus a `@code-reviewer`
**Confidence:** HIGH

Split v1.x's `@reviewer` into spec (catches scope/criteria problems before code) and code (catches implementation problems before commit). Both `disallowedTools: Write, Edit` so read-only-ness is mechanical.

**Why differentiating:** Catches issues at the cheapest possible point in the workflow. A misspecified brief caught at `/brief` time is 10× cheaper than caught at `/verify` time.

---

## 3. Anti-features — what we explicitly DON'T ship

Each anti-feature has an explicit reason linked to PROJECT.md Out of Scope where applicable. These are guardrails against future scope creep, not just absences.

### A-01. A `/everything` mega-command that runs the full workflow
**Reason:** Hides the workflow shape. Defeats Core Value (single happy path, visible). The user must see brief → plan → build → verify → ship; collapsing them into one command is the same failure mode as v1.x's flat /execute. **PROJECT.md Out of Scope.**

### A-02. ≥ 12 user-facing slash commands
**Reason:** The cap is the differentiator. Every command past 12 dilutes the surface and forces users to remember names. We have 11; the 12th slot is reserved for proven demand. **PROJECT.md Constraints.**

### A-03. Six-level workflow vocabulary (project / milestone / roadmap / phase / plan / task)
**Reason:** Too deep. Ours collapses to five (Project / Mission / Brief / Plan / Commit) with two artifact files. Six levels is a reference-plugin shape; we don't adopt reference structures. **PROJECT.md Out of Scope.**

### A-04. Per-task artifact files (TASK.md or equivalent)
**Reason:** git log IS the execution log. A separate file duplicates and drifts. **PROJECT.md Out of Scope.**

### A-05. External CLI dependency (Node, Python, custom binary, gsd-sdk equivalent)
**Reason:** Bash + jq is the runtime budget. New deps = install pain + version drift + portability holes. The `init-context.sh` helper is the bash-native substitute. **PROJECT.md Out of Scope, Constraints.**

### A-06. Vendored copies of reference plugins
**Reason:** License burden + maintenance burden + inverts dependency direction. We read them freely, copy nothing structural. **PROJECT.md Out of Scope.**

### A-07. Bundled MCP server
**Reason:** Keeps the plugin shape pure (rules / agents / skills / hooks / statusline / permissions). MCP servers can be referenced but live in their own repos with their own release cadence. **PROJECT.md Out of Scope.**

### A-08. Domain-specific scaffolding (Next.js starters, Rails templates, Python project bootstrappers)
**Reason:** This plugin shapes how Claude works, not what users build. Scaffolding belongs in cookiecutter / create-* tools. **PROJECT.md Out of Scope.**

### A-09. Graphical UI / web dashboard
**Reason:** Surface is the terminal. Statusline is the only visual primitive. **PROJECT.md Out of Scope.**

### A-10. Telemetry / analytics
**Reason:** Trust killer. No-network is a differentiator. MIT + no telemetry = drop-in for security-sensitive teams. **PROJECT.md Out of Scope.**

### A-11. Cloud sync of `.planning/` state
**Reason:** git is the user's sync mechanism. Adding cloud sync = auth + service + data residency questions out of scope. **PROJECT.md Out of Scope.**

### A-12. v1.x backwards compatibility beyond a one-time installer migration
**Reason:** Old `/prd` / `/plan-stories` / `/execute` get one-time deprecation banners pointing to new commands, then are removed in v2.x. Carrying both indefinitely doubles the surface and defeats the cap. **PROJECT.md Out of Scope.**

### A-13. Windows-native shell support (cmd / PowerShell)
**Reason:** WSL2 is the supported path. Native ports are a separate effort with no validated demand. **PROJECT.md Out of Scope.**

### A-14. Auto-installing required tools (`brew install jq`, etc.)
**Reason:** Privilege escalation + package-manager assumptions. Preflight check + clear error message is the right call. **PROJECT.md Out of Scope.**

### A-15. Auto-prompt-engineering of user requests (silent intent mutation)
**Reason:** Silent rewrite of what the user said breaks trust. Explicit `/brief` Socratic discussion makes intent clarification visible and consensual. **PROJECT.md Out of Scope.**

### A-16. Plugin-internal package manager / skill marketplace
**Reason:** Skills are markdown files; users add them by editing `~/.claude/skills/`. A registry/marketplace is a different product.

### A-17. Built-in LLM proxy or model abstraction layer
**Reason:** Claude Code already abstracts the model. Aliases (`opus`, `sonnet`, `haiku`) are the routing primitive. A proxy layer is out of scope and would invert the relationship with Claude Code.

### A-18. AI-generated commit messages by default
**Reason:** Claude Code already does this when asked. Auto-generation per commit risks unhelpful messages and obscures intent. The user / agent author writes the message; quality gates check it.

### A-19. Per-skill cherry-pick installation
**Reason:** The plugin is opinionated and cohesive. Cherry-picking turns it into a kit, which the Core Value explicitly rejects.

### A-20. Inline AI assistant for `.planning/` files
**Reason:** Claude Code IS the assistant. A separate "edit BRIEF.md with AI" feature is redundant and adds another command to the surface.

---

## Feature dependencies (high level)

```
F-09 (version SoT) ─→ F-13 (uninstaller version check)
F-15 (live indexing) ─→ F-02 (/godmode), F-30 (docs parity)
F-18 (templates) ─→ F-19 (init-context) ─→ F-20 (SessionStart state)
F-25 (agent convention) ─→ F-21, F-22, F-23, F-24 (all agent definitions)

F-04 (/brief) ─→ F-05 (/plan) ─→ F-06 (/build) ─→ F-07 (/verify) ─→ F-08 (/ship)
F-22 (@spec-reviewer) ─→ F-04 (/brief)
F-23 (@planner) ─→ F-05 (/plan)
F-24 (@verifier) ─→ F-07 (/verify)

F-26 (PreToolUse blocker) ─→ D-08 (atomic commits enforced)
F-29 (gates SoT) ─→ F-28 (PostToolUse surfacing)
F-16 (CI shellcheck) ─→ F-17 (bats smoke), F-30 (docs parity)
```

---

## MVP recommendation — ship order if v2 has to land in stages

If we had to ship v2 in two phases, the MVP cut is:

**v2.0 (must-have, the credible "polish mature version"):**
- All of section 1 (Table stakes F-01 through F-30) except F-17 (bats smoke can slip to v2.1 if needed)
- D-01, D-02, D-03, D-04 from differentiators (these are constraints, not features — they cost zero to "ship" once F-01..F-30 are in)
- D-05 (mechanical quality gates) — needed for trust
- D-06 (mode parity) — needed for the install story
- D-07 (goal-backward verify) — needed for `/ship`
- D-08 (atomic commits) — needed for trust
- D-12 (two-stage review) — already on the F-22 critical path

**v2.1 (polish polish):**
- F-17 if it slipped
- D-09 (Auto Mode awareness) across every skill — incremental; safe to roll out skill-by-skill
- D-10 (cache-aware prompt structure) — incremental
- D-11 (wave-based parallel build) — `/build` ships sequentially in v2.0 if needed, parallel in v2.1

This matches the existing ROADMAP.md phase split (Foundation, Agent layer, Hook layer, Skill layer, Quality) without restructuring it.

---

## Confidence summary

| Section | Confidence | Notes |
|---|---|---|
| Workflow surface (F-01..F-08) | HIGH | Locked by PROJECT.md Active + Key Decisions |
| Foundation (F-09..F-14) | HIGH | All directly addressing CONCERNS.md High items |
| Quality (F-15..F-17, F-30) | HIGH | Standard CI patterns; bats smoke is well-trodden ground |
| State (F-18..F-20) | HIGH | Pure-bash + jq scope is clear |
| Agents (F-21..F-25) | HIGH | All explicit in PROJECT.md Active |
| Hooks (F-26..F-29) | MEDIUM | F-27 secret-scanning has FP/FN tradeoffs that need brief-time tuning |
| Differentiators D-01..D-08 | HIGH | Direct restatements of PROJECT.md principles |
| D-09 Auto Mode | MEDIUM | Documented primitive; integration patterns still evolving |
| D-10 cache-aware prompts | MEDIUM | Improvement, hard to measure win |
| D-11 wave-based parallel | MEDIUM | run_in_background is documented; race-handling needs care |
| D-12 two-stage review | HIGH | Explicit PROJECT.md decision |
| Anti-features A-01..A-20 | HIGH | Most are direct PROJECT.md Out of Scope items |

---

## Sources

- `.planning/PROJECT.md` (Active requirements, Out of Scope, Key Decisions, Constraints) — primary
- `.planning/codebase/STACK.md` — runtime budget (bash + jq)
- `.planning/codebase/STRUCTURE.md` — current v1.x surface
- `.planning/codebase/CONCERNS.md` — High-severity items mapped to F-09..F-15, F-26..F-29
- `.planning/codebase/INTEGRATIONS.md` — Claude Code hook contract, `gh` integration
- Claude Code primitives (knowledge cutoff Apr 2026): Auto Mode, Effort levels, prompt caching (5-minute TTL), `run_in_background`, `disallowedTools`, hook events (SessionStart, PostCompact, PreToolUse, PostToolUse), AskUserQuestion / EnterPlanMode / ScheduleWakeup, MCP server pattern.

*Reference-plugin observations were used only as inspiration to identify validated patterns (parallel agent execution, two-stage review, wave-based dispatch). No reference vocabulary, command names, or directory shapes were adopted.*

---

*Features research: 2026-04-26. claude-godmode v2 — polish mature version.*
