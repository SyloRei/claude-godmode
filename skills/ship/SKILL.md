---
name: ship
description: "Run every canonical quality gate, push the branch, and open a pull request — release in one command. Use when: ship it, ready to ship, create the PR, push and open a PR."
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git *), Bash(gh *), Bash(bin/godmode-state*)
---

# Ship

Take a verified work unit to a pull request: run the canonical quality gates, then — only if every gate passes — push the branch and open a PR. This is the final step of the spine: `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → **`/ship`**.

`/ship` is side-effecting (it pushes and opens a PR), so it is **user-triggered only** (`disable-model-invocation: true`). It is never auto-invoked.

---

## Confirm by default

`/ship` **confirms with the user before the side-effecting steps** (the push and the `gh pr create`). After the gates pass and the PR body is drafted, show the branch, target, and PR title/body, then wait for explicit confirmation before pushing.

**Exception — Auto Mode.** When `## Auto Mode Active` is present in context, skip the confirmation prompt: proceed straight to push and PR create on the default choices, and treat any user course-correction as normal input. The quality-gate block (below) is never skipped, in either mode.

---

## Step 1: Quality gates (read from the canonical source)

The gates are defined in **`config/quality-gates.txt`** — one gate per line. **Read that file; do not hardcode the gate list here.** It is the single source of truth, so the gates stay in sync with the rest of the plugin.

```bash
# The canonical gate list — read it, don't assume it.
while IFS= read -r gate; do
  [ -n "$gate" ] || continue
  printf 'gate: %s\n' "$gate"
done < config/quality-gates.txt
```

For each gate, auto-detect the project's command (typecheck, lint, test, build, secret scan) and run it. Lint includes `shellcheck` clean for any `.sh` change. Report each gate's result:

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

Re-run all gates after any fix until every one passes.

---

## Step 2: Git readiness

- Commit or stash any uncommitted changes — the working tree must be clean before pushing.
- Confirm the branch is current with its base.
- Review the commit history: atomic commits, clear messages. If messy, suggest a rebase (ask first; never rewrite without consent).

**Force-push guard.** **Never force-push to `main` or `master`** (nor any protected base) without an **explicit user request**. A normal `/ship` uses a fast-forward `git push`; if a non-fast-forward push to a base branch is ever required, stop and ask the user to confirm in plain words before using `--force` / `--force-with-lease`.

---

## Step 3: Push and open the PR

After confirmation (or immediately, in Auto Mode):

```bash
branch=$(git branch --show-current)
git push -u origin "$branch"
```

Draft the PR body from the work unit. When a brief is present, **link it**: `.planning/briefs/NN-*/BRIEF.md` describes the why + what + spec for the active work unit (find it via `bin/godmode-state get active_unit`, then glob `.planning/briefs/NN-*/BRIEF.md`). Summarize the work unit in the PR body and reference the brief path.

```bash
gh pr create --title "<concise, <70 chars>" --body "$(cat <<'EOF'
## Summary
- What this work unit delivers and why (2-3 bullets)

## Brief
- .planning/briefs/NN-name/BRIEF.md (the why + what + spec)

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
bin/godmode-state set status "shipped"
bin/godmode-state set next_command "/mission"
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
