## Recommendation-Backed Questions — Canonical Convention

This is the single canonical definition of the recommendation-backed-question
convention. Skills that ask interactive questions reference this rule; do not
restate or fork it elsewhere.

### Scope — the planning spine

The convention governs the **planning spine**: the skills `/mission`, `/brief`,
`/plan`, `/ideate`, and `/refine`. (`/ideate` and `/refine` do not exist yet —
the convention binds them the moment they are built.) These skills shape
decisions, so every interactive question they ask must carry the author's
reasoning, not punt the decision back to the user.

### Lead with Recommended

Every interactive question a spine skill asks must **lead with a Recommended
option** — the reasoned default the skill would pick. Do NOT present a flat menu
of equal choices that offloads the thinking onto the user. You did the analysis;
say what you'd do and why, then let the user override.

### Visible one-line rationale

The Recommended option carries a short, **user-visible** rationale — the explicit
thinking, shown inline, never hidden. Use the form:

```
a) X (Recommended — because …)
```

Concrete example:

```
Which storage backend should the brief assume?

  a) SQLite (Recommended — single-file, zero ops, fits the local-only
     constraint in the mission)
  b) Postgres — only if you expect concurrent writers across machines
  c) Flat JSON — simplest, but no query layer once data grows

Pick a letter, or describe a different option.
```

The rationale is one line, concrete, and tied to the actual context (the
mission, the brief, a known constraint) — not a generic "this is common."

### Marker token

Every planning-spine skill includes the exact, fixed marker token
`godmode:recommend-convention` in its body (in its question-guidance section)
to signal adherence. The token is the single greppable contract between the
skills and this rule. The CI gate `scripts/check-recommend.sh` greps the spine
skills for `godmode:recommend-convention` and fails the build if any spine skill
is missing it.

The token is literal and fixed — `godmode:recommend-convention`. Do not
paraphrase, version, or namespace it differently.
