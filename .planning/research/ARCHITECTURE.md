# Architecture Research

**Domain:** Claude Code plugin — configuration/extension distribution + opinionated engineering workflow
**Researched:** 2026-04-25
**Confidence:** HIGH (primary sources: live GSD plugin files, v1.x codebase analysis, GSD executor/planner agents, GSD workflow files)

---

## 1. What is the canonical `.planning/` directory shape used by GSD?

GSD's `.planning/` directory is the project's single source of truth across the full lifecycle. Every file has a defined owner (workflow or agent), a defined lifecycle stage, and a defined consumer.

```
.planning/
├── PROJECT.md          ← Living project context. Updated at milestone boundaries and phase transitions.
│                         Sections: What This Is, Core Value, Requirements (Validated/Active/Out of Scope),
│                         Context, Constraints, Key Decisions.
│                         Owner: /gsd-new-project (creation), /gsd-transition (evolution)
│
├── REQUIREMENTS.md     ← Scoped requirement IDs (AUTH-01, WORK-02...). Each req traces to a ROADMAP phase.
│                         Owner: /gsd-new-project (creation), gsd-executor (marks complete per plan)
│
├── ROADMAP.md          ← Phase structure. Each phase has: Goal, Depends on, Requirements IDs, Success
│                         Criteria, Plans list (checkbox). Updated by gsd-planner (plan count/list),
│                         gsd-executor (marks plans complete), /gsd-transition (marks phases complete).
│
├── STATE.md            ← Living session memory. Sections: Current Position (phase/plan/status/progress bar),
│                         Performance Metrics, Decisions, Pending Todos, Blockers, Session Continuity.
│                         Updated after every plan completion by gsd-executor via gsd-sdk.
│
├── config.json         ← Per-project workflow config. Fields: model_profile, commit_docs, git.branching_strategy,
│                         workflow.use_worktrees, workflow.inline_plan_threshold, response_language.
│                         Read by every gsd-sdk init call before spawning agents.
│
├── phases/             ← One directory per phase, named {NN}-{slug}/.
│   └── 01-foundation/
│       ├── 01-01-PLAN.md       ← Executable plan. Frontmatter: phase, plan, type, wave, depends_on,
│       │                         files_modified, autonomous, requirements, must_haves.
│       │                         Body: <objective>, <context>, <tasks>, <threat_model>,
│       │                         <verification>, <success_criteria>, <output>.
│       │                         Owner: gsd-planner. Consumer: gsd-executor.
│       │
│       ├── 01-01-SUMMARY.md    ← Execution record. Frontmatter: phase, plan, subsystem, tags,
│       │                         dependency graph (requires/provides/affects), tech-stack,
│       │                         key-files, decisions, metrics (duration, completed).
│       │                         Owner: gsd-executor. Consumer: gsd-verifier, gsd-planner (history).
│       │
│       ├── 01-CONTEXT.md       ← (Optional) User decisions from /gsd-discuss-phase. Sections:
│       │                         Decisions (locked, with D-01..D-NN IDs), Deferred Ideas, Claude's Discretion.
│       │                         Owner: /gsd-discuss-phase. Consumer: gsd-planner (locked constraints).
│       │
│       ├── 01-RESEARCH.md      ← (Optional) Phase-scoped research from /gsd-research-phase.
│       │                         Consumer: gsd-planner (standard_stack, pitfalls, architecture_patterns).
│       │
│       └── 01-VERIFICATION.md  ← (Optional) Post-execution verification output from /gsd-verify-work.
│                                 Consumer: gsd-planner (--gaps mode) for gap closure plans.
│
├── research/           ← Project-wide research (from /gsd-new-project or /gsd-new-milestone).
│   ├── SUMMARY.md      ← Executive synthesis, phase structure recommendations.
│   ├── STACK.md        ← Technology decisions.
│   ├── FEATURES.md     ← Feature landscape.
│   ├── ARCHITECTURE.md ← System structure (this file).
│   └── PITFALLS.md     ← Domain pitfalls.
│
├── codebase/           ← Codebase mapping output (from /gsd-codebase-map or equivalent).
│   ├── ARCHITECTURE.md ← Current system structure.
│   ├── STACK.md        ← Current tech stack.
│   ├── STRUCTURE.md    ← Directory layout.
│   ├── CONVENTIONS.md  ← Coding conventions.
│   ├── INTEGRATIONS.md ← External integration points.
│   ├── TESTING.md      ← Test strategy.
│   └── CONCERNS.md     ← Known issues with severity ratings.
│
└── graphs/             ← (Optional) Semantic knowledge graph.
    └── graph.json      ← Used by gsd-planner for dependency-aware task ordering.
```

**Artifact lifecycle:**

| Artifact | Created by | Updated by | Consumed by | Committed? |
|----------|-----------|------------|-------------|-----------|
| PROJECT.md | /gsd-new-project | /gsd-transition | all agents (via @reference) | Yes |
| REQUIREMENTS.md | /gsd-new-project | gsd-executor (mark complete) | gsd-planner | Yes |
| ROADMAP.md | /gsd-new-project | gsd-planner, gsd-executor | all agents | Yes |
| STATE.md | /gsd-new-project | gsd-executor after each plan | gsd-executor (resume), /gsd-next | Yes |
| config.json | /gsd-new-project | /gsd-settings | gsd-sdk (every init call) | Yes |
| NN-NN-PLAN.md | gsd-planner | — (immutable after creation) | gsd-executor | Yes |
| NN-NN-SUMMARY.md | gsd-executor | — (append: self-check) | gsd-verifier, gsd-planner | Yes |
| NN-CONTEXT.md | /gsd-discuss-phase | — (immutable) | gsd-planner | Yes |
| NN-RESEARCH.md | /gsd-research-phase | — (immutable) | gsd-planner | Yes |
| NN-VERIFICATION.md | /gsd-verify-work | — | gsd-planner (--gaps) | Yes |

