---
phase: 05-quality-ci-tests-docs-parity
reviewed: 2026-04-29T00:00:00Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - skills/build/SKILL.md
  - skills/mission/SKILL.md
  - skills/plan/SKILL.md
  - skills/ship/SKILL.md
  - skills/tdd/SKILL.md
  - skills/verify/SKILL.md
  - scripts/check-vocab.sh
  - .claude-plugin/plugin.json
  - tests/install.bats
  - CONTRIBUTING.md
findings:
  blocker: 0
  warning: 5
  info: 4
  total: 9
status: issues_found
---

# Phase 05 — Code Review (closure plans 05-04..05-07)

**Reviewed:** 2026-04-29
**Depth:** standard
**Scope:** Files changed by closure plans 05-04 (vocab gate), 05-05 (userConfig), 05-06 (bats CR-03), and 05-07 (CONTRIBUTING rewrite).
**Status:** issues_found — no BLOCKERs; 5 WARNINGs and 4 INFO-level concerns.

## Summary

The closure work mechanically meets every must-have in the four plans:

- `bash scripts/check-vocab.sh` exits 0 on the working tree (verified).
- `.claude-plugin/plugin.json` declares a well-formed `userConfig.model_profile` block matching CONTEXT D-26 / STACK.md.
- `tests/install.bats` Tests 7-10 invoke `hooks/session-start.sh` (not `post-compact.sh`), PATH-shim a fake `git`, and assert round-trip survival of the adversarial branch literal.
- `CONTRIBUTING.md` matches v2 reality: v1.4 file structure replaced; all 12 v2 agents named with correct (model, effort) tiers; `effort: max` removed; xhigh-Opus-4.7 pitfall documented; skill conventions correctly pointed at `rules/godmode-skills.md`.

No security vulnerabilities and no logic errors that would corrupt data or fail at runtime. The findings below cluster around three classes:

1. **Robustness in the new bats tests** — single-quote interpolation into `bash -c`, `BRANCH_LITERAL` propagation across `env`, and the `INPUT_JSON` shell-quoting risk are technically defensible against the current fixture set but fragile if fixtures are extended or the CI matrix grows.
2. **CONTRIBUTING.md drift** — the rule-file inventory table at lines 47-57 was not updated to list `godmode-skills.md` even though the rewritten Model Selection / New Skill sections now reference it. The table is now internally inconsistent.
3. **SKILL.md edges** — minor surface inconsistencies (duplicated guidance, self-referential vocab note) preserved through the scrub.

No BLOCKER-class defect was found.

## Warnings

### WR-01: `tests/install.bats` — `INPUT_JSON` is single-quoted into `bash -c` without sanitization

**File:** `tests/install.bats:192-193`
**Category:** Bug (robustness)
**Issue:**
```bash
run env "PATH=$FAKE_GIT_DIR:$PATH" "BRANCH_LITERAL=$BRANCH_LITERAL" \
  bash -c "printf '%s' '$INPUT_JSON' | bash '$REPO_ROOT/hooks/session-start.sh'"
```
`$INPUT_JSON` is interpolated into a double-quoted `bash -c` argument with the JSON wrapped in single quotes. `INPUT_JSON` derives from `jq -n --arg cwd "$STUB_PROJECT" '{cwd: $cwd}'`, where `$STUB_PROJECT` is a `mktemp -d` path. macOS and Linux `mktemp` paths today never contain single quotes, so the test passes; but the shell-quoting contract here is "no single quote in the interpolated value." If anyone later switches the stub-project root to a path under user control (e.g., `$HOME` for an ENV-driven test), the test silently breaks with a confusing parse error instead of a real assertion failure. This is the exact class of bug the FOUND-04 hardening was about — using `jq -n --arg` to avoid string interpolation into JSON. Here we're interpolating JSON into shell, but the principle is identical.

**Fix:**
Pass the JSON via stdin redirection rather than interpolating into the command line. Replace:
```bash
run env "PATH=$FAKE_GIT_DIR:$PATH" "BRANCH_LITERAL=$BRANCH_LITERAL" \
  bash -c "printf '%s' '$INPUT_JSON' | bash '$REPO_ROOT/hooks/session-start.sh'"
```
with a here-string:
```bash
run env "PATH=$FAKE_GIT_DIR:$PATH" "BRANCH_LITERAL=$BRANCH_LITERAL" \
  bash -c "bash '$REPO_ROOT/hooks/session-start.sh'" <<< "$INPUT_JSON"
```
(Bash 3.2 supports `<<<`.) This eliminates the single-quote-in-mktemp-path footgun entirely and also documents the data flow: input is "stdin to the hook," exactly as the production code path consumes it.

---

### WR-02: `tests/install.bats` — fake-git stub silently exits 1 on any unhandled subcommand

