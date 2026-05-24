---
name: build
description: "Execute a plan in dependency-ordered waves — run independent steps concurrently in isolated worktrees, one atomic, quality-gated commit per step. Use when: build N, execute the plan for N, run the build for roadmap unit N."
user-invocable: true
disable-model-invocation: true
argument-hint: [N]
arguments: [N]
allowed-tools: Read, Glob, Grep, Bash(git *), Bash(bin/godmode-state*), Bash(*/.claude/bin/godmode-state*), Bash(*/bin/godmode-state*)
---

# Build

Execute the plan for roadmap unit **$N** wave by wave: group the plan's steps by their declared dependencies, run independent steps **concurrently**, and land **one atomic, quality-gated commit per step**. This is the fifth step of the spine: `/mission` → `/brief N` → `/plan N` → **`/build N`** → `/verify N` → `/ship`.

`/build` is side-effecting (it writes code, runs gates, and commits), so it is **user-triggered only** (`disable-model-invocation: true`). It is never auto-invoked.

The git log **is** the execution log. There is no third artifact file — `BRIEF.md` and `PLAN.md` are the only files per unit. Each completed step becomes one commit; the commit history is the record of what was built.

---

## Confirm by default (OQ-5)

`/build` **confirms with the user before dispatching each wave** and before any other side-effecting change (committing, writing to the worktree). Before a wave runs, show: the wave number, the steps in it, the files each step touches, and the agent each step dispatches to. Wait for explicit confirmation, then proceed.

**Exception — Auto Mode.** When `## Auto Mode Active` is present in context, skip the confirmation prompts: dispatch each wave on the default choices and treat any user course-correction as normal input. The per-step quality-gate block (below) is **never** skipped, in either mode.

---

## Step 1: Read the plan

Find the brief directory for unit **$N** and read its `PLAN.md`. `NN` is `$N` zero-padded to two digits (unit `3` → `03`), matching the directory `/brief N` and `/plan N` created.

```bash
NN=$(printf '%02d' "$N")
brief_dir=$(ls -d .planning/briefs/${NN}-* 2>/dev/null | head -1)
```

If no `${brief_dir}/PLAN.md` exists, stop and tell the user to run `/plan $N` first — do not invent a plan.

Read the plan's **Steps**, its **Waves** section, and its **Verification plan**. Read the linked `BRIEF.md` for the acceptance-criterion (AC) IDs each step references — the commit messages cite them.

Also read the current workflow state and any partial progress from a prior `/build` run (see resumability, below):

```bash
bin/godmode-state get active_unit
bin/godmode-state get status
```

---

## Step 2: Derive the waves

A **wave** is a set of steps that can run concurrently because none depends on another in the same wave.

1. **Prefer the plan's pre-computed `## Waves` section.** `/plan N` writes an explicit wave grouping (e.g. `Wave 1: S1`, `Wave 2: S2, S3`). When present, use it verbatim — it is the authoritative ordering.
2. **Fall back to deriving from `dependsOn`.** If the `## Waves` section is missing or incomplete, derive waves from each step's `dependsOn` field (comma-separated step IDs; `none` = no prerequisites):
   - **Wave 1** = every step with `dependsOn: none`.
   - **Wave k** = every not-yet-placed step whose `dependsOn` IDs are all in waves `1..k-1`.
   - Repeat until all steps are placed. A cycle (no step is placeable) is a plan error — stop and report it.

Run **steps within a wave concurrently**; run **waves strictly in order** — a wave starts only after the previous wave's steps have all committed.

---

## Step 3: Dispatch each step to an isolated worktree

For each step in the current wave, dispatch the implementation to a **code-writing agent running in its own git worktree** so concurrent steps never collide on files:

- **`@executor`** — for a step that maps to a discrete, spec-shaped unit of work (the default for plan-driven steps).
- **`@writer`** — for a general implementation step that is not story-shaped.

Both agents declare `isolation: worktree` in their frontmatter: each runs in a separate worktree off the build branch and returns its changes, so parallel steps in the same wave cannot overwrite each other's edits. Spawn one agent **per step**, in parallel within the wave. Give each agent: the step's ID, the files it touches, the change it makes, and the brief AC IDs it satisfies.

Do **not** implement steps inline in this orchestrating context — always dispatch to `@executor`/`@writer`. This skill orchestrates; the agents write the code.

---

## Step 4: Per-step quality gates (before each commit)

