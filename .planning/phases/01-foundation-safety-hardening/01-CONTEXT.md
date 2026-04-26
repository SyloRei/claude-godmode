# Phase 1: Foundation & Safety Hardening - Context

**Gathered:** 2026-04-26 (auto mode — recommended defaults applied without prompts)
**Status:** Ready for planning

<domain>
## Phase Boundary

The substrate stops fighting the user. After Phase 1 ships, hand-edited customizations survive reinstall, hooks emit valid JSON under adversarial branch names, the plugin reports a single source-of-truth version (`plugin.json`), the uninstaller refuses on version mismatch, the v1.x migration is detection-only, the backup directory caps at 5 entries, and every shipped `*.sh` file is `shellcheck`-clean. Six of nine High-severity items in the v1.x codebase audit close.

This phase ships **substrate only** — install/uninstall hardening, hook safety primitives, the live-FS indexing foundation, the gates SoT file, the version-drift CI script, and `.shellcheckrc`. It does NOT ship: agent modernization (Phase 2), new hooks (Phase 3), new skills (Phase 4), or CI workflow (Phase 5). PostCompact gets two atomic commits in this phase: substrate fixes (JSON/cwd/stdin/live-FS) separately from gates-file-read, so Phase 3's PostCompact rewrite for v2 vocabulary lands cleanly on top.

</domain>

<decisions>
## Implementation Decisions

### Per-file installer prompt UX (FOUND-01)
- **D-01:** Prompt format — `[d]iff / [s]kip / [r]eplace / [a]ll-replace / [k]eep-all`, asked once per customized file. `[d]` shows diff and re-prompts; `[a]` and `[k]` set session flags that skip future prompts in the same run. Recommended over yes/no (one option set, four UX outcomes).
- **D-02:** Non-TTY default = `[k]` keep customizations. The prior "warn count and overwrite anyway" behavior is gone. Pipe-into-bash and CI safely don't destroy customizations. The user must explicitly opt into overwrite via `--replace-all` flag (deferred to v2.1 — `[a]` on stdin works for now via `echo a | ./install.sh`).
- **D-03:** `prompt_overwrite()` helper function in `install.sh` is the single implementation; rules / agents / skills / hooks all call it. Backup taken before any choice is acted on, regardless of selection.
- **D-04:** Skills are directories (multiple files per skill); the helper walks each `skills/<name>/SKILL.md` plus any other `.md`/`.sh` siblings. Per-file prompt; `[a]` per-skill covers the whole skill dir; `[a]` per-installer covers all skills.

### Version single source of truth (FOUND-02)
- **D-05:** `install.sh` reads `VERSION` via `jq -r .version "$SCRIPT_DIR/.claude-plugin/plugin.json"` at script start. Errors out cleanly if `plugin.json` is missing or `.version` is null/empty. No `VERSION="..."` literal anywhere in `install.sh`.
- **D-06:** `commands/godmode.md` line 13 (`# Claude God-Mode v1.4.1`) → `# Claude God-Mode`. Statusline carries the runtime version (already does).
- **D-07:** `scripts/check-version-drift.sh` is a new pure-Bash + grep + jq script. Greps `install.sh`, `commands/*.md`, `README.md`, `CHANGELOG.md` for version-shaped strings; compares against canonical. CHANGELOG.md is allowed to mention old versions in headings (only the topmost `## v` heading is checked). Exits non-zero on drift with `file:line: <found>` evidence.

### Hook JSON safety (FOUND-04, FOUND-05)
- **D-08:** All hook JSON output via `jq -n --arg ctx "$CONTEXT" '{hookSpecificOutput: {hookEventName: "...", additionalContext: $ctx}}'`. Never heredoc with `${VAR}` interpolation. `--arg` is sufficient (no need for `--rawfile` — `additionalContext` strings are single-line in v1).
- **D-09:** Stdin handling: `INPUT=$(cat || true)` at start of each hook (capture once, `|| true` tolerates pipefail closure). `cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)`. If `cwd` non-empty, `cd "$cwd" 2>/dev/null || true`. `pwd`-relative checks proceed normally.
- **D-10:** Adversarial-input fixtures in `tests/fixtures/hooks/`: 5 JSON files (normal, quote-branch, backslash-branch, newline-branch, apostrophe-branch) plus `setup-fixtures.sh` that creates the temp git repos. Branch-name fuzz is the canonical bats-smoke target in Phase 5.

### Statusline single jq (FOUND-06)
- **D-11:** Collapse the four `jq -r` invocations on `config/statusline.sh:22-25` into one: `IFS=$'\t' read -r MODEL COST CTX_PCT CWD < <(printf '%s' "$INPUT" | jq -r '[(.model.display_name // "—"), (.cost.total_cost_usd // 0), (.context_window.used_percentage // 0), (.cwd // "")] | @tsv' || printf '—\t0\t0\t\n')`.
- **D-12:** Tab separator. Real macOS / Linux paths can contain tabs in theory but never in practice — `cwd` is a filesystem path. Future failure mode (path contains literal tab) documented as a known limitation; switch to `\x1f` US separator if observed in the wild.

