## Recommendation-Backed Questions — Canonical Convention

This is the single canonical definition of the recommendation-backed-question
convention. Surfaces that ask the user a consequential question reference this
rule; do not restate or fork it elsewhere.

### The principle (shape-independent)

Whatever you ask the user, **lead with the answer you'd give and why**, then let
the user override. You did the analysis — say what you'd do and the reason,
inline, before you hand the decision back. Never offload the thinking with a
flat prompt of equal options or a blank question.

This one principle holds regardless of the question's shape. It renders three
ways, and every rendering carries a **visible one-line rationale** — the
explicit thinking, shown inline, never hidden, one line, concrete, and tied to
the actual context (the mission, the brief, a known constraint) — not a generic
"this is common."

**1. Menu choice** — a lettered set of options, the reasoned default marked
`(Recommended — because …)`:

```
Which storage backend should the brief assume?

  a) SQLite (Recommended — single-file, zero ops, fits the local-only
     constraint in the mission)
  b) Postgres — only if you expect concurrent writers across machines
  c) Flat JSON — simplest, but no query layer once data grows

Pick a letter, or describe a different option.
```

**2. Confirm / proceed pause** — a yes/no or go/stop gate, the default stated as
`Recommended: proceed — because …` (the generalized form already used by /brief
and /plan as "Recommended: yes"):

```
Recommended: proceed — the plan's 6 steps each map to an acceptance check and
nothing is blocked. Reply "go", or name what to change.
```

**3. Clarifying question** — lead with your **best-inferred answer to override**,
not a blank prompt. State the assumption you'd run with and invite correction,
rather than asking the user to fill in a blank:

```
I'll assume the repro is the failing `bats tests/ship-gate.bats` run — correct
me if you meant a different reproduction.
```

(Not: "what's the repro?")

### Marker token

Every in-scope surface includes the exact, fixed marker token
`godmode:recommend-convention` in its body (in its question-guidance section) to
signal adherence. The token is the single greppable contract between the
surfaces and this rule. The CI gate `scripts/check-recommend.sh` greps in-scope
surfaces for `godmode:recommend-convention` and fails the build if any is
missing it.

The token is literal and fixed — `godmode:recommend-convention`. It is the
**single** marker for all three renderings: do NOT paraphrase, version, or
namespace it per shape. There is no `…-convention:menu`, no `…-convention-v2`,
no per-surface suffix. One token, every surface.

### Scope — the ledger

The convention governs **every surface that asks the user a consequential
question**. The set is explicit:

**In scope (14) — must carry the marker:**

- `mission`
- `brief`
- `plan`
- `ideate`
- `refine`
- `build`
- `ship`
- `onboard`
- `debug`
- `refactor`
- `tdd`
- `profile`
- `triage`
- `adr` (command)

**N/A (4) — asks no consequential question, recorded but not marked:**

- `verify` — auto-runs its lenses and gates; asks the user nothing.
- `changelog` — reactive helper that renders existing history; no questions.
- `godmode` — orientation/status surface only; presents no choices.
- `pr-describe` — fills a PR body from the diff; no consequential question.

The gate `scripts/check-recommend.sh` enforces marker **presence** across the
in-scope set. Whether a question *truly* leads with Recommended — that the prose
actually renders the principle — is a `/verify` judgment-lens concern; the gate
greps a token and cannot judge prose.
