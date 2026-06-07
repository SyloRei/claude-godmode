---
name: triage
description: "Respond to a production incident, outage, or regression in the wild: establish the timeline, assess blast radius, and reconstruct what happened with cited evidence. Use this when something is failing in production and you need to understand it before fixing it."
user-invocable: true
---

# Incident Triage

Respond to a live production incident — an outage, a regression, or unexpected
behavior reported from the field. Establish what happened and how bad it is
BEFORE touching code. This skill triages; it does not write the fix.

---

## Auto Mode

Auto Mode suppresses confirmation prompts and proceed-pauses — not the one
clarifying question that can matter here: **when it started, when it was last
known-good, or who reported it is unknown, don't ask blank — lead with your
best-inferred answer to override** (e.g. "I'll take the incident start as the
first error at 14:02 UTC — correct me if it began earlier"), since triaging the
wrong incident wastes the whole effort. This clarifying question follows the
shared recommendation convention (`godmode:recommend-convention`) defined in
`rules/godmode-recommend.md`. Once the symptom is anchored, proceed: reconstruct
the timeline, assess blast radius, and route the fix without pausing. Treat
course-corrections as normal input.

---

## The Job

1. Establish the timeline
2. Assess blast radius
3. Reconstruct with cited evidence via `@incident-responder`
4. Route the confirmed fix

Do NOT skip to the fix. Understand the incident first.

---

## Step 1: TIMELINE

- What is the first observed symptom? (error, alert, user report)
- When did it start? When was the system last known-good?
- What changed in that window? (deploys, config, dependency, traffic)

**Output:** "Symptom [X] first seen at [time]. Last known-good [time]. Changed in window: [Y]."

---

## Step 2: BLAST RADIUS

- Who and what is affected? (users, endpoints, regions, downstream systems)
- How severe is it? (full outage, degraded, single feature, cosmetic)
- Is it still ongoing or self-resolved?

**Output:** "Affected: [scope]. Severity: [level]. Status: [ongoing/resolved]."

---

## Step 3: RECONSTRUCT (spawn `@incident-responder`)

Spawn `@incident-responder` (read-only) to reconstruct the timeline against the
code and recommend remediation with cited evidence. It investigates; it does
not change code.

- It correlates the symptom and the change window with the codebase
- It returns a reconstructed timeline and remediation options with `file:line`
  evidence

**Output:** "Root cause hypothesis: [cause] at [file:line]. Remediation: [options]."

---

## Step 4: ROUTE THE FIX

The triage itself does not write the fix. Once a code fix is confirmed:

- Route a small, well-understood defect to `@debugger` for a minimal targeted
  fix plus regression test.
- Route a larger or isolated change to `@writer`.

**Output:** "Routed [fix] to [@debugger / @writer]."

---

## Rules

- Triage before fixing. Anchor the symptom and blast radius first.
- `@incident-responder` is read-only — it reconstructs and recommends, it never
  edits code.
- The skill never writes the fix itself; it routes to `@debugger` or `@writer`.
- Every root-cause claim must carry `file:line` evidence.

---

## Agent Routing

| Step | Agent | Purpose |
|------|-------|---------|
| RECONSTRUCT | MUST spawn `@incident-responder` (`subagent_type: claude-godmode:incident-responder`) | Read-only reconstruction of the timeline + remediation with cited evidence |
| ROUTE | `@debugger` (small defect) or `@writer` (larger change) | Apply the confirmed code fix — the triage skill never writes it inline |

**Rule:** Never reconstruct the incident inline when `@incident-responder` can
do it read-only with cited evidence. Never write the fix from this skill.

---

## On-Demand Helper

This is an on-demand helper, invoked when an incident lands. It is not part of
the routine spine and records no workflow state — run it, route the fix, and
hand off to `@debugger` or `@writer`.

---

## Related

- **@incident-responder** — read-only reconstruction and remediation advice
- **@debugger** — minimal targeted fix plus regression test for a confirmed defect
- **@writer** — larger or isolated fix
- **/debug** — once the fix is in hand, the debugging protocol verifies it

**Spine:** off-spine helper — triage the incident and route the fix, then resume the spine at `/brief N` if the fix warrants a tracked work unit.