### Backup rotation (FOUND-10)
- **D-13:** Keep last 5 entries in `~/.claude/backups/godmode-*/`. Sort by directory name (alphabetical = chronological since `godmode-YYYYMMDD-HHMMSS` is zero-padded). Portable bash 3.2 implementation: glob expansion + counter loop. No `find -print0 | sort -z` (GNU-only). No `head -n -N` (GNU-only).
- **D-14:** Rotation runs at install start, AFTER the new backup directory is created and BEFORE any copying. So the new backup is always the 1st of 5 (or fewer); the 6th-oldest gets deleted.

### Detection-only v1.x migration (FOUND-09)
- **D-15:** Replace `install.sh:57-89` (the two destructive `rm` prompts) with a single non-destructive note:
  ```
  [!] Detected v1.x state — run /mission to migrate to the v2 workflow. (No files were changed.)
  ```
  No `read`. No `rm`. No `cp` to backup (the user's `CLAUDE.md` is theirs). Detection logic: `grep -q "Quality Gates (Canonical" CLAUDE.md` OR `[ -d .claude-pipeline ]`. Two separate notes if both detected.
- **D-16:** v1.x command names (`/prd`, `/plan-stories`, `/execute`) get deprecation banners in their skill files in Phase 4 (WORKFLOW-10). Phase 1 only handles the installer-side detection.

### Uninstaller version mismatch (FOUND-03)
- **D-17:** `uninstall.sh` reads `VERSION` from `plugin.json` at script start (same pattern as `install.sh`). Compares to `~/.claude/.claude-godmode-version` content. On mismatch, prints both values and exits non-zero. `--force` flag is positional `$1`; if `==--force`, set `FORCE=1` and bypass with a clear warning. No `mapfile`-style flag parsing — one flag, simple positional.

### Gates SoT (FOUND-07)
- **D-18:** `config/quality-gates.txt` ships in Phase 1 with the 6 gates one per line, no formatting. PostCompact reads it with `awk '{printf "%d. %s\n", NR, $0}'` to render numbered. Phase 3 (HOOK-05) reuses this read; the file is shared substrate.
- **D-19:** PostCompact in Phase 1 gets TWO atomic commits per BRIEF.md risk § (preserved from archive): substrate fixes (JSON-via-jq + cwd-from-stdin + stdin-drain + live-FS scan) separately from gates-file-read. Phase 3's PostCompact rewrite for v2 vocabulary lands cleanly on top.

### Live-FS indexing substrate (FOUND-11)
- **D-20:** Canonical glob patterns: `agents/*.md`, `skills/*/SKILL.md`. Both at maxdepth 1 from their parent dirs. `find ... -maxdepth 1 -name '*.md'`. Plugin-mode root is `${CLAUDE_PLUGIN_ROOT}`; manual-mode root is `${SCRIPT_DIR}` (when run from repo) or `~/.claude/` (post-install).
- **D-21:** Ignored prefixes: `_*` (underscore-prefixed dotfile-equivalents), `README.md` (per-dir README), `*.tmpl` (Phase 4 templates). Documented in `rules/godmode-conventions.md` (file may not exist at Phase 1 close — substrate is the live-FS scan; convention doc lands in Phase 2).
- **D-22:** Deterministic ordering: `LC_ALL=C` in front of `find` calls in hooks. So output is identical across macOS and Linux locales.

### Shellcheck cleanliness (FOUND-08)
- **D-23:** `.shellcheckrc` ships near-empty in Phase 1 (a single comment line documenting that disables added later must include a one-line rationale comment). Run `shellcheck --shell=bash --severity=warning` (the v0.11.0 default) over `install.sh`, `uninstall.sh`, `hooks/*.sh`, `config/statusline.sh`, `scripts/*.sh`, `tests/fixtures/hooks/*.sh`. Closing wave fixes any warnings.
- **D-24:** No mass-disable. Each disable in `.shellcheckrc` (if any) gets a one-line rationale comment. Expected hits: SC2086 (unquoted `$VAR`), SC2046 (word splitting in `$(...)`), SC1090/SC1091 (sourced files), SC2034 (unused export). All addressable inline.

### Wave structure for plans (carried from archived PLAN.md draft)
- **D-25:** 4 plans (waves) per ROADMAP.md:
  - **01-01: Version SoT** — install.sh / uninstall.sh / commands/godmode.md / scripts/check-version-drift.sh / config/statusline.sh single-jq. (Touches multiple files; uninstall.sh is independent of install.sh, so 01-01 has internal parallelism for the jq-read swap and the drift-script creation.)
  - **01-02: Hook hardening** — session-start.sh / post-compact.sh substrate (JSON-via-jq, cwd-from-stdin, stdin-drain, live-FS scan), then post-compact.sh gates-from-config (separate atomic commit per D-19). Includes adversarial fixtures.
  - **01-03: Installer hardening** — install.sh prompt loop helper, per-target prompts (rules/agents/skills/hooks), detection-only v1.x note, backup rotation. Sequential within install.sh; parallel with 01-01 and 01-02 (different files).
  - **01-04: Closing gate** — `.shellcheckrc`, shellcheck pass over all touched `.sh`, CHANGELOG entry. Depends on 01-01, 01-02, 01-03.

### Claude's Discretion
- Implementation details inside the plans (specific bash idioms, helper function naming, exact error message wording) are at the planner / executor's discretion as long as they honor the decisions above. Auto mode does not micro-prescribe line-by-line.
- The v2.1 deferred items (`POLISH-01..04` in REQUIREMENTS.md) are NOT in scope — even if a tempting opportunity surfaces during execution, capture it in `<deferred>` here and move on.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project context (load order)
- `.planning/PROJECT.md` — Core Value, Active requirements (Foundation section), Constraints, Key Decisions
- `.planning/REQUIREMENTS.md` — FOUND-01..FOUND-11 (the 11 requirements this phase delivers)
- `.planning/ROADMAP.md` § Phase 1 — Goal, Success Criteria, Plans (1-1..1-4)
- `.planning/STATE.md` — current position, decision log

### v1.x audit and prior planning (preserved)
- `.planning-archive-v1/codebase/CONCERNS.md` — the 9 High-severity defects this phase addresses (#1, #2, #4, #5, #6, #7 and partial #8). **Read this** to understand the failure modes the substrate fixes prevent.
- `.planning-archive-v1/codebase/STACK.md` — current v1.x stack (bash, jq, hooks, install paths)
- `.planning-archive-v1/codebase/STRUCTURE.md` — current file layout (locks targets for our edits)
- `.planning-archive-v1/codebase/CONVENTIONS.md` — bash/jq idioms already in use
- `.planning-archive-v1/briefs/01-foundation-and-safety-hardening/{BRIEF.md, PLAN.md}` — the bespoke Phase 1 brief (renamed) and PLAN draft from the prior workflow shape. The plan structure (3 waves + closing gate) carries forward; the brief shape is superseded by this CONTEXT.md.

### Research (current pass)
- `.planning/research/STACK.md` — Claude Code 2026 plugin manifest schema, hook contracts, jq idioms, bash 3.2 portability rules
- `.planning/research/PITFALLS.md` § CR-02..CR-05 (hook JSON, stdin drain, bash 3.2 landmines, diff -q exit codes), § HI-04 (single jq), § HI-05 (v1.x rm), § CR-09 (backup growth), § CR-10 (uninstaller)
- `.planning/research/ARCHITECTURE.md` § "Live-Indexing Contract", § "Plugin/Manual Parity"
- `.planning/research/SUMMARY.md` § "Phase 1: Foundation & Safety Hardening" — addresses + avoids matrix
- `.planning/research/FEATURES.md` F-09..F-16, F-28, F-38 (Foundation features)

### Source files this phase touches (working-tree paths)
- `install.sh` (rewrite: per-file prompt, version SoT, backup rotation, detection-only v1.x note)
- `uninstall.sh` (rewrite: version mismatch + --force)
- `hooks/session-start.sh` (substrate fixes)
- `hooks/post-compact.sh` (substrate fixes — TWO atomic commits per D-19)
- `commands/godmode.md` (drop literal version heading)
- `config/statusline.sh` (single-jq)
- `.claude-plugin/plugin.json` (read-only — no changes; canonical version source)

### New files this phase creates
- `scripts/check-version-drift.sh`
- `config/quality-gates.txt`
- `.shellcheckrc`
- `tests/fixtures/hooks/{cwd-normal.json, cwd-quote-branch.json, cwd-backslash-branch.json, cwd-newline-branch.json, cwd-apostrophe-branch.json, setup-fixtures.sh}`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (v1.x baseline — confirmed extant)
- **`install.sh:97-110`** — already does `diff -q` work for rules. Refactor: extract into `prompt_overwrite()` helper used for all 4 targets (rules / agents / skills / hooks).
- **`install.sh:43-54`** — backup creation already exists. Add `prune_backups()` call right after.
- **`install.sh:122-158`** — settings.json merge via `jq -s '.[0] * .[1] * {...}'`. **Don't touch** — CONCERNS #3 (silent key-drop) is mapped to QUAL-07 / Phase 5, not here.
- **`hooks/session-start.sh:106-113`** and **`hooks/post-compact.sh:66-73`** — heredoc JSON output. Replace with single `jq -n --arg` call each.
- **`hooks/post-compact.sh:70`** — hardcoded skill/agent list inline in `additionalContext` text. Replace with live `find` invocations interpolated into `$CONTEXT_BLOCK` before passing to jq.
- **`config/statusline.sh:22-25`** — four `jq -r` invocations. Collapse to one `@tsv` filter.

### Established Patterns (already in use, follow them)
- `info()`/`warn()`/`error()` color-coded output helpers (`install.sh:21-23`, `uninstall.sh:20-22`). Reuse for the new prompt loop and version-mismatch error.
- `set -euo pipefail` at top of every script. Stays.
- `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` idiom (`install.sh:9`, `uninstall.sh:8`). Reuse in `scripts/check-version-drift.sh`.
- `[ -f "$file" ] && ...` style checks (already pervasive). Stays.
- macOS-portable globs: `for f in "$dir"/*.md` rather than `find -print0 | xargs`. Use this in backup rotation (D-13).

### Integration Points
- The new substrate is consumed in:
  - **Phase 2** (agent layer) reads `rules/godmode-routing.md` (effort tier policy lives there). FOUND substrate doesn't directly feed agents but enables them: the frontmatter linter scripts/check-frontmatter.sh ships in Phase 2 using the same shellcheck-clean Bash patterns FOUND-08 establishes.
  - **Phase 3** (hook expansion) reads `config/quality-gates.txt` (FOUND-07). Adds `pre-tool-use.sh` and `post-tool-use.sh` using FOUND-04/05 patterns. Rewrites `post-compact.sh` for v2 vocabulary on top of FOUND-11 substrate.
  - **Phase 4** (skill layer) reads `.planning/STATE.md` via `skills/_shared/init-context.sh`. State file format defined in WORKFLOW-14, but FOUND-substrate hooks already inject placeholder context.
  - **Phase 5** (CI / tests) runs `scripts/check-version-drift.sh` (FOUND-02), `shellcheck` (FOUND-08), `tests/fixtures/hooks/*.json` (FOUND-04 fixtures) in `bats` smoke. Adds `scripts/check-frontmatter.sh`, `scripts/check-parity.sh`, `scripts/check-vocab.sh` using same patterns.

</code_context>

<specifics>
## Specific Ideas

- **macOS bash 3.2 is the binding portability constraint.** Test every shell change on `bash --version` showing 3.2.x before commit. The forbid list in `.planning/research/STACK.md` is canonical: no `mapfile`/`readarray`, no `[[ -v VAR ]]`, no `${var,,}`/`${var^^}`, no `declare -A`, no `coproc`, no `&>>`, no `head -n -N`, no `sed -i ''` without arg, no `date -d`, no `getopt --long`.
- **Adversarial branch-name fixtures are the canonical proof.** A passing `printf '{"cwd":"%s"}' "$repo" | bash hooks/session-start.sh | jq -e '.'` against each of the 5 fixtures (normal + 4 adversarial) is the hook-safety acceptance test. Document the test recipe in `01-PLAN.md` so Phase 5 (bats smoke) has an explicit target.
- **Sentinel choice for statusline (D-12):** if `cwd` ever observed with a literal tab in production, switch to `\x1f` US separator. Track via a comment in `config/statusline.sh` and a test fixture.

</specifics>

<deferred>
## Deferred Ideas

- **POLISH-01:** Wave-concurrency cap exposed as `.planning/config.json` knob — currently hardcoded 5 in `/build N`. Out of scope for Phase 1 (it's a Phase 4 skill change).
- **CONCERNS #3** (settings merge silent key-drop) — explicitly NOT in Phase 1 per BRIEF.md / archived PLAN.md. Mapped to QUAL-07 / Phase 5 with a regression test under `tests/install.bats`.
- **`install.sh --replace-all` flag** for non-interactive overwrite (mentioned in D-02). Useful for CI flows that want to overwrite. Currently not needed; deferred to v2.1.
- **`hooks/hooks.json` and `config/settings.template.json[hooks]` parity edits** — if a hook contract change in FOUND-04/05 forces a binding update (e.g., new env var), document the change but the parity gate itself is Phase 5 (QUAL-03). Phase 1 keeps the bindings as-is unless forced.
- **Vocabulary alignment in `hooks/post-compact.sh`** (replacing `Pipeline: /prd → /plan-stories → /execute → /ship` with the v2 chain) — that's HOOK-04 / Phase 3, not Phase 1. Phase 1 keeps the v1.x vocabulary in the rendered context for now and rewrites it in Phase 3.

</deferred>

---

*Phase: 1-Foundation & Safety Hardening*
*Context gathered: 2026-04-26*
