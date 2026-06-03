---
name: build
description: "Execute a plan in dependency-ordered waves — run independent steps concurrently in isolated worktrees, one atomic, quality-gated commit per step. Use when: build N, execute the plan for N, run the build for roadmap unit N."
user-invocable: true
disable-model-invocation: true
argument-hint: [N]
arguments: [N]
allowed-tools: Read, Glob, Grep, Bash(git *), Bash(gm=*), Bash(*godmode-state*), Bash(*godmode-model*), Bash(*godmode-worktree*)
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

## Step 1: Read the plan and reconcile state

**Resolving the godmode helpers.** The `godmode-*` helpers live in the plugin install dir — **not** the consumer repo you're working in — so a bare `bin/godmode-*` path fails from another project's working directory. Every `bash` block below resolves their location into `$gm` first (plugin mode → `$CLAUDE_PLUGIN_ROOT/bin`, manual install → `~/.claude/bin`, in-repo → `./bin`) and calls `"$gm/godmode-<name>"`. Keep the resolver line; never call a helper by a bare relative path.

Find the brief directory for unit **$N** and read its `PLAN.md`. `NN` is `$N` zero-padded to two digits (unit `3` → `03`), matching the directory `/brief N` and `/plan N` created. The glob is guarded so an empty match can't abort under `set -euo pipefail`:

```bash
NN=$(printf '%02d' "$N")
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
mission_id=$("$gm/godmode-state" get mission_id)
brief_dir=$(ls -d .planning/missions/${mission_id}/briefs/${NN}-* 2>/dev/null | head -1 || true)
[ -n "$brief_dir" ] || { echo "No brief dir for unit $N — run /plan $N first." >&2; exit 1; }
```

If no `${brief_dir}/PLAN.md` exists, stop and tell the user to run `/plan $N` first — do not invent a plan.

Read the plan's **Steps**, its **Waves** section, and its **Verification plan**. Read the linked `BRIEF.md` for the acceptance-criterion (AC) IDs each step references — the commit messages cite them.

Read the current workflow state — both the active unit and the status (which carries any partial progress from a prior `/build` run, see resumability below):

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
active=$("$gm/godmode-state" get active_unit)
status=$("$gm/godmode-state" get status)
```

**Reconcile `active_unit` with `$N` before doing anything else.** If `active` is non-empty and differs from `$N`, the state points at a different unit. Set `active_unit` to `$N` so the recorded state stays coherent, and warn the user that the active unit changed:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
if [ -n "$active" ] && [ "$active" != "$N" ]; then
  echo "warning: active_unit was '$active', building '$N' — updating active_unit to $N." >&2
  "$gm/godmode-state" set active_unit "$N"
  status=""   # prior status belongs to a different unit; ignore its done-set
fi
```

Do **not** silently proceed with mismatched state, and do **not** treat a different unit's done-set as this unit's progress.

**Re-entry contract.** Inspect `status` (the done-set schema is defined in Step 6):

- If `status` begins with `build complete` **for this unit** (it reads `build complete | unit: $N` and `active` matched `$N`, see Step 7), there is nothing to build — report it and offer `/verify $N`.
- If `status` contains a done-set for this unit, query it via `godmode-state done has`/`done list` (Step 6) and **skip** those step IDs (their commits already exist), running only the remaining steps plus any failed subtree from the prior run.
- Otherwise, this is a fresh build of unit `$N` — the done-set starts empty.

---

## Step 2: Derive the waves

A **wave** is a set of steps that can run concurrently because none depends on another in the same wave.

The authoritative source is each step's **`dependsOn`** field. Derive waves from it:

- **Wave 1** = every step with `dependsOn: none`.
- **Wave k** = every not-yet-placed step whose `dependsOn` IDs are all in waves `1..k-1`.
- Repeat until all steps are placed. A cycle (no step is placeable) is a plan error — stop and report it.

**On the plan's `## Waves` section.** `/plan N` writes a pre-computed `## Waves` grouping (e.g. `Wave 1: S1`, `Wave 2: S2, S3`) as a convenience. It is **derived from `dependsOn`**, so when both are present they must agree:

- If `## Waves` **agrees** with the `dependsOn`-derived grouping, use it as written.
- If `## Waves` **contradicts** `dependsOn` (a stale hand-edit drifted from the structured field), **prefer `dependsOn`** — it is the more precisely structured source — OR, if the contradiction looks intentional, **flag the conflict and stop** rather than guessing. Do not silently follow a stale `## Waves`.
- If `## Waves` is **absent**, derive the grouping from `dependsOn`. This is normal for older plans written before the section existed — it is not an error.

