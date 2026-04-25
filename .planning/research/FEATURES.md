# Feature Research

**Domain:** Claude Code plugin (multi-agent engineering workflow orchestrator)
**Researched:** 2026-04-25
**Confidence:** HIGH for v1.x baseline (read directly from this repo); HIGH for GSD (read directly from `~/.claude/get-shit-done/`); MEDIUM for Superpowers and everything-claude-code (READMEs and STACK.md cross-references)

> **Note on the source.** This document was written inline by the orchestrator after the parallel `gsd-project-researcher` agent for the Features dimension hit a stream-idle timeout (`a04447108062a55f3`, 47 tool uses, 641 s). The orchestrator running this is itself executing inside the GSD plugin (v1.38.3 at `~/.claude/get-shit-done/`), so GSD's surface is enumerated from the live install rather than from documentation. Findings from the other three completed researchers (STACK.md, ARCHITECTURE.md, PITFALLS.md) are cross-referenced where relevant.

---

## Reference plugins enumerated

### claude-godmode v1.x (this repo, baseline)

8 user-facing slash commands. 8 specialized subagents. 2 hooks + 1 statusline.

| Slash command | Skill file | Purpose |
|---|---|---|
| `/godmode` | `commands/godmode.md` | Quick reference + statusline setup. The "menu" of the plugin. |
| `/prd` | `skills/prd/SKILL.md` | Generate Product Requirements Document. |
| `/plan-stories` | `skills/plan-stories/SKILL.md` | Convert PRD → executable `.claude-pipeline/stories.json`. |
| `/execute` | `skills/execute/SKILL.md` | Run executor + reviewer per story. Sequential or parallel via `dependsOn`. |
| `/ship` | `skills/ship/SKILL.md` | Quality gates, push, create PR. |
| `/debug` | `skills/debug/SKILL.md` | Structured Reproduce → Hypothesize → Isolate → Fix loop. |
| `/tdd` | `skills/tdd/SKILL.md` | Red-green-refactor cycle. |
| `/refactor` | `skills/refactor/SKILL.md` | Safe refactoring with test verification. |
| `/explore-repo` | `skills/explore-repo/SKILL.md` | Deep codebase exploration. |

Subagents: `@writer` (opus, isolation=worktree, maxTurns 100), `@executor` (opus, worktree, 100, stories.json-aware), `@architect` (opus, read-only, effort high), `@security-auditor` (opus, read-only, effort high, +WebSearch), `@reviewer` (sonnet, read-only, effort high), `@test-writer` (sonnet, worktree, 80), `@doc-writer` (sonnet, +Bash), `@researcher` (sonnet, background, read-only).

### GSD v1.38.3 (primary structural reference)

GSD ships **80+ user-facing slash commands** (every `gsd-*` directory in `~/.claude/skills/`) and **33 specialized subagent types** (every `gsd-*.md` in `~/.claude/agents/`). It is intentionally a kit. claude-godmode v2 must NOT mirror that surface — the explicit constraint from PROJECT.md is ≤ 12 user-facing skills.

The patterns worth adopting from GSD (verified by reading the live install):

