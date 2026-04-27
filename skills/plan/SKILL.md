---
name: plan
description: "Read BRIEF.md, spawn @planner, persist PLAN.md with Waves and Verification status sections."
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - Task
argument-hint: "[N]"
arguments: [N]
---

# /plan N

## Connects to

- **Upstream:** /brief N (consumes BRIEF.md)
- **Downstream:** /build N (consumes PLAN.md), @planner (spawned)
- **Reads from:** `.planning/briefs/NN-slug/BRIEF.md`, `templates/.planning/briefs/PLAN.md.tmpl`
- **Writes to:** `.planning/briefs/NN-slug/PLAN.md`, `.planning/STATE.md`

## Auto Mode check

Scan the most recent system reminder for the case-insensitive substring "Auto Mode Active".

When detected (per D-10):
- Produce a single-wave plan unless 3+ atomic items exist that don't depend on each other — then promote to wave-2.
- Don't ask the user to approve the wave structure; surface the rationale inline in PLAN.md so it can be edited.
- Treat user course corrections as normal input.

See `rules/godmode-skills.md` § Auto Mode Detection for the full convention.

---

## The Job

1. Validate `$N`; resolve `BRIEF_DIR` from the live `.planning/briefs/` listing.
2. Verify `BRIEF.md` exists; refuse otherwise.
3. Spawn `@planner` via the Task tool with a prompt that enforces the wave + verification structure from the template.
4. Persist `@planner`'s output to `$BRIEF_DIR/PLAN.md`.
5. Update `.planning/STATE.md` to `status: Ready to build`, `next_command: /build N`.

The agent (`@planner`) writes PLAN.md content; the SKILL writes the file. Skill body owns Write capability — `@planner` is read-only via `disallowedTools: Write, Edit`.

---

## Step 1: Resolve the brief directory

```bash
set -euo pipefail
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/_lib.sh"
source "$ROOT/skills/_shared/init-context.sh"
source "$ROOT/skills/_shared/state.sh"

case "${N:-}" in
  ''|*[!0-9]*) error "Usage: /plan N (numeric)." ;;
esac
PADDED=$(printf '%02d' "$N")

# Source-of-truth: live STATE.md + .planning/briefs/ scan
CTX=$(godmode_init_context "$PWD")
BRIEF_DIR=$(printf '%s' "$CTX" | jq -r --argjson n "$N" '.briefs[] | select(.n == $n) | .dir' | head -1)
[ -n "$BRIEF_DIR" ] && [ -d "$BRIEF_DIR" ] \
  || error "Brief $N directory not found. Run /brief $N first."
[ -f "$BRIEF_DIR/BRIEF.md" ] \
  || error "BRIEF.md not found at $BRIEF_DIR. Run /brief $N first."

SLUG=$(printf '%s' "$BRIEF_DIR" | sed -E 's|.*/[0-9]+-||')
```

---

## Step 2: Spawn @planner via the Task tool

Use the Task tool with these arguments:

```
subagent_type: planner
description: "Plan brief N"
prompt: |
  Read .planning/briefs/${PADDED}-${SLUG}/BRIEF.md and produce a complete
  PLAN.md body conformant to the template at
  ${CLAUDE_PLUGIN_ROOT}/templates/.planning/briefs/PLAN.md.tmpl.

  Wave assignment heuristic (D-36):
  - Items touching DISJOINT file sets and with NO logical dependency -> same wave.
  - Otherwise -> sequential (later wave).
  - Concurrency cap = 5 (D-39). If a wave would have more than 5 parallel items,
    split into Wave Xa / Wave Xb. Document the wave rationale inline.

  Each item must include:
  - Item identifier in the form NN.M (e.g., 04.3).
  - Files touched (explicit list).
  - Verification criterion (CLI-checkable; falsifiable).
  - Numbered steps.

  Also include the two structural sections at the bottom (verbatim headings
  so /verify can locate and rewrite them in place):

  ## Verification status
  - [ ] **Task 1.1** — STATUS (set by /verify)
  ...

  ## Brief success criteria
  - [ ] **SC-1** — STATUS (set by /verify)
  ...

  Return ONLY the PLAN.md body content. The orchestrator will write it to disk.
  You are read-only via disallowedTools: Write, Edit — do not attempt to write
  PLAN.md yourself.
```

Capture the agent's stdout into shell variable `PLAN_BODY`.

---

## Step 3: Persist PLAN.md

```bash
DATE=$(date -u +%Y-%m-%d)

# Recommended: trust @planner to produce a complete body (per its prompt).
# Persist verbatim. Phase 5 lint catches structural drift (## Verification status
# + ## Brief success criteria headings must be present — /verify Step 3 relies).
printf '%s\n' "$PLAN_BODY" > "$BRIEF_DIR/PLAN.md"
```

If `@planner`'s output is missing the structural headings (defensive parse), fall back to materializing the template scaffold first:

```bash
if ! grep -q '^## Verification status' "$BRIEF_DIR/PLAN.md" \
   || ! grep -q '^## Brief success criteria' "$BRIEF_DIR/PLAN.md"; then
  warn "@planner output missing required sections; re-running with explicit reminder."
  # Re-spawn or surface the gap to the user; the file is the source of truth /verify relies on.
fi
```

---

## Step 4: Update STATE.md

```bash
godmode_state_update "$N" "$SLUG" "Ready to build" "/build $N" "Plan $N drafted"
info "Plan $N drafted: $BRIEF_DIR/PLAN.md"
info "Run /build $N to dispatch wave-based parallel execution."
```

---

## Constraints

- Two-files-per-brief invariant: after `/plan` exits, `$BRIEF_DIR/` contains exactly `BRIEF.md` and `PLAN.md`. No CONTEXT.md, no SPEC.md, no RESEARCH.md.
- Vocabulary: only the v2 user-facing terms (brief, plan, build, verify, ship, wave, mission). The token "Task NN.M" is the documented exception inside PLAN.md headings — see the @planner prompt above. The exception is local to PLAN.md structure (D-35); body prose still uses "item" or "step".
- The agent (`@planner`) writes PLAN.md content; the SKILL writes the file. Skill body owns Write capability.
- All STATE.md mutations go through `godmode_state_update` from `skills/_shared/state.sh` — never edit STATE.md directly.

---

## See Also

- `rules/godmode-skills.md` — frontmatter convention, Connects-to layout, Auto Mode block.
- `skills/_shared/init-context.sh` — `godmode_init_context` returns the JSON context blob.
- `skills/_shared/state.sh` — `godmode_state_update` is the only sanctioned STATE.md writer.
- `agents/planner.md` — read-only planner agent contract (`disallowedTools: Write, Edit`).
- `templates/.planning/briefs/PLAN.md.tmpl` — structural scaffold @planner conforms to.