**Key design principles observed:**
- Every `.planning/` artifact is a prompt, not a document (PLAN.md IS the executor's prompt)
- Artifacts flow strictly forward: discuss → research → plan → execute → verify → transition
- Backward references (planner reading prior SUMMARYs) are selective, not reflexive
- All commits to `.planning/` use `gsd-sdk query commit` which checks `commit_docs` config

---

## 2. How does GSD wire its skills together?

GSD uses a thin orchestrator + subagent delegation pattern. The skill (slash command) is a lean orchestrator — it initializes context, spawns typed subagents, handles their output, and routes forward. Subagents do the heavy work.

**Full skill → artifact → next-skill chain:**

```
User types /gsd-new-project
  │
  ▼
[SKILL: gsd-new-project/SKILL.md]                ← user-facing, orchestrator
  │   Loads: /gsd-new-project workflow
  │   Calls: AskUserQuestion (collects idea/goals)
  │   Spawns: Task(gsd-project-researcher) → writes .planning/research/*.md
  │   Spawns: Task(gsd-roadmapper) → writes .planning/ROADMAP.md + STATE.md
  │   Commits: gsd-sdk query commit "docs: init project"
  │   Returns: "Run /gsd-plan-phase 1"
  ▼
User types /gsd-discuss-phase 1
  │
  ▼
[SKILL: gsd-discuss-phase/SKILL.md]              ← user-facing, Socratic orchestrator
  │   Loads: .planning/ROADMAP.md (phase goal)
  │   Interviews user (AskUserQuestion loops)
  │   Writes: .planning/phases/01-foundation/01-CONTEXT.md
  │   Commits: gsd-sdk query commit "docs(phase-01): document phase decisions"
  │   Returns: "Run /gsd-plan-phase 1"
  ▼
User types /gsd-plan-phase 1
  │
  ▼
[SKILL: gsd-plan-phase/SKILL.md]                 ← user-facing, orchestrator
  │   gsd-sdk query init.plan-phase "1" → JSON with model, paths, flags
  │   Optional: Spawns Task(gsd-phase-researcher) → writes 01-RESEARCH.md
  │   Spawns: Task(gsd-planner)
  │     └─ reads ROADMAP.md + CONTEXT.md + RESEARCH.md + codebase/
  │     └─ writes .planning/phases/01-foundation/01-01-PLAN.md (+ 01-02..N)
  │     └─ updates ROADMAP.md plan list
  │     └─ commits via gsd-sdk
  │     └─ returns "## PLANNING COMPLETE"
  │   Optional: Spawns Task(gsd-plan-checker) → validates PLAN.md
  │   Returns: wave structure + "Run /gsd-execute-phase 1"
  ▼
User types /gsd-execute-phase 1
  │
  ▼
[SKILL: gsd-execute-phase/SKILL.md]              ← user-facing, wave orchestrator
  │   gsd-sdk query init.execute-phase "1" → JSON with plans, waves, models
  │   For each wave (parallel):
  │     Spawns: Task(gsd-executor, prompt=PLAN.md content + context)
  │       └─ reads PLAN.md tasks
  │       └─ implements each task
  │       └─ git add <specific files> && git commit per task
  │       └─ writes 01-01-SUMMARY.md
  │       └─ gsd-sdk query state.advance-plan, state.update-progress
  │       └─ gsd-sdk query roadmap.update-plan-progress
  │       └─ gsd-sdk query requirements.mark-complete REQ-IDs
  │       └─ final commit: docs(01-01): complete plan
  │       └─ returns "## PLAN COMPLETE" or "## CHECKPOINT REACHED"
  │   After all waves:
  │     Spawns: Task(gsd-verifier) → verifies against ROADMAP.md success criteria
  │     If gaps: gsd-sdk query suggests /gsd-plan-phase 1 --gaps
  │   Returns: "Run /gsd-plan-phase 2" or "/gsd-transition"
  ▼
Repeat for each phase
```

**Key wiring mechanisms:**

1. **init context** — Every orchestrator calls `gsd-sdk query init.<workflow>` first. Returns JSON with model assignments, file paths, config flags. Single source of truth for session config.

2. **Typed subagent spawning** — `Task(subagent_type="gsd-executor", prompt="...")`. The subagent type name maps to a file in `~/.claude/agents/gsd-executor.md`. Agents auto-load their definition without the orchestrator reading it.

3. **Completion markers** — Each agent returns a structured header (`## PLAN COMPLETE`, `## PLANNING COMPLETE`, `## CHECKPOINT REACHED`) that the orchestrator parses to route.

4. **Forward arrow in SKILL.md** — Every skill's final output includes a "Next Steps" line pointing to the next skill. This is the user-facing version of the programmatic routing.

5. **Atomic commits as workflow gates** — Each plan produces N per-task commits + 1 docs commit. The docs commit (SUMMARY.md + STATE.md + ROADMAP.md) is the gate signal that execution of that plan is done.

---

## 3. GSD agent type registry shape

GSD agents are single markdown files in `~/.claude/agents/` with a naming convention of `gsd-{role}.md`. There is no separate registry file — the agents directory IS the registry.

**Naming convention:** `gsd-<role>.md` (all lowercase, hyphenated)

**Frontmatter fields used by GSD agents:**

```yaml
---
name: gsd-executor
description: "Executes GSD plans... Spawned by execute-phase orchestrator."
tools: Read, Write, Edit, Bash, Grep, Glob, mcp__context7__*
color: yellow
---
```

**Full registry (from live `~/.claude/agents/`):**

| Agent file | Role | Spawned by |
|------------|------|-----------|
| `gsd-executor.md` | Executes PLAN.md tasks, commits, creates SUMMARY.md | execute-phase orchestrator |
| `gsd-planner.md` | Creates PLAN.md files with goal-backward methodology | plan-phase orchestrator |
| `gsd-phase-researcher.md` | Phase-scoped technical research | plan-phase orchestrator (optional) |
| `gsd-project-researcher.md` | Project-wide domain research | new-project orchestrator |
| `gsd-roadmapper.md` | Creates/revises ROADMAP.md | new-project, new-milestone orchestrators |
| `gsd-verifier.md` | Post-execution verification vs ROADMAP success criteria | execute-phase orchestrator |
| `gsd-plan-checker.md` | Plan quality validation (revision gate) | plan-phase orchestrator |
| `gsd-codebase-mapper.md` | Maps project structure to .planning/codebase/ | /gsd-codebase-map skill |
| `gsd-debugger.md` | Root cause analysis + fix | /gsd-debug skill |
| `gsd-security-auditor.md` | STRIDE threat analysis | /gsd-secure-phase skill |
| `gsd-ui-researcher.md` | UI/UX spec research | /gsd-ui skill |
| `gsd-ui-checker.md` | UI quality validation | /gsd-verify-work (UI variant) |
| `gsd-ui-auditor.md` | UI implementation audit | execute-phase (UI phases) |
| `gsd-nyquist-auditor.md` | Verification coverage sampling | execute-phase orchestrator |
| `gsd-integration-checker.md` | Cross-phase integration validation | execute-phase orchestrator |
| `gsd-doc-writer.md` | Documentation generation | /gsd-docs-update skill |
| `gsd-research-synthesizer.md` | Combines multiple research outputs | new-project orchestrator |
| `gsd-assumptions-analyzer.md` | Surfaces hidden assumptions in plans | plan-phase orchestrator |
| `gsd-user-profiler.md` | User profile inference | new-project orchestrator |
| `gsd-intel-updater.md` | Codebase intelligence update | /gsd-analyze-dependencies |
| `gsd-code-fixer.md` | Automated code fixes | /gsd-audit-fix |
| `gsd-code-reviewer.md` | Code review | /gsd-code-review skill |
| `gsd-eval-planner.md` / `gsd-eval-auditor.md` | AI eval scaffolding | /gsd-ai-integration-phase |

**How orchestrators declare and consume agent types:**

```bash
# Orchestrator spawns by type name (maps to agents/gsd-executor.md):
Task(subagent_type="gsd-executor", prompt="...")

# Model resolved before spawn:
INIT=$(gsd-sdk query init.execute-phase "${PHASE}")
executor_model=$(echo "$INIT" | jq -r '.executor_model')
# gsd-sdk reads .planning/config.json model_profile → looks up gsd-executor row in profiles table
# Returns: "inherit" (for opus) or specific model ID
```

The `gsd-sdk` is the single model resolution layer — skills never hardcode model names, they get resolved at init time from the profile table.

---

## 4. Bridging v1.x pipeline with GSD phase/plan model

The v1.x pipeline (`/prd → /plan-stories → /execute → /ship`) and the GSD phase model (`discuss → research → plan → execute → verify → transition`) are structurally homologous. The mapping is straightforward.

**V1.x → V2 skill surface map:**

| V1.x skill | V2 surface | What changes |
|------------|-----------|--------------|
| `/prd` | Becomes `/gsd-discuss-phase N` (inline) OR a pre-phase `CONTEXT.md` | PRD content becomes Decisions (D-01..N) in phase CONTEXT.md. Structured Socratic interview replaces freeform PRD writing. The `.claude-pipeline/prds/` directory is superseded by `.planning/phases/NN-name/NN-CONTEXT.md`. |
| `/plan-stories` | Becomes `/gsd-plan-phase N` | `stories.json` is replaced by `NN-NN-PLAN.md` files with wave/dependency frontmatter. Plans are executable prompts, not data structures. |
| `/execute` | Becomes `/gsd-execute-phase N` | `@executor` + `@reviewer` per-story pattern is replaced by `gsd-executor` per-plan in waves. Quality gates move from skill instructions to PLAN.md `<verification>` + `<success_criteria>`. |
| `/ship` | Becomes final `/gsd-verify-work N` → `/gsd-transition` → `gh pr create` | Final quality gates, push, PR creation are post-verify steps. `/ship` logic folds into the execute-phase completion + transition workflow. |
| `/debug` | Becomes `/gsd-debug` | Wraps `gsd-debugger` agent. Shape is nearly identical — same isolation model. |
| `/tdd` | Folds into PLAN.md `type: tdd` + `tdd="true"` task attribute | TDD is not a separate skill; it's a plan type. The `gsd-executor` handles RED/GREEN/REFACTOR cycles natively. |
| `/refactor` | Folds into a refactor phase in the roadmap | `/refactor` becomes a named phase executed by `gsd-executor` with `type: refactor` tasks. |
| `/explore-repo` | Becomes `/gsd-codebase-map` (or inline via `gsd-codebase-mapper` agent) | Writes to `.planning/codebase/` instead of being an ad-hoc skill. |
| `/godmode` | Stays as `/godmode` (quick reference) | Updated to reflect v2 vocabulary: phases, plans, GSD-aligned commands. Lists public skills with next/prev arrows. |

**State storage migration:**

| V1.x location | V2 location | Migration path |
|---------------|-------------|----------------|
| `.claude-pipeline/stories.json` | `.planning/phases/NN-name/NN-NN-PLAN.md` | install.sh detects `.claude-pipeline/` and offers migration. Archived plans stay in `.claude-pipeline/archive/` (no deletion). |
| `.claude-pipeline/prds/prd-*.md` | `.planning/phases/NN-name/NN-CONTEXT.md` | User-initiated migration; PRD content converts to D-01..N decisions. |
| `.claude-pipeline/progress.txt` | `.planning/STATE.md` | STATE.md is richer (progress bar, metrics, session continuity). |

**Interop period:** During the v1.x → v2 transition, `session-start.sh` and `post-compact.sh` should detect both `.claude-pipeline/` and `.planning/` and inject whichever is present. This allows projects mid-flight on v1.x to finish without disruption before adopting the v2 shape.

---

## 5. New v2 components

Based on the gap analysis between v1.x and GSD parity, these are the new components needed:

**Required (no equivalent in v1.x):**

| Component | Where it lives | What it does |
|-----------|---------------|--------------|
| `gsd-sdk` equivalent or bypass | `install.sh` installs nothing; hooks call shell + jq | GSD's `gsd-sdk` handles: init context assembly, model resolution, state updates, plan validation, git commit routing. V2 can bypass the Node binary using shell + jq + existing bash primitives — see "No SDK" approach below. |
| `.planning/config.json` | `.planning/config.json` per consumer project | Per-project config: model profile, commit_docs, branching strategy. Read by `session-start.sh` hook. |
| Model profile system | `rules/godmode-routing.md` + agent frontmatter | Agent frontmatter declares `model:` field. A profile table in a shared rule maps role → model for each profile tier (quality/balanced/budget). Skills read the profile from `.planning/config.json`. |
| Phase CONTEXT.md writer | `skills/discuss/SKILL.md` (new skill) | `/discuss` — Socratic interview skill that produces phase CONTEXT.md. Replaces `/prd`. |
| Phase PLAN.md writer | `skills/plan-phase/SKILL.md` (replaces `plan-stories`) | Spawns `@planner` agent (new agent). Writes PLAN.md files with wave/dependency frontmatter. |
| `@planner` agent | `agents/planner.md` (new agent) | Specialization of current `/plan-stories` logic. Model: opus. Produces PLAN.md with goal-backward methodology and threat model. |
| `@verifier` agent | `agents/verifier.md` (new agent) | Post-execution verification. Checks SUMMARY.md against ROADMAP.md success criteria. Model: sonnet. |
| STATE.md lifecycle | `hooks/session-start.sh` + `hooks/post-compact.sh` + skills | session-start.sh reads `.planning/STATE.md` and injects Current Position into session context. post-compact.sh re-injects STATE.md summary on compaction. |
| Atomic commit enforcement | Agent instructions in all code-writing agents | Every code agent commits after each task with `type(phase-plan): description` format. Rule lives in `rules/godmode-git.md` (upgrade from current v1.x git rule). |

**"No SDK" approach (recommended per PROJECT.md constraints):**

GSD's `gsd-sdk` is a Node.js binary that handles 6 concerns. Each can be replicated in shell+jq:

| gsd-sdk concern | Shell+jq equivalent | File |
|----------------|---------------------|------|
| `init.execute-phase` | `jq` reads `.planning/config.json` + `ls .planning/phases/NN-name/` | `skills/_shared/init-context.md` (shared fragment) |
| `state.advance-plan` | `jq` mutation of STATE.md fields via sed/awk | `skills/_shared/state-ops.md` |
| `roadmap.update-plan-progress` | `sed` checkbox update in ROADMAP.md | Inline in agents |
| `requirements.mark-complete` | `sed` checkbox update in REQUIREMENTS.md | Inline in agents |
| Model resolution | Profile table in `rules/godmode-routing.md` | Agent reads profile from `.planning/config.json`, applies table |
| `commit` with gitignore check | Shell: `git check-ignore -q .planning/ || git add ... && git commit ...` | Shared fragment |

The tradeoff: more verbose agent instructions (they embed the shell logic), but zero runtime dependencies beyond bash + jq, which PROJECT.md mandates.

---

## 6. Data flow across a multi-agent session

**Numbered data flow for a complete session:**

```
1. SESSION START
   Claude Code fires SessionStart hook
   └─ hooks/session-start.sh reads:
       ├─ .planning/STATE.md (Current Position, Last session)
       ├─ .planning/config.json (model_profile, flags)
       ├─ git branch, recent commits
       └─ emits hookSpecificOutput.additionalContext JSON:
           {"project": "...", "currentPhase": "...", "currentPlan": "...", "modelProfile": "..."}

2. RULES LOADED (always-on)
   Claude Code loads rules/godmode-*.md into every session.
   These establish: identity, coding standards, quality gates, routing vocabulary,
   phase lifecycle, git discipline, context injection format.
   CACHE-FRIENDLINESS: Rules are static → they hit the 5-min prompt cache on every
   subsequent turn after first load. Structure them as leading stable content.

3. USER INVOKES SKILL
   User types /plan-phase 2
   └─ skills/plan-phase/SKILL.md loads (frontmatter: model, tools, isolation)
   └─ Orchestrator reads .planning/config.json (model_profile → resolve planner model)
   └─ Orchestrator reads .planning/ROADMAP.md phase 2 goal + req IDs
   └─ Orchestrator reads .planning/phases/02-name/02-CONTEXT.md (if exists)
   └─ Orchestrator reads .planning/phases/02-name/02-RESEARCH.md (if exists)
   └─ Orchestrator reads .planning/codebase/ARCHITECTURE.md + CONVENTIONS.md

4. SUBAGENT SPAWN
   Orchestrator calls Task(subagent_type="planner", prompt=assembled-context)
   └─ @planner receives: phase goal, req IDs, context decisions, codebase conventions
   └─ @planner writes: .planning/phases/02-name/02-01-PLAN.md
   └─ @planner writes: .planning/phases/02-name/02-02-PLAN.md (etc)
   └─ @planner updates: .planning/ROADMAP.md plan list
   └─ @planner commits: "docs(phase-02): create phase plans"
   └─ @planner returns: "## PLANNING COMPLETE" + wave structure

5. EXECUTION SPAWN (per wave, parallel)
   Orchestrator calls Task(subagent_type="executor", prompt=plan-content)
   └─ @executor reads: 02-01-PLAN.md tasks
   └─ @executor implements task 1 → git add specific files → git commit "feat(02-01): ..."
   └─ @executor implements task 2 → git commit "feat(02-01): ..."
   └─ @executor writes: .planning/phases/02-name/02-01-SUMMARY.md
   └─ @executor updates STATE.md (advance-plan, update-progress, record-metric)
   └─ @executor updates ROADMAP.md (plan checkbox)
   └─ @executor updates REQUIREMENTS.md (mark req IDs complete)
   └─ @executor commits: "docs(02-01): complete plan"
   └─ @executor returns: "## PLAN COMPLETE" + commit hashes

6. VERIFICATION
   Orchestrator calls Task(subagent_type="verifier")
   └─ @verifier reads: ROADMAP.md phase 2 success criteria
   └─ @verifier reads: 02-01-SUMMARY.md, 02-02-SUMMARY.md (frontmatter only)
   └─ @verifier checks: must_haves.truths observable, artifacts exist, key_links wired
   └─ @verifier writes: .planning/phases/02-name/02-VERIFICATION.md
   └─ @verifier returns: "## Verification Complete" PASS or gaps found

7. COMPACTION (long sessions)
   Claude Code fires PostCompact hook
   └─ hooks/post-compact.sh reads .planning/STATE.md
   └─ Emits: quality gates, skill list, current phase/plan, recent decisions
   Session continues with restored critical context.

8. TRANSITION
   Orchestrator updates PROJECT.md (Requirements: Active → Validated)
   Commits: "docs: complete phase 2 — foundation done"
   Suggests: /plan-phase 3
```

**Context propagation mechanisms:**

| Mechanism | What it carries | Scope |
|-----------|----------------|-------|
| Rules (always-on) | Identity, coding standards, quality gates, workflow vocabulary | Every turn of every session |
| SessionStart hook | Project name, current phase/plan, model profile, git state | Session open |
| PostCompact hook | Quality gates, skill list, current STATE.md position | After compaction |
| @-references in PLAN.md | Phase goal, codebase conventions, prior SUMMARY frontmatter | Subagent scope only |
| STATE.md | Accumulated decisions, blockers, session continuity | Persistent across sessions |
| ROADMAP.md | Phase structure, req IDs, success criteria | Cross-phase |

---

## 7. Component boundaries

**Decision rule:** "If the user would type it, it's a skill. If only agents call it, it's an agent. If it runs on an event, it's a hook. If it shapes every response, it's a rule. If it controls access, it's a permission."

```
┌─────────────────────────────────────────────────────────────────────────┐
│  USER SURFACE (skills + commands)                                        │
│                                                                          │
│  /godmode  /discuss  /plan-phase  /execute-phase  /ship                 │
│  /debug    /tdd      /explore-repo  /refactor  /secure-phase             │
│                                                                          │
│  Rule: ≤ 12 total. Each must declare goal + connects-to arrows.          │
└─────────────────────────────────────────────────────────────────────────┘
                          │ spawns via Task()
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  INTERNAL AGENTS (not user-invocable)                                    │
│                                                                          │
│  @planner     @executor    @verifier    @architect   @security-auditor  │
│  @researcher  @reviewer    @writer      @doc-writer  @test-writer        │
│                                                                          │
│  Rule: hidden from /godmode listing. Invoked only by orchestrator skills │
└─────────────────────────────────────────────────────────────────────────┘
                          │ read/write
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  PLANNING ARTIFACTS (.planning/)                                          │
│                                                                          │
│  PROJECT.md  REQUIREMENTS.md  ROADMAP.md  STATE.md  config.json         │
│  phases/NN-name/{PLAN,SUMMARY,CONTEXT,RESEARCH,VERIFICATION}.md          │
│                                                                          │
│  Rule: all updates committed atomically via git                          │
└─────────────────────────────────────────────────────────────────────────┘
                          │ event-driven
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  HOOKS (event handlers)                                                  │
│                                                                          │
│  session-start.sh    → injects project context + current STATE position │
│  post-compact.sh     → re-injects quality gates + STATE after compaction │
│                                                                          │
│  Rule: output valid JSON always. No side effects (read-only shell execs) │
└─────────────────────────────────────────────────────────────────────────┘
                          │ always-on
                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  RULES (always-on context)                                               │
│                                                                          │
│  godmode-identity.md     → who Claude is in this plugin               │
│  godmode-workflow.md     → phase lifecycle, vocabulary alignment       │
│  godmode-coding.md       → coding standards                           │
│  godmode-git.md          → atomic commit discipline, PR discipline     │
│  godmode-quality.md      → quality gates (typecheck/lint/tests/etc.)  │
│  godmode-testing.md      → test strategy                              │
│  godmode-routing.md      → model profile table, agent routing         │
│  godmode-context.md      → .planning/ shape, STATE.md format          │
│                                                                          │
│  Rule: one concern per file. Static. Cache-friendly (lead with rules).   │
└─────────────────────────────────────────────────────────────────────────┘
```

**Belongs as skill (user-facing):** Anything the user initiates that starts a workflow phase. Has a named goal. Has upstream and downstream arrows. Example: `/plan-phase` (upstream: `/discuss`, downstream: `/execute-phase`).

**Belongs as internal agent:** Anything that does expensive specialized work as a subagent. Has a single job. Returns a completion marker. Never has a `/` command. Example: `@planner` (spawned by `/plan-phase`, writes PLAN.md).

**Belongs as hook:** Anything event-driven. Fires without user action. Must be idempotent. Must emit valid JSON. Must be fast (<10s). Example: `session-start.sh`.

**Belongs as rule:** Anything that should shape every Claude response in every session, not just workflow sessions. Static. Short. Declarative. Example: `godmode-git.md` ("always commit with --no-verify false").

**Belongs as permission:** Anything that allows or denies tool access. Lives in `settings.json`. Example: allowing `Bash` with `git push`.

---

## 8. Prompt caching strategy

Claude Code's prompt cache has a 5-minute TTL on the first cache-eligible prefix. Rules and agent system prompts are the highest-value targets.

**Cache hit opportunities:**

| Component | Cache strategy | Rationale |
|-----------|---------------|-----------|
| `rules/godmode-*.md` | Lead every conversation (placed first in context). Static content. Never vary between turns. | Rules are always-on. They appear at position 0 of every session. Cache hit on turn 2+. |
| Agent system prompts (`agents/*.md` body) | Structure as: stable preamble → stable process → variable context injection at end | First N tokens of every agent spawn are identical if the process description is static. Variable context (phase, plan paths) appended last. |
| Session-start hook output | Keep `additionalContext` structure stable. Only vary field values, not field structure. | Claude Code's parser sees same JSON schema every session → cache-eligible prefix is the schema. |
| Shared skill fragments (`skills/_shared/*.md`) | Maximize reuse. Same fragment referenced by multiple skills = repeated token sequence = cache hit when Claude reads it inline. | Fragment content is identical across skill invocations. |
| PLAN.md `<execution_context>` block | Point to stable @-references (workflow files, templates). These are always the same. | Agent reads same execution context on every plan → cache hit. |

**Cache-hostile patterns to avoid:**

| Anti-pattern | Why it hurts | Fix |
|-------------|-------------|-----|
| Embedding session-specific data (date, branch name) in rules | Rules are cache-eligible only if static. Timestamps break every cache. | Move dynamic data to hook output (additionalContext), not rules. |
| Varying agent system prompt preamble by plan | Cache requires identical prefix. Different preamble = zero hits. | Keep role + process description in agent file. Pass plan-specific data via prompt argument. |
| Long conversation context before stable content | Cache prefix must start from position 0. Inserting dynamic content early pushes rules down past the cache checkpoint. | hooks → rules → dynamic context. Never reorder. |
| Per-invocation agent instructions embedded inline in PLAN.md | PLAN.md is per-plan. Agents reading inline instructions = new token sequence = no cache hit. | Agent core instructions live in agents/*.md. PLAN.md passes only task data. |

**Recommended agent system prompt structure (cache-maximizing):**

```
[STATIC: Role declaration — identical every spawn]
[STATIC: Core responsibilities — identical every spawn]
[STATIC: Process steps — identical every spawn]
[STATIC: Output format — identical every spawn]
[DYNAMIC: Plan-specific context — injected last by orchestrator]
```

The static prefix (lines 1–N) hits cache on every re-spawn of the same agent type.

---

## 9. Suggested build order

Dependencies flow through the layers: rules must exist before hooks reference them, agents must exist before skills spawn them, the `.planning/` shape must be stable before any workflow writes to it.

**Build order (dependency-safe, independently shippable):**

```
Phase 1: Foundation layer (enables everything else)
  ├─ rules/godmode-workflow.md ── update with v2 vocabulary (phases, plans, GSD lifecycle)
  ├─ rules/godmode-git.md      ── add atomic commit discipline
  ├─ rules/godmode-routing.md  ── add model profile table (quality/balanced/budget)
  ├─ rules/godmode-context.md  ── add .planning/ shape description
  └─ hooks/session-start.sh    ── add STATE.md reader, inject currentPhase/currentPlan

Phase 2: Agent layer (new specialized agents)
  ├─ agents/planner.md     ── new: goal-backward PLAN.md writer (replaces plan-stories logic)
  ├─ agents/verifier.md    ── new: post-execution verification vs success criteria
  ├─ agents/executor.md    ── upgrade: atomic commit discipline, SUMMARY.md writer, STATE.md updater
  ├─ agents/architect.md   ── upgrade: CONTEXT.md writer for discuss phase
  └─ agents/*.md (others)  ── upgrade: add "Connects to:" forward/back arrows, model assignments

Phase 3: Skill layer (user-facing workflow)
  ├─ skills/discuss/SKILL.md          ── new: Socratic interview → CONTEXT.md (replaces /prd)
  ├─ skills/plan-phase/SKILL.md       ── new: spawns @planner, wave structure (replaces /plan-stories)
  ├─ skills/execute-phase/SKILL.md    ── new: wave orchestrator, spawns @executor in parallel (replaces /execute)
  ├─ skills/ship/SKILL.md             ── upgrade: post-verify + PR creation (simplified)
  ├─ skills/debug/SKILL.md            ── upgrade: wraps @debugger with GSD-style completion markers
  ├─ skills/tdd/SKILL.md              ── deprecate: fold into PLAN.md type:tdd (or keep as thin wrapper)
  ├─ skills/refactor/SKILL.md         ── upgrade: becomes a phase-scoped refactor orchestrator
  └─ commands/godmode.md              ── upgrade: v2 vocabulary, public agent list, next/back arrows

Phase 4: State management layer
  ├─ hooks/post-compact.sh            ── upgrade: read STATE.md, inject phase/plan position
  ├─ skills/_shared/state-ops.md      ── new: shell+jq STATE.md update fragments
  ├─ skills/_shared/init-context.md   ── new: config.json reader + model resolution fragment
  └─ skills/_shared/commit-ops.md     ── new: gitignore-aware planning commit fragment

Phase 5: .planning/ initialization
  ├─ skills/init-project/SKILL.md     ── new (or `/godmode` flow): writes .planning/ scaffold
  │                                      PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, config.json
  └─ install.sh                        ── upgrade: detect v1.x .claude-pipeline/, offer migration

Phase 6: Quality + CI
  ├─ Upgrade: hooks emit valid JSON under adversarial inputs (escaping fixes)
  ├─ Add: CI shellcheck, JSON schema validation, frontmatter lint
  ├─ Add: smoke test: install → /godmode → /discuss → /plan-phase → /execute-phase → uninstall
  └─ Fix: version drift (plugin.json canonical, install.sh + godmode.md read from it)
```

**Dependency arrows:**

```
Phase 1 (rules + hooks) → must ship first (everything reads rules)
Phase 2 (agents) → depends on Phase 1 rules (agents follow rule conventions)
Phase 3 (skills) → depends on Phase 2 (skills spawn agents)
Phase 4 (state mgmt) → depends on Phase 3 (state updated by skills/agents)
Phase 5 (.planning/ init) → depends on Phase 4 (init creates STATE.md)
Phase 6 (CI) → depends on Phase 5 (tests need full stack)
```

Each phase boundary is independently shippable: after Phase 1, rules are v2-grade and hooks are improved. After Phase 2, agents are production-ready. After Phase 3, the full user workflow is functional. Phases 4–6 are hardening passes.

---

## V1.x → V2 Full Migration Map

**What changes shape:**

| V1.x component | V2 shape | Migration |
|---------------|----------|-----------|
| `.claude-pipeline/stories.json` | `.planning/phases/NN-name/NN-NN-PLAN.md` | Detect on session-start, offer migration |
| `.claude-pipeline/prds/` | `.planning/phases/NN-name/NN-CONTEXT.md` | Manual conversion; old PRDs archived not deleted |
| `skills/prd/SKILL.md` | `skills/discuss/SKILL.md` | New skill, old skill retired |
| `skills/plan-stories/SKILL.md` | `skills/plan-phase/SKILL.md` | New skill, old skill retired |
| `skills/execute/SKILL.md` | `skills/execute-phase/SKILL.md` | New orchestrator pattern (wave-based) |
| `skills/tdd/SKILL.md` | Absorbed into PLAN.md `type:tdd` | Skill deprecated or kept as thin alias |
| Agent invocation: inline in skill | Agent invocation: `Task(subagent_type="agent-name")` | All skills updated to typed spawning |
| Per-story quality gates (in skill) | Per-task verification (in PLAN.md `<verification>`) | Quality gate logic moves to planner output |
| Agent model: hardcoded `model: opus` | Agent model: `model:` resolved from profile table | `rules/godmode-routing.md` + `config.json` |

**What survives unchanged:**

- `rules/godmode-coding.md`, `rules/godmode-testing.md` — coding and testing rules are stable
- `agents/architect.md`, `agents/security-auditor.md`, `agents/writer.md` — roles stay, only model assignments + forward arrows added
- `hooks/` basic structure — SessionStart + PostCompact event bindings unchanged
- `config/statusline.sh` — no changes needed
- `install.sh` plugin/manual mode detection — preserved; migration logic added
- `.claude-plugin/plugin.json` — version becomes single source of truth

**New files (don't exist in v1.x):**

```
agents/planner.md              ← new role
agents/verifier.md             ← new role
skills/discuss/SKILL.md        ← new skill
skills/plan-phase/SKILL.md     ← replaces plan-stories
skills/execute-phase/SKILL.md  ← replaces execute (wave orchestrator)
skills/init-project/SKILL.md   ← new skill (optional, or absorbed into /godmode)
skills/_shared/state-ops.md    ← new fragment
skills/_shared/init-context.md ← new fragment
skills/_shared/commit-ops.md   ← new fragment
```

---

## Anti-Patterns

### Anti-Pattern 1: Orchestrator that executes

**What people do:** Skills directly implement work (write files, run git) instead of delegating to typed agents.

**Why it's wrong:** Skill context fills up fast. Parallel execution is impossible. Model choice is inflexible (skill model = task model). Resumability after compaction is lost.

**Do this instead:** Skills are lean coordinators (< 30% context budget for orchestration). Execution goes to typed agents via `Task(subagent_type=...)`.

### Anti-Pattern 2: Monolithic PLAN.md

**What people do:** One big plan with 10+ tasks covering the entire phase.

**Why it's wrong:** Context degrades past 50% — later tasks get rushed, incomplete. Parallelism is zero (all sequential). Recovery after failure means re-running the whole plan.

**Do this instead:** 2-3 tasks per plan. Decompose into waves. Each plan is independently committable.

### Anti-Pattern 3: Dynamic content in rules

**What people do:** Embedding current branch, date, or project name in `rules/godmode-*.md`.

**Why it's wrong:** Rules must be static to be cache-eligible. Dynamic content burns cache on every turn.

**Do this instead:** Rules contain only stable behavior definitions. Dynamic project state lives in hook output (`additionalContext`), not rules.

### Anti-Pattern 4: Implicit skill ordering

**What people do:** Skills exist with no stated connections. Users guess the order.

**Why it's wrong:** Users assembling parts ≠ one clear workflow. This is the core failure mode PROJECT.md is trying to fix.

**Do this instead:** Every skill declares `Connects to: upstream ← this → downstream`. `/godmode` lists every public skill with its forward arrow.

### Anti-Pattern 5: Version drift

**What people do:** `plugin.json`, `install.sh`, and `commands/godmode.md` each maintain a separate version string.

**Why it's wrong:** They drift. Any release process that touches fewer than all three creates a mismatch.

**Do this instead:** `plugin.json` is the canonical version. `install.sh` reads it with `jq`. `commands/godmode.md` reads it via hook or install-time template substitution.

---

## Integration Points

### Internal component boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Skill → Agent | `Task(subagent_type, prompt)` | Prompt contains assembled context + plan content; agent loads own instructions from agents/*.md |
| Agent → .planning/ | `Write` / `Edit` tools | Agents write PLAN.md, SUMMARY.md, STATE.md, ROADMAP.md. Never use Bash heredoc writes. |
| Hook → Session | `hookSpecificOutput.additionalContext` JSON | Strict protocol. Malformed JSON causes silent failure. Must escape all shell-special chars in values. |
| Rules → Session | Always-on context injection (Claude Code loads) | No explicit handshake. Rules are passive. |
| Skill → Config | Shell reads `.planning/config.json` via jq | Skill reads model_profile, branching_strategy before spawning. |

### External integration points

| External system | Integration pattern | Notes |
|----------------|---------------------|-------|
| Claude Code plugin registry | `.claude-plugin/plugin.json` | Version, description, keywords. Plugin mode vs manual mode. |
| git | Atomic commits per task + docs commit per plan | Hooks must not call git in a way that bypasses pre-commit hooks. |
| gh CLI | `/ship` skill calls `gh pr create` | Permission in settings.json. User must be authenticated. |
| MCP servers (Context7, etc.) | Declared in agent `tools:` frontmatter as `mcp__context7__*` | Not bundled. User configures. |

---

## Sources

- Live GSD plugin files: `~/.claude/agents/gsd-executor.md`, `gsd-planner.md` (confidence: HIGH — primary source)
- Live GSD workflow: `~/.claude/get-shit-done/workflows/execute-phase.md` (confidence: HIGH)
- GSD templates: `~/.claude/get-shit-done/templates/state.md`, `roadmap.md`, `project.md` (confidence: HIGH)
- GSD references: `model-profiles.md`, `agent-contracts.md`, `context-budget.md`, `gates.md`, `git-planning-commit.md`, `planning-config.md` (confidence: HIGH)
- V1.x codebase analysis: `.planning/codebase/ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md` (confidence: HIGH)
- V2 goals and constraints: `.planning/PROJECT.md` (confidence: HIGH)

---

*Architecture research for: claude-godmode v2 — GSD-aligned plugin architecture*
*Researched: 2026-04-25*
