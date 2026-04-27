# Phase 5: Quality — CI, Tests, Docs Parity - Discussion Log

> **Audit trail only.** Decisions are captured in CONTEXT.md.

**Date:** 2026-04-27
**Phase:** 05-quality-ci-tests-docs-parity
**Mode:** Interactive (4 user-answered AskUserQuestion calls; remaining decisions taken as recommended defaults)
**Areas discussed:** CI workflow shape, README + marketplace tone, bats fixture organization, v2.0.0 release process, vocab gate exceptions, surface-count gate, parity gate normalization, marketplace metadata, settings merge regression, CHANGELOG format

---

## CI workflow shape (QUAL-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Single ci.yml with matrix | One workflow file, one job per gate, bats matrix [macos, ubuntu]. Each gate independently passing/failing. | ✓ |
| Split per-concern workflows | ci-lint.yml + ci-test.yml + ci-parity.yml. More files; logs scoped per concern. | |
| Single ci.yml, single job, all gates inline | One workflow, one job, gates sequential. Loses per-gate signal — fails QUAL-01 SC #1. | |

**User's choice:** Single ci.yml with matrix (recommended). Captured as D-01..D-04.

---

## README + marketplace tone (QUAL-05, QUAL-06)

| Option | Description | Selected |
|--------|-------------|----------|
| Punchy + tutorial-first | Quick-start in first 30 lines; "Senior engineering team, in a plugin." marketplace tagline. Maximizes install rate. | ✓ |
| Precise + reference-first | Capability catalog upfront, tutorial after. Best for users who already know they want a workflow plugin. | |
| Technical-deep, doc-style | Manual structure: architecture diagram → rationale → tutorials. Slowest to first install. | |

**User's choice:** Punchy + tutorial-first (recommended). Captured as D-18..D-21, D-25.

---

## bats fixture organization (QUAL-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Single tests/install.bats with @load helpers | Matches QUAL-02 SC verbatim; fixtures in tests/fixtures/. Easy CI invocation. | ✓ |
| Split: install / uninstall / reinstall / hooks bats files | Run individual scenarios locally. More boilerplate. | |
| Single file, inline fixtures | Smallest footprint; harder to extend. | |

**User's choice:** Single tests/install.bats with @load helpers (recommended). Captured as D-05..D-08, D-30.

---

## v2.0.0 release process

| Option | Description | Selected |
|--------|-------------|----------|
| Tag from main after PR merge | repo-polish PR merges → CI green → `git tag v2.0.0 && git push --tags`. Conventional. | ✓ |
| Tag from a release/v2.0.0 branch | Cut release branch first. Adds branch lifecycle overhead for v2.0.0; better for v2.x. | |
| Tag from main directly (no PR) | Push to main, tag immediately. Skips review. Not recommended for milestone release. | |

**User's choice:** Tag from main after PR merge (recommended). Captured as D-27..D-29.

---

## Recommended defaults applied (no user prompt needed — captured inline)

- **Vocab gate per-file allowlist** (D-13): `task` token allowed in `skills/{build,verify,ship}/SKILL.md`; v1.x deprecated bodies below `--- v1.x body below ---` separator entirely exempt. Inherited from Phase 4 hand-off contracts.
- **Parity gate normalization** (D-10): `${CLAUDE_PLUGIN_ROOT}` → `~/.claude` substitution before diff. The one accepted divergence; everything else byte-for-byte.
- **Surface-count gate** (D-16, D-17): wired into `scripts/check-vocab.sh` inline; uses Phase 4's canonical `find` recipe with explicit prunes for `_shared`, `prd`, `plan-stories`, `execute`. Externalize to `scripts/check-surface.sh` only if inline check exceeds ~30 lines.
- **CHANGELOG format** (D-22..D-24): Keep-a-Changelog format; v2.0.0 entry grouped by milestone area; v1.x history compressed into one block at the bottom.
- **Marketplace description** (D-25): `"Senior engineering team, in a plugin. One arrow chain (/godmode → /mission → /brief → /plan → /build → /verify → /ship), 11 skills, mechanical quality gates."` (197 chars). Keywords: workflow, agents, skills, hooks, planning, quality-gates, auto-mode, claude-code.
- **Settings merge regression test** (D-30, D-31): dedicated bats `@test` setting `customKey` outside template, asserting it survives reinstall. Implementation hint: `jq -s '.[0] * .[1]'` deep-merge with right-side priority for top-level keys.
- **CI gate ordering** (D-04): failure-likelihood gradient (shellcheck → frontmatter → version-drift → parity → vocab → bats). Matches developer's debugging order.
- **bats-core version pin** (D-08): v1.13.0 per STACK.md.
- **CI external deps** (D-02): only `actions/checkout@v4` and `ludeeus/action-shellcheck@master`. No setup-node/python/ruby.

---

## Claude's Discretion

- Exact CHANGELOG bullet wording (the planner curates from milestone closing commits)
- Exact CI gate job ordering in YAML (D-04 recommends; planner may reorder)
- Exact bats fixture JSON shape for adversarial branches (D-07 specifies the principle)
- Whether surface-count check stays inline in `check-vocab.sh` or extracts to `check-surface.sh` (D-17 size threshold)
- Whether the README terminal-cast GIF ships (D-20 marks optional; defer if production cost > marginal install gain)
- README FAQ specific questions (5 evergreen Qs as fallback)
- Exact order of CHANGELOG sub-bullets within a release section

---

## Deferred Ideas

- Pre-commit hook installer for end users (v2.x)
- Plugin marketplace screenshots / animated GIFs (v2.x)
- Cross-AI peer review of Phase 5 plans (user-optional; not default in --auto)
- Documentation site separate from README (v2.x)
- `scripts/check-surface.sh` extraction (only if inline exceeds ~30 lines)
- `config/vocab-allowlist.txt` externalized (only if inline exceeds ~10 entries)
- Release branches `release/v2.0.x` (only when hotfix volume warrants)
- CI matrix beyond ubuntu-latest + macos-latest (v2.x may add LTS variants)
- Performance/timing benchmarks (out of scope per PROJECT.md "no telemetry")
- Mechanically enforced tag protection (v2.x; relies on GitHub UI in v2.0)
- Minimum Claude Code version compatibility floor (README mentions; full version-matrix is v2.x)
- `bats-assert` / `bats-support` library helpers (reconsider in v2.x)
- `cosign` / supply-chain attestation on releases (v2.x)

---

*Phase: 05-quality-ci-tests-docs-parity*
*Discussion logged: 2026-04-27*
