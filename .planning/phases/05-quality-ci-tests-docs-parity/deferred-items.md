# Deferred items — Phase 05

Out-of-scope discoveries logged during plan execution. NOT to be fixed in the originating plan; tracked here for later closure.

## Deferred-01 — `scripts/check-vocab.sh` reports 18 pre-existing violations on `main`

**Discovered during:** Plan 05-05 verification battery (the plan listed `bash scripts/check-vocab.sh; echo $?` outputs `0` as a guard-rail acceptance criterion).

**Reality on base** (`ae784b0`): the script exits `1` with 18 reported violations spanning `skills/build/SKILL.md`, `skills/mission/SKILL.md`, `skills/plan/SKILL.md`, `skills/ship/SKILL.md`, `skills/tdd/SKILL.md`, `skills/verify/SKILL.md`. The violations are flagged tokens like `phase:`, `milestone:` in skill prose — many are intentional (e.g., comments referencing Phase 1/2/3/5 of the dev process; the skills note that `Phase 5's vocabulary gate must whitelist 'task'/'phase' for parser regions`).

**Why deferred (per deviation rule scope boundary):** Plan 05-05 scope is the manifest only (`.claude-plugin/plugin.json`). The vocab-script issue is independent of the userConfig change — confirmed by `git stash`-ing the manifest change and re-running the script: same 18 violations. This is CR-03 (`scripts/check-vocab.sh` whitelist / vocab leakage in skill bodies) territory, owned by Plan 05-06.

**Verification:** `git stash; bash scripts/check-vocab.sh; echo $?` ⇒ exit 1 with identical 18 lines. Re-applied stash; manifest change does not touch the vocab surface.

**Owner:** Plan 05-06 or a future plan that re-scopes the vocabulary gate (whitelist regions, decide which tokens are intentional vs leakage).
