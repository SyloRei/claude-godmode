# Claude Code God-Mode System — Usage Guide

## Overview

This system transforms Claude Code into a professional software engineering environment with structured workflows, quality enforcement, and specialized agents. It works across any language, framework, and project type.

---

## Quick Reference

### Skills (Slash Commands)

| Command | What it does |
|---------|-------------|
| `/prd` | Create a Product Requirements Document with clarifying questions |
| `/plan-stories` | Convert a PRD into executable stories.json with auto-detected quality gates |
| `/execute` | Run stories using @executor + @reviewer agents |
| `/ship` | Pre-flight quality checks → push → create PR |
| `/debug` | 4-phase structured debugging: Reproduce → Hypothesize → Isolate → Fix |
| `/tdd` | Red-Green-Refactor test-driven development |
| `/refactor` | Safe refactoring with test verification at each step |
| `/explore-repo` | Deep codebase exploration and architecture analysis |

### Agents (Spawned Workers)

| Agent | Model | Purpose | Can Write Code? |
|-------|-------|---------|-----------------|
| `@researcher` | Sonnet | Find patterns, trace flows, gather context | No (read-only) |
| `@reviewer` | Opus | Code review with severity-rated findings | No (read-only) |
| `@architect` | Opus | System design, tradeoff analysis | No (advisory) |
| `@writer` | Opus | General-purpose implementation (worktree) | Yes |
| `@executor` | Opus | Story-specific implementation from stories.json (worktree) | Yes |
| `@security-auditor` | Opus | OWASP audit, secrets scan, dependency check | No (read-only) |
| `@test-writer` | Opus | Write comprehensive test suites (worktree) | Yes |
| `@doc-writer` | Sonnet | Generate documentation | Yes (no worktree — docs go to main directly) |

---

## The Feature Pipeline

For building multi-story features end-to-end:

```
Step 1:  /prd                 Create PRD with clarifying questions
           ↓ optional         @architect reviews design
Step 2:  /plan-stories        Convert PRD → stories.json
Step 3:  /execute             For each story:
                                @executor implements (worktree)
                                @reviewer validates
                                quality gates run
                                commit + update stories.json
Step 4:  /ship                Push + create PR
```

### Example Workflow

```
You:    create a prd for adding user authentication
Claude: [asks 3-5 clarifying questions with lettered options]
You:    1A, 2C, 3B
Claude: [generates PRD, saves to tasks/prd-user-auth.md]

You:    /plan-stories
Claude: [converts PRD → stories.json with 6 stories + quality gates]

You:    /execute
Claude: [picks US-001, spawns @executor, implements, @reviewer validates]
        Story US-001: Add users table ✓
        Story US-002: Create auth middleware ✓
        ...
        All stories complete! Run /ship to push and create PR.

You:    /ship
Claude: [runs quality gates, pushes, creates PR, returns URL]
```

---

## Standalone Workflows

### Fix a Bug
```
You:    /debug the login page returns 500 after password reset
Claude: [follows 4 phases: reproduce → hypothesize → isolate → fix]
```

### Add Test Coverage
```
You:    @test-writer add tests for the auth middleware
Claude: [analyzes code, writes tests, runs them, reports coverage]
```

### Code Review
```
You:    @reviewer review my staged changes
Claude: [analyzes diff, returns verdict with CRITICAL/WARNING/NIT findings]
```

### Refactor Safely
```
You:    /refactor extract the validation logic from UserService
Claude: [baseline tests → plan steps → execute one-at-a-time → verify]
```

### TDD New Feature
```
You:    /tdd implement email validation
Claude: [RED: write test → GREEN: minimal code → REFACTOR → repeat]
```

### Security Audit
```
You:    @security-auditor audit the API endpoints
Claude: [scans for OWASP Top 10, secrets, dependencies, reports findings]
```

### Understand a Codebase
```
You:    /explore-repo
Claude: [detects stack, maps architecture, reports patterns and commands]
```

### Design Architecture
```
You:    @architect design the notification system
Claude: [analyzes requirements, proposes design, evaluates tradeoffs]
```

---

## When to Use What

| Situation | Use |
|-----------|-----|
| Planning a feature | `/prd` → `/plan-stories` → `/execute` → `/ship` |
| Implementing a one-off task | `@writer` (general-purpose, worktree) |
| Implementing pipeline stories | `@executor` (stories.json-aware, worktree) |
| Code review | `@reviewer` |
| Bug fixing | `/debug` |
| Adding tests to existing code | `@test-writer` |
| TDD for new feature | `/tdd` |
| Refactoring | `/refactor` |
| Understanding a codebase | `/explore-repo` or `@researcher` |
| Architecture decisions | `@architect` |
| Security analysis | `@security-auditor` |
| Writing docs | `@doc-writer` |
| Ready to push | `/ship` |

### @writer vs @executor
- **@writer** — general-purpose. Use for any implementation task outside the pipeline.
- **@executor** — pipeline-specific. Reads stories.json, tracks progress in progress.txt, knows quality gate commands. Used by `/execute`.

