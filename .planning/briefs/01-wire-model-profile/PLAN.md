# Plan 01: Wire model_profile

**Updated:** 2026-05-25
**Brief:** .planning/briefs/01-wire-model-profile/BRIEF.md

## Steps
Each step is mechanical, names the files it touches, and references the brief
acceptance criteria it advances by ID.

### S1 — Create `bin/godmode-model` resolver
- **dependsOn:** none
- **Files:** `bin/godmode-model` (new, executable)
- **Criteria:** AC-1, AC-2, AC-3, AC-4, AC-5, AC-6
- **Change:** Bash-3.2-compatible POSIX-ish shell script (match `bin/godmode-state` style: `set -euo pipefail`, no GNU-only constructs, BSD-safe). Signature `godmode-model <agent> [profile]`:
  - If `profile` omitted, read `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-}`; if unset/empty/unrecognized → `balanced` (AC-6).
  - If `profile` given explicitly and not `quality|balanced|budget` → exit non-zero, message on stderr (AC-1).
  - Locate agent file: try `agents/<agent>.md` relative to the script's repo root, falling back to `$(dirname "$0")/../agents/<agent>.md` for installed layout. Unknown agent → exit non-zero on stderr (AC-1).
  - `balanced`: parse `model:` and `effort:` from the agent's frontmatter; print `<model> <effort>` (AC-2).
  - `quality`: code-writer allowlist `{writer, executor, test-writer}` → `opus high` (carve-out, AC-4); all other agents → `opus xhigh` (AC-3).
  - `budget`: any agent → `haiku default` (AC-5).
  - Print exactly one space-separated line to stdout, exit 0 (AC-1).

### S2 — Wire the resolver into the spine skills
- **dependsOn:** S1
- **Files:** `skills/build/SKILL.md`, `skills/verify/SKILL.md`, `skills/ship/SKILL.md`
- **Criteria:** AC-7
- **Change:** Add a short "Model profile" subsection to each: before spawning any agent, resolve the active profile and call `bin/godmode-model <agent>` to obtain the model, then pass that model to the Agent tool's `model` override at spawn. State explicitly that `effort` is frontmatter-only and is NOT set at spawn (platform limitation). Keep wording consistent across the three skills.

### S3 — Add `tests/model-profile.bats`
- **dependsOn:** S1
- **Files:** `tests/model-profile.bats` (new)
- **Criteria:** AC-8 (exercises AC-2, AC-3, AC-4, AC-5, AC-6)
- **Change:** bats suite (load `test_helper.bash`) asserting: balanced echoes frontmatter for `writer`/`reviewer`/`architect`; quality maps each non-code-writer to `opus xhigh`; quality maps `writer`/`executor`/`test-writer` to `opus high`; budget maps a sample of agents to `haiku default`; unset/empty/garbage `CLAUDE_PLUGIN_OPTION_MODEL_PROFILE` resolves to balanced; explicit bad profile arg and unknown agent both exit non-zero.

### S4 — Extend install completeness test
- **dependsOn:** S1
- **Files:** `tests/install.bats`
- **Criteria:** AC-10
- **Change:** Add `godmode-model` to the "install installs bin helpers" assertions (exists + executable). No `install.sh` edit needed — it already copies `bin/*` wholesale (install.sh:248).

### S5 — Fix README FAQ honesty paragraph
- **dependsOn:** S1
- **Files:** `README.md`
- **Criteria:** AC-9
- **Change:** Rewrite the "Current state (be honest)" paragraph (~README.md:442): model switching is now consumed at spawn via `bin/godmode-model` (model-only); keep the effort-is-frontmatter / not-runtime-overridable limitation explicit; remove the stale "nothing in the plugin yet consumes the value" sentence. Leave the preset table (lines 434–440) intact.

