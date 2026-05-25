---
name: profile
description: "Analyze and improve the performance of code that is too slow or too heavy: establish a baseline, find the real bottleneck with profiling, and recommend the highest-payoff optimizations. Use this when something is measurably slow and you need to know what to fix before changing it."
user-invocable: true
---

# Performance Profiling

Diagnose a performance problem — high latency, low throughput, excessive memory
or allocation — and find the change with the highest payoff for the lowest risk.
Measure BEFORE touching code. This skill profiles and recommends; it does not
write the optimization.

---

## Auto Mode

Auto Mode suppresses confirmation prompts and proceed-pauses — not the one
clarifying question that can matter here: **if the symptom or the target metric
is unknown, ask for it** (optimizing the wrong path wastes the whole effort).
"Slow" is not a target; "p99 request latency is 800ms, want <200ms" is. Once the
symptom and metric are anchored, proceed: baseline, profile, and route the fix
without pausing. Treat course-corrections as normal input.

---

## The Job

1. Measure first — establish a baseline and the symptom
2. Profile to find the real bottleneck via `@perf-engineer`
3. Route the confirmed optimization

Do NOT skip to the optimization. Find the dominant cost first.

---

## Step 1: BASELINE

- What is the symptom? (slow endpoint, high memory, low throughput)
- What is the target metric and its current value? (latency, throughput, memory)
- How is it measured? (existing benchmark, profiler, timing harness, load test)

Never optimize on intuition. If there is no way to measure the symptom, the
first task is to establish one.

**Output:** "Symptom [X]. Baseline [metric = value]. Target [value]. Measured by [Y]."

---

## Step 2: PROFILE (spawn `@perf-engineer`)

Spawn `@perf-engineer` (read-only) to profile against the baseline, locate the
actual hotspot rather than the suspected one, and recommend the highest-payoff,
lowest-risk optimizations. It analyzes; it does not change code.

- It runs the project's benchmarks/profilers and identifies what dominates the cost
- It returns ranked recommendations with `file:line` evidence and expected gain

**Output:** "Bottleneck: [cause] at [file:line] ([share of cost]). Recommendation: [ranked options]."

---

## Step 3: ROUTE THE OPTIMIZATION

The profiling itself does not write the optimization. Once a change is confirmed:

- Route a small, well-scoped optimization to `@writer`.
- Route a multi-file or planned optimization to `@executor`.
- After the change lands, re-measure against the baseline to confirm the gain.

**Output:** "Routed [optimization] to [@writer / @executor]. Re-measure to confirm."

---

## Rules

- Measure before optimizing. Anchor the baseline and target metric first.
- `@perf-engineer` is read-only — it profiles and recommends, it never edits code.
- The skill never writes the optimization itself; it routes to `@writer` or `@executor`.
- Optimize the dominant cost, not the most visible one. Every claim carries `file:line` evidence.
- Re-measure after the change — an unconfirmed gain is not a gain.

---

## Agent Routing

| Step | Agent | Purpose |
|------|-------|---------|
| PROFILE | MUST spawn `@perf-engineer` (`subagent_type: claude-godmode:perf-engineer`) | Read-only profiling: locate the real bottleneck and rank optimizations with cited evidence |
| ROUTE | `@writer` (small change) or `@executor` (multi-file change) | Apply the confirmed optimization — the profile skill never writes it inline |

**Rule:** Never profile inline when `@perf-engineer` can do it read-only with
cited evidence. Never write the optimization from this skill.

---

## On-Demand Helper

This is an on-demand helper, invoked when a performance problem lands. It is not
part of the routine spine and records no workflow state — run it, route the
optimization, and hand off to `@writer` or `@executor`.

---

## Related

- **@perf-engineer** — read-only profiling and optimization recommendations
- **@writer** — small, well-scoped optimization
- **@executor** — multi-file or planned optimization
- **@architect** — when the bottleneck is architectural (wrong data model, sync-where-async)
