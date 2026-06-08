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
driving constraint) — and when you ask, follow the shared recommendation
convention (`godmode:recommend-convention`) in `rules/godmode-recommend.md`: its
clarifying rendering leads with your best-inferred answer to override, not a
blank prompt. So state what you'd record and invite correction:

> I'll record the alternatives as in-process queue vs. Redis from the diff —
> tell me if I missed one.

(Not: "what alternatives did you consider?")

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
above the highest existing ADR. Writing the file is a consequential step, so
pause with the convention's confirm/proceed rendering — lead with a Recommended:

> Recommended: proceed — write to `docs/adr/0007-queue-backend.md`, next free
> number under the existing ADRs. Reply "go", or name a different path.

Write the file only on confirm; otherwise print the ADR for them to place.

Keep it terse. One decision, four sections, no filler.

---

## Output

<!-- Output follows the in-skill output convention: godmode:output-convention — see rules/godmode-output.md -->

Close the run with a short status block so it reads as finished, not just the raw ADR:

- **Status** — ADR drafted; say where it landed — written to `docs/adr/NNNN-title.md` on confirm, or printed inline for the user to place.
- **Produced** — a one-line gloss of the decision recorded (its title and the choice made), distinct from the full ADR body above.
- **Next** — Accepted? Run `/plan N` to act on the decision; spawn **@architect** first if it still needs working out.

---

## Related

- **@architect** — produces the design analysis and trade-offs an ADR records; spawn it first when the decision still needs working out, then capture the outcome here.
- **/plan N** — the recorded decision shapes the tactical plan for the unit it affects; run it once the ADR is accepted.
- **/changelog** — surface a decision that changes user-visible behavior in the release notes too.