Run **steps within a wave concurrently**; run **waves strictly in order** — a wave starts only after the previous wave's steps have all committed and merged back (Step 5). Because the plan makes the steps in a wave file-disjoint, this ordering keeps the build-branch HEAD up to date by the time each step's agent merges it into its worktree (Step 3).

---

## Step 3: Dispatch each step to an isolated worktree

**Reap orphaned worktrees first.** Before this wave dispatches any agent, prune leaked/orphaned worktrees so a stale `.git/worktrees/<id>` admin entry can't block a fresh `git worktree add`. Resolve `$gm` exactly as the **Resolving the godmode helpers** note in Step 1 shows; `cleanup` is idempotent and never touches a live worktree or the main tree:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-worktree" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-worktree" cleanup
```

For each step in the current wave, dispatch the implementation to a **code-writing agent running in its own git worktree** so concurrent steps never collide on files:

- **`@executor`** — for a step that maps to a discrete, spec-shaped unit of work (the default for plan-driven steps).
- **`@writer`** — for a general implementation step that is not story-shaped.

Both agents declare `isolation: worktree` in their frontmatter. **The SDK roots each agent's worktree on `main`, not on the build branch** — so each agent's **first action inside its worktree** is to run the `godmode-worktree create` helper, which merges the up-to-date build-branch HEAD into that main-based tree (the enforced base). Because waves run strictly in order (Step 2) and each wave merges back before the next begins (Step 5), the build-branch HEAD each agent merges in is up to date — every worktree in a wave converges on the same base. Spawn one agent **per step**, in parallel within the wave. Give each agent:

- the step's **ID**, the **files it touches**, the **change it makes**, and the brief **AC IDs** it satisfies;
- the **build-branch HEAD ref**, captured by the orchestrator on the build branch *before* dispatch, with the instruction to, **as its first action inside its worktree**, run the `godmode-worktree create` helper with that ref as the explicit `<build-ref>` — this merges the current build-branch HEAD into the agent's SDK-provided (main-based) worktree so it builds on the enforced base, not a stale `main`. Capturing the ref is the **orchestrator side** of the create-first contract (`@executor`/`@writer` declare the create-first first action); the orchestrator resolves the ref here and hands it to each agent's brief. Resolve `$gm` exactly as the **Resolving the godmode helpers** note in Step 1 shows; never call a bare relative `bin/godmode-worktree` path:

  ```bash
  # Orchestrator, on the build branch: capture the HEAD ref to hand each agent.
  build_ref=$(git rev-parse HEAD)
  [ -n "$build_ref" ] || { echo "error: cannot resolve the build-branch HEAD to pass to agents." >&2; exit 1; }
  # Pass "$build_ref" into each dispatched agent's brief as its <build-ref>, with
  # the instruction that the agent's FIRST in-worktree action is:
  #   gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-worktree" ] && { echo "$c/bin"; break; }; done)
  #   "$gm/godmode-worktree" create "<build-ref>"
  ```

- the instruction to then, inside its own worktree: implement the step, **run the per-step quality gates** (Step 4), and on green make **exactly one atomic commit** for the step — **never `--no-verify`** (Step 5). The agent does **not** push and does **not** merge; it returns its worktree branch name and commit hash.

Do **not** implement steps inline in this orchestrating context — always dispatch to `@executor`/`@writer`. This skill orchestrates; the agents write the code, run the gates, and commit in their worktrees.

### Model profile

Before spawning any agent, resolve the active model profile from `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-balanced}`, then call the resolver `"$gm/godmode-model" <agent>` (resolve `$gm` as the **Resolving the godmode helpers** note in Step 1 shows) to obtain the model for that agent under the active profile. Pass that model to the Agent tool's `model` override at spawn time. The resolver also reports the agent's effort, but **`effort` is frontmatter-only and is NOT set at spawn** (platform limitation — effort cannot be overridden when spawning an agent), so override **only** `model`; effort stays whatever the agent's frontmatter declares.

---

## Step 4: Per-step quality gates (run by the agent, in its worktree)

Before a step's changes are committed, they **must pass every canonical quality gate**. **The dispatched `@executor`/`@writer` agent runs these gates inside its own worktree, before it commits** — not this orchestrating skill. That is deliberate: the agents have broad `Bash` access (they write code and run `typecheck`/`lint`/`test`/`build`), so the gate commands execute where the changes live. This skill's narrow `allowed-tools` (no `npm`/`cargo`/`shellcheck`/etc.) is therefore **intentional, not a blocker** — the orchestrator never needs to run a project toolchain itself; it reads the plan, dispatches, and merges.

The gates are defined in **`config/quality-gates.txt`** — one gate per line. **Read that file; do not hardcode the gate list here.** It is the single source of truth. Pass the resolved gate list to each agent so every step is held to the same bar.

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

For each gate, the agent auto-detects the project's command (typecheck, lint, test, build, secret scan) and runs it against the step's changes inside its worktree. Lint includes `shellcheck` clean for any `.sh` change. Each agent reports its step's gate results back to the orchestrator:

```
Step S2 — quality gates (from config/quality-gates.txt):
  [✓/✗] Typecheck passes (zero errors)
  [✓/✗] Lint passes (zero errors; shellcheck clean for any .sh change)
  [✓/✗] All tests pass (existing + new)
  [✓/✗] No hardcoded secrets in the diff
  [✓/✗] No regressions in related functionality
  [✓/✗] Changes match the original requirements
