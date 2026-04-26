# Plan 02-01 Summary — Linter + rules

**Executed:** 2026-04-26
**Mode:** Inline
**Result:** ✓ All 2 tasks COVERED

## What landed

| Task | Commit | Files |
|---|---|---|
| 1.1 Effort Tier Policy + Connects-to Convention sections | 1cb43ad | rules/godmode-routing.md |
| 1.2 Pure-bash agent frontmatter linter | 934faad | scripts/check-frontmatter.sh (new) |

## Closes

- AGENT-01 (frontmatter convention locked) ✓
- AGENT-02 (effort tier policy + linter enforcement) ✓
- AGENT-06 (frontmatter linter ships) ✓

## Verification

`shellcheck scripts/check-frontmatter.sh` exits 0.
`bash scripts/check-frontmatter.sh` exits 1 against pre-modernization v1.x agents (correct — they need 02-03 to land first); exits 0 after Plans 02-02 + 02-03.
Synthetic CR-01 violator (xhigh + Write/Edit + no disallowedTools): linter flags `xhigh-with-write` and exits 1.

## Deviations

None.
