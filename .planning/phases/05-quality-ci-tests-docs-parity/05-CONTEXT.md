# Phase 5: Quality — CI, Tests, Docs Parity - Context

**Gathered:** 2026-04-27
**Status:** Ready for planning

<domain>
## Phase Boundary

The closing milestone. After Phase 5, v2.0.0 is shippable. Concretely:

- **CI pipeline** (`.github/workflows/ci.yml`) runs on every PR with 5 independent gates (shellcheck, frontmatter linter, version drift, plugin/manual parity, vocabulary) plus a bats-core smoke matrix on `macos-latest` + `ubuntu-latest`. Each gate must pass independently — a single inline-script gate fails QUAL-01 SC #1.
- **bats-core smoke** (`tests/install.bats`) covers install → uninstall → reinstall round-trip, settings merge regression (QUAL-07), and 4 adversarial-branch hook fixtures (branch with quote, backslash, newline, apostrophe).
- **Plugin/manual parity gate** (`scripts/check-parity.sh`) asserts byte-for-byte equivalence between `hooks/hooks.json` and `config/settings.template.json[hooks]` on bindings + timeouts + permissions.
- **Vocabulary gate** (`scripts/check-vocab.sh`) refuses commits where forbidden tokens (`phase`, `task`, `story`, `PRD`, `gsd-*`, `cycle`, `milestone`) appear in user-facing surface (`commands/`, `skills/`, `README.md`). Documented exceptions enforced via a path/file allowlist (Phase 4 hand-off contracts).
- **README rewrite** (`README.md`) ≤500 lines, tutorial-first, with TOC + getting-started + troubleshooting + FAQ. Punchy marketplace tone matching PROJECT.md core value statement.
- **CHANGELOG** (`CHANGELOG.md`) gains a dated `## v2.0.0` heading summarizing the 5 milestone areas in Keep-a-Changelog format.
- **Marketplace metadata polish** in `.claude-plugin/plugin.json`: `description` ≤200 chars, `keywords` array tuned for discovery, `homepage`/`repository`/`author` fields verified.
- **v2.0.0 git tag** cut from `main` AFTER the Phase 5 PR merges and CI is green.

This phase does NOT change agents, hooks, or skills (Phases 2-4). It does NOT add new mandatory runtime deps. The CI environment may use `shellcheck` and `bats-core` — both are dev-time tools, no runtime dependency on either.

**Locked from prior work:**
- Phase 4 vocab exceptions: `task` token whitelist for `skills/{build,verify,ship}/SKILL.md` (PLAN.md task structure references); body content below `--- v1.x body below ---` separator in deprecation banners exempt entirely.
- Phase 4 surface-count canonical recipe (in `04-04-SURFACE-AUDIT.md`): the simple `find commands skills -name '*.md'` from ROADMAP SC #1 over-counts by 3 due to v1.x deprecated bodies retaining `user-invocable: true` + `_shared/*.md` matching. Phase 5's surface-count linter must use the canonical recipe.
- Phase 1 SoT: `.claude-plugin/plugin.json:.version` is canonical; `scripts/check-version-drift.sh` ships and gates already.
- Phase 2 frontmatter linter ships and runs in CI; Phase 5 just wires the workflow.

</domain>

<decisions>
## Implementation Decisions