```

A step **commits only when every gate passes** (the agent makes that commit in its worktree, below). If a gate fails, the step has failed — see failure isolation below.

---

## Step 5: Atomic commit in the worktree, then sequential merge-back

This is where one atomic, gated commit per step lands on the build branch. The work splits cleanly between the agent and the orchestrator — **the orchestrator never re-commits work it did not write; it merges.**

**5a — The agent commits, in its own worktree.** When a step's gates pass, the dispatched agent makes **exactly one atomic commit** of *its* changes on its worktree branch. The commit message references the unit, the step ID, and the brief AC IDs the step satisfies:

```
feat: unit $N S2 — <step summary> (AC-2, AC-3)
```

The agent does this with `git commit` inside its worktree. **Never `--no-verify`. Never bypass a quality gate.** The commit lands only after Step 4 is green. The agent then returns its **worktree branch name** and **commit hash** to the orchestrator. The orchestrator does **not** stage or commit these files — they are already committed.

**5b — The orchestrator merges each step's branch back, sequentially.** After every step in the wave has returned (committed in its worktree, or failed), the orchestrator merges the wave's step branches **one at a time** onto the build branch, in step order:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-worktree" ] && { echo "$c/bin"; break; }; done)
# For each successfully-committed step branch in the wave, in order:
for step_branch in "${WAVE_STEP_BRANCHES[@]}"; do
  # The helper owns the ff-only -> no-edit -> abort+report ladder; the
  # orchestrator just reacts to its exit code. Non-zero == conflict (the
  # helper has already aborted, leaving a clean tree).
  if ! "$gm/godmode-worktree" mergeback "$step_branch"; then
    echo "merge conflict on $step_branch — halting that step's subtree; reporting." >&2
    # Reap ONLY this failed step's worktree (targeted cleanup, $step_id its
    # worktree id/path) so the abandoned tree doesn't leak. This is the
    # failure-path reap — distinct from the Step 3 wave-start full sweep.
    "$gm/godmode-worktree" cleanup "$step_id"
    # Record the step as failed (its descendants are skipped — see Step 6).
    continue
  fi
done
```

Because the plan makes the steps in a wave **file-disjoint**, these sequential merges are clean in the normal case — `mergeback` fast-forwards when the build branch hasn't advanced and does a trivial no-edit merge otherwise. **On conflict** the helper aborts that single merge and exits non-zero; the orchestrator then **reaps that one failed step's worktree** with `godmode-worktree cleanup <id>` (a targeted reap of just that worktree, not the Step 3 full sweep), **halts that step's dependency subtree** (Step 6), and reports it — other steps and waves are unaffected.

