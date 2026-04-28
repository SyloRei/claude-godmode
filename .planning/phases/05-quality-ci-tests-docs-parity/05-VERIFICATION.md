---
phase: 05-quality-ci-tests-docs-parity
verified: 2026-04-28T00:00:00Z
status: gaps_found
score: 1/5 must-haves verified
overrides_applied: 0
gaps:
  - truth: "SC #1 — `.github/workflows/ci.yml` exists; on a fresh push, all 5 gates run and pass: shellcheck, frontmatter linter, version-drift check, plugin/manual parity gate, vocabulary gate."
    status: failed
    reason: "ci.yml exists with the 5 lint jobs wired correctly, but `bash scripts/check-vocab.sh` exits 1 on the current tree (18 violations across 6 SKILL.md files: build, mission, plan, ship, tdd, verify). On the very first push to main after merge, the CI vocab job will be RED. The gate is mechanically correct; the corpus it gates is dirty. CR-01 verified: `phase`/`milestone` references in SKILL.md prose are not allowlisted, and the deprecation-banner exemption does not cover them."
    artifacts:
      - path: "scripts/check-vocab.sh"
        issue: "Allowlist ('task' for skills/*/SKILL.md, 'PRD' for the 3 v1.x deprecated skills) does not cover legitimate dev-side `phase`/`milestone` cross-references in skill bodies."
      - path: "skills/build/SKILL.md"
        issue: "6 violations on lines 34, 115, 207, 212, 241, 246 (token: phase)"
      - path: "skills/mission/SKILL.md"
        issue: "3 violations on lines 77, 80, 194 (tokens: milestone, phase)"
      - path: "skills/plan/SKILL.md"
        issue: "1 violation on line 128 (token: phase)"
      - path: "skills/ship/SKILL.md"
        issue: "2 violations on lines 132, 210 (token: phase)"
      - path: "skills/tdd/SKILL.md"
        issue: "1 violation on line 68 (token: phase)"
      - path: "skills/verify/SKILL.md"
        issue: "4 violations on lines 43, 47, 176, 178 (token: phase)"
    missing:
      - "Either extend `scripts/check-vocab.sh` allowlist to cover the legitimate dev-cross-references in build/mission/plan/ship/tdd/verify SKILL.md bodies (per-file `phase`/`milestone` allowance)"
      - "OR scrub `Phase N`-style cross-references out of every shipped SKILL.md and replace with brief-shaped equivalents"
      - "Once chosen, re-run `bash scripts/check-vocab.sh` and confirm exit 0 on the working tree before phase closure"

  - truth: "SC #2 — `bats tests/install.bats` exits 0 on `macos-latest` and `ubuntu-latest`; the suite covers install → uninstall → reinstall and the 4 adversarial-branch hook fixtures."
    status: partial
    reason: "tests/install.bats exists with all 10 @test blocks declared (1 fresh install, 1 hand-edit reinstall, 1 uninstall happy, 1 version-mismatch, 1 reinstall-preserves, 1 settings-merge regression, 4 adversarial branch fixtures). However the 4 adversarial-branch tests do NOT actually exercise an adversarial branch path. The fixtures only differ in a `branch_hint` field; `hooks/post-compact.sh` (lines 9-15 confirmed) reads only `.cwd` and never touches `branch_hint`. All 4 branch tests therefore reduce to a single 'stdin parses, stdout is JSON' smoke check executed four times — the JSON-construction-via-jq regression class CONCERNS #6 / FOUND-04 / QUAL-07 promised to guard is not actually being exercised. CR-03 verified."
    artifacts:
      - path: "tests/install.bats"
        issue: "Tests 7-10 pipe 4 different fixtures into post-compact.sh, but post-compact.sh discards branch_hint. No assertion that the adversarial literal survives JSON round-trip."
      - path: "hooks/post-compact.sh"
        issue: "Reads only stdin's .cwd; never derives or emits a branch name. The fixtures' branch_hint field is never consumed."
      - path: "tests/fixtures/branches/{quote,backslash,newline,apostrophe}.json"
        issue: "Fixtures carry adversarial bytes in `branch_hint`, but the hook under test ignores that field — the test design is a stub of the regression it promised."
    missing:
      - "Either (a) make `hooks/post-compact.sh` consume `.branch_hint` from stdin and include it in `additionalContext`, then assert in each bats test that the emitted JSON correctly preserves the adversarial branch literal (e.g. `jq -e '.hookSpecificOutput.additionalContext | contains(\"feat/with\\\"quote\")'`)"
      - "OR drive `hooks/session-start.sh` directly with a fake-git-repo fixture (PATH shim for `git branch --show-current`) so the actual JSON-construction code path runs against the adversarial branch literal"
      - "Per-test assertion that the adversarial literal survived the round-trip — not just `jq -e '.'` validity"

  - truth: "SC #5 — `wc -l README.md` ≤ 500; `head -3 CHANGELOG.md` shows a dated `## v2.0.0` heading; `jq -r .description .claude-plugin/plugin.json` returns a marketplace-polished string ≤200 chars; `git tag` shows `v2.0.0`."
    status: failed
    reason: "Three of four sub-criteria pass: README is 115 lines (well under 500), CHANGELOG line 8 has `## v2.0.0 — 2026-04-28` (dated heading present after preamble), plugin.json description is a marketplace-polished string of ~165 chars (≤200). The fourth sub-criterion fails: `git tag --list` returns no v2.0.0 tag — phase 5 plan 03 deliberately deferred tag creation to a post-merge step (D-27), but the phase is being verified before merge so the tag is not yet present. Additionally README:84 and CHANGELOG:57 advertise a `userConfig.model_profile` knob that does NOT exist in `plugin.json` (CR-02 verified — file has only name/description/version/author/keywords/repository/homepage/license; no userConfig block at all). Documented public API does not exist."
    artifacts:
      - path: ".claude-plugin/plugin.json"
        issue: "Missing `userConfig.model_profile` block referenced by README:84 and CHANGELOG:57. The hook command substitution `${user_config.model_profile}` documented in README will resolve to the empty string."
      - path: "README.md"
        issue: "Line 84 documents a userConfig knob that doesn't exist."
      - path: "CHANGELOG.md"
        issue: "Line 57 claims `userConfig.model_profile` was 'preserved' in v2.0.0 polish — the field was never present, so 'preserved' is misleading."
      - path: "git tag"
        issue: "v2.0.0 tag not yet created; deferred to post-merge per Plan 05-03 D-27 — acceptable for phase verification but the SC literally asks for the tag."
    missing:
      - "Add the `userConfig.model_profile` block to .claude-plugin/plugin.json (default 'balanced', enum quality|balanced|budget) AND verify hook commands actually substitute it; OR remove the bullet from README:84 and the CHANGELOG:57 line. Pick one and reconcile."
      - "Cut the `v2.0.0` git tag from main after the phase 5 PR merges and CI is green (acknowledged as out-of-scope-per-D-27 but required for SC #5 closure)."

  - truth: "Phase contract — CONTRIBUTING.md is current with the v2 layout (implicitly required: README pointer + tag-protection note added in 05-03 land in a CONTRIBUTING that contributors can actually follow)."
    status: failed
    reason: "Plan 05-03 Task 4 was scoped 'light-touch' and explicitly out-of-scoped a v2 rewrite. The two requested insertions (README pointer at top, tag-protection H3 near PR Process) DID land — confirmed at lines 3-5 and 126-131. However the rest of CONTRIBUTING is materially out of date for v2.0.0 (CR-04 verified): line 61 says `## File Structure (v1.4)`, the structure block omits `.claude-plugin/`, `scripts/`, `tests/`, `bin/`, `templates/`, `.github/workflows/`, `config/quality-gates.txt`. Line 106 still references `effort: max` which is not a valid project value (the v2 effort tiers are `high` and `xhigh`, with `xhigh` documented to skip rules on Opus 4.7). Lines 86-106 list only 8 of 12 v2 agents and contradict CLAUDE.md's effort policy for code-writing agents. A new contributor following CONTRIBUTING today will produce frontmatter inconsistent with the rest of agents/."
    artifacts:
      - path: "CONTRIBUTING.md"
        issue: "Line 61 'File Structure (v1.4)' heading is wrong for v2; structure block omits scripts/, tests/, .github/, .claude-plugin/, config/quality-gates.txt, templates/, bin/."
      - path: "CONTRIBUTING.md"
        issue: "Line 106 references `effort: max` — not a valid project value. v2 uses `high` (code-writing) and `xhigh` (audit/design)."
      - path: "CONTRIBUTING.md"
        issue: "Lines 86-106 list 8 v1.x agents, missing @planner, @verifier, @spec-reviewer, @code-reviewer (all shipped in Phase 2)."
      - path: "CONTRIBUTING.md"
        issue: "Line 24/30 routing-entry guidance points contributors at rules/godmode-routing.md for skill conventions; skill conventions actually live in rules/godmode-skills.md."
    missing:
      - "Replace `## File Structure (v1.4)` block with v2.0 structure that includes scripts/, tests/, .github/workflows/, .claude-plugin/, config/quality-gates.txt, templates/.planning/, bin/."
      - "Replace every occurrence of `effort: max` with `effort: xhigh`. Add the `xhigh skips rules on Opus 4.7 — do NOT use it on @executor/@writer/@test-writer; use high there` pitfall verbatim from CLAUDE.md."
      - "Enumerate all 12 v2 agents with correct (model, effort) tiers. Cross-reference rules/godmode-skills.md for skill frontmatter conventions."

