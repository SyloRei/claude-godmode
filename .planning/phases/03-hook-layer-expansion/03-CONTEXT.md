# Phase 3: Hook Layer Expansion - Context

**Gathered:** 2026-04-26 (auto mode — recommended defaults applied without prompts)
**Status:** Ready for planning

<domain>
## Phase Boundary

Mechanical (not aspirational) quality gates ship. After Phase 3, the user **cannot bypass** the 6 quality gates without an explicit `--force` flag — the substrate refuses. Specifically:

- New `hooks/pre-tool-use.sh` blocks `Bash(git commit --no-verify*)`, `git commit -n*`, `--no-gpg-sign*`, `git push --force` to `main`/`master`, and other quality-gate-bypass patterns. It also scans tool input for hardcoded secret patterns (AWS keys, GitHub PATs, generic `api_key=...`/`secret=...`/`password=...`).
- New `hooks/post-tool-use.sh` detects when a typecheck/lint/test command exited non-zero and surfaces the failure via `additionalContext` into the next assistant turn.
- Existing `hooks/session-start.sh` reads `.planning/STATE.md` if present and injects current-brief context (active brief #, status, next command). The v1.x `.claude-pipeline/` stories.json detection is replaced.
- Existing `hooks/post-compact.sh` vocabulary aligned to v2 chain (`/godmode → /mission → /brief → /plan → /build → /verify → /ship`); the v1.x `Pipeline: /prd → /plan-stories → /execute → /ship` line replaced.
- Both hook configs (`hooks/hooks.json` for plugin-mode, `config/settings.template.json` for manual-mode) declare equivalent bindings, timeouts, and permission rules. M5 (QUAL-03) asserts byte-for-byte parity in CI; M3 keeps them aligned.

This phase ships the **safety substrate** that Phase 4's skills layer relies on. Phase 4 skills call the Agent tool — the tool dispatch is only safe behind PreToolUse/PostToolUse enforcement. Without Phase 3, gates remain documentation; with it, they're mechanically enforced.

</domain>

<decisions>
## Implementation Decisions

### PreToolUse — quality-gate bypass blocker (HOOK-01)
- **D-01:** New file `hooks/pre-tool-use.sh`. Reads stdin JSON describing the proposed tool call. Returns `permissionDecision: deny` JSON for any of these patterns in `tool_input.command` (when `tool_name == "Bash"`):
  - `git commit --no-verify` (or `--no-verify=true`)
  - `git commit -n` (short form — must match `\bgit\s+commit\b.*\s-n\b` to avoid false-positives on `-n` as a flag for other commands)
  - `git commit --no-gpg-sign` (and `--no-gpg-sign=true`)
  - `git -c commit.gpgsign=false commit` (config override)
  - `git push --force` (or `-f`) to `main`, `master`, or `origin/main`/`origin/master`
- **D-02:** Bypass mechanism: a tool input matching the `--force` pattern + the user explicitly typed `claude-godmode-force-bypass` as part of the command (a deliberate, hard-to-mistype guard) is allowed. v2.0 prefers no bypass at all; bypass-or-not is a v2.1 design call.
- **D-03:** Refusal output format (per Claude Code 2026 hook contract):
  ```json
  {
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "additionalContext": "[godmode-pre-tool-use] BLOCKED: <pattern> bypasses quality gates. See rules/godmode-quality.md. Use the gates-respecting path: <suggestion>."
    }
  }
  ```
  Decision precedence: `deny > defer > ask > allow` per STACK.md research.
- **D-04:** No-op fast-path: when `tool_name != "Bash"` OR `tool_input.command` doesn't match any blocked pattern, hook returns `{}` (allow by absence). Sub-millisecond fast-path; doesn't slow tool dispatch.

### PreToolUse — secret pattern scan (HOOK-02)
- **D-05:** Same hook (`pre-tool-use.sh`) — secret scan runs after the bypass blocker. Patterns refused:
  - AWS keys: `AKIA[0-9A-Z]{16}` (access key prefix), `aws_secret_access_key\s*=\s*['"]?[A-Za-z0-9/+=]{40}['"]?`
  - GitHub PATs: `ghp_[A-Za-z0-9]{36}`, `github_pat_[A-Za-z0-9_]{82}`
  - JWT shape (heuristic): `ey[A-Za-z0-9_-]+\.ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`
  - Generic: `(api[_-]?key|secret|password|token)\s*=\s*['"][^'"]+['"]`
- **D-06:** Exemption pattern list documented inline in the hook. Test fixtures, mock data, `.env.example`, and clearly-fake values like `xxxxx`, `your-key-here`, `change-me`, `<TOKEN>` get a pass via path allow-list (`tests/`, `*.example`, `*.md`).
- **D-07:** Refusal output is the same format as D-03, with `[godmode-secret-scan]` prefix and remediation pointer ("use env var or read from `.env`; never hardcode in source").
- **D-08:** False-positive tolerance: the linter is bias-toward-block. False-positives in test fixtures are fine — exemption list grows over time as patterns surface. False-negatives (real secrets slip through) are unacceptable.

### PostToolUse — failed gate surfacing (HOOK-03)
- **D-09:** New file `hooks/post-tool-use.sh`. Reads stdin JSON describing the just-completed tool call (`tool_name`, `tool_input`, `tool_output`, `tool_exit_code`). When the tool was `Bash` and the command matches a quality-gate pattern (`tsc`, `eslint`, `pytest`, `cargo test`, `go test`, `bats`, `npm test`, `yarn test`, `pnpm test`, `bun test`) AND the exit code is non-zero, inject `additionalContext` into the next turn:
  ```
  [godmode-post-tool-use] Last quality-gate command exited non-zero: <command> → exit <code>. Address before continuing.
  ```
- **D-10:** Other commands (cat, ls, grep) are no-op fast-path. Only the gate-pattern set fires the surfacing.
- **D-11:** When `tool_exit_code` is 0 (success), no surfacing. The gate passing is silent.

### SessionStart — STATE.md injection + v1.x compat (HOOK-04)
- **D-12:** `hooks/session-start.sh` modification:
  1. **Add** `.planning/STATE.md` detection. If present, parse the front matter / Current Position section to extract: `active phase`, `status`, `last_activity`, and the "Next command" line.
  2. **Inject** as a separate context block: `Active phase: <N> — <name>. Status: <status>. Next: <next command>. Last activity: <date>.`
  3. **Keep** the v1.x `.claude-pipeline/` detection logic — but downgrade its message to a one-liner deprecation: `[v1.x] .claude-pipeline/ detected. Run /mission to migrate.` No more "Run /execute" or "Run /plan-stories" hints (v1.x deprecation).
  4. **Replace** the trailing `Pipeline: /prd → /plan-stories → /execute → /ship` line with the v2 chain: `Workflow: /godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship`.
- **D-13:** STATE.md parsing: `awk` to extract values from YAML front matter (the new GSD-style STATE.md has `gsd_state_version: 1.0` etc.) AND from the legacy markdown body (the bespoke STATE.md format). Supporting both: GSD-style first; fall back to markdown body if YAML keys not found.
- **D-14:** When neither STATE.md nor `.claude-pipeline/` exist, the session-start hook still injects: project type detection (existing logic) + workflow chain reminder. No regression on greenfield repos.

### PostCompact — vocabulary alignment (HOOK-05)
- **D-15:** `hooks/post-compact.sh` is already done at the substrate level (Phase 1 added live FS scan + gates-from-config). Phase 3 only updates the v1.x `Feature Pipeline: /prd → ...` line at the bottom of `$CONTEXT_BLOCK` to: `Workflow: /godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship`.
- **D-16:** Also update the `PIPELINE_STATE` detection (lines 38-58 of post-compact.sh, the stories.json parsing). v1.x `.claude-pipeline/` detection downgrades to a one-line deprecation note: `[v1.x] .claude-pipeline/ detected.` No "Next: <story>" parsing — that was v1.x-specific.
- **D-17:** Add new `.planning/STATE.md`-aware section parallel to D-12: if STATE.md exists, parse `active phase` / `status` / `next command` and inject. (Same parsing routine as D-13.)

### Hook bindings parity (HOOK-06)
- **D-18:** `hooks/hooks.json` already declares `"timeout": 10` on both SessionStart and PostCompact. `config/settings.template.json` does NOT — it's missing the timeout field. Fix: add `"timeout": 10` to both bindings in `settings.template.json`.
- **D-19:** Add `PreToolUse` and `PostToolUse` blocks to BOTH config files. Plugin-mode binding (`hooks.json`):
  ```json
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh", "timeout": 5 }]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/post-tool-use.sh", "timeout": 5 }]
    }
  ]
  ```
  Manual-mode binding (`settings.template.json`): same shape, with `~/.claude/` path prefix.
- **D-20:** `matcher: "Bash"` scopes both hooks to Bash tool dispatch only — they don't run on Read/Edit/Write/Grep/Glob (those are not gate-relevant). Sub-millisecond fast-path for non-Bash tools.
- **D-21:** Timeout 5 seconds for Pre/PostToolUse (faster than 10 — these run on EVERY Bash dispatch and must be quick). 10 seconds for SessionStart/PostCompact (those only fire on session boundaries — can be slower).
- **D-22:** Phase 5's `scripts/check-parity.sh` (QUAL-03) asserts byte-for-byte agreement between the two configs. Phase 3 ships them aligned; Phase 5 mechanically enforces.

### Out of scope for Phase 3 (mapped elsewhere)
- **OUT-01:** Wiring `pre-tool-use.sh` to call `scripts/check-frontmatter.sh` when an agent file is being committed — Phase 3 ships the hook substrate; Phase 4's `/build N` skill orchestrates the cross-call. The hook itself doesn't invoke other scripts in v2.0.
- **OUT-02:** `claude-godmode-force-bypass` magic phrase as the hard-to-mistype `--force` guard — v2.1. v2.0 has NO bypass; refusal is final.
- **OUT-03:** Telemetry on hook firings (how often blocked, what patterns, false-positive rate) — out of scope per PROJECT.md "no telemetry".
- **OUT-04:** Per-hook performance budget enforcement — v2.1 may add `/godmode profile-hooks` to time hook execution and refuse if any hook exceeds 100ms p99.

### Claude's Discretion
- Exact wording of `additionalContext` strings in PreToolUse/PostToolUse refusals — keep concise and remediation-pointer-rich; pattern lifted from install.sh's `error()` messages.
- Pattern regex tightening — D-01..D-05 lock the conceptual targets; if the planner finds a tighter regex that catches the same set without false-positives, override the regex and document.
- Whether the secret-scan exemption list lives inline in the hook or in a separate `config/secret-scan-exemptions.txt` file — recommend inline for v2.0 (small list, zero-config); externalize when the list grows past ~10 entries.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project context
- `.planning/PROJECT.md` — Active section "Hook layer expansion" subsection (the 6 HOOK-NN bullets); Constraints (mechanical enforcement vs. aspirational rules)
- `.planning/REQUIREMENTS.md` — HOOK-01..HOOK-06 (the 6 requirements this phase delivers)
- `.planning/ROADMAP.md` § Phase 3 — Goal, Success Criteria, Plans (3 plans)

### Prior phases
- `.planning/phases/01-foundation-safety-hardening/01-CONTEXT.md` — D-08, D-09 (jq -n --arg pattern); D-19 (post-compact two-commit rationale, now consumed); D-20..D-22 (live FS scan; consumed in Phase 1)
- `.planning/phases/01-foundation-safety-hardening/01-VERIFICATION.md` — confirms substrate is solid
- `.planning/phases/02-agent-layer-modernization/02-CONTEXT.md` — D-21..D-23 (frontmatter linter; this phase MAY wire it but does not require it)
- `.planning/phases/02-agent-layer-modernization/02-VERIFICATION.md` — confirms agents are linter-clean

### Research (current pass)
- `.planning/research/STACK.md` § "Hook contracts" — full per-event stdin/stdout JSON shapes, `permissionDecision` precedence, `additionalContext` cap (10000 chars), runtime does NOT validate emitted JSON (substrate's job to validate)
- `.planning/research/STACK.md` § "PreToolUse" — `tool_name`, `tool_input` schema, `permissionDecision: allow|deny|ask|defer`
- `.planning/research/STACK.md` § "PostToolUse" — `tool_exit_code`, `tool_output`, `additionalContext` injection
- `.planning/research/PITFALLS.md` § CR-02 (heredoc + branch fuzz — DON'T regress); § HI-03 (plugin/manual parity drift); § CR-06 (Auto Mode rubber-stamp drift)
- `.planning/research/FEATURES.md` F-23..F-27, F-28 — the hook-layer feature catalog

### v1.x baseline (post-Phase-1 state)
- `hooks/session-start.sh` — already has Phase 1 substrate (INPUT capture, cwd-from-stdin, jq -n --arg). Needs HOOK-04 (STATE.md read + vocabulary update).
- `hooks/post-compact.sh` — already has Phase 1 substrate (live FS scan, gates from quality-gates.txt, jq -n --arg). Needs HOOK-05 (vocabulary update).
- `hooks/hooks.json` — declares SessionStart + PostCompact bindings with timeout 10. Phase 3 adds PreToolUse + PostToolUse.
- `config/settings.template.json` — declares hooks block but missing timeouts. Phase 3 adds timeouts AND the new PreToolUse/PostToolUse bindings.

### Source files this phase touches
- `hooks/session-start.sh` (HOOK-04)
- `hooks/post-compact.sh` (HOOK-05)
- `hooks/pre-tool-use.sh` (NEW — HOOK-01, HOOK-02)
- `hooks/post-tool-use.sh` (NEW — HOOK-03)
- `hooks/hooks.json` (HOOK-06 — add PreToolUse + PostToolUse blocks)
- `config/settings.template.json` (HOOK-06 — add timeouts + PreToolUse + PostToolUse blocks)

### New files this phase creates
- `hooks/pre-tool-use.sh`
- `hooks/post-tool-use.sh`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (from Phase 1)
- **`hooks/session-start.sh:8`** — `INPUT=$(cat || true)` capture pattern. Reuse in pre-tool-use / post-tool-use.
- **`hooks/post-compact.sh:12`** — `printf '%s' "$INPUT" | jq -r '.cwd // empty'` cwd extraction. Reuse pattern.
- **`hooks/post-compact.sh:64-66`** — `jq -n --arg ctx "$CTX" '{hookSpecificOutput: ...}'` JSON output. Reuse for PreToolUse/PostToolUse refusal output.
- **`scripts/check-version-drift.sh`** — pure-bash + grep + jq style for the two new hook scripts.
- **`config/quality-gates.txt`** — 6-line SoT. Pre-tool-use's `--no-verify` block message points users at this file.

### Established Patterns
- `set -euo pipefail` at top of every hook
- `INPUT=$(cat || true)` to tolerate stdin closure under pipefail
- `jq -n --arg KEY "$VAL"` for ALL JSON construction (never heredoc)
- `awk '/^---$/{count++; if(count==2)exit} count==1 && match(...)'` for YAML frontmatter parsing (lifted from `scripts/check-frontmatter.sh`)
- `case "$cmd" in *PATTERN*)` for substring matching (POSIX, bash 3.2 compatible)
- `[ "$tool_name" = "Bash" ]` not `[[ "$tool_name" =~ ... ]]` (POSIX preferred for portability)

### Integration Points (downstream)
- **Phase 4** (`/build N` skill) relies on PreToolUse to prevent `--no-verify` and on PostToolUse to surface failed gates. Without Phase 3, `/build` would have to repeat these checks inline — fragile and bypasseable.
- **Phase 4** (`/godmode` skill) reads STATE.md the same way SessionStart does — the parsing logic in HOOK-04 should be lifted into a shared helper if it ends up duplicated.
- **Phase 5** (CI) runs `scripts/check-parity.sh` (QUAL-03) which asserts hooks.json and settings.template.json byte-for-byte equivalence. Phase 3 must keep them perfectly aligned.

### Anti-patterns to AVOID
- **Heredoc + variable interpolation in hook output** — closes CR-02; do NOT regress (Phase 1 substrate already enforced this in session-start.sh / post-compact.sh; new hooks must match)
- **Hardcoded skill/agent lists in pre-tool-use refusal messages** — use the live FS scan substrate (FOUND-11) if any pre-tool-use logic needs to enumerate skills
- **Tool-input parsing without `jq`** — `pre-tool-use.sh` MUST parse `tool_input.command` via `jq`, never via grep on raw JSON

</code_context>

<specifics>
## Specific Ideas

- **Hook timing.** PreToolUse/PostToolUse fire on every Bash dispatch. Their fast-path (when no pattern matches) MUST be sub-millisecond — single jq invocation, single case match, return `{}`. Bench during Phase 5 if needed.
- **STATE.md format support (D-13).** GSD writes YAML front matter (`---\ngsd_state_version: 1.0\n...\n---\n`). The bespoke v1 STATE.md (archived) had a markdown body with `## Current Position` table. Both should parse — GSD format takes precedence.
- **Bypass words discipline.** D-02 reserves `claude-godmode-force-bypass` for v2.1. Documented but NOT implemented in v2.0. The hook source-file MUST contain a comment explaining the deferral so the next maintainer doesn't add it casually.
- **Pattern test fixtures.** The Phase 1 fixture pattern (placeholders + setup script) doesn't quite fit here — Pre/PostToolUse fixtures are JSON inputs the hook consumes. Add `tests/fixtures/hooks/pre-tool-use/` with one JSON per pattern (commit-no-verify.json, commit-short-form.json, secret-aws.json, secret-github.json, normal-bash.json) and run them in Phase 5 bats smoke.

</specifics>

<deferred>
## Deferred Ideas

- **`claude-godmode-force-bypass` magic phrase as a hard-to-mistype --force guard.** v2.1 design call. v2.0 refuses, period.
- **Hook performance budget enforcement** (`/godmode profile-hooks`). v2.1 if hook latency becomes user-visible.
- **Telemetry on hook firings.** Out of scope per PROJECT.md (no telemetry, ever).
- **Externalizing the secret-scan exemption list to `config/secret-scan-exemptions.txt`.** When the list grows past ~10 entries; v2.0 keeps it inline.
- **Wiring `scripts/check-frontmatter.sh` into pre-tool-use.sh** for agent file commits. v2.1 — the hook doesn't currently invoke other scripts; that's a clean boundary worth preserving in v2.0.
- **Per-hook regex tightening** based on observed false-positives. Iterate post-ship.
- **`PreToolUse` for non-Bash tools** (refusing Edit on certain paths, refusing Write to source from `@code-reviewer`, etc.). v2.1 — the matcher is `"Bash"` only in v2.0 to keep blast radius small.

</deferred>

---

*Phase: 3-Hook Layer Expansion*
*Context gathered: 2026-04-26*