### CI workflow shape (QUAL-01)
- **D-01:** Single `.github/workflows/ci.yml` file. One job per lint gate, one bats job with OS matrix. Each gate runs independently — pass/fail signal per gate is preserved (QUAL-01 SC #1). Job structure:
  ```yaml
  name: CI
  on: [push, pull_request]
  jobs:
    shellcheck:    { runs-on: ubuntu-latest, steps: [...] }
    frontmatter:   { runs-on: ubuntu-latest, steps: [...] }
    version-drift: { runs-on: ubuntu-latest, steps: [...] }
    parity:        { runs-on: ubuntu-latest, steps: [...] }
    vocab:         { runs-on: ubuntu-latest, steps: [...] }
    bats:
      strategy:
        matrix:
          os: [macos-latest, ubuntu-latest]
      runs-on: ${{ matrix.os }}
      steps: [...]
  ```
- **D-02:** Use `actions/checkout@v4` and `ludeeus/action-shellcheck@master` per STACK.md. No Node/Python/Ruby setup-* actions — this is a pure bash + jq plugin.
- **D-03:** Each lint job invokes the SHIPPED script directly (`bash scripts/<name>.sh`), NOT inline shell. Reason: scripts are user-invokable too — running locally must produce the same result as CI. CI wraps with `set -e` and timing; logic stays in scripts.
- **D-04:** Gate ordering in workflow YAML mirrors the failure-likelihood gradient: shellcheck (most common authoring failure) → frontmatter → version-drift → parity → vocab → bats. Visual reading order matches the developer's debugging order.

### bats-core smoke shape (QUAL-02)
- **D-05:** Single `tests/install.bats` file with `@load tests/fixtures/<name>` helpers. Matches QUAL-02 SC wording verbatim. Each `@test` is one scenario:
  - `install over fresh ~/.claude/`
  - `install over ~/.claude/ with hand-edited rules` (per-file diff/skip/replace prompt; non-TTY default = keep)
  - `uninstall on installed plugin`
  - `uninstall refuses on version mismatch (no --force)`
  - `reinstall preserves customizations`
  - `settings merge: top-level keys not in template survive reinstall` (QUAL-07)
  - `hook fixture: branch name contains "` (adversarial)
  - `hook fixture: branch name contains \` (adversarial)
  - `hook fixture: branch name contains \n` (adversarial)
  - `hook fixture: branch name contains '` (adversarial)
- **D-06:** Each test runs in a `mktemp -d` `$HOME` (per STACK.md "bats-core" row — temp HOME per test). Setup teardown via bats `setup_file` / `teardown_file` for fixtures shared across tests; per-test `setup` / `teardown` for HOME isolation.
- **D-07:** Adversarial-branch fixtures live in `tests/fixtures/branches/` as static JSON files (one per pattern). The bats test reads the JSON, sets it as the stdin-input to the hook script, and asserts the hook output passes `jq -e '.'`. Reuses Phase 1's CR-02 hardening test pattern.
- **D-08:** bats-core version pinned to v1.13.0 per STACK.md (released 2024-11-07; bash 3.2 compatible). CI installs via `npm install -g bats` OR `apt-get install bats` OR `brew install bats-core` — workflow uses the package manager native to each matrix runner.

### Plugin/manual parity gate (QUAL-03)
- **D-09:** `scripts/check-parity.sh` (NEW) is pure bash + jq. Reads:
  - `hooks/hooks.json` → extract `.hooks` object (PreToolUse, PostToolUse, SessionStart, PostCompact bindings + per-binding timeout)
  - `config/settings.template.json` → extract `.hooks` object (same shape)
  - Diff via `diff <(jq -S .hooks hooks/hooks.json) <(jq -S .hooks config/settings.template.json)` — `-S` sorts keys for stable comparison.
- **D-10:** Comparison is **byte-for-byte after canonicalization** (jq -S). Path differences (`${CLAUDE_PLUGIN_ROOT}/...` vs `~/.claude/...`) are EXPECTED and intentional — the gate must normalize them before diffing. Normalization: replace `${CLAUDE_PLUGIN_ROOT}` with `~/.claude` in plugin-mode JSON before diffing. Document this normalization rule inline in `check-parity.sh`.
- **D-11:** Exit codes: 0 if equivalent, 1 with diff output if drift. Wired into CI as the `parity` job in D-01.

### Vocabulary gate (QUAL-04)
- **D-12:** `scripts/check-vocab.sh` (NEW) is pure bash + grep + jq. Tokens: `phase`, `task`, `story`, `PRD`, `gsd-*`, `cycle`, `milestone` (case-insensitive, word-boundary). Surface scanned: `commands/*.md`, `skills/**/SKILL.md`, `README.md`. Internal docs (`rules/`, `agents/`, `.planning/`, `tests/`, `scripts/`, `hooks/`, `config/`, `bin/`) exempt via a path allowlist documented inline.
- **D-13:** Per-file exceptions enforced via an inline allowlist (Phase 4 hand-off contracts):
  - `skills/build/SKILL.md`, `skills/verify/SKILL.md`, `skills/ship/SKILL.md`: `task` token allowed (PLAN.md task structure references). Other forbidden tokens still hard-fail.
  - `skills/prd/SKILL.md`, `skills/plan-stories/SKILL.md`, `skills/execute/SKILL.md`: body below `--- v1.x body below ---` separator EXEMPT entirely (preserved v1.x bodies). Banner block above the separator still subject to vocab discipline.
- **D-14:** Allowlist format: bash associative array fallback (bash 3.2 portable) — parallel indexed arrays mapping path glob → allowed-tokens-for-that-path. Documented inline; review threshold ~10 entries before externalizing to `config/vocab-allowlist.txt`.
- **D-15:** Output: one line per violation (`<file>:<line>:<token>:<excerpt>`). Exit 0 on clean; 1 on any hit. False-positive bias: token matches inside fenced code blocks (`` ` ``, `` ``` ``) ARE counted (the user reads them too) — if a code example must contain a forbidden token (e.g., demoing v1.x deprecation), wrap with `<!-- vocab-allowlist: <token> -->` HTML comments inline. Document the escape hatch in body of `check-vocab.sh`.

### Surface-count gate (NEW — derives from QUAL-04 + Phase 4 04-04-SURFACE-AUDIT.md)
- **D-16:** Phase 4's `04-04-SURFACE-AUDIT.md` documents the canonical 11-skill recipe. Phase 5 wires it into the vocabulary gate (or a sibling `scripts/check-surface.sh` if `check-vocab.sh` grows past ~150 lines): assert exactly 11 user-invocable skills via:
  ```bash
  find commands skills -name '*.md' -type f \
    -not -path 'skills/_shared/*' \
    -not -path 'skills/prd/*' \
    -not -path 'skills/plan-stories/*' \
    -not -path 'skills/execute/*' \
    | wc -l
  ```
  Expected = 11. Refuses on any other count. v1.x deprecation banners are pruned (they retain `user-invocable: true` for mid-migration but don't count toward the v2 cap).
- **D-17:** Surface gate logic lives inline in `check-vocab.sh` for v2.0 (D-15 file size budget allows). Externalize to `scripts/check-surface.sh` if the inline check exceeds ~30 lines.

### README rewrite (QUAL-05)
- **D-18:** Tone: **punchy, tutorial-first**. Opens with the core value statement (`## Senior engineering team, in a plugin.`) and a "ship a feature in 2 minutes" tutorial. Reference content (full agent/skill catalog, architecture details) lives in CONTRIBUTING.md and inline frontmatter — README does NOT duplicate.
- **D-19:** Structure (every section ≤80 lines):
  ```
  # claude-godmode
  > Senior engineering team, in a plugin.
  ## Quick start (2-minute tutorial)
  ## What you get (one-paragraph capability summary + visual chain)
  ## Installation (plugin marketplace + manual paths, side-by-side)
  ## The /godmode arrow chain (one-line explanation per skill)
  ## Auto Mode (one paragraph)
  ## Customization (rule overrides, model_profile, skill authoring pointer)
  ## Troubleshooting (5-7 most common issues with one-line fixes)
  ## FAQ (5-7 questions)
  ## Contributing & development (one-line pointer to CONTRIBUTING.md)
  ## License (one line)
  ```
  Hard cap: ≤500 lines including blank lines. CI gate (`wc -l README.md`) enforces.
- **D-20:** Visual elements:
  - **The arrow chain rendered ASCII once** in `## What you get`: `/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship` plus `+ /debug /tdd /refactor /explore-repo` underneath as helpers.
  - One terminal-cast GIF embedded in README (optional, low priority — link out to repo wiki if too large for v2.0 ship).
- **D-21:** No duplication with CONTRIBUTING.md, CHANGELOG.md, or inline skill descriptions. README is the marketing front door; CONTRIBUTING is the code-author manual. Link, don't copy.

### CHANGELOG (QUAL-06)
- **D-22:** Format: **Keep-a-Changelog** (https://keepachangelog.com/en/1.1.0/). Each release section has subsections `### Added`, `### Changed`, `### Fixed`, `### Removed`, `### Security`. Top of file has `# Changelog` heading and the standard Keep-a-Changelog preamble (one paragraph + format/SemVer compliance lines).
- **D-23:** v2.0.0 entry header: `## [v2.0.0] - 2026-04-DD` (concrete date filled at tag time). Body groups changes by milestone area (Foundation / Agents / Hooks / Skills / Quality). Each bullet links to the closing commit or PR where applicable. ~30-50 bullets total — covers 46 v1 requirements + 7 QUAL reqs.
- **D-24:** v1.x history compressed into a single `## [v1.x.x]` block at the bottom — sufficient context for "what was v1?" without competing for v2.0.0's space.

### Marketplace metadata polish (QUAL-06)
- **D-25:** `.claude-plugin/plugin.json` polish:
  - `description`: `"Senior engineering team, in a plugin. One arrow chain (/godmode → /mission → /brief → /plan → /build → /verify → /ship), 11 skills, mechanical quality gates."` (197 chars; under the 200-char limit).
  - `keywords`: `["workflow","agents","skills","hooks","planning","quality-gates","auto-mode","claude-code"]`. Affects marketplace discovery — these are the search terms the audience would type.
  - `homepage`: GitHub repo URL.
  - `repository`: same.
  - `author`: `{"name":"…","email":"…","url":"…"}` — required for marketplace listing.
  - `license`: `"MIT"` (already set; verify).
- **D-26:** Polish must preserve `userConfig.model_profile` (Phase 1) — the single user-tunable knob. Don't strip it; it's not metadata.

### v2.0.0 release process
- **D-27:** Release flow:
  1. Phase 5 PR (the `repo-polish` branch) merges to `main`.
  2. CI runs on main; all 5 lints + bats matrix pass.
  3. `git tag v2.0.0 && git push --tags`.
  4. GitHub Release page auto-renders from CHANGELOG.md v2.0.0 section.
  5. Marketplace plugin re-indexes within hours (no action required if `.claude-plugin/plugin.json` is correct).
- **D-28:** No release branch in v2.0.0. If a hotfix is needed, branch from the `v2.0.0` tag, fix, tag `v2.0.1`. Release branches reserved for v2.x if hotfix volume warrants.
- **D-29:** Tag protection: GitHub repo settings should require admin to push `v*` tags. Documented in CONTRIBUTING.md (touched lightly in this phase). Out of scope to enforce mechanically — relies on GitHub UI.

### Settings merge regression test (QUAL-07)
- **D-30:** `tests/install.bats` includes a dedicated `@test "settings merge preserves user keys"`:
  1. Set up `~/.claude/settings.json` with: `{"theme":"dark","customKey":"customValue"}` (where `customKey` is NOT in `settings.template.json`).
  2. Run `./install.sh`.
  3. Assert `~/.claude/settings.json` STILL contains `customKey`.
  4. Assert it ALSO contains the keys from the template (e.g., `hooks`, `permissions`).
- **D-31:** Implementation hint for `install.sh` if the merge logic regresses: use `jq -s '.[0] * .[1]' user-settings.json template-merge.json > merged.json` (deep-merge with right-side priority for top-level keys). Phase 1 should have shipped this; Phase 5's regression test catches drift.

### Out of scope for Phase 5 (mapped elsewhere)
- **OUT-01:** Adding new agents, skills, hooks, or rules — that work shipped in Phases 2-4.
- **OUT-02:** New runtime dependencies — none. CI uses shellcheck + bats-core but they're dev-time only.
- **OUT-03:** Performance benchmarking — out of scope per PROJECT.md "no telemetry, ever". Statusline `jq` invocation count was already addressed in Phase 1 (FOUND-06).
- **OUT-04:** Pre-commit hook installer for end users — out of scope for v2.0. CI is the gate; users can opt in via their own `git config` separately.
- **OUT-05:** Documentation site (separate from README) — link out to GitHub wiki for v2.0; dedicated docs site is v2.x.
- **OUT-06:** v2.0.x release branch lifecycle — reserved for hotfix volume that doesn't exist yet.
- **OUT-07:** Plugin marketplace listing screenshots / GIFs beyond the README terminal cast — v2.x polish.
- **OUT-08:** Cross-AI peer review of Phase 5 plans (`/gsd-review`) — optional in `--auto`; user can opt in manually.

### Claude's Discretion
- Exact wording of CHANGELOG bullets — group by milestone area, link to PR/commit, but the prose style is the planner's call.
- Order of CI gate jobs in `ci.yml` (D-04 recommends failure-likelihood ordering; planner may reorder if benchmarking suggests differently).
- Exact bats fixture JSON shape for adversarial branches (D-07 specifies the principle; concrete JSON is the planner's call).
- Whether the surface-count check lives inline in `check-vocab.sh` or as a sibling `check-surface.sh` (D-17 size threshold).
- README terminal-cast GIF inclusion (D-20 marks optional — defer if production cost > marginal install-rate gain).
- README FAQ specific questions — the planner curates from the v1.x issue tracker if available, else 5 evergreen Qs (install path? Auto Mode? customizing rules? upgrading from v1.x? where to file bugs?).
- Exact order of CHANGELOG sub-bullets within a release (D-22 provides the section taxonomy).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project context
- `.planning/PROJECT.md` — Active section "Quality" subsection (the 7 QUAL-NN bullets); Constraints (≤500 line README, MIT license, no telemetry, single SoT for version)
- `.planning/REQUIREMENTS.md` — QUAL-01..QUAL-07 (the 7 requirements this phase delivers)
- `.planning/ROADMAP.md` § Phase 5 — Goal, Success Criteria (5 SCs), Plans (3 plans)
- `IDEA.md` — repo-root locked decisions (11-command surface; bash + jq only; MIT)

### Prior phases
- `.planning/phases/01-foundation-safety-hardening/01-CONTEXT.md` — version SoT (FOUND-02), `scripts/check-version-drift.sh` already ships; backup rotation; install.sh per-file prompt loop (Phase 5 bats tests this); `.shellcheckrc` already shipped
- `.planning/phases/01-foundation-safety-hardening/01-VERIFICATION.md` — confirms substrate is solid
- `.planning/phases/02-agent-layer-modernization/02-CONTEXT.md` — `scripts/check-frontmatter.sh` already ships; AGENT-01..AGENT-08 frontmatter convention is the contract Phase 5 lints
- `.planning/phases/02-agent-layer-modernization/02-VERIFICATION.md` — confirms agents linter-clean
- `.planning/phases/03-hook-layer-expansion/03-CONTEXT.md` — `hooks/hooks.json` and `config/settings.template.json` aligned in Phase 3 D-19..D-22; Phase 5 mechanically asserts
- `.planning/phases/03-hook-layer-expansion/03-VERIFICATION.md` — confirms hook substrate operational
- `.planning/phases/04-skill-layer-state-management/04-CONTEXT.md` — D-NN decisions Phase 5 vocab gate respects; vocab exceptions documented
- `.planning/phases/04-skill-layer-state-management/04-VERIFICATION.md` — 14/14 reqs, 5/5 SCs COVERED
- `.planning/phases/04-skill-layer-state-management/04-04-SURFACE-AUDIT.md` — **MANDATORY READ** for Phase 5 D-16 — the canonical 11-skill `find` recipe and documented exceptions

### Research (current pass — already produced)
- `.planning/research/STACK.md` § "Dev-time tooling" — shellcheck v0.11.0 (2025-08-04 release), bats-core v1.13.0 (2024-11-07 release), inline `jq -e` for JSON schema lint (vs ajv-cli/Node), pure-bash + awk for frontmatter lint (vs markdownlint-cli2/Node)
- `.planning/research/STACK.md` § "Plugin manifest" — version SoT contract; `userConfig.model_profile` knob to preserve
- `.planning/research/STACK.md` § "Bash 3.2 portability" — patterns for the new `check-parity.sh` and `check-vocab.sh`
- `.planning/research/STACK.md` § "jq patterns" — `jq -n --arg`, `@tsv` batched extraction, `// empty` vs `// "default"`, `-e` for assertions
- `.planning/research/PITFALLS.md` § HI-03 (plugin/manual parity drift — drives QUAL-03 / D-09); § HI-06 (vocab leakage — drives QUAL-04 / D-12); § HI-08 (settings merge silently drops keys — drives QUAL-07 / D-30); § ME-04 (README/CHANGELOG/godmode quick-ref drift — drives D-21 no-duplication rule)
- `.planning/research/FEATURES.md` F-34..F-38 — the quality-layer feature catalog
- `.planning/research/ARCHITECTURE.md` § Section 5 "Plugin-mode vs Manual-mode Parity Contract" — the file-by-file parity table that QUAL-03 mechanically enforces

### v1.x baseline / current state
- `.github/workflows/` — currently empty (no CI). Phase 5 ships the first workflow.
- `tests/fixtures/` — Phase 1 may have shipped some hook fixtures; Phase 5 augments with adversarial-branch fixtures for QUAL-02
- `scripts/check-version-drift.sh`, `scripts/check-frontmatter.sh` — exist; Phase 5 wires into CI
- `README.md` — current state is v1.x leftover; Phase 5 rewrites
- `CHANGELOG.md` — may not exist or may be sparse; Phase 5 ships v2.0.0 entry
- `.claude-plugin/plugin.json` — version + userConfig already set (Phase 1); Phase 5 polishes description + keywords

### Source files this phase touches
- `.github/workflows/ci.yml` (NEW)
- `tests/install.bats` (NEW)
- `tests/fixtures/branches/{quote,backslash,newline,apostrophe}.json` (NEW)
- `scripts/check-parity.sh` (NEW)
- `scripts/check-vocab.sh` (NEW — may include surface-count inline per D-16)
- `README.md` (rewrite to v2 shape)
- `CHANGELOG.md` (add v2.0.0 entry; create file if absent)
- `.claude-plugin/plugin.json` (description + keywords polish only)
- `CONTRIBUTING.md` (light touch — pointer from README to here; document tag protection note per D-29)

### New files this phase creates
- `.github/workflows/ci.yml`
- `tests/install.bats`
- `tests/fixtures/branches/quote.json`
- `tests/fixtures/branches/backslash.json`
- `tests/fixtures/branches/newline.json`
- `tests/fixtures/branches/apostrophe.json`
- `scripts/check-parity.sh`
- `scripts/check-vocab.sh`
- `CHANGELOG.md` (if not present)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (from Phases 1-4)
- **`scripts/check-version-drift.sh`** (Phase 1) — pattern lift for the 2 new scripts (`check-parity.sh`, `check-vocab.sh`): same shellcheck-clean style, same `info()/warn()/error()` color helpers (cribbed from `install.sh`), same `set -euo pipefail` discipline, same exit-code contract (0 = clean, 1 = violations found).
- **`scripts/check-frontmatter.sh`** (Phase 2) — second analog for the new scripts; pure-bash + awk + jq pattern documented in Phase 2 D-21..D-23.
- **`hooks/post-compact.sh` Phase 1 substrate** — `find ... -name '*.md' \! -name '_*' -print` style for D-16 surface-count recipe.
- **`install.sh` color helpers** — `info()/warn()/error()` lifted into the new scripts for consistent UX with the installer.
- **Phase 1 hook fixtures** (`tests/fixtures/hooks/post-compact-state.txt` and similar) — pattern for D-07 adversarial-branch JSON fixtures.
- **Phase 4's `skills/_shared/init-context.sh`** — NOT used directly in Phase 5 scripts (CI scripts run before the plugin is installed), but its `awk` YAML parser pattern is the template for any YAML-frontmatter parsing in `check-frontmatter.sh` extensions.
- **Phase 4's vocab exception list** (in `04-04-SURFACE-AUDIT.md` and `skills/build/SKILL.md` body) — the per-file vocab allowlist Phase 5's `check-vocab.sh` codifies.

### Established Patterns (from Phases 1-4)
- `set -euo pipefail` at top of every shell script
- `info()/warn()/error()` color helpers (lifted into every Phase 5 script)
- `[ -f "$file" ] && ...` POSIX-style guards (bash 3.2 compatible)
- `jq -n --arg KEY "$VAL"` for ALL JSON construction (CR-02 discipline — NOT relevant for Phase 5 scripts since they READ JSON, but observed in case any script writes)
- `awk '/^---$/{count++; if(count==2)exit} count==1 && match(...)'` for YAML front-matter parsing
- Exit-code contract: 0 = clean, non-zero = violations
- `# shellcheck disable=SC<NNNN>` directives MUST include rationale comment
- Phase 4 vocabulary discipline: `phase`/`task`/`story`/`PRD`/`gsd-*`/`cycle`/`milestone` forbidden in `commands/` + `skills/*/SKILL.md` + `README.md`. Internal docs exempt.

### Integration Points
- **GitHub Actions (`actions/checkout@v4`, `ludeeus/action-shellcheck@master`)** — only external dependencies in CI. No Node/Python/Ruby setup-* actions.
- **`tests/install.bats` runs `./install.sh` and `./uninstall.sh`** — these scripts are Phase 1 deliverables; Phase 5 only TESTS them. If a bats test fails because of an installer bug, file it as a Phase 1 regression and fix in install.sh.
- **`scripts/check-parity.sh` reads `hooks/hooks.json` + `config/settings.template.json`** — Phase 3 D-22 ships them aligned. Phase 5 verifies the alignment held through Phase 4. If Phase 4 (or any subsequent edit) broke parity, this gate catches it.

### Anti-patterns to AVOID
- **Inline gate logic in CI YAML** (vs invoking shipped scripts) — CI scripts and local scripts MUST be the same code path. If a developer can't reproduce CI failure locally, the gate is broken.
- **Setup actions for Node/Python/Ruby** in CI — would violate the dep budget. Only `actions/checkout` + `action-shellcheck` (and the OS-native `bats` install).
- **README content duplicated in CHANGELOG or CONTRIBUTING** — drift is inevitable. Link, don't copy (D-21).
- **Marketplace description over 200 chars** — affects discovery (CR-07 from PITFALLS). Hard cap.
- **Brittle vocab regex without word boundaries** — `phase` MUST match as a whole word, not as a substring of `phaseout` or `metaphase`. Use `\b` anchors.
- **Hardcoded surface count of 11 anywhere outside `04-04-SURFACE-AUDIT.md`** — drift target. The CI gate must compute the canonical recipe live.

</code_context>

<specifics>
## Specific Ideas

- **Tutorial-first README opening.** First 30 lines: H1 + tagline + a 5-step quick-start (`./install.sh`, open Claude Code, type `/godmode`, run `/mission`, follow the chain). Make the second-time reader's "where's the install command?" answer be on screen 1.
- **Marketplace description is the headline.** "Senior engineering team, in a plugin." is locked from PROJECT.md. Don't water it down. The keywords array carries the technical hooks for search.
- **CHANGELOG dates the milestone, not each commit.** v2.0.0 has ONE date; the 30-50 bullets within share that date. Per-bullet dates would clutter and aren't conventional.
- **CI parallelism is by-job, not by-step.** Each gate is its own job (D-01) so they run in parallel; matrix is OS only for bats. This minimizes wall-clock time on green PRs.
- **Adversarial-branch JSON fixtures use literal Unicode escape for `\n`.** Don't try to embed a literal newline in a JSON value — bats reads the file via `cat`, then pipes to `jq` which handles the escape. Document this in the fixture file's first-line comment.
- **bats `setup`/`teardown` ALWAYS use `mktemp -d` for HOME.** Never let a test write to the real `~/.claude/` — even if the user runs `bats tests/install.bats` locally, no side effects.
- **The vocab gate's HTML-comment escape (D-15)** is a deliberate pressure-release valve. We expect future doc bullets to need to demo v1.x deprecation; the gate must accommodate without weakening the principle.
- **Plugin/manual parity normalization (D-10)** is the ONE place we accept divergence. Every other field (timeouts, matchers, permissions) must be byte-identical. If a future change needs a new exception, document it in `check-parity.sh` AND in `.planning/PROJECT.md` Active section, OR refactor the contract.
- **README hard cap is 500 lines including blanks.** No exceptions for v2.0. If content overflows, it goes to CONTRIBUTING.md or repo wiki. The cap exists because READMEs over 500 lines reliably go unread.
- **v2.0.0 tag is cut from main, not from `repo-polish`.** The PR merge is the milestone-end; tagging from main makes git log linear and matches GitHub release expectations.

</specifics>

<deferred>
## Deferred Ideas

- **Pre-commit hook installer for end users.** v2.x — opt-in workflow to mirror CI gates locally. v2.0 ships CI only.
- **Plugin marketplace listing screenshots / animated GIFs.** v2.x polish. v2.0 ships terminal cast (optional).
- **Cross-AI peer review of Phase 5 plans (`/gsd-review`).** v2.0 user-optional. Default in `--auto` is no.
- **Documentation site (e.g., docs/ subdirectory or external).** v2.x. v2.0 link out to GitHub wiki.
- **`scripts/check-surface.sh` extracted from `check-vocab.sh`.** Only if the inline check exceeds ~30 lines (D-17 size threshold).
- **`config/vocab-allowlist.txt` externalized config.** Only if inline allowlist (D-14) exceeds ~10 entries.
- **Release branches (`release/v2.0.x`) for hotfix workflows.** Only when hotfix volume warrants. v2.0 cuts directly from main.
- **CI matrix beyond `ubuntu-latest` + `macos-latest`.** v2.x may add `ubuntu-22.04` LTS for stability assurance. v2.0 picks the latest of each.
- **Performance/timing benchmarks for hook execution.** Out of scope per PROJECT.md "no telemetry, ever".
- **Tag protection mechanically enforced.** v2.x — currently relies on GitHub UI settings (D-29).
- **Compatibility floor declarations** (e.g., minimum Claude Code version `v2.1.111`). README mentions; full version-matrix is v2.x.
- **`bats-assert` / `bats-support` library helpers.** Plain bats matchers are sufficient for QUAL-02; helper libs add a dep target. Reconsider in v2.x if assertion ergonomics become painful.
- **`cosign` / supply-chain attestation on releases.** v2.x — relies on infrastructure we don't control today.

</deferred>

---

*Phase: 05-quality-ci-tests-docs-parity*
*Context gathered: 2026-04-27*
