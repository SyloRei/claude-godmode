---
name: verify
description: "Spawn @verifier (read-only) to walk back from BRIEF.md success criteria; orchestrator mutates PLAN.md ## Verification status section in place."
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

# /verify N

## Connects to

- **Upstream:** /build N (consumed PLAN.md item verifications)
- **Downstream:** /ship (when all-COVERED), /build N (when gaps — re-build)
- **Reads from:** `.planning/briefs/NN-slug/BRIEF.md`, `.planning/briefs/NN-slug/PLAN.md`, git log, working tree
- **Writes to:** `.planning/briefs/NN-slug/PLAN.md` (## Verification status + ## Brief success criteria sections only), `.planning/STATE.md`

## Auto Mode check

Scan the most recent system reminder for the case-insensitive substring "Auto Mode Active".

When detected (per D-10):
- Report COVERED / PARTIAL / MISSING without asking for clarification.
- Do not prompt the user to interpret ambiguous results — pick the strictest interpretation (mark as PARTIAL when in doubt) and let `/ship`'s gate refusal surface the issue.
- Treat user course corrections as normal input.

See `rules/godmode-skills.md` § Auto Mode Detection for the full convention.

---

## The Job

1. Validate `$N`; resolve `BRIEF_DIR` from the live `.planning/briefs/` listing.
2. Verify `BRIEF.md` and `PLAN.md` exist; refuse otherwise.
3. Spawn `@verifier` via the Task tool. The agent is read-only via `disallowedTools: Write, Edit` (Phase 2 D-15) — it returns a structured markdown report, not file mutations.
4. Capture the report and rewrite the `## Verification status` and `## Brief success criteria` sections of `PLAN.md` in place — single atomic replacement per section.
5. Update `.planning/STATE.md`: `Ready to ship` if all COVERED, else `Verify found gaps` with `/build N` as the next command.

The agent (`@verifier`) reads only; the SKILL writes (scoped to PLAN.md). Any future change making the agent writable would make this mutation flow redundant — that is a Phase 2 contract change, not a `/verify` change. (T-04-28 mitigation: skill body Edit/Write SCOPED to `$BRIEF_DIR/PLAN.md`.)

---

## Step 1: Resolve the brief

```bash
set -euo pipefail
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/_lib.sh"
source "$ROOT/skills/_shared/init-context.sh"
source "$ROOT/skills/_shared/state.sh"

case "${N:-}" in
  ''|*[!0-9]*) error "Usage: /verify N (numeric)." ;;
esac
PADDED=$(printf '%02d' "$N")

CTX=$(godmode_init_context "$PWD")
BRIEF_DIR=$(printf '%s' "$CTX" | jq -r --argjson n "$N" '.briefs[] | select(.n == $n) | .dir' | head -1)
[ -n "$BRIEF_DIR" ] && [ -f "$BRIEF_DIR/BRIEF.md" ] && [ -f "$BRIEF_DIR/PLAN.md" ] \
  || error "BRIEF.md and PLAN.md required at $BRIEF_DIR. Run /brief and /plan first."
SLUG=$(printf '%s' "$BRIEF_DIR" | sed -E 's|.*/[0-9]+-||')
PLAN_FILE="$BRIEF_DIR/PLAN.md"
```

---

## Step 2: Spawn @verifier (read-only)

Use the Task tool with these arguments:

```
subagent_type: verifier
description: "Verify brief N"
prompt: |
  Read BRIEF.md success criteria at .planning/briefs/${PADDED}-${SLUG}/BRIEF.md
  and item verifications at .planning/briefs/${PADDED}-${SLUG}/PLAN.md.

  For each criterion AND each item, walk back to:
  - Working tree state (file existence, content, grep matches)
  - Git log since brief started (commits with [brief ${PADDED}.*] token)
  - Verification commands (run them, capture exit codes)

  Return a structured markdown report with these EXACT sections (the
  orchestrator will rewrite the matching sections in PLAN.md verbatim):

  ## Verification status
  - [x] **Task 1.1** — COVERED
  - [ ] **Task 1.2** — PARTIAL — <one-line reason>
  - [ ] **Task 1.3** — MISSING — <one-line reason>
  ...

  ## Brief success criteria
  - [x] **SC-1** — COVERED
  - [ ] **SC-2** — PARTIAL — <one-line reason>
  - [ ] **SC-3** — MISSING — <one-line reason>
  ...

  Pick the strictest interpretation when ambiguous: mark as PARTIAL rather
  than COVERED. Better to surface a gap that can be closed than to silently
  pass the /ship gate.

  DO NOT write to PLAN.md, BRIEF.md, or any other file. The orchestrator
  (skill body) owns the PLAN.md mutation. Your output IS the report.

  You have `disallowedTools: Write, Edit` enforced — the orchestrator trusts
  your output is a pure read.
```

Capture the agent's stdout into shell variable `VERIF_REPORT`.

---

## Step 3: Mutate PLAN.md `## Verification status` + `## Brief success criteria` sections

The agent returned both sections; rewrite them in place via a single atomic awk pass (POSIX rename semantics).

```bash
NEW_VERIF=$(printf '%s' "$VERIF_REPORT" | awk '
  /^## Verification status/ {flag=1}
  /^## Brief success criteria/ {flag=0}
  flag
')
NEW_SC=$(printf '%s' "$VERIF_REPORT" | awk '
  /^## Brief success criteria/ {flag=1}
  flag
')

TMP=$(mktemp -t godmode-plan.XXXXXX) || error "mktemp failed"
awk -v new_verif="$NEW_VERIF" -v new_sc="$NEW_SC" '
  BEGIN { in_verif=0; in_sc=0 }
  /^## Verification status/   { in_verif=1; print new_verif; next }
  /^## Brief success criteria/ { in_verif=0; in_sc=1; print new_sc; next }
  /^## / && (in_verif || in_sc) { in_verif=0; in_sc=0; print; next }
  !(in_verif || in_sc) { print }
' "$PLAN_FILE" > "$TMP"
mv "$TMP" "$PLAN_FILE"
```

Alternatively, use the `Edit` tool with `old_string` = the entire `## Verification status` block plus `## Brief success criteria` block in PLAN.md, and `new_string` = the rewritten content from `VERIF_REPORT`. Both yield in-place semantics. The awk-mv recipe is recommended because it is a single atomic file replace; the Edit tool is acceptable when the section boundaries are unambiguous.

The skill body MUST NOT modify any file other than `$PLAN_FILE` (`.planning/briefs/${PADDED}-${SLUG}/PLAN.md`) and `.planning/STATE.md` (via `godmode_state_update`). T-04-28 scope discipline.

---

## Step 4: Update STATE.md per coverage

```bash
# Count non-COVERED lines in the verification + SC sections.
GAP_COUNT_VERIF=$(awk '/^## Verification status/,/^## /' "$PLAN_FILE" \
  | grep -cE '^- \[.\].*\b(PARTIAL|MISSING)\b' || true)
GAP_COUNT_SC=$(awk '/^## Brief success criteria/,0' "$PLAN_FILE" \
  | grep -cE '^- \[.\].*\b(PARTIAL|MISSING)\b' || true)
TOTAL_GAPS=$((GAP_COUNT_VERIF + GAP_COUNT_SC))

if [ "$TOTAL_GAPS" -eq 0 ]; then
  godmode_state_update "$N" "$SLUG" "Ready to ship" "/ship" "Verify $N: all COVERED"
  info "Verify $N: all criteria COVERED. Run /ship."
else
  godmode_state_update "$N" "$SLUG" "Verify found gaps" "/build $N" "Verify $N: $TOTAL_GAPS gap(s)"
  warn "Verify $N: $TOTAL_GAPS gap(s) (PARTIAL or MISSING). Re-run /build $N to close."
fi
```

---

## Constraints

- The agent MUST be `@verifier` whose Phase 2 frontmatter has `disallowedTools: Write, Edit`. The skill enforces this by trusting the agent contract; if a future change makes the agent writable, this skill's mutation flow becomes redundant — that's a Phase 2 contract change.
- Skill body Edit/Write capability is SCOPED to `$BRIEF_DIR/PLAN.md` and `.planning/STATE.md` (via `godmode_state_update`) only. The orchestrator MUST NOT modify BRIEF.md or any other file (T-04-28).
- Vocabulary: only the v2 user-facing terms. The token "Task NN.M" is the documented exception inside PLAN.md headings (D-35 template constraint) — this skill body parses those headings, so the token unavoidably appears in awk patterns and grep arguments. Phase 5's vocabulary gate must whitelist `task` for `skills/verify/SKILL.md`. Body prose still uses "item" or "criterion".
- All STATE.md mutations go through `godmode_state_update` from `skills/_shared/state.sh`.

---

## See Also

- `rules/godmode-skills.md` — frontmatter convention, Connects-to layout, Auto Mode block.
- `skills/_shared/init-context.sh` — `godmode_init_context` returns the JSON context blob.
- `skills/_shared/state.sh` — `godmode_state_update` is the only sanctioned STATE.md writer.
- `agents/verifier.md` — read-only verifier agent contract (`disallowedTools: Write, Edit`).
- `templates/.planning/briefs/PLAN.md.tmpl` — structural scaffold the agent's report must align with.