1. **Project artifact pipeline.** `.planning/` directory: `PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `MILESTONES.md`, plus subdirs `phases/`, `codebase/`, `research/`, `intel/`, `seeds/`. Strict ownership per file. Every workflow step adds or mutates exactly one artifact, then commits.
2. **Project → Milestone → Phase → Plan → Task hierarchy.** Project is long-lived; milestones are versioned slices (v1, v1.1, v2…); phases break a milestone into 5-8 numbered units; plans break a phase into atomic, parallelizable tasks; tasks are the commit-grain unit.
3. **Init-context system.** Before each workflow runs, `gsd-sdk query init.<workflow>` returns a single JSON blob with model assignments, file paths, config flags, agent availability — read once, parsed once, used everywhere. Eliminates ad-hoc state queries.
4. **Discuss → Plan → Execute → Verify lifecycle.** Each phase walks this loop. Discuss is Socratic context-gathering. Plan is goal-backward task decomposition. Execute is wave-based with atomic commits. Verify checks the goal was achieved (not just that tasks completed).
5. **Goal-backward verification.** `gsd-verifier` reads the phase goal, looks at the codebase, and reports COVERED / PARTIAL / MISSING per success criterion. Distinct from "tests pass."
6. **Atomic commits per gate.** Every artifact change commits immediately. Phase plans commit. Phase results commit. Roadmap updates commit. Context loss is recoverable from git alone.
7. **Codebase mapping (this is what we just used).** `gsd-codebase-mapper` writes 7 documents capturing existing system shape — feeds into project setup and per-phase research.
8. **Parallel agent orchestration.** `Task(run_in_background=true)` + `TaskOutput` (or output file polling — see PITFALLS.md #3) for fan-out/fan-in. Multiple researchers, multiple executors, single synthesizer.
9. **Model profile.** A single `model_profile` config key (`quality` / `balanced` / `budget` / `inherit`) flips the whole agent tree. Per-agent overrides exist but are rare.
10. **Workflow gates as user preferences.** `workflow.research`, `workflow.plan_check`, `workflow.verifier`, `workflow.nyquist_validation` — each toggleable, each a real subagent that runs.
11. **`/gsd-progress`, `/gsd-next`, `/gsd-resume-work`.** Three orthogonal commands that answer "where am I, what's next, pick up where I left off." Powerful in long sessions and across context resets.

### Superpowers (Anthropic's productivity plugin, MEDIUM confidence)

Cross-referenced from STACK.md key finding 6. Two patterns worth adopting:

1. **`isolation: worktree` per parallel executor agent.** v1.x already does this on `@executor` and `@writer`. Confirms the pattern. v2 should keep and extend (any code-writing parallel agent runs in its own worktree).
2. **Two-stage review: spec compliance first, then code quality.** v1.x has a single `@reviewer`; v2 should consider splitting "did this match the spec?" from "is this clean code?" Each stage gates on different criteria.

### everything-claude-code (community awesome-list, MEDIUM confidence)

Cross-referenced from STACK.md key finding 7. Two patterns worth adopting:

1. **`Stop` hook pattern extraction.** A hook that runs on session end to extract decisions, lessons, and patterns into persistent storage. Adapt the pattern (not the SQLite implementation) into a markdown-based session report.
2. **`PreToolUse` secret detection.** A hook that scans tool input for hardcoded secrets before the tool runs. Adapt the pattern as a pure-Bash regex matcher; CONCERNS.md item 4 already flags secret-detection as a v2 polish item.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features any 2026-grade Claude Code plugin must ship. Missing these = the plugin feels broken.

| Feature | Why Expected | Complexity | Notes |
|---|---|---|---|
| **Plugin manifest with name/version/description** | Plugin registry + plugin loader require it | LOW | ✓ existing (`.claude-plugin/plugin.json`); needs version unification — see CONCERNS #10 |
| **Installable via plugin mode AND manual mode** | User choice; some users avoid plugin registries | MEDIUM | ✓ existing (`install.sh` MODE detection); divergence is a v2 cleanup item — see PITFALLS #1 |
| **SessionStart context injection** | Context-aware help is the bare minimum 2026 expectation | LOW | ✓ existing (`hooks/session-start.sh`); needs JSON-safe interpolation — CONCERNS #6 |
| **PostCompact context recovery** | Long sessions are routine; without recovery the workflow breaks | LOW | ✓ existing (`hooks/post-compact.sh`); same JSON-safety fix needed |
| **Statusline with model + context%** | Every modern plugin has one; users expect to see token usage | LOW | ✓ existing (`config/statusline.sh`); single-jq pass is a perf polish item |
| **Permissions allow/deny lists** | Security baseline; reduces permission prompts | LOW | ✓ existing (`config/settings.template.json`); deny-pattern fragility is documented |
| **A canonical workflow** (PRD → plan → execute → ship style) | The reason users adopt these plugins | HIGH | ✓ existing (`/prd → /plan-stories → /execute → /ship`); v2 must align it with phase-shaped GSD pattern |
| **Specialized subagents** (architect, executor, reviewer, etc.) | Differentiates a plugin from a single-prompt CLAUDE.md | MEDIUM | ✓ existing (8 agents); v2 must add `effort`, `memory`, refresh model assignments to current lineup |
| **Quality gates** (typecheck/lint/test/no-secrets) before commit | Industry standard; nobody ships without them | LOW | ✓ existing (rules + skills); v2 should also enforce via PreToolUse hook (mechanical, not just instructional) |
| **Atomic commits per gate** | Git history must be navigable; partial work shouldn't leak | MEDIUM | ⚠ partial — v1.x commits per story, but doesn't commit planning artifacts atomically |
| **Goal-backward verification after execution** | "Tests pass" ≠ "goal achieved"; users want the latter | MEDIUM | ✗ missing — `@reviewer` checks code quality, but no agent reads the goal and verifies coverage |
| **Codebase mapping for brownfield projects** | Onboarding to existing repos is a top use case | MEDIUM | ✗ missing in v1.x; ✓ available via GSD's `/gsd-map-codebase` (we just used it) |
| **A `/help`-style menu** that lists every public skill and agent with goal | Discoverability; users forget what's available | LOW | ✓ existing (`/godmode` Quick Reference); v2 must add per-skill "Connects to:" lines |
| **Uninstaller that cleanly reverses install** | Trust signal; without it, users hesitate to install | LOW | ✓ existing (`uninstall.sh`); needs version-mismatch detection — CONCERNS #4 |

### Differentiators (Competitive Advantage)

This is where v2 wins. None of GSD/Superpowers/everything-claude-code does ALL of these in one simple plugin.

| Feature | Value Proposition | Complexity | Notes |
|---|---|---|---|
| **One canonical workflow with explicit "Connects to:" between every component** | Eliminates the "kit feeling" GSD has at 80 commands. Every skill/agent declares its upstream and downstream link. Users never have to ask "what next?" | MEDIUM | New to v2. Implemented in skill frontmatter + `/godmode` menu. Single source of truth for workflow shape. |
| **≤ 12 user-facing slash commands** (vs. GSD's 80+) | Cognitive load is the #1 reason workflow plugins get abandoned. v2 hides orchestrators and helpers as internal subagents. | MEDIUM | Constraint, not a build. Enforced at every phase via "command count ≤ 12 check" (PITFALLS implication). |
| **First-run UX: install → `/godmode` answers "what now?" within 5 lines** | Most plugins fail at first contact. v2 makes the next step obvious immediately. | LOW | New to v2. `/godmode` already exists; expand its output for new installs. |
| **Hidden internal agent layer** (orchestrators, mappers, classifiers, synthesizers, verifiers) | Best-of-both: rich agent orchestration without surface-area bloat. Internal agents are spawned by skills, never by users. | MEDIUM | New to v2. Architecture pattern from GSD (gsd-roadmapper, gsd-doc-classifier, etc.) without exposing them as commands. |
| **Prompt-cache-aware rule structure** | 96-103K tokens of cached state survive PostCompact (PITFALLS #2). Volatile content stays out of `additionalContext`. | LOW-MEDIUM | New to v2. Rules `godmode-*.md` get reordered: static preamble first, dynamic context appended last (or moved to statusline). |
| **Mechanical quality-gate enforcement via PreToolUse hook** | Instructions are ignorable (PITFALLS #4 — Opus 4.7 xhigh has been observed to skip rule text). A hook that blocks `git commit --no-verify` is not. | MEDIUM | New to v2. `hooks/pre-tool-use.sh` matches against `Bash(git commit --no-verify*)` and similar. |
| **Auto Mode awareness** | Auto Mode is the new default for many users. v2 skills detect it and adjust prompts (skip approval gates, surface course-corrections proactively). | MEDIUM | New to v2. Each skill checks `Auto Mode Active` system reminder and routes accordingly. |
| **Single source of truth for plugin version** | `plugin.json` is canonical; everything reads from it. Eliminates 1.6.0 / 1.4.1 / 1.4.1 drift. | LOW | New to v2. CONCERNS #10. |
| **Agent frontmatter declares model + effort + isolation + memory + connects-to** | Every agent's purpose, dependencies, and resource shape are introspectable from a single file. | LOW | New to v2. Standardized frontmatter audit pass. STACK.md key finding 2 — 8 new fields available. |
| **Two-stage review (spec compliance + code quality)** | Catches the failure mode where code looks great but doesn't match the spec. | MEDIUM | New to v2 (Superpowers pattern). Splits `@reviewer` into `@spec-reviewer` (read-only, checks against PLAN.md / requirements) + `@code-reviewer` (read-only, checks quality). |
| **`memory: project` on persistent agents** | Researcher and executor learnings persist across sessions (v2.1.33+ feature; STACK.md key finding 2). Patterns accumulate; mistakes don't repeat. | LOW | New to v2. Frontmatter change. |
| **Internal agent registry surfaced in one `/godmode` command** | Every public skill, every internal agent, with goal and connections. Documentation that can't go stale because it IS the menu. | LOW-MEDIUM | New to v2. `/godmode` reads the live filesystem and renders the menu. |
| **Native MCP integration documentation** (Context7, Playwright, Chrome DevTools) | Plugin advertises which MCP servers complement it; doesn't bundle them. | LOW | New to v2. README + `/godmode` mentions discoverable integrations. |
| **`isolation: worktree` for every parallel code-writing agent** | Eliminates merge conflicts on parallel `/execute`. Already done for `@executor` and `@writer`; extend to any future parallel writer. | LOW | Existing convention; codify as a frontmatter requirement. |
| **CI green on macOS + Linux for install/uninstall round-trip** | Trust signal; catches Bash 3.2 vs 5.x divergence and macOS-specific bugs. | MEDIUM | New to v2. STACK.md proposes shellcheck + bats-core + GitHub Actions. |

### Anti-Features (Commonly Requested, Often Problematic)

Things that look good but make the plugin worse. Documented to prevent re-introduction during v2.

| Feature | Why Requested | Why Problematic | Alternative |
|---|---|---|---|
| **Mirror GSD's 80-command surface** | "Feature parity with the reference" | Cognitive load destroys adoption. Users in 2026 have plugin fatigue; ≤ 12 wins. | Hide orchestrators. Compose, don't list. |
| **Vendored copies of GSD / Superpowers / everything-claude-code** | "Self-contained install" | License complications, maintenance burden, dependency inversion (we'd be shipping their bugs). | Reference patterns; never copy code. |
| **Bundled MCP server (e.g., a custom claude-godmode MCP)** | "Single install gets everything" | Pollutes plugin shape; creates a node/python runtime dep; couples release cadence with MCP changes. | Document MCP integrations; users install separately. |
| **A graphical UI / dashboard** | "Visualize the workflow" | Surface is the terminal. Statusline is the visual primitive. | Better statusline; well-formatted markdown in skill output. |
| **Cloud sync of `.planning/` state** | "Multi-device continuity" | Not a plugin's job. Users have git for this. | Document the git workflow; don't add a service. |
| **Telemetry / analytics** | "Improve the product" | Trust killer. v1.x's MIT, no-network promise is itself a differentiator. | Voluntary feedback via GitHub. |
| **Per-language scaffolding** (Next.js starters, Rails templates, etc.) | "Make new projects easier" | Domain creep. v2 shapes how Claude works, not what users build. | External cookiecutter / generators; v2 stays domain-agnostic. |
| **Hardcoded skill/agent lists in hooks** | "Faster than scanning the filesystem" | Drift between hook output and reality (CONCERNS #8). | Generate the list at hook-execution time from the live filesystem. |
| **`set -e` workarounds in hooks** (e.g., `\|\| true` everywhere) | "Don't break the session if anything fails" | Silently swallows real bugs. statusline already does this; PITFALLS expansion in v2 must NOT spread it. | Targeted handling for specific known-safe failures (e.g., `cat > /dev/null \|\| true` for stdin drain); fail loud elsewhere with debug logging. |
| **Auto-installing required tools** (e.g., `brew install jq`) | "Friction-free install" | Privilege escalation, package-manager assumptions, breaks reproducibility. v1.x already does the right thing: preflight check, error out clearly. | Document jq as a prereq; preflight check stays. |
| **A `/everything` mega-command that does the whole pipeline** | "One command to rule them all" | Hides the workflow shape; defeats the goal of "every component connected and goal-stated." | Keep the workflow visible. `/godmode` shows the chain. |
| **Backwards-compat shims for v1.x slash command names beyond migration** | "Don't break existing users" | Permanent technical debt. PROJECT.md Out-of-Scope already excludes this beyond the one-time migration. | Migration in `install.sh`; v2 is the canonical surface. |
| **Pre-defined `dependsOn` graphs in stories.json** | "Smarter parallel execution out of the box" | Premature optimization; users' graphs differ. v1.x already supports this when users supply it. | Optional. Users opt in by adding `dependsOn`. |
| **Auto-prompt-engineering of user requests** (rewriting their prompts before execution) | "Make Claude smarter at understanding intent" | Silent intent mutation; users lose trust when they get something different from what they asked. | Explicit `/discuss` step; visible to the user. |

---

## Feature Dependencies

```
Plugin manifest + version unification
    └──prereq──> Single source of truth for everything else
                       └──prereq──> install.sh, /godmode menu, plugin registry

