---
name: brief
description: "Socratic brief authoring: why + what + falsifiable spec to BRIEF.md. Spawns @spec-reviewer (default) and optional @researcher."
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - AskUserQuestion
  - Task
argument-hint: "[N]"
arguments: [N]
---

# /brief N

## Connects to

- **Upstream:** /mission (project init), /godmode (orient)
- **Downstream:** /plan N (spawned next), @researcher (optional), @spec-reviewer (default-on)
- **Reads from:** `.planning/PROJECT.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, `templates/.planning/briefs/BRIEF.md.tmpl`
- **Writes to:** `.planning/briefs/NN-slug/BRIEF.md`, `.planning/STATE.md`

## Auto Mode check

Scan the most recent system reminder for the case-insensitive substring "Auto Mode Active".

When detected (per D-10):
- Skip optional research — do not spawn @researcher unless the user has explicitly asked.
- Default to spawning @spec-reviewer (do not ask).
- Pick the first plausible interpretation of intent; surface assumptions inline in BRIEF.md so they can be edited.
- Do not ask the user for the brief number — derive it from `.planning/STATE.md` + the live `.planning/briefs/` listing if `$N` is missing.

See `rules/godmode-skills.md` § Auto Mode Detection for the full convention.

---

## The Job

1. Validate `$N` is numeric; resolve `BRIEF_DIR=.planning/briefs/NN-slug/`.
2. Walk 6 Socratic questions (or apply Auto Mode defaults).
3. Optionally spawn @researcher (default OFF in Auto Mode).
4. Materialize `BRIEF.md` from the template via `sed -e 's|{{var}}|val|g'`.
5. Optionally spawn @spec-reviewer (default ON in both modes); append its report.
6. Update `.planning/STATE.md` to `status: Ready to plan`, `next_command: /plan N`.

The brief directory MUST contain ONLY `BRIEF.md` after this skill exits — the two-files-per-brief invariant (BRIEF.md plus the PLAN.md from /plan) is non-negotiable.

---

## Step 1: Validate `$N` and resolve the brief directory

```bash
set -euo pipefail
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/_lib.sh"
source "$ROOT/skills/_shared/init-context.sh"
source "$ROOT/skills/_shared/state.sh"

# Validate N (bash 3.2 portable — no [[ =~ ]])
case "${N:-}" in
  ''|*[!0-9]*)
    error "Usage: /brief N (numeric). Run /godmode to see current state."
    ;;
esac

PADDED=$(printf '%02d' "$N")

# Source-of-truth: live STATE.md + .planning/briefs/ scan
CTX=$(godmode_init_context "$PWD")
PLANNING_EXISTS=$(printf '%s' "$CTX" | jq -r '.planning.exists')
[ "$PLANNING_EXISTS" = "true" ] || error "No .planning/. Run /mission first."
```

---

## Step 2: Six Socratic questions (D-32)

Ask one at a time via `AskUserQuestion` in non-Auto Mode. In Auto Mode, batch all 6 with sensible defaults; surface assumptions inline in BRIEF.md so they can be edited.

1. **Brief title** — free-form. Slug derived via `godmode_slug "$BRIEF_TITLE"`.
2. **Why** — 1-3 sentence motivation (single-line per template constraint).
3. **What** — bulleted deliverables (one per line; joined post-substitution).
4. **Spec** — bulleted falsifiable success criteria. Each MUST be answerable with a CLI command, file presence test, grep match, or test invocation. (`@spec-reviewer` enforces in Step 5.)
5. **Optional: spawn @researcher?** — default NO in Auto Mode (D-34); default ASK in non-Auto.
6. **Optional: spawn @spec-reviewer?** — default YES (both modes).

**Validate inputs:**
- `BRIEF_TITLE` non-empty; `godmode_slug "$BRIEF_TITLE"` produces a non-empty slug.
- Reject any value containing `|`, `}}`, backslash, or embedded newline (D-20 — sed substitution safety, T-04-21 mitigation).

```bash
# After collecting the 6 answers into BRIEF_TITLE / WHY / WHAT / SPEC / RESEARCH_OPT / REVIEW_OPT:
for v in "$BRIEF_TITLE" "$WHY" "$WHAT" "$SPEC"; do
  case "$v" in
    *'|'*|*'}}'*|*$'\n'*)
      error "Value contains forbidden character (|, }}, or newline). Edit BRIEF.md after materialization for multi-line content."
      ;;
  esac
