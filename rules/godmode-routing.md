## When to Use What

```
Plan a feature           → /prd → /plan-stories → /execute → /ship
Implement a task         → @writer agent (isolated worktree, general purpose)
Execute pipeline stories → @executor agent (stories.json-aware, used by /execute)
Code review              → @reviewer agent
Find/fix a bug           → /debug skill
Write tests              → @test-writer (existing code) or /tdd (new feature)
Refactor                 → /refactor skill
Understand codebase      → /explore-repo or @researcher
Architecture advice      → @architect agent
Security audit           → @security-auditor agent
Documentation            → @doc-writer agent
Push & create PR         → /ship skill
```

## Agent Routing

When a skill's Agent Routing section says to spawn an agent, always spawn it. Never perform the agent's job inline in the main context.

### Agent Type Mapping

When spawning godmode agents, use these exact `subagent_type` values. Never substitute a built-in agent:

| @name | subagent_type | Never use instead |
|-------|---------------|-------------------|
| @researcher | `claude-godmode:researcher` | NOT `Explore` (built-in) |
| @writer | `claude-godmode:writer` | NOT `general-purpose` (built-in) |
| @executor | `claude-godmode:executor` | — |
| @reviewer | `claude-godmode:reviewer` | — |
| @architect | `claude-godmode:architect` | — |
| @test-writer | `claude-godmode:test-writer` | — |
| @security-auditor | `claude-godmode:security-auditor` | — |
| @doc-writer | `claude-godmode:doc-writer` | — |

Built-in agents (`Explore`, `general-purpose`, `Plan`) must never replace a godmode agent. The `@researcher` agent is NOT the same as the built-in `Explore` agent — @researcher provides structured, cited findings with `file:line` references and runs on the `sonnet` model with `WebFetch` and `WebSearch` access.

## Plan Mode

- Make plans extremely concise. Sacrifice grammar for concision.
- End each plan with unresolved questions list, if any.

## Severity Scales

**Severity scales** (different domains, established conventions):
- Code review (@reviewer): CRITICAL / WARNING / NIT
- Security audit (@security-auditor): CRITICAL / HIGH / MEDIUM / LOW

## Effort Tier Policy (locked 2026-04-26 — Phase 2)

Every agent declares `effort: high` OR `effort: xhigh` in its frontmatter. No `medium`, `low`, or blank.

**Code-writing agents (effort: high):** `@executor`, `@writer`, `@test-writer`, `@doc-writer`, `@code-reviewer`. These agents have `Write` and/or `Edit` in their `tools:` field. They lock at `effort: high` because Opus 4.7's `xhigh` is documented to skip rule adherence — too risky when an agent is mutating source files.

**Design / audit agents (effort: xhigh):** `@architect`, `@security-auditor`, `@planner`, `@verifier`, `@spec-reviewer`. These agents declare `disallowedTools: Write, Edit` (mechanically read-only). They use `xhigh` for deeper analysis on read-only work where rule-skipping has no source-modifying consequences.

**Exception:** `@researcher` stays at `effort: high` despite being read-only. Research is shallow-many (lots of small lookups, web fetches), not deep design — `xhigh` wastes tokens on this workload.

The frontmatter linter (`scripts/check-frontmatter.sh`) refuses commits where `effort: xhigh` is combined with `Write` or `Edit` in `tools:` and `disallowedTools` does NOT contain both. This is the mechanical enforcement of the policy.

## Connects-to Convention (locked 2026-04-26 — Phase 2)

Every agent body has a `## Connects to` H2 section near the top (after the H1 title, before the main process description). Bullets describe upstream / downstream relationships:

```markdown
## Connects to
- **Upstream:** /skill-name (the skill that spawns this agent)
- **Downstream:** Writes <artifact> consumed by /next-skill or @next-agent
- **Reads from:** <upstream artifact path>
```

`/godmode` (Phase 4) renders this section by `grep -A 20 '^## Connects to' agents/*.md` and presents the chain to the user. Power users can modify any agent without breaking the indexer — the convention is the contract.

The linter asserts every agent has a `## Connects to` section with at least one `**Upstream:**` line and at least one `**Downstream:**` line.