Quality gates (instructional, in rules)
    └──hardened by──> PreToolUse hook (mechanical enforcement)
                       └──depends on──> Hook fragility fixes (JSON safety)

Codebase mapping
    └──prereq──> Brownfield project initialization
                       └──prereq──> PROJECT.md inferring "Validated" requirements

PROJECT.md / REQUIREMENTS.md / ROADMAP.md / STATE.md
    └──prereq──> Phase lifecycle (discuss → spec → plan → execute → verify → secure → ship)
                       └──prereq──> Goal-backward verification

Hidden internal agents
    └──prereq──> ≤ 12 surface constraint
                       └──prereq──> /godmode menu listing only public skills

Prompt-cache-aware rules
    └──prereq──> Static preamble + dynamic-content separation
                       └──prereq──> Volatile content moved out of additionalContext

Two-stage review (spec + code)
    └──supersedes──> Single @reviewer
                       └──depends on──> Spec artifact existing (PLAN.md or SPEC.md)

`memory: project` on persistent agents
    └──requires──> Claude Code v2.1.33+
                       └──documented in──> README "min Claude Code version"

CI (shellcheck + bats + smoke test)
    └──independent of──> Other phases
                       └──unblocks──> "no automated test suite" concern (TESTING.md)

Auto Mode awareness in skills
    └──independent of──> Other phases
                       └──depends on──> Reliable detection of Auto Mode Active reminder
