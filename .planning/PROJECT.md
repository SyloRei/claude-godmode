# Project: claude-godmode v3

**Updated:** 2026-05-25

## Purpose
Evolve claude-godmode from the best-in-class spec-first workflow plugin for Claude Code into a distribution-ready v3 — without abandoning the "one workflow, ≤12 surface" opinionated stance. The bet stays the same: a single legible spine plus a small team of constraint-enforcing agents, not a buffet of 100+ specialists. v3 closes the credibility gaps (model_profile not wired, single-lens review, no MCP/LSP/output-styles, low discoverability) while keeping the CI rigor and worktree isolation that make the workflow actually hold.

Source of truth: `docs/v3-roadmap.md` (approved competitive analysis + phased plan).

## Success Criteria
- `userConfig.model_profile` switches model tier and effort at agent spawn time (quality/balanced/budget), verified by a `model-profile.bats` test; a `budget` run on a trivial feature costs <$0.10.
- `/verify N` fans out 5 parallel review lenses (code, security, perf, convention, test) with confidence-scored, categorized findings.
- Rules reach "active" state on a fresh install with zero user steps (SessionStart `additionalContext`), retiring the `/godmode` rule-install dance.
- Plugin ships `.mcp.json` (opt-in), `outputStyles/`, and bundled deterministic scripts in spine skills.
- Published to the `claude-community` marketplace; `AGENTS.md` generated for cross-tool reuse.
- Every CI gate stays green throughout (shellcheck, JSON/frontmatter lint, version-drift, parity, vocab, surface-count, bats) on Ubuntu+macOS.

## Constraints
- Language-agnostic core; no Node/Python/Ruby required in CI. Per-language depth ships only as opt-in sub-plugins.
- Surface-count gate stays (≤12 spine; off-spine skills counted per the gate's rules) — load-bearing for positioning.
- Worktree isolation for code-writing agents is non-negotiable.
- Alias models only; no pinned model IDs.
- Mechanical enforcement over instruction: prefer PreToolUse blocks, `disallowedTools`, deterministic scripts, and CI gates over rule-file prose.
- Do NOT auto-install MCP servers; ship `.mcp.json` as opt-in reference.
- MIT license; plugin/manual install parity maintained.

## Decisions
- [2026-05-25] Adopt `docs/v3-roadmap.md` as project direction — approved competitive analysis; phases map 1:1 to roadmap units.
- [2026-05-25] Position as workflow-rigor leader ("what feature-dev is to one feature, godmode is to the whole pipeline"), not on agent breadth. Anti-goal: 80+ language specialists in core.
- [2026-05-25] Phase 1 (v2.1) leads with the three P0 items: P1.1 model_profile wiring, P1.5 output style, P1.3 rules→SessionStart.