**Reap on agent-abort too.** When a dispatched agent reports it cannot complete its step (gates won't pass, or it aborts) — not a merge conflict but a failure before any merge-back — apply the same targeted reap so the agent's abandoned worktree is cleaned up promptly rather than waiting for the next wave's Step 3 sweep:

```bash
# $step_id is the aborted step's worktree id/path.
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-worktree" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-worktree" cleanup "$step_id"
```

**5c — Record and advance.** The orchestrator records each merged step's commit hash, marks the step done (resumability, Step 6), and only then advances to the next wave. The next wave's worktrees are still SDK-rooted on `main`, but each agent's first-action `godmode-worktree create` (Step 3) merges the **now-updated** build-branch HEAD in — so no wave ever builds on a stale base.

---

## Step 6: Failure isolation and resumability

A failed step (gates won't pass, or its agent reports it cannot complete) **halts only its dependency subtree** — the steps that transitively declare `dependsOn` on the failed step — **not** unrelated waves or steps:

- **Compute the subtree to skip with `godmode-skipset`** instead of hand-walking `dependsOn`. Feed the plan's `dependsOn` adjacency — the same `STEP: dep1, dep2` mapping the orchestrator already parses to derive waves (Step 2) — on stdin to `godmode-skipset <failed-step>`. It emits the **transitive descendant closure** (every step that depends on the failed step directly or transitively, one ID per line, sorted and de-duplicated, excluding the failed step itself). Treat those emitted IDs as the exact set to skip. Resolve `$gm` exactly as the **Resolving the godmode helpers** note in Step 1 shows:

  ```bash
  # $failed is the failed step ID; the adjacency is the same STEP: deps mapping
  # used to derive waves (Step 2), one line per step ("S3: S1, S2" / "S1: none").
  gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-skipset" ] && { echo "$c/bin"; break; }; done)
  skip_ids=$(printf '%s\n' "$ADJACENCY" | "$gm/godmode-skipset" "$failed")
  # $skip_ids is the exact set of steps to skip — do NOT dispatch them.
  ```

- **Continue** running every other independent step and wave. Steps with no dependency on the failure proceed and commit normally.
- Report which step failed, why, and which descendant steps were skipped as a result (the `godmode-skipset` output).

Record **partial progress** so `/build` is **resumable** — a re-run picks up where it left off rather than redoing committed steps. The state file has exactly three keys (`active_unit`, `status`, `next_command`); the done-set is encoded **into `status`** using a fixed, parseable convention so no fourth key is needed:

```
status = "building <N> | done: <S-id>,<S-id>,..."
```

`building <N>` is the human-readable label; everything after ` | done: ` is the machine done-set — a comma-separated list of completed step IDs. The completion state uses `build complete` (Step 7). **This schema is owned by the `godmode-state` helper** — the orchestrator never parses or rebuilds the encoded list by hand; it calls the helper's `done` subcommands, which encode membership inside `status` while preserving the three-key invariant.

**Append a just-merged step to the done-set** with `godmode-state done add <step>`. The helper reads the current `status`, appends the step (idempotently — re-adding a member is a no-op), and writes it back, preserving the label prefix. Resolve `$gm` exactly as the **Resolving the godmode helpers** note in Step 1 shows; never hardcode or hand-parse the list:

```bash
# $step is the step ID that just merged (e.g. "S2").
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-state" done add "$step"
```

To **test membership** when deciding whether to skip a step on re-entry, use `godmode-state done has <step>` — it exits `0` when the step is already in the done-set (skip it) and `1` otherwise (run it). The helper does the comma-wrapped match so `S2` never matches `S20`:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
if "$gm/godmode-state" done has "$step"; then
  echo "skip $step — already done"
else
  echo "run $step"
fi
```

To **read the whole done-set** (e.g. to report resumable progress), use `godmode-state done list`, which prints the comma-separated set.

On a fresh `/build $N` (Step 1 re-entry contract), query the done-set via `godmode-state done has`/`done list`, **skip** every step already listed (their commits already exist and are merged), and resume with the first wave that still has incomplete steps. A re-run after a failure retries the failed subtree without touching the steps that already committed.

---

## Step 7: Record workflow state on completion

When every step has committed and merged back (or only a contained failed subtree remains, reported to the user), point the workflow forward via `bin/godmode-state`. The completion status records the unit so the Step 1 re-entry check can recognize an already-built unit:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-state" set active_unit "$N"
"$gm/godmode-state" set status "build complete | unit: $N"
"$gm/godmode-state" set next_command "/verify $N"
```

This lets `/godmode` tell the user the build is done and what to do next. On a later `/build $N`, Step 1 sees `build complete | unit: $N` (with `active_unit` matching `$N`) and reports there is nothing to build, offering `/verify $N`.

---

## Output

After building, report:

- The waves derived from `dependsOn` (and whether the plan's `## Waves` section agreed, was absent, or conflicted) and the steps in each.
- For each step: the agent dispatched (`@executor`/`@writer`), its gate results, the worktree commit hash, and how it merged back (fast-forward / merge / conflict).
- Any failed step (gate failure or merge conflict), the descendant steps skipped, and the resumable done-set recorded in `status`.
- The workflow state set and the next step:

> "Build complete for unit N. Run `/verify N` to check it against the plan."

---

## Related

- **/plan N** — preceding step: writes the `PLAN.md` (steps, `dependsOn`, `## Waves`) this skill executes.
- **/verify N** — next step: checks the built change against the plan's verification plan.
- **/debug** — when a step's quality gate fails and the cause isn't obvious.
- **/godmode** — reads the workflow state this skill records and tells the user the next command.

**Spine:** `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. Build runs the plan wave by wave in isolated worktrees, one atomic, gated commit per step.