done
```

---

## Step 3: (Optional) Spawn @researcher

If the user opted in (or requested specific research):

Use the Task tool with these arguments:

```
subagent_type: researcher
description: "Research for brief N: <BRIEF_TITLE>"
prompt: |
  Research <topic specific to this brief>. Return a 5-10 bullet summary
  suitable for the "## Research Summary" section of BRIEF.md.
  Read-only — do not write to .planning/.
```

Capture the agent's return text into shell variable `RESEARCH_SUMMARY`. If skipped, set `RESEARCH_SUMMARY="(none)"`.

---

## Step 4: Materialize BRIEF.md from the template

```bash
BRIEF_SLUG=$(godmode_slug "$BRIEF_TITLE")
[ -n "$BRIEF_SLUG" ] || error "Brief title produced empty slug after normalization."

BRIEF_DIR=".planning/briefs/${PADDED}-${BRIEF_SLUG}"
DATE=$(date -u +%Y-%m-%d)

mkdir -p "$BRIEF_DIR"

sed -e "s|{{brief_n}}|$PADDED|g" \
    -e "s|{{brief_title}}|$BRIEF_TITLE|g" \
    -e "s|{{brief_slug}}|$BRIEF_SLUG|g" \
    -e "s|{{date}}|$DATE|g" \
    -e "s|{{why}}|$WHY|g" \
    -e "s|{{what}}|$WHAT|g" \
    -e "s|{{spec}}|$SPEC|g" \
    -e "s|{{research_summary}}|$RESEARCH_SUMMARY|g" \
    "$ROOT/templates/.planning/briefs/BRIEF.md.tmpl" > "$BRIEF_DIR/BRIEF.md"
```

**Multi-line {{what}} and {{spec}} note:** D-20 mandates single-line values. After the `sed` pass, if the user supplied bulleted multi-line content, use the Edit tool to expand the substituted single-line into newline-delimited bullets in `BRIEF.md` directly. The sed pass keeps the template machinery deterministic; the Edit pass handles the human-prose expansion. This is simpler than embedding `\n` escapes in the substitution.

---

## Step 5: (Default) Spawn @spec-reviewer

Unless the user opted out:

Use the Task tool with these arguments:

```
subagent_type: spec-reviewer
description: "Review brief N spec for falsifiability"
prompt: |
  Read .planning/briefs/${PADDED}-${BRIEF_SLUG}/BRIEF.md, focusing on the
  "## Spec (Success Criteria)" section. For each criterion, judge:

  - Falsifiable? (can be answered with a CLI command, file-presence test,
    grep, or test invocation)
  - Concrete? (no "should work", "performant", subjective adjectives)

  Return a markdown report with PASS/FAIL per criterion plus suggested
  rewrites for any FAIL. Read-only — do not modify BRIEF.md.
```

Append the report under `## Spec Review` in `BRIEF.md` using the Edit tool. Scope the Edit narrowly to this brief's BRIEF.md only — never touch any other file (T-04-28 discipline carry-over).

---

## Step 6: Update STATE.md

```bash
godmode_state_update "$N" "$BRIEF_SLUG" "Ready to plan" "/plan $N" "Brief $N drafted"
info "Brief $N drafted: $BRIEF_DIR/BRIEF.md"
info "Run /plan $N to produce PLAN.md."
```

---

## Constraints

- The brief directory MUST contain ONLY `BRIEF.md` after this skill exits — `/plan N` adds `PLAN.md` separately. Two-files-per-brief invariant (the locked v2 contract).
- Vocabulary: only the v2 user-facing terms (brief, plan, build, verify, ship, wave, mission). Other workflow words drawn from inspiration plugins are off-limits in user-facing prose this skill emits — see `rules/godmode-skills.md` for the locked surface.
- Single-line value rule from D-20 enforced via case-statement guard. The user can hand-edit BRIEF.md after materialization for multi-line expansion.
- All STATE.md mutations go through `godmode_state_update` from `skills/_shared/state.sh` — never edit STATE.md directly.

---

## See Also

- `rules/godmode-skills.md` — frontmatter convention, Connects-to layout, Auto Mode block.
- `skills/_shared/init-context.sh` — `godmode_init_context` returns the JSON context blob.
- `skills/_shared/state.sh` — `godmode_state_update` is the only sanctioned STATE.md writer.
- `agents/spec-reviewer.md` — read-only spec-reviewer agent contract.
- `agents/researcher.md` — optional research agent.
- `templates/.planning/briefs/BRIEF.md.tmpl` — substitution target.