```

### Dependency Notes

- **Version unification** (CONCERNS #10) blocks several other items because installer, `/godmode`, README, and CHANGELOG all need to read from the canonical source.
- **Hook JSON-safety** (CONCERNS #6, PITFALLS #1) blocks the PreToolUse mechanical-enforcement layer — building enforcement on top of a fragile JSON-emit pipeline compounds risk.
- **Codebase mapping** is already done for THIS repo (`.planning/codebase/`); the v2 work is to make the same flow available to consumer projects via a `/godmode` skill that delegates to the existing `gsd-map-codebase`-style approach (or composes one inline if we keep zero runtime deps).
- **`.planning/` artifact set** (PROJECT/REQUIREMENTS/ROADMAP/STATE) is a foundation for phase lifecycle; lifecycle skills must wait for the artifact contracts to be defined.
- **Hidden internal agents** is more constraint than feature — it shapes how every other v2 feature is exposed.
- **CI** is fully orthogonal; can ship as its own phase without blocking workflow features.

---

## MVP Definition

### Launch With (v2.0)

What "polish mature version" means. Each item is essential to the v2 promise.

- [ ] **Modernization pass** — every agent updated to current model lineup (`opus` = 4.7, `sonnet` = 4.6, `haiku` = 4.5), `effort` declared, `memory: project` on persistent agents, `isolation: worktree` enforced where appropriate, `maxTurns` set defensively
- [ ] **Hook hardening** — JSON-safe interpolation everywhere; stdin drain tolerant; cwd-aware; remove hardcoded skill/agent lists; PreToolUse added for mechanical quality-gate enforcement
- [ ] **Version unification** — `plugin.json` is canonical; `install.sh`, `/godmode`, README, CHANGELOG all read from it
- [ ] **`.planning/` artifact set** for consumer projects — minimal, GSD-shaped: PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md
- [ ] **Phase lifecycle** — `/discuss-phase`, `/plan-phase`, `/execute-phase`, `/verify-phase` (or composed equivalents); replaces `/prd → /plan-stories → /execute → /ship` shape but preserves the underlying user value
- [ ] **Goal-backward verification** — a verifier agent that checks the phase goal against what's in the codebase, not just that tests pass
- [ ] **Two-stage review** — split spec compliance from code quality; both still read-only
- [ ] **`/godmode` menu** — single command lists every public skill and agent with goal + connects-to; reads live filesystem; first-run output answers "what now?" within 5 lines
- [ ] **CI on macOS + Linux** — shellcheck on every shell file, JSON schema validation on configs, frontmatter lint on agents/skills, smoke test of install→use→uninstall round trip
- [ ] **Concerns triage** — every High-severity item from `.planning/codebase/CONCERNS.md` resolved
- [ ] **Auto Mode awareness** — skills detect and respect Auto Mode signals
- [ ] **Migration path** — v1.x users upgrading via `./install.sh` get a clean v2 install with their `.claude-pipeline/` state intact (read-only) and a one-line note about the new shape
- [ ] **One-pass documentation refresh** — README, CHANGELOG, every rule file, every agent description aligned with v2 surface

### Add After Validation (v2.1+)

- [ ] **`/explore` (advisory)** — Socratic ideation before committing to a plan. GSD's `gsd-explore` is the model. Trigger: users who don't yet know what they want to build.
- [ ] **`/secure-phase`** — retroactive threat-model verification per phase. Trigger: users who shipped without `@security-auditor`. Lower priority than goal-backward verification.
- [ ] **Spec phase** — falsifiable-requirements clarification before plan. Trigger: complex phases where ambiguity is causing rework.
- [ ] **MCP integration recipes** — short, copy-paste setup for Context7, Chrome DevTools, Playwright. Trigger: enough users asking.
- [ ] **`memory: user`** for cross-project learnings — wait until the upstream `memory: project` proves valuable.
- [ ] **Stop hook for session learnings extraction** (everything-claude-code pattern) — adapted to markdown.

### Future Consideration (v3+)

- [ ] **Knowledge graph of phases / decisions / requirements** — GSD's `gsd-graphify` approach. Defer until usage data shows it's actually queried.
- [ ] **Cross-AI peer review** (`gsd-review` model) — invoke external CLIs for plan critique. Defer; multi-vendor coupling is heavy.
- [ ] **Workspace isolation** for parallel features (`gsd-new-workspace`) — defer until users hit the single-worktree-per-feature limit.
- [ ] **A "GUI" via stdout** (rich tables, ASCII charts in skill output). Polish; not a v2 priority.
- [ ] **Custom MCP server bundled with the plugin** — explicitly Out of Scope per PROJECT.md; revisit only if no other path solves a real problem.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---|---|---|---|
| Modernization pass (model lineup, frontmatter fields) | HIGH | LOW | **P1** |
| Hook hardening (JSON safety, PreToolUse enforcement) | HIGH | MEDIUM | **P1** |
| Version unification (plugin.json canonical) | MEDIUM | LOW | **P1** |
| `.planning/` artifact set | HIGH | MEDIUM | **P1** |
| Phase lifecycle (discuss/plan/execute/verify) | HIGH | HIGH | **P1** |
| Goal-backward verification | HIGH | MEDIUM | **P1** |
| Two-stage review | MEDIUM | LOW | **P1** |
| `/godmode` menu refresh (≤ 12 surface, live filesystem) | HIGH | LOW | **P1** |
| CI green (shellcheck + bats + schema) | MEDIUM | MEDIUM | **P1** |
| Auto Mode awareness in skills | MEDIUM | LOW | **P1** |
| All High-severity CONCERNS items | HIGH | MEDIUM | **P1** |
| Migration path for v1.x users | MEDIUM | LOW | **P1** |
| Documentation refresh | MEDIUM | LOW | **P1** |
| `/explore` advisory ideation | MEDIUM | MEDIUM | **P2** |
| `/secure-phase` retroactive | LOW | MEDIUM | **P2** |
| Spec-phase ambiguity scoring | MEDIUM | HIGH | **P2** |
| MCP integration recipes | LOW | LOW | **P2** |
| `memory: user` cross-project | LOW | MEDIUM | **P2** |
| Stop hook for session learnings | LOW | MEDIUM | **P2** |
| Knowledge graph | LOW | HIGH | **P3** |
| Cross-AI peer review | LOW | HIGH | **P3** |
| Workspace isolation | LOW | HIGH | **P3** |

**Priority key:**
- P1: Must have for v2.0 launch (this milestone)
- P2: Should have, add when possible (v2.1+)
- P3: Nice to have, future consideration (v3+)

---

## Competitor Feature Analysis

| Feature | GSD v1.38 | Superpowers | everything-claude-code | claude-godmode v2 |
|---|---|---|---|---|
| User-facing slash command count | 80+ | ~20 (estimated, MEDIUM) | ~30 (awesome-list aggregate, MEDIUM) | **≤ 12 (hard cap)** |
| `.planning/` artifact set | ✓ canonical | ✗ | ✗ | ✓ adopted (slimmed) |
| Phase lifecycle | ✓ discuss→plan→exec→verify→secure→ship | ✗ | ✗ | ✓ adopted, one canonical chain |
| Goal-backward verification | ✓ `gsd-verifier` | ✗ | ✗ | ✓ adopted |
| Two-stage review | ⚠ implicit | ✓ explicit | ✗ | ✓ adopted (Superpowers pattern) |
| `isolation: worktree` for parallel writers | ✓ | ✓ | partial | ✓ existing; codified |
| `memory: project` on persistent agents | ✓ | unknown | unknown | ✓ adopted |
| PreToolUse mechanical gate enforcement | ⚠ instructional | ⚠ instructional | ✓ pattern (secret detection) | ✓ adopted (quality gates + secrets) |
| Codebase mapping | ✓ `gsd-codebase-mapper` | ✗ | ✗ | ✓ available; surfaced via skill |
| Single canonical `/help` listing live filesystem | ⚠ static | unknown | ⚠ static | ✓ live, with goal + connects-to |
| Init-context system (single JSON read at workflow start) | ✓ `gsd-sdk query init.*` | ✗ | ✗ | ✓ adopted, pure-shell+jq (no Node SDK) |
| Atomic commits per gate | ✓ | partial | partial | ✓ adopted |
| Hidden internal agents (orchestrators, not user-facing) | ✗ all 33 are public | unknown | partial | ✓ — this is the surface-area win |
| Mandatory runtime deps beyond Claude Code | Node.js + Python (gsd-sdk) | unknown | mixed (Node, Python, SQLite) | **jq only** |
| Backwards-compat with v1.x | n/a | n/a | n/a | one-time migration in install.sh |

**Where v2 wins:** The combination of "phase lifecycle adopted from GSD" + "≤ 12 user-facing skills via hidden internals" + "jq-only runtime" + "PreToolUse mechanical enforcement" + "first-run UX answers next step in 5 lines" is not, to our knowledge, present in any single existing plugin. v2's competitive position is the integration, not the invention.

**Where v2 deliberately loses:** GSD's deep specialization (32+ workflows, knowledge graph, cross-AI peer review, workspace isolation, ultraplan cloud integration) is intentionally absent. Users who need those should use GSD; v2 is for users who want one clear engineering workflow with all the right defaults.

---

## Sources

- **claude-godmode v1.x**: this repo, especially `commands/godmode.md`, `skills/*/SKILL.md`, `agents/*.md`, `hooks/*.sh`, `config/settings.template.json`, `install.sh`, `.planning/codebase/*` (mapped 2026-04-25).
- **GSD v1.38.3**: `~/.claude/get-shit-done/` (live install), `~/.claude/skills/gsd-*/SKILL.md`, `~/.claude/agents/gsd-*.md`. Workflow files at `~/.claude/get-shit-done/workflows/`. Confidence HIGH for what GSD ships; MEDIUM for what each subskill does in detail (50+ workflows; deeper inspection deferred to plan-phase research).
- **Superpowers**: cross-referenced from `.planning/research/STACK.md` key finding 6. Direct inspection deferred (not installed locally).
- **everything-claude-code**: cross-referenced from `.planning/research/STACK.md` key finding 7. Direct inspection deferred.
- **Claude Code platform**: `.planning/research/STACK.md` (HIGH confidence, verified against `code.claude.com/docs`).
- **Pitfalls**: `.planning/research/PITFALLS.md` for failure modes that constrain feature design.
- **Existing concerns**: `.planning/codebase/CONCERNS.md` for v1.x-specific feature gaps.

---

*Feature research for: claude-godmode v2 (best-in-class Claude Code engineering workflow plugin)*
*Researched: 2026-04-25*