deferred: []

human_verification: []
---

# Phase 5: Quality — CI, Tests, Docs Parity Verification Report

**Phase Goal:** Gate the entire substrate before v2.0.0 ships. CI workflow runs 5 lints (shellcheck, frontmatter, version drift, plugin/manual parity, vocabulary). bats-core smoke exercises install → uninstall → reinstall → adversarial-input hook fixtures on macOS + Linux. README ≤500 lines, CHANGELOG dated, plugin marketplace metadata polished. Settings merge regression test prevents silent key drops on upgrade.

**Verified:** 2026-04-28
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth (verbatim from ROADMAP.md) | Status | Evidence |
|---|----------------------------------|--------|----------|
| 1 | `.github/workflows/ci.yml` exists; on a fresh push, all 5 gates run and pass: shellcheck, frontmatter linter, version-drift check, plugin/manual parity gate, vocabulary gate. | ✗ FAILED | ci.yml exists with all 6 jobs wired (5 lint + bats matrix). Each gate uses a shipped script (no inline shell). However `bash scripts/check-vocab.sh` exits 1 on the current tree with 18 violations across 6 SKILL.md files. The vocab CI job will be RED on the very first post-merge push. CR-01 verified by direct execution of the gate. |
| 2 | `bats tests/install.bats` exits 0 on `macos-latest` and `ubuntu-latest`; the suite covers install → uninstall → reinstall and the 4 adversarial-branch hook fixtures. | ⚠ PARTIAL | Suite has 10 @test blocks structurally complete with mktemp HOME isolation. `bats` is not installed locally so end-to-end run is unverified. The 4 adversarial-branch fixtures (CR-03) do NOT exercise an adversarial code path: post-compact.sh reads only `.cwd`, never `branch_hint`, so the 4 tests collapse to one smoke check repeated 4 times. The CONCERNS #6 regression class is not actually guarded. |
| 3 | `bash scripts/check-parity.sh` exits 0 — hook bindings, timeouts, and permissions are byte-for-byte equivalent between `hooks/hooks.json` and `config/settings.template.json[hooks]`. | ✓ VERIFIED | Direct execution: `bash scripts/check-parity.sh` exits 0 with `[+] hooks/hooks.json and config/settings.template.json[hooks] are equivalent`. Script is shellcheck-clean. Normalization via `jq -S` + `walk(...) gsub(...)` correctly substitutes `${CLAUDE_PLUGIN_ROOT}` → `~/.claude` for diff. |
| 4 | `bash scripts/check-vocab.sh` exits 0 — no occurrences of `phase`, `task`, `story`, `PRD`, `gsd-*`, `cycle`, or `milestone` in `commands/`, `skills/`, or `README.md`. | ✗ FAILED | Direct execution: exits 1 with 18 vocabulary violations. Script logic and allowlist mechanisms (per-file `task` for skills/*/SKILL.md, `PRD` for v1.x deprecated skills, `<!-- vocab-allowlist: -->` HTML escape, v1.x body separator) are correct, but the corpus has legitimate dev-side `Phase N` and `milestone` cross-references in 6 shipped SKILL.md bodies that are not allowlisted. README.md alone is clean — the failure is in skills/. |
| 5 | `wc -l README.md` ≤ 500; `head -3 CHANGELOG.md` shows a dated `## v2.0.0` heading; `jq -r .description .claude-plugin/plugin.json` returns a marketplace-polished string ≤200 chars; `git tag` shows `v2.0.0`. | ✗ FAILED | README is 115 lines (well under 500) ✓. CHANGELOG line 8 (after preamble) has `## v2.0.0 — 2026-04-28` ✓. plugin.json description is ~165 chars, marketplace-shaped, contains tagline + arrow chain ✓. `git tag --list` returns no `v2.0.0` ✗ — deferred to post-merge per D-27 but ROADMAP SC #5 literally requires the tag. Additionally CR-02: README:84 and CHANGELOG:57 document a `userConfig.model_profile` knob that is absent from plugin.json (only name/description/version/author/keywords/repository/homepage/license present). Documented public API doesn't exist. |

**Score:** 1/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.github/workflows/ci.yml` | 6 jobs, no inline shell, lint scripts wired | ✓ VERIFIED | 6 jobs declared (shellcheck/frontmatter/version-drift/parity/vocab/bats matrix). 4 lint scripts invoked via `bash scripts/<name>.sh`. shellcheck via ludeeus action. bats matrix covers ubuntu+macos. No setup-node/python/ruby. |
| `scripts/check-parity.sh` | Plugin/manual parity gate, shellcheck-clean | ✓ VERIFIED | 47 lines, shellcheck-clean, exits 0 on current tree, correct normalization via `jq -S walk(... gsub('${CLAUDE_PLUGIN_ROOT}'; '~/.claude'))`. |
| `scripts/check-vocab.sh` | Vocab + surface-count gate, shellcheck-clean | ✗ STUB-ADJACENT | 141 lines, shellcheck-clean, **exits 1 on current tree** because the per-file allowlist does not cover the `phase`/`milestone` references that legitimately appear in shipped SKILL.md bodies. The gate's logic is correct; the gate's contract with the corpus is broken. |
| `tests/install.bats` | 10 @test blocks, mktemp HOME isolation, no external bats helper deps | ⚠ PARTIAL | 10 @test blocks present, mktemp HOME setup/teardown correct, no bats-assert/support deps. **Tests 7-10 do not actually exercise the adversarial code path** (CR-03). Suite is structurally complete but semantically a partial-stub for QUAL-07's stated regression class. |
| `tests/fixtures/branches/{quote,backslash,newline,apostrophe}.json` | 4 valid JSON fixtures with adversarial bytes | ✓ VERIFIED (file existence) / ⚠ HOLLOW (consumption) | All 4 files exist, parse via `jq -e '.'`, contain expected adversarial bytes in `branch_hint`. But the field is never read by the hook under test — the data flows nowhere. |
| `README.md` | ≤500 lines, locked tagline + arrow chain, vocab-clean | ⚠ PARTIAL | 115 lines, tagline at line 3, arrow chain at lines 34-35, 11 skills enumerated. Vocab-clean within README.md itself. **But documents a `userConfig.model_profile` knob that doesn't exist** (CR-02 — line 84). |
| `CHANGELOG.md` | Dated v2.0.0 heading, Keep-a-Changelog taxonomy, v1.x compressed | ⚠ PARTIAL | Line 8 has `## v2.0.0 — 2026-04-28`, all 5 sub-headings present (Added/Changed/Fixed/Removed/Security) plus Foundation/Agents/Hooks/Skills/Quality H4s. v1.x compressed to single block at line 79. **Line 57 claims a `userConfig.model_profile` field was 'preserved' — the field was never there**. |
| `.claude-plugin/plugin.json` | version 2.0.0, ≤200-char marketplace description, v2 keywords (8), userConfig preserved | ⚠ PARTIAL | version=2.0.0 ✓; description ~165 chars with locked tagline + arrow chain ✓; keywords are exactly the v2 set (length 8: workflow,agents,skills,hooks,planning,quality-gates,auto-mode,claude-code) ✓; license=MIT ✓. **userConfig block absent** — Plan 05-03 D-26 said 'preserve if present' and Phase 1 evidently did not add it; this is a Phase 1 gap leaking into Phase 5 (README/CHANGELOG documents the missing field as if it exists). |
| `CONTRIBUTING.md` | README pointer + tag-protection note (per Plan 05-03 Task 4 light-touch scope) | ⚠ PARTIAL | Lines 3-5 contain the README pointer ✓; lines 126-131 contain the tag-protection H3 ✓. **The rest of CONTRIBUTING is materially out of date for v2** (CR-04: v1.4 file structure block at line 61, `effort: max` references at line 106, only 8 of 12 v2 agents listed). Plan deliberately scoped this 'light-touch' but the v1.x dev manual will misdirect contributors today. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| ci.yml | scripts/check-parity.sh | `bash scripts/check-parity.sh` | ✓ WIRED | Line 41 `run: bash scripts/check-parity.sh`. Script exits 0 standalone. |
| ci.yml | scripts/check-vocab.sh | `bash scripts/check-vocab.sh` | ✓ WIRED but ✗ HOSTILE | Line 49 wiring is correct. Script exits 1 against current tree → CI will FAIL. |
| ci.yml | scripts/check-version-drift.sh | `bash scripts/check-version-drift.sh` | ✓ WIRED + DATA-FLOWS | Pre-existing Phase 1 script. Direct execution exits 0. |
| ci.yml | scripts/check-frontmatter.sh | `bash scripts/check-frontmatter.sh` | ✓ WIRED | Pre-existing Phase 2 script. Wired at line 25. |
| scripts/check-parity.sh | hooks/hooks.json + config/settings.template.json | `jq -S '.hooks'` reads | ✓ WIRED + DATA-FLOWS | Both files exist; normalized JSON diffs to empty. |
| scripts/check-vocab.sh | commands/, skills/*/SKILL.md, README.md | per-file walk | ✓ WIRED | Walk loop covers all 3 surfaces; surface-count find recipe verbatim from 04-04-SURFACE-AUDIT.md. |
| tests/install.bats | install.sh, uninstall.sh | `run bash "$REPO_ROOT/install.sh"` | ✓ WIRED | Tests 1-6 invoke install/uninstall directly. |
| tests/install.bats | tests/fixtures/branches/*.json | `cat "$FIXTURE" \| bash hooks/post-compact.sh` | ⚠ WIRED but ✗ HOLLOW_PROP | Pipe is correct; fixture content is correct; **the hook ignores `branch_hint`** so the data flows into a void (CR-03). |
| tests/install.bats | hooks/post-compact.sh | stdin pipe | ⚠ PARTIAL | Hook receives stdin and emits valid JSON, but does not read `branch_hint`. The 4 'adversarial' tests don't differ behaviorally. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| ci.yml vocab job | scripts/check-vocab.sh exit code | running the script | Yes — exit 1 on current tree | ⚠ STATIC (gate is hostile to corpus) |
| ci.yml parity job | scripts/check-parity.sh exit code | running the script | Yes — exit 0 | ✓ FLOWING |
| tests/install.bats Tests 7-10 | $output (hook stdout) | post-compact.sh emission | Yes (valid JSON) but indistinguishable across 4 fixtures | ✗ HOLLOW (4 tests run identical code path; `branch_hint` not consumed) |
| README.md `userConfig.model_profile` reference | n/a | n/a | No — field doesn't exist in plugin.json | ✗ DISCONNECTED (documented public API not implemented) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Parity gate exits 0 on current tree | `bash scripts/check-parity.sh` | exit 0 | ✓ PASS |
| Vocab gate exits 0 on current tree | `bash scripts/check-vocab.sh` | exit 1 (18 violations) | ✗ FAIL |
| Version-drift gate exits 0 | `bash scripts/check-version-drift.sh` | exit 0, canonical 2.0.0 | ✓ PASS |
| plugin.json is valid JSON, version=2.0.0, description ≤200 | `jq -e '.' && jq -r .version && jq -r '.description \| length'` | valid, 2.0.0, ≤200 chars | ✓ PASS |
| plugin.json contains userConfig block | `jq -e '.userConfig' .claude-plugin/plugin.json` | exit 1 (null) | ✗ FAIL — README claims it exists |
| README ≤500 lines | `wc -l README.md` | 115 | ✓ PASS |
| CHANGELOG dated v2.0.0 heading present | `grep -E '^## v2\.0\.0 — 20' CHANGELOG.md` | line 8 match | ✓ PASS |
| All 4 fixtures parse as JSON | `jq -e '.' tests/fixtures/branches/*.json` | all parse | ✓ PASS |
| v2.0.0 git tag exists | `git tag --list \| grep v2.0.0` | no match | ✗ FAIL (deferred to post-merge per D-27 — known gap relative to SC #5) |
| bats run end-to-end | `bats tests/install.bats` | bats not installed locally | ? SKIP (CI is the authoritative environment; structural completeness verified by 10-@test count + mktemp setup/teardown) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| QUAL-01 | 05-01 | `.github/workflows/ci.yml` runs 5 gates each independently passing/failing | ⚠ PARTIAL | All 5 gates wired as independent jobs. Vocab gate fails on the corpus → CI not green. |
| QUAL-02 | 05-02 | `tests/install.bats` covers install round-trip + 4 adversarial-input hook fixtures on macos + ubuntu | ⚠ PARTIAL | Round-trip covered (Tests 1-5). Adversarial fixtures present but don't exercise an adversarial code path (CR-03). |
| QUAL-03 | 05-01 | `scripts/check-parity.sh` asserts byte-for-byte equivalence | ✓ SATISFIED | Script exists, shellcheck-clean, exits 0; normalization via `jq -S walk(...gsub)` is correct. |
| QUAL-04 | 05-01 | `scripts/check-vocab.sh` greps user-facing surface for forbidden tokens | ⚠ PARTIAL | Script logic is correct; allowlist does not cover legitimate dev-side cross-references → fails on current corpus. |
| QUAL-05 | 05-03 | README.md ≤500 lines, scannable, no duplication | ⚠ PARTIAL | 115 lines, well-structured. Documents userConfig knob that doesn't exist (CR-02). |
| QUAL-06 | 05-03 | CHANGELOG dated v2.0.0 entry + plugin.json description/keywords polished | ⚠ PARTIAL | Heading + taxonomy + compressed v1.x correct. Line 57 claims preserved userConfig that doesn't exist. |
| QUAL-07 | 05-02 | bats includes regression test for settings merge | ✓ SATISFIED | Test 6 (lines 92-114) seeds customKey + theme, reinstalls, asserts BOTH user keys AND template keys (permissions.allow non-empty, hooks.SessionStart present). Structurally complete. |

**Coverage:** 2/7 SATISFIED, 5/7 PARTIAL. No BLOCKED, no ORPHANED.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| README.md | 84 | Documented public API absent from code (`userConfig.model_profile`) | 🛑 Blocker | User following docs to set the knob will edit a nonexistent field; `${user_config.model_profile}` substitutes to empty string. |
| CHANGELOG.md | 57 | Claims a v2.0.0 'preserved' feature that was never there | 🛑 Blocker | Audit-trail lie. Future regressions will be hard to diagnose because the changelog records a state that never existed. |
| CONTRIBUTING.md | 61 | Stale `(v1.4)` File Structure block | ⚠ Warning | New contributors will not know about scripts/, tests/, .github/, .claude-plugin/, config/quality-gates.txt — they'll bypass the CI gates locally. |
| CONTRIBUTING.md | 106 | References `effort: max` (not a valid value) | ⚠ Warning | Contributors set the wrong effort tier; produces frontmatter inconsistent with rest of agents/. |
| CONTRIBUTING.md | 86-106 | Lists 8 v1.x agents (missing @planner, @verifier, @spec-reviewer, @code-reviewer) | ⚠ Warning | Half the v2 agent layer is invisible to new contributors. |
| skills/build/SKILL.md, skills/mission/SKILL.md, skills/plan/SKILL.md, skills/ship/SKILL.md, skills/tdd/SKILL.md, skills/verify/SKILL.md | various | `phase`/`milestone` references in skill body prose | 🛑 Blocker (relative to vocab gate) | Blocks CI vocab job on first post-merge push. |
| hooks/post-compact.sh | n/a | Hook ignores `branch_hint` field that the bats fixtures use to differentiate | ⚠ Warning | The bats 'adversarial' tests are decorative — the regression they claim to guard isn't being tested. |
| scripts/check-vocab.sh | 89 | `LC_ALL=C` not exported (per CR review WR-01) | ℹ Info | Pinning intent silently violated; out-of-scope for this verification but worth noting. |
| tests/install.bats | 64-77 | `--force` test asserts only status, not post-condition | ℹ Info | If `--force` no-ops silently, test still passes. Per CR review WR-03. |
| .github/workflows/ci.yml | n/a | jq not explicitly installed; relies on runner pre-install | ℹ Info | Works today; not contractual. Per CR review WR-02. |

### Human Verification Required

(none — all material gaps are mechanically observable; no UI/UX behavior to subjective-test)

### Gaps Summary

Phase 5 ships the substrate but the substrate has three contract violations between the gates it builds and the corpus they gate, plus one documented-but-absent public API:

1. **CR-01 (BLOCKER, SC #1, SC #4)** — The vocab gate works mechanically but the corpus has 18 unallowlisted `phase`/`milestone` references in 6 SKILL.md bodies. CI will be RED on the first push to main. The gate cannot ship green as written.

2. **CR-02 (BLOCKER, SC #5)** — README:84 and CHANGELOG:57 document a `userConfig.model_profile` knob that does not exist in `.claude-plugin/plugin.json`. The plugin advertises an API it doesn't implement. This is a Phase 1 / Plan 05-03 inconsistency: Plan 05-03 D-26 said 'preserve userConfig if present' (good), but if Phase 1 never added it, the docs should not advertise it — neither plan caught the gap.

3. **CR-03 (BLOCKER, SC #2)** — The 4 adversarial-branch bats tests don't actually exercise an adversarial path. `hooks/post-compact.sh` reads only `.cwd` from stdin; the `branch_hint` field that distinguishes the 4 fixtures is ignored. All 4 tests collapse to a single 'stdin parses, stdout is JSON' check repeated 4 times. The CONCERNS #6 / FOUND-04 regression class promised by QUAL-07 is not actually being guarded.

4. **CR-04 (WARNING, phase contract)** — CONTRIBUTING.md's 'light-touch' update added the README pointer + tag-protection note correctly, but the rest of the file still describes a v1.4 layout. New contributors today get wrong frontmatter shapes, miss the CI gates, and are pointed at the wrong rule file for skill conventions.

**Recommendation for the planner:** Group CR-01 + CR-02 + CR-03 into a single closure plan ('Phase 5 closure: fix the gate-vs-corpus mismatches'). Decide CR-01 by either (a) extending the vocab allowlist or (b) scrubbing skill bodies — both are plan-shaped. CR-02 needs an artifact decision: add userConfig to plugin.json OR remove the doc claims. CR-03 needs a code change to post-compact.sh (or session-start.sh) so the fixtures actually drive an adversarial code path. CR-04 can ride along or defer to v2.x docs polish (the plan explicitly said it was light-touch).

The v2.0.0 git tag is correctly deferred to post-merge per D-27 — that is not a real gap, just a literal-reading-of-SC-5 mismatch.

---

_Verified: 2026-04-28_
_Verifier: Claude (gsd-verifier)_