### S6 — Run full quality-gate suite
- **dependsOn:** S1, S2, S3, S4, S5
- **Files:** (none — verification)
- **Criteria:** AC-10
- **Change:** Run shellcheck on `bin/godmode-model`, then the repo gates: `scripts/lint-json.sh`, `scripts/lint-frontmatter.sh`, `scripts/check-version-drift.sh`, `scripts/check-parity.sh`, `scripts/check-vocab.sh`, `scripts/check-surface-count.sh`, and `bats tests/`. Fix any failures before declaring done.

## Waves (derived from dependsOn)
- **Wave 1:** S1 (dependsOn: none)
- **Wave 2:** S2, S3, S4, S5 (all dependsOn: S1 — run in parallel)
- **Wave 3:** S6 (dependsOn: S1, S2, S3, S4, S5)

## Verification plan
Every brief acceptance criterion, by ID, with how it is checked.

- **[AC-1]** — `bin/godmode-model writer balanced` prints one space-separated line, exit 0; `bin/godmode-model nosuch balanced` and `bin/godmode-model writer bogus` each exit non-zero with stderr text. Inspect via `echo $?` and stderr capture.
- **[AC-2]** — `bin/godmode-model writer balanced` → `opus high`; `... reviewer balanced` → `sonnet high`; `... architect balanced` → `opus xhigh`. Cross-check against each agent's frontmatter.
- **[AC-3]** — For each of `architect planner verifier security-auditor reviewer code-reviewer spec-reviewer doc-writer researcher`: `bin/godmode-model <a> quality` → `opus xhigh`.
- **[AC-4]** — `bin/godmode-model writer quality`, `... executor quality`, `... test-writer quality` each → `opus high` (never `xhigh`).
- **[AC-5]** — `bin/godmode-model <any-agent> budget` → `haiku default` for a sampled set.
- **[AC-6]** — With `CLAUDE_PLUGIN_OPTION_MODEL_PROFILE` unset, empty, and set to `garbage`, `bin/godmode-model writer` (no profile arg) → `opus high` (balanced) and exit 0 in all three cases.
- **[AC-7]** — `grep -n "godmode-model" skills/build/SKILL.md skills/verify/SKILL.md skills/ship/SKILL.md` shows the spawn-time wiring in all three; each file also states effort is frontmatter-only / not set at spawn.
- **[AC-8]** — `bats tests/model-profile.bats` passes; `bats tests/` (full suite) passes including the new file.
- **[AC-9]** — `grep -c "nothing in the plugin yet consumes" README.md` → 0; the rewritten paragraph mentions `bin/godmode-model` and retains the effort limitation. Inspect README.md FAQ.
- **[AC-10]** — Each gate script exits 0: `shellcheck bin/godmode-model`, `scripts/lint-json.sh`, `scripts/lint-frontmatter.sh`, `scripts/check-version-drift.sh`, `scripts/check-parity.sh`, `scripts/check-vocab.sh`, `scripts/check-surface-count.sh`, `bats tests/`. (CI runs the same on Ubuntu+macOS.)
- **[AC-11]** — MANUAL (real API spend, not CI-gated): set `model_profile=budget`, run a `/build`-style spawn of a code-writing agent on a trivial change, confirm it spawns with `model: haiku` and the agent's session cost is < $0.10. Recorded as evidence in `/verify 1`, not blocking.

## Assumptions
- Code-writer allowlist is exactly `{writer, executor, test-writer}` (from BRIEF assumption + README carve-out). All other agents get the `quality` → `xhigh` treatment.
- `balanced` reads live frontmatter from `agents/<name>.md` (single source of truth); the resolver does not hardcode the balanced table.
- Frontmatter parsing can rely on simple `model:`/`effort:` line grep within the first `---`…`---` block (every agent file follows this shape, confirmed across all 12).
- Resolver resolves its repo root from the script location so it works in both repo and installed (`~/.claude/`) layouts; agent files exist in both.
- AC-11 stays manual; no CI cost-measurement harness is built in this unit (cost tracking is unit 13 / P3.4).
