---
phase: 05-quality-ci-tests-docs-parity
plan: 05
subsystem: plugin-manifest
tags: [userConfig, model_profile, manifest, marketplace, CR-02, QUAL-05, QUAL-06]
gap_ids: ["CR-02"]
requirements: [QUAL-05, QUAL-06]
dependency_graph:
  requires:
    - .claude-plugin/plugin.json (existing 22-line v2.0.0 manifest)
    - scripts/check-version-drift.sh (must continue to exit 0)
  provides:
    - .claude-plugin/plugin.json:.userConfig.model_profile (documented user-tunable knob)
  affects:
    - README.md:84 (now describes a present-tense API that actually exists)
    - CHANGELOG.md:57 (the `userConfig.model_profile preserved` bullet becomes truthful)
tech_stack:
  added: []
  patterns:
    - jq-driven JSON mutation (no heredoc) preserves valid JSON
    - userConfig schema follows STACK.md plugin manifest spec verbatim
key_files:
  created: []
  modified:
    - .claude-plugin/plugin.json
decisions:
  - id: D-05-05-01
    decision: ADD userConfig.model_profile to manifest (do NOT remove README/CHANGELOG claims)
    rationale: CONTEXT D-26 explicitly says "preserve userConfig.model_profile"; the intent was always for the field to exist. README and CHANGELOG copy already describes the field correctly. Removing doc claims would lose a deliberate v2 design feature.
    source: 05-05-PLAN.md objective; CONTEXT D-26; STACK.md "Plugin manifest" row
metrics:
  duration_seconds: 141
  completed_date: 2026-04-28
  tasks_completed: 1
  files_modified: 1
---

# Phase 05 Plan 05: userConfig.model_profile Manifest Closure Summary

One-liner: Inject `userConfig.model_profile` (string, default `balanced`, options `quality|balanced|budget`) into `.claude-plugin/plugin.json` via `jq`, closing the documented-but-missing public API gap (CR-02) so README:84 and CHANGELOG:57 describe a field that actually exists.

## Goal

Close CR-02 from `05-VERIFICATION.md`: README.md:84 and CHANGELOG.md:57 advertised a `userConfig.model_profile` user-tunable knob that did not exist in `.claude-plugin/plugin.json`. Phase 1 D-26 said "preserve userConfig if present" — but Phase 1 had a gap (the field was never added in the first place), so "preserve" silently became "leave absent" while the docs described a present-tense API. A user following README:84 to set `model_profile` would have edited a non-existent field and `${user_config.model_profile}` substitutions would resolve to the empty string.

Path chosen: **ADD the userConfig block** (not REMOVE the doc claims), per the plan's `<objective>` rationale.

## Changes Made

### `.claude-plugin/plugin.json`

**Before** (22 lines, ended with `"license": "MIT" }`):
```json
{
  "name": "claude-godmode",
  "description": "Senior engineering team, in a plugin. One arrow chain (...).",
  "version": "2.0.0",
  "author": { "name": "sylorei", "url": "https://github.com/sylorei" },
  "keywords": [ "workflow", "agents", "skills", "hooks", "planning",
                "quality-gates", "auto-mode", "claude-code" ],
  "repository": "https://github.com/sylorei/claude-godmode",
  "homepage":   "https://github.com/sylorei/claude-godmode",
  "license":    "MIT"
}
```

**After** (35 lines; new `userConfig` object added after `license`, all other keys preserved unchanged):
```json
{
  "name": "claude-godmode",
  ...
  "license": "MIT",
  "userConfig": {
    "model_profile": {
      "type": "string",
      "default": "balanced",
      "options": ["quality", "balanced", "budget"],
      "description": "Quality vs cost tradeoff for agent model selection. Substituted into hook commands as ${user_config.model_profile} and exported as CLAUDE_PLUGIN_OPTION_MODEL_PROFILE to subprocesses."
    }
  }
}
```

**Diff stat:** `1 file changed, 13 insertions(+), 1 deletion(-)` (the deletion is the trailing `}` line repositioned, not a content removal).

**Mutation method:** `jq '. + { ... }'` piped to `mktemp` → `mv` (no heredoc; preserves valid JSON byte-for-byte).

## Tasks Completed

