---
name: pr-describe
description: "Draft a PR description (summary / what changed / test plan) from the branch's commits and diff against the base branch. Off-spine helper, no agents."
user-invocable: true
allowed-tools: Bash, Read
---

# /pr-describe — draft a pull-request description

Compose a clear PR description from the branch's **commits** and **diff** against
its **base** branch. A reactive helper — it does not spawn agents and is not part
of the spine. (Pushing and opening the PR is `/ship`'s job; this only drafts the
body.)

---

## The Job

1. Resolve the base branch and the commit range.
2. Read the commits and the diff.
3. Draft summary / what changed / test plan.

---

## 1. Resolve base and range

Determine the base branch (the branch this one will merge into) and the range of
commits unique to the current branch:

```bash
BASE=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@')
BASE=${BASE:-main}
git log --oneline "$BASE"..HEAD     # commits on this branch
git diff --stat "$BASE"...HEAD      # files changed vs base
```

If the base cannot be resolved, ask the user which branch this PR targets.

## 2. Draft the description

Build the body from the commit subjects/bodies and the diff — the commits tell
you *why*, the diff tells you *what*:

```markdown
## Summary

One or two sentences: what this PR does and why it exists.

## What changed

- Bullet per logical change, grounded in the commits and diff.

## Test plan

- How the change was verified (gates run, tests added, manual steps).
```

Keep it terse and factual. Do not invent test steps that were not run — if you
cannot tell how it was tested, say so and ask. Print the description for the user
to paste when opening the PR.