Before a step's changes are committed, they **must pass every canonical quality gate**. The gates are defined in **`config/quality-gates.txt`** — one gate per line. **Read that file; do not hardcode the gate list here.** It is the single source of truth.

Resolve the file across install modes exactly as `/ship` does — plugin mode exposes `${CLAUDE_PLUGIN_ROOT}`; manual mode installs it under `~/.claude/config/`; fall back to a repo-relative path when developing the plugin itself:

```bash
# Locate the canonical gate list — read it, don't assume it.
GATES_FILE=""
for cand in \
  "${CLAUDE_PLUGIN_ROOT:-}/config/quality-gates.txt" \
  "$HOME/.claude/config/quality-gates.txt" \
  "config/quality-gates.txt"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { GATES_FILE="$cand"; break; }
done
[ -n "$GATES_FILE" ] || { echo "error: quality-gates.txt not found" >&2; exit 1; }
while IFS= read -r gate; do
  [ -n "$gate" ] || continue
  printf 'gate: %s\n' "$gate"
done < "$GATES_FILE"
```

For each gate, auto-detect the project's command (typecheck, lint, test, build, secret scan) and run it against the step's changes. Lint includes `shellcheck` clean for any `.sh` change. Report each gate's result per step:

```
Step S2 — quality gates (from config/quality-gates.txt):
  [✓/✗] Typecheck passes (zero errors)
  [✓/✗] Lint passes (zero errors; shellcheck clean for any .sh change)
  [✓/✗] All tests pass (existing + new)
  [✓/✗] No hardcoded secrets in the diff
  [✓/✗] No regressions in related functionality
  [✓/✗] Changes match the original requirements
```

A step **commits only when every gate passes**. If a gate fails, the step has failed — see failure isolation below.

---

## Step 5: One atomic commit per completed step

When a step's gates all pass, commit **its changes only** — one atomic commit per step. The commit message references the unit, the step ID, and the brief AC IDs the step satisfies:

```bash
git add <only this step's files>
git commit -m "feat: unit $N S2 — <step summary> (AC-2, AC-3)"
```

**Never `--no-verify`. Never bypass a quality gate.** The commit lands only after Step 4 is green. After committing, record the step as done (resumability, below).

---

## Step 6: Failure isolation and resumability

A failed step (gates won't pass, or its agent reports it cannot complete) **halts only its dependency subtree** — the steps that transitively declare `dependsOn` on the failed step — **not** unrelated waves or steps:

- Skip the failed step's descendants (any step that depends on it, directly or transitively, via `dependsOn`).
- **Continue** running every other independent step and wave. Steps with no dependency on the failure proceed and commit normally.
- Report which step failed, why, and which descendant steps were skipped as a result.

Record **partial progress** so `/build` is **resumable** — a re-run picks up where it left off rather than redoing committed steps. Persist the done-set via the single state source, `bin/godmode-state`:

```bash
# Append a committed step to the resumable done-set.
done=$(bin/godmode-state get status)
bin/godmode-state set status "building $N — done: S1,S2"
```

On a fresh `/build $N`, read `status` first: skip steps already recorded as done (their commits already exist), and resume with the first wave that still has incomplete steps. A re-run after a failure retries the failed subtree without touching the steps that already committed.

---

## Step 7: Record workflow state on completion

When every step has committed (or only a contained failed subtree remains, reported to the user), point the workflow forward via `bin/godmode-state`:

```bash
bin/godmode-state set active_unit "$N"
bin/godmode-state set status "build complete"
bin/godmode-state set next_command "/verify $N"
```

This lets `/godmode` tell the user the build is done and what to do next.

---

## Output

After building, report:

- The waves derived (from the plan's `## Waves` section, or the `dependsOn` fallback) and the steps in each.
- For each step: the agent dispatched (`@executor`/`@writer`), its gate results, and its commit hash.
- Any failed step, the descendant steps skipped, and the resumable done-set recorded.
- The workflow state set and the next step:

> "Build complete for unit N. Run `/verify N` to check it against the plan."

---

## Related

- **/plan N** — preceding step: writes the `PLAN.md` (steps, `dependsOn`, `## Waves`) this skill executes.
- **/verify N** — next step: checks the built change against the plan's verification plan.
- **/debug** — when a step's quality gate fails and the cause isn't obvious.
- **/godmode** — reads the workflow state this skill records and tells the user the next command.

**Spine:** `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. Build runs the plan wave by wave in isolated worktrees, one atomic, gated commit per step.