| Task | Name                                                                    | Commit  | Files                          |
| ---- | ----------------------------------------------------------------------- | ------- | ------------------------------ |
| 1    | Insert `userConfig.model_profile` block into `.claude-plugin/plugin.json` | 3bae12b | `.claude-plugin/plugin.json`   |

## Verification (closure assertion + rear-guard)

All commands run in working tree root after Task 1.

| Check | Command | Expected | Actual |
| ----- | ------- | -------- | ------ |
| field present       | `jq -e '.userConfig.model_profile' .claude-plugin/plugin.json` | exit 0 | exit 0 |
| `type`              | `jq -r '.userConfig.model_profile.type'` | `string` | `string` |
| `default`           | `jq -r '.userConfig.model_profile.default'` | `balanced` | `balanced` |
| `options` length    | `jq -r '.userConfig.model_profile.options \| length'` | `3` | `3` |
| `options` set       | `jq -r '.userConfig.model_profile.options \| sort \| join(",")'` | `balanced,budget,quality` | `balanced,budget,quality` |
| description length  | `jq -r '.userConfig.model_profile.description \| length'` | ≥ 50 | `182` |
| description has substitution token | `jq -r '...description' \| grep -F '${user_config.model_profile}'` | match | matches |
| valid JSON          | `jq empty .claude-plugin/plugin.json` | exit 0 | exit 0 |
| version preserved   | `jq -r '.version'` | `2.0.0` | `2.0.0` |
| description prose   | `jq -r '.description'` | unchanged tagline | unchanged |
| description ≤ 200   | `jq -r '.description \| length'` | ≤ 200 | `157` |
| keywords len        | `jq -r '.keywords \| length'` | `8` | `8` |
| license             | `jq -r '.license'` | `MIT` | `MIT` |
| version-drift gate  | `bash scripts/check-version-drift.sh` | exit 0 (`[+] no version drift`) | exit 0 |
| README still claims | `grep -F 'userConfig.model_profile' README.md` | ≥ 1 match | 1 match |
| CHANGELOG still claims | `grep -F 'userConfig.model_profile' CHANGELOG.md` | ≥ 1 match | 1 match |

All success criteria from the plan satisfied.

## Deviations from Plan

None of the auto-fix rules (1, 2, 3) triggered. Plan executed exactly as written.

The plan's acceptance criteria included a guard-rail check `bash scripts/check-vocab.sh; echo $?` outputs `0`. The script exits `1` on the current main with **18 pre-existing violations** in `skills/{build,mission,plan,ship,tdd,verify}/SKILL.md` — verified pre-existing on base by `git stash`-ing the manifest change and re-running. This is independent of `.claude-plugin/plugin.json` (the manifest is not in the vocab surface). Logged as **Deferred-01** in `.planning/phases/05-quality-ci-tests-docs-parity/deferred-items.md`. Owner: Plan 05-06 (CR-03) or a future plan that re-scopes the vocabulary gate.

Per the executor scope boundary: only auto-fix issues directly caused by the current task's changes; the vocab failures are unrelated to this plan's manifest mutation.

## Threat Model Check

| Threat ID | Disposition | Status |
|-----------|-------------|--------|
| T-05-05-01 (Tampering: malformed JSON) | mitigate | jq-driven mutation; `jq empty` exits 0; manifest still parses |
| T-05-05-02 (Repudiation: 'preserved' claim) | mitigate | Field now exists → CHANGELOG bullet is truthful as of this commit |
| T-05-05-03 (Info disclosure: description visible) | accept | Description is documentation, not secret; same content already in README:84 |
| T-05-05-04 (EoP: env var becomes user-controlled) | accept | Pre-existing manifest contract; this plan adds schema only, not the substitution mechanism |

No new threat surface introduced. No `Threat Flags` to report.

## Self-Check: PASSED

- `[ -f .claude-plugin/plugin.json ]` → FOUND
- `git log --oneline --all | grep -q 3bae12b` → FOUND (commit `3bae12b feat(05-05): add userConfig.model_profile to plugin.json (CR-02)`)
- `[ -f .planning/phases/05-quality-ci-tests-docs-parity/05-05-SUMMARY.md ]` → FOUND (this file)
- `[ -f .planning/phases/05-quality-ci-tests-docs-parity/deferred-items.md ]` → FOUND (Deferred-01 logged)
