---
phase: 05-quality-ci-tests-docs-parity
reviewed: 2026-04-28T23:55:00Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - .claude-plugin/plugin.json
  - .github/workflows/ci.yml
  - CHANGELOG.md
  - CONTRIBUTING.md
  - README.md
  - scripts/check-parity.sh
  - scripts/check-vocab.sh
  - tests/fixtures/branches/apostrophe.json
  - tests/fixtures/branches/backslash.json
  - tests/fixtures/branches/newline.json
  - tests/fixtures/branches/quote.json
  - tests/install.bats
findings:
  critical: 4
  warning: 8
  info: 5
  total: 17
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-04-28T23:55:00Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

Phase 5 ships CI workflow, parity/vocab gates, bats smoke tests, branch-name fixtures, and the v2 docs trio (README, CHANGELOG, CONTRIBUTING). The mechanical gates themselves (`scripts/check-parity.sh`, JSON fixtures) are correct and pass. The vocabulary gate works but is currently failing on legitimate dev-side text in shipped SKILL.md files, so wiring it into CI as written will hard-fail the next push to `main` (BLOCKER CR-01).

Two larger problems sit in the docs/test contract:

1. **README claims a `userConfig.model_profile` user-tunable knob** that is **not present in `plugin.json`** (CR-02). This is a documented public API that does not exist.
2. **The four "adversarial branch" bats tests do not actually exercise an adversarial branch path** (CR-03) — the hook under test (`hooks/post-compact.sh`) never reads the `branch_hint` field that distinguishes the four fixtures from each other. All four tests reduce to a single "stdin is valid JSON" smoke check, defeating QUAL-07's stated goal of guarding the CONCERNS #6 regression class.

CONTRIBUTING.md is materially out of date (CR-04, WR-04..WR-06): it shows the `v1.4` file-structure block, omits `scripts/`, `tests/`, `bin/`, `templates/`, `.github/`, claims an `effort: max` field the project does not use, lists only 8 of 12 agents, and contradicts the CLAUDE.md effort policy for code-writing agents. Anyone following CONTRIBUTING to add a new agent today will end up with the wrong frontmatter shape.

The CI workflow has two latent gaps: `jq` is never explicitly installed (BLOCKER-adjacent — relies on GitHub-hosted-runner pre-install, undocumented), and the `bats` job has no `shell: bash` or shellcheck step gating for the new scripts to fail fast on macOS-only regressions.

## Critical Issues

### CR-01: `scripts/check-vocab.sh` will hard-fail CI on `main` immediately after merge

**File:** `scripts/check-vocab.sh:72-86`, run on current `skills/*/SKILL.md` content
**Issue:**
Running the gate against the current tree produces 18 violations and `exit 1`:

```
[!] skills/build/SKILL.md:34: phase: ...
[!] skills/build/SKILL.md:115: phase: ...
[!] skills/mission/SKILL.md:77: milestone: ...
[!] skills/plan/SKILL.md:128: phase: ...
[!] skills/ship/SKILL.md:132: phase: ...
[!] skills/tdd/SKILL.md:68: phase: ...
[!] skills/verify/SKILL.md:43: phase: ...
[x] 18 vocabulary/surface violation(s) — see above
```

`.github/workflows/ci.yml:43-49` wires this script as a required job on every push to `main` and every PR. As soon as this PR merges, every subsequent CI run on `main` will be red until either the SKILL.md bodies are scrubbed of `phase`/`milestone` references or the gate is loosened. This is a mechanical contradiction between the gate and the corpus it gates.

The `task` allowlist for `skills/*/SKILL.md` (lines 49-54) was extended after a "Rule-1 fix"; the same per-file mechanism needs to be applied to `phase`/`milestone` for skills that legitimately reference dev-side milestones (or those references must be removed).

**Fix:** Either (a) extend the allowlist to cover the legitimate dev-cross-references the SKILL bodies make:

