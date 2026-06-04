## Lifecycle Routing — One Owner per Step

Every developer step maps to exactly ONE owner: a user-facing skill (`/x`)
or an agent (`@y`). No step is orphaned; no two owners overlap a step. This
table is canonical — when you reach for a capability, look it up here.

| Developer step | Owner | Kind |
|---|---|---|
| Orient — "what now?" | `/godmode` | skill |
| Initialize / update project + roadmap (mission) | `/mission` | skill |
| Brief / spec — why + what + spec | `/brief N` | skill |
| Plan — tactical breakdown | `/plan N` | skill |
| Implement / build — wave-based execution | `/build N` | skill |
| Verify — goal-backward COVERED/PARTIAL/MISSING | `/verify N` | skill |
| Ship — gates, push, open PR | `/ship` | skill |
| Debug — find/fix a defect | `/debug` | skill |
| Refactor — restructure without behavior change | `/refactor` | skill |
| TDD — red-green-refactor a new behavior | `/tdd` | skill |
| Explore / understand a codebase | `/onboard` | skill |
| Write an Architecture Decision Record | `/adr` | command |
| Draft a Keep-a-Changelog entry | `/changelog` | command |
| Draft a PR description from the branch | `/pr-describe` | command |

`/adr`, `/changelog`, and `/pr-describe` are **off-spine plain commands** —
reactive, one-shot helpers like `/debug` and `/refactor`, not spine steps. Unlike
those two, these three do the work inline and delegate to no agents; `/changelog`
is a standalone helper and does **not** replace `/ship`'s release/changelog step.

Skills own the **workflow**. Agents own the **work** a skill delegates. When a
skill's body says to spawn an agent, spawn it — never do the agent's job inline.

| Developer step | Owning agent |
|---|---|
| Architecture advice / system design | `@architect` |
| Plan authoring (deep tactical breakdown) | `@planner` |
| Verification of goal coverage | `@verifier` |
| Implement a brief's work (gated, brief-driven) | `@executor` |
| Implement an isolated, general-purpose change | `@writer` |
| Write tests for existing code | `@test-writer` |
| Research / cited codebase & web findings | `@researcher` |
| Code review (5 parallel lenses) | `/verify` → `@code-reviewer`, `@security-auditor`, `@perf-reviewer`, `@convention-reviewer`, `@test-reviewer` |
| Spec-level review (does the plan meet the brief) | `@spec-reviewer` |
| Code-level review (does the diff meet the plan) | `@code-reviewer` |
| Performance review | `@perf-reviewer` |
| Convention/style review | `@convention-reviewer` |
| Test-quality review | `@test-reviewer` |
| Security audit | `@security-auditor` |
| Documentation authoring | `@doc-writer` |
| Debugging / root-cause a failure (delegated; `/debug` skill still owns the workflow) | `@debugger` |
| Performance analysis / profiling | `@perf-engineer` |
| Incident response / timeline reconstruction | `@incident-responder` |
| Schema / dependency / framework migration | `@migration-engineer` |

## Skill → Agent delegation map

Which agent each workflow skill spawns for its heavy lifting:

| Skill | Delegates to |
|---|---|
| `/brief N` | `@researcher` (context), `@spec-reviewer` (brief sanity) |
| `/plan N` | `@planner` (authoring), `@spec-reviewer` (plan vs brief) |
| `/build N` | `@executor` (implement), `@test-writer` (tests), `@code-reviewer` (diff vs plan) |
| `/verify N` | `@verifier` (goal-backward coverage) |
| `/ship` | `/verify` (5-lens review final pass), `@security-auditor` (secret/vuln scan) |
| `/debug` | `@researcher` (reproduce/isolate), `@writer` (minimal fix) |
| `/refactor` | `@writer` (steps), `/verify` (5-lens no-behavior-change check) |
| `/tdd` | `@test-writer` (red tests), `@writer` (green impl) |
| `/onboard` | `@researcher` (cited findings) |
| `/triage` | `@incident-responder` (timeline reconstruction) |
| `/profile` | `@perf-engineer` (performance analysis) |
| `/mission` | `@architect` (roadmap shaping) |