### Skills vs Agents
- **Skills** — workflow templates that guide YOUR session (you stay in control)
- **Agents** — isolated workers spawned in separate context windows (they work independently and return results)

---

## Quality Gates

Defined once in CLAUDE.md. Referenced by all skills and agents.

Every task must pass before completion:
1. Typecheck passes (zero errors)
2. Lint passes (zero errors)
3. All tests pass (existing + new)
4. No hardcoded secrets in diff
5. No regressions
6. Changes match requirements

Commands are auto-detected per project (e.g., `pnpm type-check`, `cargo test`).

---

## Severity Scales

Two scales for different domains:

**Code Review (@reviewer):**
- CRITICAL — must fix (bugs, security, data loss)
- WARNING — should fix (potential issues, missing tests)
- NIT — nice to fix (style, minor improvements)

**Security Audit (@security-auditor):**
- CRITICAL / HIGH / MEDIUM / LOW (industry standard)

---

## Auto-Detection

On first interaction in any project, the system auto-detects:
- Language, framework, package manager
- Test runner, linter, formatter, typechecker
- Build system, CI/CD, monorepo structure

This ensures commands like `/ship` and `/execute` use the right tools automatically.

---

## File Locations

```
~/.claude/
├── CLAUDE.md              # Core config (quality gates, workflows, standards)
├── INSTRUCTIONS.md        # This file
├── settings.json          # Permissions and plugins
├── skills/
│   ├── prd/SKILL.md       # PRD creation
│   ├── plan-stories/SKILL.md  # PRD → stories.json
│   ├── execute/SKILL.md   # Story execution pipeline
│   ├── ship/SKILL.md      # Push and PR
│   ├── debug/SKILL.md     # Structured debugging
│   ├── tdd/SKILL.md       # Test-driven development
│   ├── refactor/SKILL.md  # Safe refactoring
│   └── explore-repo/SKILL.md  # Codebase exploration
└── agents/
    ├── researcher.md      # Read-only research
    ├── reviewer.md        # Code review
    ├── architect.md       # System design
    ├── writer.md          # General implementation
    ├── executor.md        # Pipeline story execution
    ├── security-auditor.md # Security audit
    ├── test-writer.md     # Test generation
    └── doc-writer.md      # Documentation
```

---

## Continuous Learning

The system learns and remembers across sessions automatically.

### How It Works

1. **Native Auto-Memory** — Claude automatically saves learnings to `~/.claude/projects/<project>/memory/MEMORY.md`. First 200 lines load at every session start.

2. **Session Start Hook** — on every new session, a hook auto-detects your project type (language, package manager, test runner) and injects it as context. No need to run `/explore-repo` every time.

3. **Post-Compaction Hook** — during long sessions when context compresses, a hook re-injects quality gates, available skills/agents, and project context. Claude never loses track of the system.

4. **Agent Memory** — `@writer`, `@executor`, and `@researcher` have persistent project memory (`memory: project`). They remember patterns, conventions, and gotchas from previous sessions.

### What Gets Remembered
- Project patterns and conventions
- Quality gate commands for this project
- Debugging solutions for non-obvious problems
- Architecture decisions and constraints
- Codebase-specific knowledge

### What Doesn't Get Remembered
- Code (it's in the repo)
- Git history (use `git log`)
- Temporary task state
- Anything already in CLAUDE.md

### File Locations
```
~/.claude/hooks/
├── statusline.sh          # Context %, model, cost, project display
├── post-compact.sh        # Restores context after compaction
└── session-start.sh       # Injects project context on session start

~/.claude/projects/<project>/memory/
├── MEMORY.md              # Auto-memory index (loads at session start)
└── [topic].md             # Topic-specific memory files
```

---

## Context Monitoring

The status line shows context capacity at all times:

```
 nodle │ main │ Opus │ ████░░░░░░ 42% │ $0.45
```

### Threshold Colors
- **Green** (<60%) — healthy, plenty of room
- **Yellow** (60-80%) — compact soon with `/compact`
- **Red** (>80%) — compact immediately or start new session

### Best Practices
- Run `/compact "preserve X"` proactively at ~70%
- Use subagents (@researcher) for heavy research to keep main context clean
- After major milestones, compact to start the next phase fresh
- PostCompact hook automatically restores quality gates and available skills/agents
- Check `/cost` for detailed token breakdown

---

## Tips

- **Start a new session** after making changes to pick up updates
- **Use `/explore-repo` first** when working in an unfamiliar codebase
- **Agents run in parallel** — spawn @researcher + @security-auditor simultaneously
- **Worktree agents** (@writer, @executor, @test-writer) work on isolated copies
- **Quality gates are mandatory** — no skill or agent skips them
- **Cross-references** — every skill suggests next steps and related tools
- **Long sessions are safe** — post-compaction hook restores critical context
- **Memory persists** — @writer and @executor remember project patterns between sessions
