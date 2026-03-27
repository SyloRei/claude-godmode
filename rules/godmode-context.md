## Context Management

- **Monitor context** — the status line shows capacity %. Watch it.
- **Compact at ~70%** — run `/compact` proactively, not reactively at 90%+
- **Before compacting** — state what to preserve: `/compact "preserve the auth refactoring progress"`
- **After milestones** — compact with a summary to start fresh for the next phase
- **Use subagents** — heavy research goes into @researcher, not main context. Keep main window clean.
- Summarize research findings before acting on them
- After compaction, a hook restores quality gates and available skills/agents
- Never let context degrade quality — compact early, compact often

## Continuous Learning

After completing significant tasks, save learnings to project memory:
- Project patterns (conventions, architecture decisions, gotchas)
- Quality gate commands discovered for this project
- Debugging solutions for non-obvious problems
- Codebase-specific knowledge not derivable from reading code

Do NOT save to memory:
- Code snippets (they're in the repo)
- Git history (use git log)
- Ephemeral task state (use tasks instead)
- Anything already in CLAUDE.md or project docs

Organize memory by topic (one file per topic, concise). Keep MEMORY.md index under 200 lines.
