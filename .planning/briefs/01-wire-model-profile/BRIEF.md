# Brief 01: Wire model_profile

**Updated:** 2026-05-25
**Roadmap unit:** 1 — quality/balanced/budget switches model tier + effort at spawn time; `model-profile.bats` proves it

## Why
`userConfig.model_profile` is declared in the manifest and exposed to hooks as `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE}`, but **nothing consumes it** — the README FAQ admits this verbatim (README.md:442). The "quality / balanced / budget" preset table is therefore dead documentation, and the Haiku-tier cost story competitors lack goes unfulfilled. This is the highest-ROI P0 item: make the knob actually change what gets spawned, honestly and mechanically.

**Platform reality that shapes the design:** an agent's `effort` is frontmatter-only — the platform cannot override it at spawn. `model` *can* be overridden at spawn (Agent tool `model` param). So "wiring" means **model-only switching at spawn**, with effort left to frontmatter and the limitation documented. Beneficiary: any user who sets a profile and expects cheaper/cheaper-or-more-careful runs to actually happen.

## What

### In scope
- A deterministic resolver (`bin/godmode-model`) that maps `(agent, profile)` → `model effort`, with the code-writer effort carve-out baked in.
- `balanced` reads each agent's own frontmatter `model`/`effort` (single source of truth = the agent files); `quality` and `budget` apply the preset rules.
- Spine skills `/build`, `/verify`, `/ship` instruct spawning agents with the resolver's **model** value via the Agent tool's `model` override.
- Reading the active profile from `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE}`, defaulting to `balanced` when unset/empty/unrecognized.
- `tests/model-profile.bats` proving the resolution table (incl. carve-out and default fallback).
- README FAQ "Current state" paragraph updated to reflect model switching is now wired (model-only), effort noted as platform-limited at spawn.

### Out of scope
- Effort enforcement at spawn (platform can't do it) — and per-profile agent file variants to fake it.
- Soft effort hints injected into agent context (the rejected "model + soft effort" option).
- Surfacing the active profile in the statusline — that is unit 13 (P3.4).
- Cost tracking to `.planning/COSTS.md` — also unit 13.
- Any change to the `/debug`, `/tdd`, `/refactor`, `/explore-repo` helpers or to agent frontmatter values themselves.

## Spec — acceptance criteria
Each criterion is verifiable and carries a stable **`AC-N`** label.

- [ ] **AC-1:** `bin/godmode-model <agent> <profile>` is executable, prints exactly `<model> <effort>` (space-separated, single line) to stdout and exits 0 for a known agent + valid profile. An unknown agent or unrecognized profile exits non-zero with a message on stderr.
- [ ] **AC-2:** Under `balanced`, the resolver echoes each agent's own frontmatter values — e.g. `godmode-model writer balanced` → `opus high`; `godmode-model reviewer balanced` → `sonnet high`; `godmode-model architect balanced` → `opus xhigh`.
- [ ] **AC-3:** Under `quality`, every non-code-writing agent maps to `opus xhigh` — verified for `architect`, `planner`, `verifier`, `security-auditor`, `reviewer`, `code-reviewer`, `spec-reviewer`, `doc-writer`, `researcher`.
- [ ] **AC-4:** Under `quality`, the three code-writing agents `writer`, `executor`, `test-writer` map to `opus high` — effort capped at `high`, **never** `xhigh` (the locked carve-out).
- [ ] **AC-5:** Under `budget`, every agent maps to `haiku default`.
- [ ] **AC-6:** When `${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE}` is unset, empty, or not one of `quality|balanced|budget`, the resolver treats the profile as `balanced` (no error for the empty/unset case; only an explicit bad *argument* errors per AC-1).
- [ ] **AC-7:** `skills/build/SKILL.md`, `skills/verify/SKILL.md`, and `skills/ship/SKILL.md` each instruct: resolve the active profile, call `bin/godmode-model` per agent, and pass the resulting model to the Agent tool's `model` override at spawn; each notes effort is frontmatter-only and not set at spawn.
- [ ] **AC-8:** `tests/model-profile.bats` exists and asserts AC-2 through AC-6; `bats tests/` passes (pinned bats v1.13.0) with the new tests included.
- [ ] **AC-9:** README FAQ "Current state (be honest)" paragraph (README.md:442) is rewritten to state model switching is now consumed at spawn (model-only), with the effort-is-frontmatter limitation kept explicit. No stale "nothing in the plugin yet consumes the value" claim remains.
- [ ] **AC-10:** All existing CI gates stay green: shellcheck (v0.11.0), JSON lint, frontmatter lint, version-drift, plugin/manual parity, vocab, surface-count (≤12), bats — on both Ubuntu and macOS.
- [ ] **AC-11 (live benchmark, manual):** With `model_profile=budget`, a `/build`-style run that spawns a code-writing agent on a trivial change spawns it with `model: haiku` and the session cost for that agent is **< $0.10**. Marked manual because it requires real API spend; not gated in CI.

## Assumptions
- The resolver classifies code-writing agents via an explicit allowlist `{writer, executor, test-writer}`; all other agents are treated as read-only/design for the `quality` → `xhigh` rule. (To be confirmed in `/plan 1`.)
- `balanced` resolution reads `model:`/`effort:` from `agents/<name>.md` frontmatter at runtime, keeping agent files the single source of truth rather than duplicating a table in the resolver.
- The resolver is POSIX shell (consistent with `bin/godmode-state`), no new runtime dependency, so it stays inside the language-agnostic / no-Node-Python CI constraint.
- Parity gate: `bin/godmode-model` must be present and identical in both plugin-cache and manual-install layouts (same as other `bin/` scripts).