```bash
case "$rel" in
  skills/build/SKILL.md|skills/ship/SKILL.md|skills/verify/SKILL.md|skills/plan/SKILL.md|skills/tdd/SKILL.md)
    allowed="$allowed phase" ;;
esac
case "$rel" in
  skills/mission/SKILL.md)
    allowed="$allowed milestone" ;;
esac
```

OR (b) scrub `Phase 3 D-01`-style cross-references out of every shipped SKILL.md and replace with brief-shaped equivalents. The current state (gate active, corpus dirty) ships a broken `main`.

### CR-02: README documents a `userConfig.model_profile` knob that does not exist in `plugin.json`

**File:** `README.md:84`, `CHANGELOG.md:57`, `.claude-plugin/plugin.json:1-22`
**Issue:**
README:84 states:

> **One user-tunable knob:** `userConfig.model_profile` in `.claude-plugin/plugin.json` selects `quality | balanced | budget`. Substituted into hook commands as `${user_config.model_profile}` and exported as `CLAUDE_PLUGIN_OPTION_MODEL_PROFILE` to subprocesses.

CHANGELOG.md:57 confirms it as a "preserved" v2 feature:

> `.claude-plugin/plugin.json` — description and keywords polished for marketplace SEO; version bumped to 2.0.0; `userConfig.model_profile` preserved. (QUAL-06)

Actual `.claude-plugin/plugin.json` has no `userConfig` block at all. The plugin.json is 22 lines and contains only `name`, `description`, `version`, `author`, `keywords`, `repository`, `homepage`, `license`. Users following the README to set `model_profile` will edit a nonexistent field and find no behavior change. The hook command substitution `${user_config.model_profile}` referenced in README will resolve to the empty string under the actual manifest.

**Fix:** Either add the missing `userConfig` block to `plugin.json` (and verify hook commands actually substitute it):

```json
{
  ...
  "license": "MIT",
  "userConfig": {
    "model_profile": {
      "type": "string",
      "default": "balanced",
      "enum": ["quality", "balanced", "budget"],
      "description": "Model selection profile"
    }
  }
}
```

OR remove the bullet from README:84 and the CHANGELOG:57 line. Pick one and reconcile.

### CR-03: Adversarial-branch bats tests don't actually test branch-name handling

**File:** `tests/install.bats:117-147`, `tests/fixtures/branches/{quote,backslash,newline,apostrophe}.json`, `hooks/post-compact.sh`
**Issue:**
The four fixtures all carry the same `cwd` and `hook_event_name`; they differ only in a `branch_hint` field, e.g.:

```json
{"cwd":"/tmp/repo","hook_event_name":"PostCompact","trigger":"manual","branch_hint":"feat/with\"quote"}
```

`hooks/post-compact.sh` does not reference `branch_hint` anywhere. It reads only `.cwd` (line 13). Branch name is computed by `hooks/session-start.sh` via `git branch --show-current`, never by `post-compact.sh`. So all four tests run the identical code path, see the identical `cwd` (`/tmp/repo`), and reduce to "did stdin parse as JSON and did the hook emit JSON?" — a single smoke check, repeated four times, that never touches the adversarial-branch class CONCERNS #6 was about.

The CONCERNS #6 regression was about JSON construction injecting branch names through `jq -n --arg`. To exercise that, the fixture must drive a code path that *includes the branch name in emitted JSON*. As written, the four fixtures are pure decoration.

**Fix:** Either (a) make `post-compact.sh` consume `.branch_hint` from stdin and include it in `additionalContext` (so the four fixtures actually exercise four different code paths), and assert in each test that the emitted JSON correctly preserves the adversarial branch literal — e.g.:

```bash
@test "hook fixture: branch name contains \"" {
  FIXTURE="$REPO_ROOT/tests/fixtures/branches/quote.json"
  run bash -c "cat '$FIXTURE' | bash '$REPO_ROOT/hooks/post-compact.sh'"
  [ "$status" -eq 0 ]
  # Validate JSON is well-formed AND the literal branch survived round-trip
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("feat/with\"quote")' >/dev/null
}
```

OR (b) drive `session-start.sh` directly with a fake-git-repo fixture (mock `git branch --show-current` output via `PATH` shim) so the actual JSON-construction path is exercised. The current shape gives a green CI light without testing what FOUND-04/QUAL-07 promised.

### CR-04: CONTRIBUTING.md "File Structure (v1.4)" block is materially wrong for v2

**File:** `CONTRIBUTING.md:61-75`
**Issue:**
The shipped tree is a v2.0.0 plugin; CONTRIBUTING shows a `v1.4` file structure that:

- Omits `.claude-plugin/plugin.json` (the canonical version SoT — locked in CLAUDE.md)
- Omits `scripts/` (4 CI lint scripts — central to Phase 5)
- Omits `tests/` (bats smoke tests, fixtures)
- Omits `.github/workflows/ci.yml` (5-gate CI)
- Omits `config/quality-gates.txt` (single source of truth for the 6 gates)
- Omits `templates/.planning/` (artifact templates)
- Omits `bin/` (referenced in PROJECT.md/STACK.md as planned)

A new contributor following this section to "add a hook" or "add a skill" will not know the version-drift script will fail their PR if they bump a literal anywhere except `plugin.json`. They will not run the CI gates locally. They will not see the parity contract.

**Fix:** Replace the `(v1.4)` block with a v2 layout:

```markdown
## File Structure (v2.0)

```
claude-godmode/
  .claude-plugin/
    plugin.json          # canonical version + manifest
  agents/                # 12 agent definitions
  commands/              # /godmode (1 command file in v2)
  config/
    quality-gates.txt    # canonical gate list (single source)
    settings.template.json
    statusline.sh
  hooks/                 # 4 hook scripts + hooks.json
  rules/                 # godmode-*.md → ~/.claude/rules/
  scripts/               # CI lint gates (shellcheck-clean)
    check-frontmatter.sh
    check-parity.sh
    check-version-drift.sh
    check-vocab.sh
  skills/                # 14 skills (11 v2 + 3 v1.x deprecated)
  templates/.planning/   # artifact templates
  tests/                 # bats smoke + fixtures
  .github/workflows/     # ci.yml
  install.sh
  uninstall.sh
```

(Update agent/skill counts, drop the `(v1.4)` heading, drop `effort: max` references — see WR-05.)

## Warnings

### WR-01: `LC_ALL=C` set without `export` in `check-vocab.sh` and `post-compact.sh`

**File:** `scripts/check-vocab.sh:89`, `hooks/post-compact.sh:18`
**Issue:**
```bash
LC_ALL=C
```
This sets the variable in the current shell but does NOT export it to subprocesses. `grep`, `find`, `awk`, `sort` invocations after this line run with whatever `LC_ALL` was inherited from the environment (often `en_US.UTF-8` on macOS, which gives different `\b` word-boundary semantics than `C` for non-ASCII). The intent of pinning `LC_ALL=C` is to get deterministic byte-level matching; without `export`, that intent is silently violated.

**Fix:**
```bash
export LC_ALL=C
```

OR per-command:
```bash
LC_ALL=C grep -iqE "\\b${token}\\b"
LC_ALL=C find ...
```

### WR-02: CI workflow does not explicitly install `jq` on either runner

**File:** `.github/workflows/ci.yml`
**Issue:**
`scripts/check-version-drift.sh`, `scripts/check-frontmatter.sh`, `scripts/check-parity.sh`, and the bats settings-merge test (`tests/install.bats:97-113`) all require `jq` 1.6+. The workflow installs `bats-core` explicitly but not `jq`. This works *today* because GitHub-hosted `ubuntu-latest` and `macos-latest` images ship `jq` pre-installed, but that is not contractual — it can change in any image refresh. The runtime dependency contract (CLAUDE.md: "bash 3.2+ and `jq` 1.6+ only") should be mirrored explicitly in CI.

**Fix:** Add an explicit step to each job that uses jq:

```yaml
- name: Install jq
  run: |
    if [ "$RUNNER_OS" = "macOS" ]; then
      brew install jq || true   # may already be present
    else
      sudo apt-get update && sudo apt-get install -y jq
    fi