## Agent Type Mapping

When spawning godmode agents, use these exact `subagent_type` values. Never
substitute a built-in agent:

| @name | subagent_type | Never use instead |
|-------|---------------|-------------------|
| @architect | `claude-godmode:architect` | — |
| @planner | `claude-godmode:planner` | NOT `Plan` (built-in) |
| @verifier | `claude-godmode:verifier` | — |
| @executor | `claude-godmode:executor` | — |
| @writer | `claude-godmode:writer` | NOT `general-purpose` (built-in) |
| @test-writer | `claude-godmode:test-writer` | — |
| @researcher | `claude-godmode:researcher` | NOT `Explore` (built-in) |
| @spec-reviewer | `claude-godmode:spec-reviewer` | — |
| @code-reviewer | `claude-godmode:code-reviewer` | — |
| @perf-reviewer | `claude-godmode:perf-reviewer` | — |
| @convention-reviewer | `claude-godmode:convention-reviewer` | — |
| @test-reviewer | `claude-godmode:test-reviewer` | — |
| @security-auditor | `claude-godmode:security-auditor` | — |
| @doc-writer | `claude-godmode:doc-writer` | — |
| @debugger | `claude-godmode:debugger` | — |
| @perf-engineer | `claude-godmode:perf-engineer` | — |
| @incident-responder | `claude-godmode:incident-responder` | — |
| @migration-engineer | `claude-godmode:migration-engineer` | — |

Built-in agents (`Explore`, `general-purpose`, `Plan`) must never replace a
godmode agent. `@researcher` is NOT the built-in `Explore` — it returns
structured, cited findings with `file:line` references on the `sonnet` model
with `WebFetch` and `WebSearch` access.

## Plan Mode

- Make plans extremely concise. Sacrifice grammar for concision.
- End each plan with unresolved questions list, if any.

## Severity Scales

Different domains, established conventions:
- Code review (`@code-reviewer`, `@spec-reviewer`, and the `/verify` lenses): CRITICAL / WARNING / NIT
- Security audit (`@security-auditor`): CRITICAL / HIGH / MEDIUM / LOW

## Architect Gate

`@architect` (opus, advisory) is the strongest design reasoner in the roster, but
running it on every unit breaks the cost budget. The Architect Gate is the single
source of truth for **when** a unit warrants an architect pass: it runs only on
non-trivial units. This section **defines** the gate; `/brief` and `/plan` are its
two readers (the unit that wires each skill to act on it is separate from this
definition). The gate exists so an architect pass is reserved for design-heavy
work and adds nothing to trivial, localized changes.

**Trigger criteria.** Evaluate the unit against this checklist. **Design-risk
verdict = `yes` if any one trigger fires**; if none fire, the verdict is `no`.

| # | Trigger |
|---|---|
| 1 | A new system, service, or component is introduced. |
| 2 | A cross-cutting change touching ≥3 modules/surfaces, or a shared contract. |
| 3 | A new or changed data model, schema, or persistent format. |
| 4 | A new or changed public API, interface, or CLI contract. |
| 5 | A migration (schema, dependency, or framework). |
| 6 | A security- or auth-sensitive surface. |
| 7 | A performance-critical path with non-obvious tradeoffs. |
| 8 | Multiple viable approaches that diverge materially (a real design fork). |

**Override.** The brief author or the user may **force** the verdict to `yes` or
`no` regardless of which triggers fire — recording a one-line reason for the
override. An override is authoritative over the checklist result.

**Signal format.** `/brief` records the gate outcome as a `## Design Risk` section
in each `BRIEF.md`, with exactly three fields:

- **Verdict** — `yes` or `no` (default: `no`).
- **Triggers fired** — which checklist item(s) drove a `yes`, or the override.
- **Rationale** — a one-line reason for the recorded verdict.

**Readers + default / fail-cheap.** `/brief` and `/plan` are the **two readers**
of this signal. The gate is
**default-off and fail-cheap**: an absent, empty, or unset Design Risk verdict is
treated as `no` — no architect pass runs, it adds no cost, and it never blocks
work. Trivial units stay cheap and unblocked with zero extra effort.