**File:** `tests/install.bats:131-159` (the `STUB` heredoc)
**Category:** Bug (robustness / test discipline)
**Issue:**
The fake-git stub's `case "$1"` only handles `rev-parse`, `branch`, and `log`. Every other invocation falls through to `exit 1`. `hooks/session-start.sh` only issues these three subcommands today, so the stub is sufficient. **However**, if `session-start.sh` is later extended (e.g., to read `git config user.email` for an author hint, or `git rev-parse HEAD` for a commit-SHA banner), the stub silently exits 1 on the new path. The test still PASSES because `git rev-parse --is-inside-work-tree` and `git branch --show-current` continue to succeed, the hook proceeds, the round-trip assertion holds — and the broken new code path is invisible. Tests give a false-positive PASS until someone manually re-reviews the hook.

**Fix:**
Add an explicit contract comment in the stub enumerating the subcommands session-start.sh is permitted to call. Better: have the default case write a marker file (e.g., `touch "$FAKE_DIR/unexpected-call-$1"`) and have the helper assert the marker is absent. This converts a silent skip into a loud failure if the contract drifts. Minimum-viable version:
```bash
case "$1" in
  rev-parse) ... ;;
  branch)    ... ;;
  log)       ... ;;
  *)
    # Stub contract: hooks/session-start.sh today calls only the three cases
    # above. Adding new git invocations to the hook requires extending this
    # stub or these tests will silently exit 1 on the unhandled subcommand.
    exit 1
    ;;
esac
```

---

### WR-03: `CONTRIBUTING.md` — rule-file inventory table at lines 47-57 omits `godmode-skills.md`

**File:** `CONTRIBUTING.md:46-57`
**Category:** Code quality (documentation drift)
**Issue:**
The "Existing rule files and their concerns" table lists 8 rule files (`godmode-identity.md` … `godmode-routing.md`). The actual `rules/` directory contains 9 files — `godmode-skills.md` exists and is referenced TWICE elsewhere in the same CONTRIBUTING.md (line 32: "Follow the conventions in `rules/godmode-skills.md`"; line 135: "see `rules/godmode-skills.md`"). A new contributor reads the New Skill section, follows the pointer to `godmode-skills.md`, then later checks the inventory and sees no such file documented — they assume one of the two is wrong and may file a spurious bug. Plan 05-07 Task 3 added the pointer to `rules/godmode-skills.md` but did not update the inventory table to match.

**Fix:**
Add a row to the inventory table at line 56-57:
```markdown
| `godmode-skills.md` | Skill frontmatter contract, Connects-to layout, Auto Mode detection, vocabulary discipline |
```
While editing, also tighten the `godmode-routing.md` row — it currently reads "Agent/skill routing and model selection," but skill conventions now live in `godmode-skills.md`. Update to "Agent routing (which agent does what); model-selection summary."

---

### WR-04: `CONTRIBUTING.md` — `shellcheck $(find …)` recipe breaks on filenames with whitespace

**File:** `CONTRIBUTING.md:103`
**Category:** Bug (documentation correctness)
**Issue:**
```bash
shellcheck $(find . -name '*.sh' -not -path './.git/*')
```
This unquoted command-substitution word-splits on `IFS` (default: space + tab + newline). The repo today has no shell scripts with spaces in their names, so the recipe works — but documenting an unsafe pattern in a CONTRIBUTING file is a bad signal: contributors copy-paste it into other contexts (their own repos) and get silently mis-globbed. Worse, this is the section where the doc says "mirror the CI gates locally" — if CI's `.github/workflows/ci.yml` uses a safer form, the local recipe diverges from CI behavior, undermining the "run these locally" promise.

**Fix:**
Document a `find -exec`/`xargs -0` form that survives whitespace and avoids word-splitting:
```bash
find . -name '*.sh' -not -path './.git/*' -exec shellcheck {} +
```
(`-exec … +` is POSIX and bash-3.2 portable.) Or, equivalently:
```bash
find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck
```

---

### WR-05: `tests/install.bats` — newline fixture relies on undocumented `env` newline-passthrough behavior

**File:** `tests/install.bats:174-192` (newline fixture path)
**Category:** Bug (portability)
**Issue:**
`jq -r '.branch_hint' newline.json` returns `feat/with` + literal newline + `newline` (17 bytes — verified). The test passes this through `env "BRANCH_LITERAL=$BRANCH_LITERAL"`. POSIX `execve(2)` permits newlines in environment values, and both Linux and macOS handle this correctly today — so the fixture survives end-to-end. However, this is one of the few cases where bats `run` semantics interact with `execve` quirks, and at least one `env` implementation (older BusyBox `env`, used in Alpine/some Docker contexts) has historically truncated values at the first `\n`. The CI matrix is `[ubuntu-latest, macos-latest]`, neither of which uses BusyBox, so the test passes today. But if the CI matrix ever extends to Alpine, Test 9 silently fails — `BRANCH_LITERAL` is truncated, the round-trip assertion `contains($lit)` returns false, and the diagnostic ("the test failed") doesn't point at `env` as the culprit. The fragility is invisible until it bites.

**Fix:**
Two options, in order of preference:
1. **Pass `BRANCH_LITERAL` via a tempfile, not env.** Refactor: write `printf '%s' "$BRANCH_LITERAL" > "$FAKE_DIR/branch_literal"` from the helper, and have the stub `cat "$(dirname "$0")/branch_literal"` instead of reading `$BRANCH_LITERAL`. This eliminates the env-passthrough roundtrip entirely.
2. **Document the dependency.** Add a comment near the `env` invocation: "Tests 7-10 require an `env` that preserves newlines in values (POSIX-compliant). Tested on Ubuntu, macOS. BusyBox env is not supported."

