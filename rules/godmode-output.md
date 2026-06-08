## In-Skill Output — Canonical Convention

This is the single canonical definition of the in-skill output-block
convention. Surfaces that print a result reference this rule; do not restate or
fork it elsewhere.

### The principle (shape-independent)

Every run ends with a legible result block — say what state the run reached,
what it changed, and where to go next — in one consistent shape, so every
surface reads as one finished product. The reader should never have to scroll
back to reconstruct the outcome: the block names the terminal state, the work,
and the single next move, in that order.

This one principle holds regardless of the surface's shape. Every result block
carries the same **three shared required elements**:

1. **Status header** — one line naming the terminal state the run reached
   (done, blocked, shipped, no-op, needs-input). It leads the block.
2. **What-changed / what-was-produced summary** — what the run did when it did
   work: files written, a diff summary, findings, gate results, metrics. A
   no-op run says so instead.
3. **Explicit next-step line** — the single onward pointer: a `/command` the
   reader runs next, or a named handoff. Exactly one onward move, stated plainly.

The block renders two ways. The renderings differ only in **addressee + form** —
the three beats above are identical in both.

**Rendering A — Terminal output** (the 14 skills + 4 commands): addressed to the
**user**, in prose plus light formatting, pretty at first order for Claude Code.
The next-step is a `/command` the user runs next:

```
Built S3. Wrote scripts/check-output-style.sh (+118) and
tests/output-style.bats (+64); all gates green (vocab, cohesion, bats).

Next: run `/verify 5` to confirm the unit meets its brief.
```

**Rendering B — Caller-contract block** (the 3 in-scope agents `verifier`,
`planner`, `doc-writer`): addressed to the **orchestrator**, as a fenced,
machine-parseable template — a status/verdict header, a what-changed/coverage
summary, and a handoff next-step line. Modeled on `agents/code-reviewer.md`'s
`## Output Format`:

```
## Verdict: [PASS | GAPS | BLOCKED]

## Coverage
- Criteria checked: <n>/<total>
- Gaps: [file:line — what is missing, or "none"]

## Next
→ [the single handoff: /command or @agent the orchestrator runs next]
```

Both renderings lead with state, summarize the work, and end on one next move;
only the addressee (user vs. orchestrator) and the form (prose vs. fenced
template) change.

### Marker token

Every in-scope surface includes the exact, fixed marker token
`godmode:output-convention` in its body, at its Output section, to signal
adherence. The token is the single greppable contract between the surfaces and
this rule. The CI gate `scripts/check-output-style.sh` greps in-scope surfaces
for `godmode:output-convention` and fails the build if any is missing it.

The token is literal and fixed — `godmode:output-convention`. It is the
**single** marker for both renderings: do NOT paraphrase, version, or namespace
it per rendering. There is no `…-convention:A`, no `…-convention-v2`, no
per-rendering suffix. The rule body — not the token — says which rendering
applies, since the CI gate cannot judge rendering. One token, every surface.

### Scope — the ledger

The convention governs **every surface that prints a result**. The set is
explicit: **21 in-scope surfaces** must carry the marker.

**14 skills:**

- `mission`
- `brief`
- `plan`
- `build`
- `ship`
- `verify`
- `ideate`
- `refine`
- `onboard`
- `debug`
- `refactor`
- `tdd`
- `profile`
- `triage`

**4 commands:**

- `adr`
- `changelog`
- `godmode`
- `pr-describe`

**3 agents:**

- `verifier`
- `planner`
- `doc-writer`

**Out of scope by design — the ~15 other agents:** their output is a caller
contract that was **not flagged sub-threshold by the unit-1 audit**. Agent
output is machine-facing; only the 3 agents the audit flagged opt in. The rest
are recorded here as deliberately excluded, not overlooked.

**Delegation boundary.** The CI gate asserts heading + marker **presence** only.
Whether a block truly leads with a status header, summarizes what changed, and
names a real next step is a `/verify` Lens-4 judgment — mirroring how
`scripts/check-cohesion.sh` and `scripts/check-recommend.sh` delegate prose
quality to the same lens. The gate greps a token; it cannot judge prose.
