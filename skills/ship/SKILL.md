---
name: ship
description: "Run every canonical quality gate, push the branch, and open a pull request — release in one command. Use when: ship it, ready to ship, create the PR, push and open a PR."
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git *), Bash(gh *), Bash(gm=*), Bash(*godmode-state*), Bash(*godmode-model*), Bash(*godmode-findings*), Bash(*/skills/ship/scripts/gates.sh*), Bash(skills/ship/scripts/gates.sh*)
---

# Ship

Take a verified work unit to a pull request: run the canonical quality gates, then — only if every gate passes — push the branch and open a PR. This is the final step of the spine: `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → **`/ship`**.

`/ship` is side-effecting (it pushes and opens a PR), so it is **user-triggered only** (`disable-model-invocation: true`). It is never auto-invoked.

---

## Flags

- **`--no-push`** (aliases: `--dry-run`, `--local`) — run every quality gate **and the findings gate (Step 1b)**, prepare git readiness (commit), then **stop before the push and the PR**. Draft and print the PR title/body for review, but do **not** run `git push` or `gh pr create`, and do **not** record `status=shipped`. Use this to land a verified, committed, gate-green branch locally without publishing it. `--no-push` does **not** exempt the findings gate any more than it exempts the quality gates: open blocking findings BLOCK `--no-push` too (no commit), exactly as they BLOCK a normal ship.

When `--no-push` is set the confirmation prompt is moot — there is nothing side-effecting to confirm — so skip it and run the gates and git readiness straight through.

---

## Confirm by default

`/ship` **confirms with the user before the side-effecting steps** (the push and the `gh pr create`). After the gates pass and the PR body is drafted, show the branch, target, and PR title/body, then wait for explicit confirmation before pushing.

**Exception — Auto Mode.** When `## Auto Mode Active` is present in context, skip the confirmation prompt: proceed straight to push and PR create on the default choices, and treat any user course-correction as normal input. The quality-gate block (Step 1) **and the findings gate (Step 1b)** are never skipped, in either mode — Auto Mode skips only the confirmation, never a BLOCK. (The findings gate's waive escape is inherently conversational, so it still requires an explicit user-named ID + reason even under Auto Mode; Auto Mode never auto-waives.)

---

**Resolving the godmode helpers.** The `godmode-*` helpers live in the plugin install dir — **not** the consumer repo you're working in — so a bare `bin/godmode-*` path fails from another project's working directory. Every `bash` block below that calls one resolves its location into `$gm` first (plugin mode → `$CLAUDE_PLUGIN_ROOT/bin`, manual install → `~/.claude/bin`, in-repo → `./bin`) and calls `"$gm/godmode-<name>"`. Keep the resolver line; never call a helper by a bare relative path.

## Step 1: Quality gates (read from the canonical source)

The gates are defined in **`config/quality-gates.txt`** — one gate per line. **Read that file; do not hardcode the gate list here.** It is the single source of truth, so the gates stay in sync with the rest of the plugin.

Don't re-derive the gate-running loop: invoke the bundled **`skills/ship/scripts/gates.sh`**. It resolves `config/quality-gates.txt` across install modes (`${CLAUDE_PLUGIN_ROOT}/config` → `~/.claude/config` → repo-relative), reads the gate list, prints one labelled status line per gate, and exits non-zero if any gate fails. You supply the per-gate verdicts via `GATES_RUNNER`: a command `gates.sh` invokes once per gate as `$GATES_RUNNER "<gate text>"` — exit 0 = pass, non-zero = fail. Wire `GATES_RUNNER` to your auto-detected per-gate dispatcher: for each gate text, run the project's matching command (typecheck, lint, test, build, secret scan; lint includes `shellcheck` clean for any `.sh` change) and exit with its status.

Resolve the script the same way across install modes, then run it:

```bash
# Locate the bundled gate runner — plugin mode, manual install, then repo-relative.
GATES_SH=""
for cand in \
  "${CLAUDE_PLUGIN_ROOT:-}/skills/ship/scripts/gates.sh" \
  "$HOME/.claude/skills/ship/scripts/gates.sh" \
  "skills/ship/scripts/gates.sh"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { GATES_SH="$cand"; break; }
done
[ -n "$GATES_SH" ] || { echo "error: gates.sh not found" >&2; exit 1; }

# GATES_RUNNER is your auto-detected per-gate dispatcher: it receives one gate's
# text as $1, runs the project command that gate maps to, and exits 0 (pass) or
# non-zero (fail). gates.sh reads config/quality-gates.txt and calls it per gate.
# GATES_RUNNER must resolve to a single executable — a script path or a command
# name on PATH — NOT a shell function (invisible to the child process) and NOT a
# space-separated string like "bash runner.sh" (invoked as one token, so it
# would fail to find that file). Point it at an executable runner script.
GATES_RUNNER="$run_one_gate" bash "$GATES_SH"
```