Preferred: option 1 — it removes the dependency rather than documenting it.

## Info

### IN-01: `skills/plan/SKILL.md` — Constraints "Task NN.M" wording diverges from `build`/`verify`/`ship`

**File:** `skills/plan/SKILL.md:158`
**Category:** Code quality (consistency)
**Issue:**
The Constraints section says: "The token 'Task NN.M' is the documented exception inside PLAN.md headings — see the @planner prompt above. The exception is local to PLAN.md structure (D-35); body prose still uses 'item' or 'step'." Meanwhile `skills/build/SKILL.md:246`, `skills/verify/SKILL.md:178`, and `skills/ship/SKILL.md:211` all close the equivalent constraint with "The CI vocabulary gate allowlists `task` for `skills/<name>/SKILL.md`." `plan/SKILL.md` does NOT add the equivalent allowlist sentence, even though the same per-file allowlist applies (`scripts/check-vocab.sh:50-54` uses a universal `skills/*/SKILL.md` match for `task`).

**Fix:**
Either align all four SKILL.md constraint blocks to the same template (preferred — readers learn the pattern once), or drop the Constraint entirely from `plan/SKILL.md` since it's not parsing PLAN.md heading text directly (the @planner agent does). Inconsistency is the actual smell here.

---

### IN-02: `skills/build/SKILL.md` / `verify/SKILL.md` — Constraint comment elides the universal-`task` rationale

**File:** `skills/build/SKILL.md:246`, `skills/verify/SKILL.md:178`
**Category:** Code quality (stale comment)
**Issue:**
The constraints in build and verify say "this skill body parses those headings, so the token unavoidably appears in awk patterns and grep arguments. The CI vocabulary gate allowlists `task` for `skills/<name>/SKILL.md`." This is true and accurate. However, `scripts/check-vocab.sh:38-48` documents a SECOND, broader rationale for the universal `task` allowlist: "every SKILL.md that spawns subagents necessarily references the Claude Code SDK `Task` tool by name." The SKILL.md constraint blocks only mention the narrower "we parse PLAN.md headings" reason, which is misleading: a contributor adding a new skill that spawns agents but doesn't parse PLAN.md headings might think the allowlist doesn't apply to them.

**Fix:**
None required (informational). For clarity, consider citing the broader Task-tool-collision rationale in one canonical SKILL.md and referencing it from the others.

---

### IN-03: `skills/mission/SKILL.md:194` — vocabulary-discipline note is now self-referential

**File:** `skills/mission/SKILL.md:194`
**Category:** Code quality (documentation)
**Issue:**
After the Plan 05-04 scrub, the line reads: "this skill body uses the v2 chain words (`brief`, `mission`, `milestone`, `plan`, `build`, `verify`, `ship`). The v1.x leakage tokens enumerated in `rules/godmode-skills.md` and enforced by the CI vocabulary gate must not appear in user-facing prose." But this sentence USES `milestone`, which is precisely why the per-file allowlist was added in Plan 05-04 Task 3. The sentence is structurally fine (the allowlist permits the word for this file), but the prose now reads as if `milestone` is a generic v2 chain word allowed everywhere — when in fact only `mission/SKILL.md` may use it.

**Fix:**
Tighten the wording to make the scoped-allowlist explicit:
```
this skill body uses the v2 chain words (brief, mission, plan, build, verify, ship)
plus `milestone` (the chain word above the brief level — surfaced in /mission's
Socratic flow at lines 77, 80; allowlisted ONLY for this file in scripts/check-vocab.sh).
```

---

### IN-04: `.claude-plugin/plugin.json:31` — `userConfig.model_profile.description` mixes user and plugin-author surfaces

**File:** `.claude-plugin/plugin.json:31`
**Category:** Code quality (API surface)
**Issue:**
The description reads: "Quality vs cost tradeoff for agent model selection. Substituted into hook commands as `${user_config.model_profile}` and exported as `CLAUDE_PLUGIN_OPTION_MODEL_PROFILE` to subprocesses." The first sentence is the user-facing meaning; the second sentence documents two implementation details (the substitution token and the env-var name) useful to plugin authors but irrelevant to end users running `claude --setting model_profile=quality`. Marketplace UIs render this description verbatim, so end users see a substring they cannot act on.

**Fix:**
Optional. The current description is correct, JSON-valid, and within the marketplace cap; leaving it is acceptable for v2.0. If trimmed in a follow-up, ensure README.md:84 still mentions the substitution token and env-var name so plugin authors retain the discoverability path.

---

_Reviewed: 2026-04-29_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Notes: All findings are non-blocking. The work meets every must-have in the four closure plans. Pre-existing issues in `hooks/session-start.sh` (e.g., `tr '\n' ' | '` is buggy — `tr` only takes single chars in this mode) were observed during analysis but are out of scope for this review (file unchanged in plans 05-04..05-07)._
