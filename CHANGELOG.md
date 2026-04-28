# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## v2.0.0 — 2026-04-28

Polish mature version. Replaces the v1.x pipeline with a single arrow chain (/godmode → /mission → /brief → /plan → /build → /verify → /ship), hardens every defect the v1.x audit surfaced, modernizes the agent layer to the 2026 capability surface (Opus 4.7, effort: xhigh, auto mode, plugin marketplace, native skills/agents/hooks), and adds mechanical quality gates (5 CI lints, bats matrix on macOS+Linux). 46 v1 requirements + 7 QUAL requirements landed across 5 milestone areas.

### Added

#### Foundation (substrate hardening)

- `scripts/check-version-drift.sh` — CI guard ensuring the version SoT (`.claude-plugin/plugin.json:.version`) matches every user-facing mention. (FOUND-02)
- `config/quality-gates.txt` — single source of truth for the 6 quality gates. (FOUND-07)
- `.shellcheckrc` — repo-level shellcheck configuration; every shipped shell file `shellcheck`-clean at v0.11.0 default severity. (FOUND-08)
- Backup rotation in `~/.claude/backups/godmode-<ts>/` keeping last 5. (FOUND-10)
- Live filesystem indexing substrate consumed by PostCompact hook (no hardcoded agent/skill list). (FOUND-11)
- `tests/fixtures/hooks/setup-fixtures.sh` + 5 placeholder fixtures (`cwd-{normal,quote-branch,backslash-branch,newline-branch,apostrophe-branch}.json`) — adversarial branch-name test inputs. (FOUND-04 substrate)

#### Agents (modernization)

- `@planner` — Opus, xhigh, read-mostly; produces PLAN.md tactical breakdown. (AGENT-03)
- `@verifier` — Opus, xhigh, read-only; produces COVERED/PARTIAL/MISSING per success criterion. (AGENT-04)
- `@spec-reviewer` (pre-execution) and `@code-reviewer` (post-execution) — Sonnet, high; two-stage read-only review split. (AGENT-05)
- `scripts/check-frontmatter.sh` — pure-bash + jq + awk linter; refuses commits with malformed agent metadata. (AGENT-06)

#### Hooks (mechanical quality gates)

- `hooks/pre-tool-use.sh` — blocks `git commit --no-verify`, `git push --force` to main, hardcoded secret patterns (AWS keys, GitHub PATs, JWT shapes). (HOOK-01, HOOK-02)
- `hooks/post-tool-use.sh` — surfaces failed quality-gate exit codes from `bash -e` chains in the next assistant turn. (HOOK-03)
- `hooks/session-start.sh` — reads `.planning/STATE.md` and injects current-brief context (active brief #, status, next command). (HOOK-04)
- `hooks/post-compact.sh` — reads agent / skill lists from the live filesystem; quality gates from `config/quality-gates.txt`. (HOOK-05)

#### Skills (workflow rebuild)

- 11 user-facing skills shipping the new arrow chain: `/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`. (WORKFLOW-01..WORKFLOW-09)
- Auto Mode detection in every workflow skill — recognizes `## Auto Mode Active` and routes to defaults. (WORKFLOW-11)
- `skills/_shared/init-context.sh` — pure-bash + jq state helper consumed by skills. (WORKFLOW-12)
- `.planning/` artifact templates under `templates/.planning/`. (WORKFLOW-13)

#### Quality (CI, tests, docs)

- `.github/workflows/ci.yml` — 5 lint gates (shellcheck, frontmatter, version-drift, parity, vocab) + bats matrix on `macos-latest` + `ubuntu-latest`. (QUAL-01)
- `tests/install.bats` — install round-trip + uninstall + reinstall + adversarial-branch hook fixtures + settings-merge regression. (QUAL-02, QUAL-07)
- `scripts/check-parity.sh` — plugin/manual hooks parity gate (byte-for-byte after `${CLAUDE_PLUGIN_ROOT}` normalization). (QUAL-03)
- `scripts/check-vocab.sh` — vocabulary + surface-count gate; refuses forbidden tokens in user-facing surface. (QUAL-04)

### Changed

- `install.sh` — version sourced from `plugin.json:.version` at runtime via `jq`; per-file `[d/s/r/a/k]` diff/skip/replace prompt for customizations; non-TTY default keeps customizations; v1.x migration is detection-only (never destroys). (FOUND-01, FOUND-02, FOUND-09)
- `uninstall.sh` — version sourced from `plugin.json`; refuses on `~/.claude/.claude-godmode-version` mismatch unless `--force`; jq preflight added. (FOUND-03)
- `config/statusline.sh` — collapsed 4 `jq` invocations into 1 `@tsv` filter. (FOUND-06)
- 8 v1.x agents migrated to v2 frontmatter convention (model alias, effort tier, `Connects to:` line, `maxTurns` ceiling, `isolation: worktree` for code-writers, `memory: project` for persistent learners). (AGENT-07)
- `.claude-plugin/plugin.json` — description and keywords polished for marketplace SEO; version bumped to 2.0.0; `userConfig.model_profile` preserved. (QUAL-06)
- `README.md` — rewritten to v2 9-section skeleton (≤500 lines, tutorial-first, no v1.x vocabulary). (QUAL-05)
- `commands/godmode.md` — drops literal version from heading; statusline carries it. (FOUND-02)

### Fixed

- Hook JSON construction now uses `jq -n --arg` exclusively; valid JSON under adversarial branch names (quote, backslash, newline, apostrophe). (FOUND-04 / CONCERNS #6)
- Hook cwd resolution from stdin envelope (not bare `pwd`); stdin-drain tolerance with `cat > /dev/null || true` under `set -euo pipefail`. (FOUND-05 / CONCERNS #7, #18)
- Settings merge no longer drops top-level user keys not in template — deep-merge via `jq -s '.[0] * .[1]'`. (QUAL-07 / CONCERNS #3)
- Agent routing — explicit `subagent_type` mapping prevents Claude Code from substituting built-in agents for godmode agents. (AGENT-08)

### Removed

- v1.x `/prd`, `/plan-stories`, `/execute` skills are deprecated with migration banners; will be removed in v2.x. (WORKFLOW-10)
- v1.x version literals from `install.sh`, `commands/godmode.md`, `README.md` — single source of truth is now `.claude-plugin/plugin.json:.version`. (FOUND-02)
- v1.x heredoc JSON construction in hooks — replaced everywhere by `jq -n --arg`. (FOUND-04)

### Security

- PreToolUse hook blocks `git commit --no-verify`, `git commit -n`, `git push --force` to `main`/`master`, and hardcoded secret patterns (AWS keys, GitHub PATs, common JWT shapes) — refuses with clear remediation. (HOOK-01, HOOK-02)
- Read-only agents (`@architect`, `@security-auditor`, `@reviewer`, `@spec-reviewer`, `@code-reviewer`, `@verifier`, `@researcher`) declare `disallowedTools: Write, Edit` — read-only enforced mechanically, not by convention. (AGENT-07)

## v1.x.x

v1.x history compressed. The v1.x pipeline was `/prd → /plan-stories → /execute → /ship` with 8 agents and 8 skills. v2.0.0 supersedes the entire surface; v1.x deprecation banners on `/prd`, `/plan-stories`, `/execute` guide migration through v2.x. For v1.x release-by-release detail, see git history before tag `v2.0.0`.