```

OR consolidate into a setup composite action. Same applies to `shellcheck` for jobs that don't use `ludeeus/action-shellcheck@master`.

### WR-03: bats Test 4 `--force` path tests two assertions but only checks `status`

**File:** `tests/install.bats:64-77`
**Issue:**
The test asserts uninstall refuses on version mismatch (lines 71-73) — good. Then it runs `uninstall.sh --force` and asserts `status -eq 0` (lines 75-76). It does NOT assert the post-condition (`! [ -f "$HOME/.claude/.claude-godmode-version" ]`). If `--force` silently no-ops, this test still passes. The whole point of `--force` is that the marker gets removed; that needs explicit assertion.

**Fix:**
```bash
run bash "$REPO_ROOT/uninstall.sh" --force
[ "$status" -eq 0 ]
[ ! -f "$HOME/.claude/.claude-godmode-version" ]
```

### WR-04: CONTRIBUTING.md model-selection guidance contradicts CLAUDE.md and the actual agents

**File:** `CONTRIBUTING.md:86-106`
**Issue:**
CONTRIBUTING describes a four-tier strategy:
- "Opus + high effort: @architect, @security-auditor"
- "Opus + default effort: @writer, @executor"
- "Sonnet + high effort: @reviewer, @test-writer, @doc-writer"
- "Sonnet + default effort: @researcher"

Reality from `agents/*.md` frontmatter:
- `@architect: opus xhigh`, `@security-auditor: opus xhigh`, `@planner: opus xhigh`, `@verifier: opus xhigh`
- `@executor: opus high`, `@writer: opus high`, `@test-writer: opus(?) high`
- `@code-reviewer: ? high`, `@reviewer: ? high`, `@spec-reviewer: ? high`
- `@researcher: ? high` (NOT default)
- `@planner`, `@verifier`, `@spec-reviewer`, `@code-reviewer` are absent entirely from CONTRIBUTING

CLAUDE.md says explicitly: "Opus 4.7 — `@executor`, `@writer`. Effort: `high` (NOT `xhigh` — `xhigh` skips rules on Opus 4.7, see PITFALLS)." CONTRIBUTING calls this same tier "Opus + default effort" and never mentions the rule-skipping pitfall.

A contributor following CONTRIBUTING to add a new code-writing agent will set no `effort` field (default), miss the `xhigh` pitfall context, and produce frontmatter inconsistent with the rest of `agents/`.

**Fix:** Rewrite §"Model Selection" against the actual tiers from CLAUDE.md "Default model assignments (v2)". Include the `xhigh`-skips-rules pitfall verbatim. Enumerate all 12 agents.

### WR-05: CONTRIBUTING.md references `effort: max`, which is not a valid value

**File:** `CONTRIBUTING.md:106`
**Issue:**
> "**Note:** `effort: max` is an Opus-exclusive setting. Do not assign it to Sonnet agents. Most agents should use `high` or omit the field (default). Reserve `max` for edge cases…"

The Claude Code subagent contract documents `effort` as `low | medium | high | xhigh` (per CLAUDE.md research). `max` is not in the project agents anywhere — `grep -r "effort: max" agents/` returns nothing. The actual Opus-exclusive level the project uses is `xhigh`. CLAUDE.md says: "Opus — `@architect`, `@security-auditor`, `@planner`, `@verifier`. Effort: `xhigh`". CONTRIBUTING is teaching a value the codebase rejects.

**Fix:** Replace every occurrence of `effort: max` with `effort: xhigh`. Add a sentence: "`xhigh` skips rules on Opus 4.7 — do NOT use it on code-writing agents (`@executor`, `@writer`, `@test-writer`); use `high` there." Keep the don't-use-on-Sonnet caveat if accurate, but verify against current Anthropic docs.

### WR-06: CONTRIBUTING.md missing routing entries are referenced as required

**File:** `CONTRIBUTING.md:24, 30`
**Issue:**
CONTRIBUTING tells contributors to add agents and skills via "a routing entry in `rules/godmode-routing.md` under 'When to Use What'". `rules/godmode-routing.md` exists, but the file's first line is:
```
> See `rules/godmode-skills.md` for skill frontmatter convention, Auto Mode detection, and Connects-to chain rendering.
```

So skill conventions live in `godmode-skills.md`, not `godmode-routing.md`. CONTRIBUTING points contributors at the wrong file for skills (they need to know the frontmatter contract before editing routing). Also: CONTRIBUTING never mentions `rules/godmode-skills.md` exists.

**Fix:** Update CONTRIBUTING §"New Skill" to:
1. Show frontmatter convention (cite `rules/godmode-skills.md`)
2. Add routing entry in `rules/godmode-routing.md`
3. Confirm vocab gate passes (`bash scripts/check-vocab.sh`)
4. Confirm parity gate passes if hook bindings change

### WR-07: README "Hooks not firing — Re-run ./install.sh to re-merge" misleads when settings.json has unrelated user keys

**File:** `README.md:94`
**Issue:**
Test 6 in `tests/install.bats:91-114` covers exactly the case where `~/.claude/settings.json` has user-added top-level keys that should survive. The README troubleshooting bullet says "Re-run `./install.sh` to re-merge" which is correct *if* deep-merge actually preserves user keys. The CHANGELOG line for QUAL-07 says it does. But a user reading README:94 won't know the merge is deep — and the install.sh prompt may still ask `[d/s/r/a/k]` for `settings.json` if it differs from template, which under non-TTY default = keep, will leave hooks NOT re-merged. README:94's advice is incomplete.

**Fix:** Reword to:
```
- **Hooks not firing** — verify `~/.claude/settings.json` has the `hooks` block.
  Re-run `./install.sh --force` to forcibly re-merge if a prior run kept your
  customized settings. The merge is deep — your other top-level keys survive.
```

### WR-08: `check-parity.sh` jq normalization regex is fragile to leading/trailing braces

**File:** `scripts/check-parity.sh:28-31`
**Issue:**
```jq
gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; "~/.claude")
```
This substitutes `${CLAUDE_PLUGIN_ROOT}` literally. It does not match `$CLAUDE_PLUGIN_ROOT` (no braces) or `${CLAUDE_PLUGIN_ROOT }` (trailing space). If a future hook entry uses the unbraced form (which is valid in shell and might creep in), parity will silently report drift. The current corpus uses braces consistently, so this works *today*, but the gate should fail closed on form changes.

**Fix:** Either (a) extend the regex to match both forms:
```jq
gsub("\\$\\{?CLAUDE_PLUGIN_ROOT\\}?"; "~/.claude")
```
OR (b) add a separate sanity check in `check-parity.sh` that asserts every `command` string in `hooks/hooks.json` starts with `bash ${CLAUDE_PLUGIN_ROOT}/hooks/` (form-locked), so only the braced form is ever generated.

## Info

### IN-01: `tests/install.bats` `setup()` doesn't `unset` other Claude-related env vars

**File:** `tests/install.bats:10-16`
**Issue:**
`setup()` sets `HOME` to a tempdir but doesn't `unset CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_SESSION_ID`, etc. If a developer runs `bats tests/install.bats` from inside a Claude Code session that exports these, the install/uninstall scripts may take plugin-mode branches mid-test. Belt-and-suspenders.

**Fix:**
```bash
setup() {
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_SESSION_ID
  ...
}
```

### IN-02: `check-vocab.sh` `lint_file` `awk` could replace the per-token grep loop

**File:** `scripts/check-vocab.sh:60-86`
**Issue:**
The current shape calls `printf '%s\n' "$line" | grep -iqE` six times per line per file (one per token), plus once for `gsd-*`. For a typical SKILL.md (~250 lines × 7 calls = 1750 grep invocations per file, × 14 skill files), this is fork-heavy on macOS. Not a correctness bug — out of v1 scope per review-scope rules — but worth noting for a future pass: a single `awk` filter against all 7 tokens would be one process per file.

**Fix:** Out of v1 scope. Optional: collapse into a single regex `grep -iqE '\\b(phase|task|story|prd|cycle|milestone|gsd-[a-z])\\b'` and post-classify the matches.

### IN-03: README §"What you get" prose drifts from CHANGELOG list of changes

**File:** `README.md:31`, `CHANGELOG.md:30-77`
**Issue:**
README:31 ends "Plugin-mode and manual-mode installs are parity-tested in CI." Good. But the list of new things (PostToolUse hook, bats matrix, frontmatter linter, version-drift, vocab gate) is buried in CHANGELOG only. Users browsing README won't see what's new in v2 unless they click through. Minor — not load-bearing.

**Fix:** Optional: add a "What's new in v2.0" subsection between "Quick start" and "What you get", or keep CHANGELOG as the authority. Pick one.

### IN-04: bats Test 6 doesn't validate that `hooks` block was merged from template

**File:** `tests/install.bats:97-113`
**Issue:**
Line 112-113:
```bash
run jq -e '.hooks.SessionStart' "$HOME/.claude/settings.json"
[ "$status" -eq 0 ]
```
This asserts `.hooks.SessionStart` exists, but doesn't assert that other hook events (`PreToolUse`, `PostToolUse`, `PostCompact`) are also present. A regression that drops 3 of 4 hooks during merge would still pass this test.

**Fix:**
```bash
run jq -e '.hooks | has("SessionStart") and has("PreToolUse") and has("PostToolUse") and has("PostCompact")' "$HOME/.claude/settings.json"
[ "$status" -eq 0 ]
[ "$output" = "true" ]
```

### IN-05: CHANGELOG.md says "tests/fixtures/hooks/setup-fixtures.sh + 5 placeholder fixtures" but Phase 5 ships `tests/fixtures/branches/` (not `hooks/`)

**File:** `CHANGELOG.md:21`
**Issue:**
CHANGELOG line 21 (under "Foundation") credits FOUND-04 with creating `tests/fixtures/hooks/setup-fixtures.sh + 5 placeholder fixtures (cwd-{normal,quote-branch,backslash-branch,newline-branch,apostrophe-branch}.json)`. Phase 5 shipped `tests/fixtures/branches/{quote,backslash,newline,apostrophe}.json` (4 fixtures, different path, different filenames). The CHANGELOG describes the Foundation-phase substrate that may have been reorganized in Phase 5. Either this paragraph should be updated to reference the actual final paths, or the older substrate should also still exist. `.gitignore` line 16 (`tests/fixtures/hooks/cwd-*.json`) suggests the older fixtures were expected to be generated and gitignored — confirm whether `tests/fixtures/hooks/setup-fixtures.sh` actually still exists, since it's claimed in the CHANGELOG.

**Fix:** Either (a) verify `tests/fixtures/hooks/setup-fixtures.sh` exists and the 5 placeholder fixtures generate correctly; or (b) update CHANGELOG line 21 to reflect the final Phase-5 shape (`tests/fixtures/branches/*.json`, 4 fixtures, no setup script needed because they're checked-in static files).

---

_Reviewed: 2026-04-28T23:55:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
