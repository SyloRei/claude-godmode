---
name: adr
description: "Generate a well-formed Architecture Decision Record from a change in context — Status / Context / Decision / Consequences. One-shot helper, off-spine."
user-invocable: true
allowed-tools: Bash, Read, Write
---

# /adr — write an Architecture Decision Record

A focused, single-shot generator. Capture *one* architectural decision as a
well-formed ADR. This is a reactive helper — it does not spawn agents and is not
part of the spine.

---

## The Job

1. Identify the decision being recorded.
2. Read the surrounding change/context.
3. Produce a complete ADR with all four sections.

---

## 1. Gather context

Read whatever explains the decision — the relevant diff, the files it touches,
and any motivating discussion in the request:

```bash
git diff --stat            # what changed
git log --oneline -10      # recent direction
```

Ask the user only what you cannot infer (e.g. alternatives considered, the
driving constraint).

## 2. Produce the ADR

Emit a single Markdown document with these exact sections, in order:

```markdown
# NNNN. <short title in imperative mood>

## Status

Proposed | Accepted | Superseded by ADR-MMMM   (pick one)

## Context

The forces at play: the problem, the constraints, the requirement that makes a
decision necessary. State facts, not the choice.

## Decision

The change being made, in active voice ("We will …"). One decision per record.

## Consequences

What becomes easier and what becomes harder as a result — both the positive and
the negative. Note follow-on work and any new constraints introduced.
```

## 3. Suggest a home

Suggest (do not require) a path like `docs/adr/NNNN-title.md`, numbering one
above the highest existing ADR. Write the file only if the user confirms the
path; otherwise print the ADR for them to place.

Keep it terse. One decision, four sections, no filler.