`gates.sh` prints the report below; map each gate text to its detected command in your `GATES_RUNNER` dispatcher:

```
Quality gates (from config/quality-gates.txt):
  [✓/✗] Typecheck passes (zero errors)
  [✓/✗] Lint passes (zero errors; shellcheck clean for any .sh change)
  [✓/✗] All tests pass (existing + new)
  [✓/✗] No hardcoded secrets in the diff
  [✓/✗] No regressions in related functionality
  [✓/✗] Changes match the original requirements
```

**BLOCK on any failure.** If a gate fails: stop, report **which** gate failed and the error, and do **not** push or open a PR. Never `--no-verify`, never bypass a gate.

- Test / typecheck failures → use `/debug`.
- Lint → auto-fix where available, otherwise fix manually.
- Multi-file fixes → spawn `@writer`.

**Model profile.** Before spawning `@writer` (or any agent), resolve the active model profile from `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-balanced}`, then call the resolver `"$gm/godmode-model" <agent>` (resolve `$gm` as the **Resolving the godmode helpers** note above shows) to obtain the model for that agent under the active profile. Pass that model to the Agent tool's `model` override at spawn time. The resolver also reports the agent's effort, but **`effort` is frontmatter-only and is NOT set at spawn** (platform limitation — effort cannot be overridden when spawning an agent), so override **only** `model`; effort stays whatever the agent's frontmatter declares.

Re-run all gates after any fix until every one passes.

---

## Step 1b: Findings gate (load-bearing — blocks the ship)

Runs **only after** the Step 1 quality gates all pass, and **before** Step 2 git readiness. The verification loop persists confirmed, blocking findings to a tracked `FINDINGS.md` (via `/verify`); this gate is the door where they become load-bearing. An open, blocking finding blocks `/ship` exactly as a failing quality gate does — `FINDINGS.md` is enforcement, not advisory paperwork.

**Resolve the brief dir (same resolution `/ship` already uses for the PR body).** Find the active unit and mission, then glob the brief directory — the same dir that holds `FINDINGS.md`:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-findings" ] && { echo "$c/bin"; break; }; done)
active_unit=$("$gm/godmode-state" get active_unit)
mission_id=$("$gm/godmode-state" get mission_id)
NN=$(printf '%02d' "$active_unit" 2>/dev/null)
brief_dir=$(ls -d .planning/missions/${mission_id}/briefs/${NN}-* 2>/dev/null | head -1)
```

**Not applicable → skip.** If no active-unit `brief_dir` resolves, or it holds no `FINDINGS.md`, there are no findings to gate on: skip Step 1b and proceed to Step 2. This is the standalone-change case — consistent with `/ship` already omitting the PR's **Brief** section when there is no brief.

**Read the live blocking count — the gate's sole source of truth.** When a `brief_dir` with a `FINDINGS.md` resolves, read the count of open, blocking findings *now*, at gate time:

```bash
open_blocking=$("$gm/godmode-findings" count "$brief_dir" --blocking)
count_status=$?
```

The blocking predicate (`status==open AND (sev==CRITICAL OR conf==HIGH)`) is the frozen helper's authoritative definition — never re-derived here. This gate trusts the **live** count it just read. It does **not** read the verify-recorded `open_blocking` state key for the block decision: that key is **advisory only** (it lets `/godmode` surface the right next command), and a `/build N --fix` since the last `/verify` could have left it stale. The gate always computes its own count.

**Fail-closed.** If `count` exits non-zero (`count_status` != 0 — store unreadable or corrupt), treat the gate as **BLOCKED** and report the error. Never ship past a findings store you cannot read.

**Decision:**

- **`open_blocking == 0`** (and `count` succeeded) → the findings gate passes; proceed to Step 2.
- **`open_blocking > 0`** (or `count` failed) → **BLOCK**, with the same hard semantics as a failing quality gate: do **not** commit, do **not** `git push`, do **not** `gh pr create`, do **not** record `status=shipped`, and never `--no-verify` or otherwise bypass. **This BLOCK applies in both normal and `--no-push` mode** — `--no-push` does not exempt the findings gate any more than it exempts the quality gates (under `--no-push` the BLOCK means: do not even commit).

On BLOCK, report the blocking findings so the user can act:

```bash
"$gm/godmode-findings" list "$brief_dir" --open --blocking --decode
```

**The two escapes.** When blocked, present exactly two ways forward:

1. **Fix** — run `/build N --fix` to mechanically resolve the open findings, then re-`/verify` and re-`/ship`.
2. **Waive** — if a blocking finding is a genuine false positive, waive it (reason required).

**The waive is conversational — `/ship` never auto-waives.** `/ship` does **not** waive anything on its own and never invents or supplies a reason. **Only** when the user explicitly names a specific finding ID **and** a reason does `/ship` run the waive:

```bash
"$gm/godmode-findings" waive "$brief_dir" "<ID-the-user-named>" "<reason-the-user-gave>"
```

The helper rejects an empty reason (non-zero exit) — so a waive without a user-supplied reason cannot succeed. After each waive, **re-read the live count in the same invocation** and proceed the moment it reaches 0:

```bash
open_blocking=$("$gm/godmode-findings" count "$brief_dir" --blocking)
```

A multi-finding block clears by repeating this conversational waive per finding (or by `/build N --fix`) — there is no bulk-waive. Once the live count reaches 0, the gate passes and `/ship` proceeds to Step 2. Until then, the ship stays blocked.

---

## Step 2: Git readiness

- Commit or stash any uncommitted changes — the working tree must be clean before pushing.
- Confirm the branch is current with its base.
- Review the commit history: atomic commits, clear messages. If messy, suggest a rebase (ask first; never rewrite without consent).

**Force-push guard.** **Never force-push to `main` or `master`** (nor any protected base) without an **explicit user request**. A normal `/ship` uses a fast-forward `git push`; if a non-fast-forward push to a base branch is ever required, stop and ask the user to confirm in plain words before using `--force` / `--force-with-lease`.

---

## Step 3: Push and open the PR

**If `--no-push` is set:** stop here. Draft the PR title/body (see below) and print it for the user, then report that the branch is gate-green and committed but **not** pushed — skip Step 4 (do not record `status=shipped`). Tell the user to re-run `/ship` without `--no-push` when ready to publish.

After confirmation (or immediately, in Auto Mode):

```bash
branch=$(git branch --show-current)
# Guard: never ship FROM a base branch. If you're on main/master, you'd push
# the base itself — stop and ask the user to switch to a feature branch.
case "$branch" in
  main|master) echo "On base branch '$branch' — switch to a feature branch before /ship." >&2; exit 1 ;;
esac
git push -u origin "$branch"
```

Draft the PR body from the work unit. When a brief is present, **link it**: `.planning/missions/<mission_id>/briefs/NN-*/BRIEF.md` describes the why + what + spec for the active work unit (find it via `"$gm/godmode-state" get active_unit` and `mission_id=$("$gm/godmode-state" get mission_id)` (resolve `$gm` per the helper-resolution note above), then glob `.planning/missions/${mission_id}/briefs/NN-*/BRIEF.md`). Summarize the work unit in the PR body and reference the brief path.

```bash
gh pr create --title "<concise, <70 chars>" --body "$(cat <<'EOF'
## Summary
- What this work unit delivers and why (2-3 bullets)

## Brief
- .planning/missions/<mission_id>/briefs/NN-name/BRIEF.md (the why + what + spec)

## Changes
- The concrete changes in this branch

## Verification
- Quality gates passed (config/quality-gates.txt)
- How to verify
EOF
)"
```

If no brief exists (e.g. a standalone change), omit the **Brief** section and summarize the work directly.

Return the PR URL.

---

## Step 4: Record workflow state

On success, point the workflow forward via the single state source — `bin/godmode-state`:

```bash
gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
"$gm/godmode-state" set status "shipped"
"$gm/godmode-state" set next_command "/mission"
```

This lets `/godmode` tell the user the work unit shipped and what to do next.

---

## Output

After shipping, report:

- The gate results (all ✓).
- The pushed branch and the PR URL.
- The brief that was linked (if any).
- The workflow state recorded and the next step:

> "Shipped. PR opened at [URL]. Run `/mission` to pick up the next work unit."

---

## Related

- **/verify N** — preceding step: confirm the work unit meets its brief before shipping.
- **/debug** — when a quality gate fails.
- **/godmode** — reads the workflow state this skill records and tells the user the next command.

**Spine:** `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. Ship gates, pushes, and opens the PR — the last step before merge.
