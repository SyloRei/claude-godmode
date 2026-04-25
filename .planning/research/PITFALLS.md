# Pitfalls — claude-godmode v2

**Domain:** Claude Code plugin maturation (brownfield)
**Researched:** 2026-04-25
**Vocabulary check:** Pitfalls below use the project's own names — Brief / Plan / Commit / `/godmode` / `/mission` / `/brief` / `/plan` / `/build` / `/verify` / `/ship`. Reference-plugin terms (phase, story, gsd-sdk, .claude-pipeline cycle, etc.) appear ONLY where they identify the failure mode being described (e.g. "leaking GSD vocabulary"); they are never the recommended path.

Severity scale:
- **Critical** — silently corrupts user state, breaks the published surface, or violates a hard PROJECT.md constraint
- **High** — degrades trust, causes data loss for one user, or invalidates the v2 → v1 migration story
- **Medium** — drift, doc rot, inconsistent UX between install paths
- **Low** — minor hygiene, cosmetic, or marginal efficiency

Brief mapping uses the v2 build briefs (working names, refined in roadmap):
- **B-FOUND** — Foundation & Safety Hardening (install/uninstall, version SoT, hook hardening)
- **B-AGENTS** — Agent Layer Modernization (model aliases, effort, isolation, frontmatter linter)
- **B-HOOKS** — Hook Layer Expansion (PreToolUse, PostToolUse, dynamic skill list, JSON safety)
- **B-SKILLS** — Skill Layer Rebuild (the 7-command happy path + 4 helpers)
- **B-STATE** — `.planning/` Artifact Set & init-context.sh
- **B-QUAL** — CI, Tests, Doc Parity, prompt-cache rule structure

---

## Category A — v1.x carry-over (CONCERNS.md High items, must resolve in v2)

### A1. Silent overwrite of user-customized rules / agents / skills on reinstall

**Severity:** Critical
**Origin:** CONCERNS.md #1, #2 (`install.sh:97-110`, `install.sh:171-200`)
**What goes wrong:** A user who edits `~/.claude/rules/godmode-coding.md` to add house-style notes loses them on the next `./install.sh`. Backup is created, but no per-file prompt. Manual mode doesn't even do the `diff` count — it blanket `cp -r`s agents and skills.

**Warning signs (early detection):**
- New code that calls `cp -r` or `cp ... -*.md` over `~/.claude/{rules,agents,skills,commands}/` without a prior `diff -q` loop
- Backup directory present but no `prompt_overwrite` or `confirm_replace` function in install.sh
- Manual install path and plugin install path diverging on this check (one prompts, the other doesn't)

**Prevention strategy (mechanism):**
1. Single function `install_dir_with_diff <src_dir> <dst_dir>` used by both modes — for each file: `diff -q`; if changed, prompt `[d]iff / [s]kip / [r]eplace / [a]ll-replace / [q]uit`.
2. Non-interactive default (stdin not a TTY) = **keep customizations**, log skipped files.
3. Bats round-trip test: install → edit a rule → reinstall non-interactively → assert edit survives.
4. CI: grep `install.sh` for `cp -r .* ~/\.claude` patterns NOT preceded by the diff function — fail on match.

**Brief:** B-FOUND
**Reference-plugin temptation:** None — this is pure v1.x carry-over.

---

### A2. JSON injection in hooks via unescaped branch / commit / path interpolation

**Severity:** Critical
**Origin:** CONCERNS.md #6 (`hooks/session-start.sh:50`, `hooks/post-compact.sh:43-49`)
**What goes wrong:** Hooks build `additionalContext` by string interpolation inside a heredoc. A branch name like `feat/"quoted"`, a commit message containing a literal newline, or a path with `\` corrupts the JSON. Best case: Claude Code discards the hook output. Worst case: the injected fragment terminates the JSON early and following content is reinterpreted — a user with write access to `git config` or branch names could in principle smuggle text into the assistant's context. (Trust impact, even if exploitability is narrow.)

**Warning signs:**
- Any hook script using `cat <<EOF ... "${VAR}" ... EOF` where `VAR` is git output, a file path, or anything user-controlled
- `jq -n` not used to construct the final hook JSON
- Bats / shellcheck not run against hooks under adversarial inputs

**Prevention strategy:**
1. **Hard rule:** every hook constructs its output object via `jq -n --arg <name> "$VAR" '{...}'`. No string interpolation into JSON, anywhere. Document in `rules/godmode-hooks.md` (new file).
2. CI grep gate: `grep -nE '"\$\{?[A-Z_][A-Z0-9_]*\}?"' hooks/*.sh | grep -v 'jq ' && exit 1` — flags raw shell-var-in-quoted-context inside hook scripts.
3. Bats fixture set: branch names containing `"`, `\`, `$`, newline, `'`, ` ` injected via a temp git repo; assert hook output is valid JSON (`jq -e .`).
4. shellcheck must be clean (catches some but not all of these).

**Brief:** B-HOOKS (with B-QUAL CI gate)
**Reference-plugin temptation:** Some reference plugins use `printf '%s'`-based JSON construction; we adopt the *micro-pattern* (always-jq-build) but keep our own naming.

---

### A3. Version drift across `plugin.json` / `install.sh` / `commands/godmode.md`

**Severity:** High
**Origin:** CONCERNS.md #10
**What goes wrong:** Three files claim three different versions today (1.6.0 / 1.4.1 / 1.4.1). Plugin registry advertises one number, installer writes another to `~/.claude/.claude-godmode-version`, statusline / `/godmode` shows a third. Trust killer; release-note correctness collapses.

**Warning signs:**
- More than one file containing a literal version triplet `[0-9]+\.[0-9]+\.[0-9]+`
- A `VERSION=` assignment in any `*.sh` file
- Docs that bake a version number into prose

**Prevention strategy:**
1. **Single source of truth:** `.claude-plugin/plugin.json:.version`. Period.
2. `install.sh` reads it via `jq -r '.version' .claude-plugin/plugin.json` at runtime — no `VERSION=` constant.
3. `commands/godmode.md` stops carrying a version number entirely (statusline carries it; README carries it via release-time tooling, not hand-edit).
4. CI gate (`scripts/check-version-drift.sh`):
   ```bash
   canonical=$(jq -r '.version' .claude-plugin/plugin.json)
   ! grep -rnE 'v?[0-9]+\.[0-9]+\.[0-9]+' install.sh uninstall.sh commands/ rules/ \
     | grep -v "$canonical" | grep -vE '^\s*#'
   ```
5. README + CHANGELOG are checked at release time (not every PR — version bump is a release event).

**Brief:** B-FOUND (mechanism) + B-QUAL (CI gate)
**Reference-plugin temptation:** None.

---

### A4. Hardcoded skill / agent lists in hooks and commands drift from filesystem

**Severity:** High
**Origin:** CONCERNS.md #8, #9
**What goes wrong:** `hooks/post-compact.sh:70` lists `/prd, /plan-stories, /execute, /ship, /debug, /tdd, /refactor, /explore-repo` and `@researcher, @reviewer, @architect, @writer, @executor, @security-auditor, @test-writer, @doc-writer`. v2 changes the surface. Anyone who renames a skill in `skills/` and forgets to update `post-compact.sh` ships a hook that lies after every compaction.

**Warning signs:**
- Any list of skill names (`/word, /word, ...`) or agent names (`@word, ...`) in a file other than `skills/*/` and `agents/*` themselves
- A new agent file added in PR with no diff in `hooks/` or `commands/godmode.md`

**Prevention strategy:**
1. `hooks/post-compact.sh` and `commands/godmode.md` rendering script enumerate live filesystem at runtime:
   ```bash
   skills=$(find "${CLAUDE_PLUGIN_ROOT:-.}/skills" -name SKILL.md -maxdepth 2 \
     | xargs -I{} dirname {} | xargs -n1 basename | sort | tr '\n' ' ')
   ```
2. `commands/godmode.md` is a markdown file (no shell), so it cannot enumerate. **Resolution:** `commands/godmode.md` does NOT list skills/agents inline; it links to a section that's rendered via a SessionStart additionalContext block, OR it instructs the assistant to "list the contents of `${CLAUDE_PLUGIN_ROOT}/skills/`" rather than naming them.
3. CI grep: `grep -rE '/(prd|plan-stories|execute|ship|debug|tdd|refactor|explore-repo|mission|brief|plan|build|verify|godmode)\b' hooks/ commands/godmode.md` — any match outside the canonical command file fails CI.
4. Quality gates list (currently duplicated in `rules/godmode-quality.md` and `hooks/post-compact.sh`) → moved to `config/quality-gates.txt` (one line per gate); both consumers `cat` it.

**Brief:** B-HOOKS (dynamic enumeration) + B-FOUND (quality-gates.txt SoT) + B-QUAL (CI grep)
**Reference-plugin temptation:** Some references hardcode lists too — we don't follow them here.

---

### A5. Hooks rely on `pwd` instead of stdin's `cwd` field

**Severity:** High
**Origin:** CONCERNS.md #7
**What goes wrong:** Both hooks check `package.json`, `Cargo.toml`, `.claude-pipeline/` relative to current directory. If invoked with cwd elsewhere (tested under bats fixture, or future Claude Code change), they silently report nothing.

**Warning signs:**
- Hook script body without `cd "$(jq -r '.cwd // "."' <<<"$INPUT")"` near the top
- Tests that pipe `{}` and assert non-empty output — a fixture that pipes `{"cwd":"/tmp/empty"}` would catch nothing currently

**Prevention strategy:**
1. Standard preamble for every hook:
   ```bash
   INPUT="$(cat || echo '{}')"
   PROJECT_ROOT="$(jq -r '.cwd // empty' <<<"$INPUT")"
   [ -n "$PROJECT_ROOT" ] && [ -d "$PROJECT_ROOT" ] && cd "$PROJECT_ROOT" || true
   ```
2. Refactor into `hooks/_lib/preamble.sh` sourced by every hook (clean — one place to fix).
3. Bats test: feed `{"cwd":"/path/to/fixture"}`; assert output reflects fixture's git/state, not the test runner's cwd.

**Brief:** B-HOOKS
**Reference-plugin temptation:** None.

---

### A6. Stdin-drain failure under `pipefail` aborts hook before useful work

**Severity:** Medium
**Origin:** CONCERNS.md #18
**What goes wrong:** `cat > /dev/null` under `set -euo pipefail` aborts if Claude Code closes stdin first.

**Warning signs:** Any hook with `set -euo pipefail` and `cat > /dev/null` (no `|| true`).

**Prevention:** `cat > /dev/null || true` in the preamble (combine with A5 fix).

**Brief:** B-HOOKS

---

### A7. No version-mismatch guard between installed marker and incoming uninstaller

**Severity:** High
**Origin:** CONCERNS.md #4
**What goes wrong:** A user with v2.1 installed runs `./uninstall.sh` from a v2.0 checkout — files added in v2.1 are left behind, the user thinks they uninstalled cleanly, weird residue corrupts a future reinstall.

**Prevention:**
1. `uninstall.sh` reads `~/.claude/.claude-godmode-version`, compares against `jq -r '.version' .claude-plugin/plugin.json`, refuses (with `--force` override) if newer than its own.
2. `uninstall.sh` enumerates files via the same logic `install.sh` uses (find `rules/godmode-*.md`, `agents/*.md`, etc.) at runtime — no hardcoded file list.

**Brief:** B-FOUND

---

### A8. Settings merge silently drops new top-level keys

**Severity:** High
**Origin:** CONCERNS.md #3
**What goes wrong:** The `jq -s '$existing * $template'` merge handles top-level keys, but if anyone adds a new top-level template key, existing-user upgrade paths must propagate it. Easy to forget.

**Prevention:**
1. Snapshot test: representative `~/.claude/settings.json` fixtures × template → diff against expected merged output. Bats + fixture files in `tests/fixtures/settings/`.
2. The merge expression itself is documented inline in install.sh with a comment listing every top-level key it explicitly handles — so a new key in the template without an updated comment is a code-review smell.

**Brief:** B-FOUND + B-QUAL

---

## Category B — New principle ("inspiration only") — vocabulary leakage and dependency creep

### B1. Reference-plugin vocabulary leaks into agent prompts, skill bodies, or rule files

**Severity:** Critical
**Why it matters:** The Core Value asks for ONE workflow with names matching user intent. If `@planner`'s prompt says "produce a plan-phase artifact" or `/build` says "execute the next story", we've recreated the dependency we're escaping. Worse: the user can't tell if `claude-godmode` is its own thing or a GSD wrapper.

**Warning signs:**
- Strings in `agents/*.md`, `skills/*/SKILL.md`, `rules/godmode-*.md`, `commands/*.md`, or `hooks/*.sh` matching:
  - `\bphase\b`, `\bstory\b`, `\bstories\b`, `\bcycle\b` (in workflow sense)
  - `gsd[ -_]?sdk`, `\bgsd\b` (outside attribution comments)
  - `superpowers`, `everything-claude-code` (outside attribution comments)
  - `plan-phase`, `discuss-phase`, `verify-work` (GSD command names)
  - `\.claude-pipeline\b` references in v2 NEW files (the dirname survives in v1.x consumer state but is not a v2 *plugin* concept)
- Frontmatter `description:` fields containing reference-plugin terms

**Prevention:**
1. CI gate `scripts/check-vocabulary.sh`:
   ```bash
   FORBIDDEN='\b(phase|story|stories|cycle|plan-phase|discuss-phase|verify-work)\b|gsd[-_ ]?sdk|\bgsd\b|\bsuperpowers\b|everything-claude-code'
   ALLOW_FILES='\.planning/codebase/|\.planning/research/|\.planning/PROJECT\.md|CHANGELOG\.md|^docs/attribution\.md'
   git ls-files | grep -vE "$ALLOW_FILES" \
     | xargs grep -nIE "$FORBIDDEN" 2>/dev/null \
     | grep -vE '<!-- attribution:' && exit 1 || exit 0
   ```
   Allowed: planning artifacts (this very file uses these terms to *forbid* them), CHANGELOG migration notes, an explicit `docs/attribution.md`. Disallowed: rules, agents, skills, commands, hooks, READMEs.
2. PR template checkbox: "I checked that no reference-plugin vocabulary leaked into shipped artifacts."
3. `@spec-reviewer` agent prompt explicitly lists forbidden terms and treats their presence as a review block.

**Brief:** B-QUAL (CI gate) + B-AGENTS (reviewer prompt) + B-SKILLS (writing the new skill bodies)

---

### B2. Adopting reference-plugin directory shape under a different name

**Severity:** High
**What goes wrong:** Renaming `phases/` to `briefs/` is a rename. Renaming `phases/01-foundation/{CONTEXT,SPEC,RESEARCH,PLAN,EXECUTE,VERIFICATION,REVIEW}.md` to `briefs/01-foundation/{BRIEF,SPEC,...}.md` recreates the GSD shape with new labels — same file proliferation, same six-level hierarchy, same fan-out. Core Value demands two artifact files per active brief.

**Warning signs:**
- A new file appearing in `.planning/briefs/NN-name/` other than `BRIEF.md` or `PLAN.md`
- Generators or templates that scaffold more than 2 files per brief
- Skill prompts that reference a third artifact ("update the EXECUTE.md", "write to RESEARCH.md")
- `.planning/briefs/NN-name/` directory containing a subdirectory (e.g. `tasks/`, `commits/`) — git log IS the execution log

**Prevention:**
1. `rules/godmode-planning.md` (new): "A brief directory contains exactly two files: BRIEF.md and PLAN.md. No exceptions. Anything else lives in git history or in commit messages."
2. CI gate:
   ```bash
   for d in .planning/briefs/*/; do
     extras=$(find "$d" -mindepth 1 -maxdepth 2 ! -name BRIEF.md ! -name PLAN.md)
     [ -n "$extras" ] && { echo "Forbidden artifact in $d: $extras"; exit 1; }
   done
   ```
3. `@planner` agent prompt: "You write to PLAN.md only. You never create new files in the brief directory."
4. Templates ship exactly two files; no scaffolding for additional ones.

**Brief:** B-STATE + B-AGENTS + B-QUAL

---

### B3. Marketing the plugin as "GSD-compatible" or "Superpowers-compatible"

**Severity:** High (trust + dependency-direction)
**What goes wrong:** Compatibility claim creates a dependency that we explicitly chose not to take. If a reference plugin renames a command, "GSD-compatible" becomes a maintenance burden or a lie.

**Prevention:**
1. README explicitly states: "Inspired by GSD, Superpowers, and everything-claude-code. Not compatible with, dependent on, or interoperable with them. Use one or the other."
2. CHANGELOG / release notes reviewed at ship time for compatibility claims; `@spec-reviewer` flags them.
3. No `claude-godmode-gsd-bridge` style helper. Ever.

**Brief:** B-QUAL (release-time review checklist)

---

### B4. Vendoring reference-plugin code or templates

**Severity:** Critical (license + Out-of-Scope violation)
**Origin:** PROJECT.md "Out of Scope": "Vendored copies of GSD, Superpowers, or everything-claude-code — license + maintenance burden; inverts the dependency direction."
**What goes wrong:** Copy-pasting a useful template from a reference plugin and committing it to this repo creates a license-attribution obligation, drifts from upstream, and inverts the dependency direction.

**Warning signs:**
- New files in `templates/` or `skills/_shared/` whose first commit message mentions a reference plugin
- Markdown files starting with attribution comments to reference plugins (other than `docs/attribution.md`)
- Identical-byte-for-byte fragments matched by `comm` against checked-out reference repos

**Prevention:**
1. PR template checkbox: "No content vendored from reference plugins. Specific micro-patterns adopted: <list with attribution>."
2. `docs/attribution.md` — the ONLY place reference-plugin names appear in shipped content; lists adopted micro-patterns with explicit attribution.
3. `@spec-reviewer` reviews any new template / shared file for vendored fragments.

**Brief:** B-QUAL + B-AGENTS

---

## Category C — New workflow surface (Brief → Plan → Build hand-off failures)

### C1. `/plan` runs without a fresh BRIEF.md and silently invents requirements

**Severity:** Critical
**What goes wrong:** User runs `/plan 03` but BRIEF.md is empty / missing / stale (last edited two milestones ago). `@planner` proceeds with the empty file, hallucinates a tactical plan, the user runs `/build`, and a week of work later the plan reveals it was solving a misremembered problem.

**Warning signs:**
- A PLAN.md whose mtime is newer than its corresponding BRIEF.md by > 1 day
- BRIEF.md with the literal string `<!-- TODO: fill from /brief -->` left in
- `@planner` invocations with no upstream `/brief` in the same session

**Prevention:**
1. `/plan` command: pre-flight reads `.planning/briefs/NN-*/BRIEF.md`; if absent, missing required sections (Why / What / Spec), or contains TODO sentinels, it refuses with `Run /brief NN first.`
2. `@planner` agent prompt: "You receive BRIEF.md as input. If it lacks Why / What / Spec, return an error block — do not invent."
3. BRIEF.md template includes a closing sentinel `<!-- BRIEF-COMPLETE -->`; missing sentinel → `/plan` refuses.
4. `@spec-reviewer` runs at brief completion (before `/plan` is offered).

**Brief:** B-SKILLS + B-AGENTS + B-STATE

---

### C2. `/build` runs without a fresh PLAN.md and skips verification gates

**Severity:** Critical
**What goes wrong:** User runs `/build 03` directly (skipping `/plan`). `@executor` finds no PLAN.md, falls back to "interpret BRIEF.md tactically", commits work without the verification status table that `/verify` depends on. `/verify` then has no commit-by-commit acceptance to check against.

**Prevention:**
1. `/build` pre-flight: `PLAN.md` must exist AND contain a `## Tactical Plan` section AND contain a `## Verification Status` table with rows.
2. If absent → refuse: `Run /plan NN first.`
3. `@executor` after each commit appends to `## Verification Status` (commit SHA + which spec line it satisfies).
4. `/verify` reads `## Verification Status` and cross-checks every BRIEF.md spec line.

**Brief:** B-SKILLS + B-AGENTS

---

### C3. Agent context drift across the chain — `@planner` sees brief, `@executor` doesn't see plan rationale

**Severity:** High
**What goes wrong:** Each subagent spawn starts with a fresh context window. `@planner` reads BRIEF.md and produces PLAN.md with rationale embedded. `@executor` only sees PLAN.md's task list, not the rationale, and "optimizes" by skipping a step that looked redundant — but it was load-bearing.

**Prevention:**
1. `init-context.sh` (skills/_shared) returns a structured JSON blob that includes BRIEF.md path, PLAN.md path, and current commit slot. Every skill sources it; every agent invocation passes both paths.
2. PLAN.md format: each task has a `## Why` field beside `## What` — rationale travels with task.
3. `@executor` prompt: "Read both BRIEF.md and PLAN.md before each commit. Do not skip steps marked load-bearing."
4. Prompt-cache-aware structure: BRIEF.md and PLAN.md content live in the static preamble portion of agent prompts (per PROJECT.md cache-aware-rule-structure requirement).

**Brief:** B-AGENTS + B-STATE + B-SKILLS

---

### C4. `/verify` produces COVERED for items that were never actually tested

**Severity:** High
**What goes wrong:** `@verifier` reads BRIEF.md spec lines and PLAN.md verification status; if rows are filled, marks COVERED. But "filled" is just a string match — `@executor` could write `[x] tested` without running tests.

**Prevention:**
1. `@verifier` is a *read-only* agent (declared `disallowedTools: Write,Edit`) and re-runs the relevant test/check/grep. It does not trust the table — it reproduces.
2. PLAN.md verification rows include a `Check command` field; `@verifier` runs it and records actual exit code.
3. `/verify` output template explicitly distinguishes:
   - **COVERED (independently re-run)** — `@verifier` ran the check, exit 0
   - **CLAIMED COVERED (not re-runnable)** — manual or visual verification, called out
   - **PARTIAL** — re-run failed or check command missing
   - **MISSING** — no verification row exists for the spec line

**Brief:** B-AGENTS (`@verifier`) + B-SKILLS (`/verify`)

---

### C5. `/mission` and `/brief` silently mutate user intent ("auto-prompt-engineering")

**Severity:** Critical (PROJECT.md Out of Scope explicit)
**Origin:** PROJECT.md Out of Scope: "Auto-prompt-engineering of user requests — silent intent mutation breaks trust; explicit `/brief` Socratic discussion instead."
**What goes wrong:** `@planner` or `/brief` rewrites the user's stated goal "more concretely" without asking — user wanted X, brief now says Y, plan delivers Y, user sees Y at `/verify` and is annoyed.

**Prevention:**
1. `/brief` is Socratic — it ASKS questions, doesn't ANSWER them on the user's behalf. Output BRIEF.md must contain a `## User Goal (verbatim)` section quoting the user's literal request.
2. `@planner` prompt: "Never paraphrase the user goal. Quote the verbatim section from BRIEF.md. If you believe the goal is unclear, surface a question — do not resolve it silently."
3. `@spec-reviewer` checks BRIEF.md `## User Goal (verbatim)` exists and is non-empty.

**Brief:** B-SKILLS + B-AGENTS

---

## Category D — Claude Code primitives (Auto Mode, effort, prompt cache, hook timeouts, JSON safety)

### D1. Auto Mode bypasses interactive quality gates and ships work the user didn't review

**Severity:** Critical
**What goes wrong:** Auto Mode tells the assistant to "minimize interruptions" and "prefer action over planning." If `/build` includes an interactive `AskUserQuestion` gate ("commit this?"), Auto Mode answers itself and ships. If the PreToolUse hook prompts on `--no-verify`, Auto Mode might re-issue the command with a workaround.

**Warning signs:**
- A skill that uses `AskUserQuestion` for go/no-go on a destructive op without an Auto-Mode-aware fallback
- An "Auto Mode Active" system reminder in a session that subsequently runs a destructive op without explicit confirmation logged
- Hook bypass attempts (e.g. `git -c core.hooksPath=/dev/null commit`)

**Prevention:**
1. **Every skill detects Auto Mode** by checking for the `Auto Mode Active` system reminder in its prompt, and **routes destructive operations differently**: in Auto Mode, destructive ops (rm -rf, force push, schema migrations, settings.json writes) are *refused* with a clear "explicit user confirmation required, exit Auto Mode" message — per the Auto Mode contract item 5 ("Anything that deletes data or modifies shared or production systems still needs explicit user confirmation").
2. PreToolUse hook (per FOUND requirements) blocks `Bash(git commit --no-verify*)` and similar bypasses **regardless** of Auto Mode — the hook doesn't ask, it refuses.
3. `rules/godmode-auto-mode.md` (new): canonical list of operations Auto Mode must NOT do without explicit user confirmation.
4. Bats test: simulate Auto Mode marker; assert destructive op refuses.

**Brief:** B-HOOKS (PreToolUse) + B-SKILLS (per-skill detection) + a new rule file

---

### D2. `effort: xhigh` on Opus 4.7 silently skips rules in code-writing agents

**Severity:** High
**Origin:** PROJECT.md Key Decisions ("Code-writing agents use `effort: high`, not `xhigh`")
**What goes wrong:** Empirically (per the project's own decision log), `xhigh` on Opus 4.7 has been observed skipping rule application during code generation. Design / audit agents tolerate this trade. Code-writing agents do not.

**Warning signs:**
- Frontmatter `effort: xhigh` AND any of `tools: ...Write...` / `Edit` / `MultiEdit` in the same file
- A code-writing agent producing output that violates `rules/godmode-*` invariants
- A diff that adds `effort: xhigh` to `@executor`, `@test-writer`, `@doc-writer`

**Prevention:**
1. Frontmatter linter rule: `if effort == 'xhigh' and tools.includes('Write'|'Edit'|'MultiEdit') → fail`. Pure-bash linter (per PROJECT.md), runs in CI.
2. `rules/godmode-routing.md` (new): the policy is a rule, not just a frontmatter convention — so reviewers see it.
3. PR template note: agent effort changes require a one-line rationale in the commit message.

**Brief:** B-AGENTS (linter + routing rule) + B-QUAL (CI invocation)

---

### D3. Prompt cache invalidation from dynamic content in rule bodies

**Severity:** Medium
**Origin:** PROJECT.md Active requirements ("Prompt-cache-aware rule structure (static preamble first, no dates/branches/dynamic content in rule bodies)")
**What goes wrong:** Claude Code caches prompts on a 5-minute TTL. If `rules/godmode-*.md` contains today's date, current branch, or anything else that changes per session, every session pays the full cost.

**Warning signs:**
- `rules/godmode-*.md` containing date stamps, `pwd`-style paths, branch references, or `<!-- generated YYYY-MM-DD -->`-style markers
- SessionStart hook injecting a giant preamble *before* rules in the order Claude Code assembles context

**Prevention:**
1. Rule structure convention: rules are static markdown. No dates, no branches, no dynamic anything. Dynamic info lives in SessionStart `additionalContext` — separately, in a known position.
2. CI grep: `rules/godmode-*.md` must not contain `\b\d{4}-\d{2}-\d{2}\b`, `^Branch:`, or `<!-- generated`.
3. `rules/godmode-cache.md` (or note in existing convention rule): "Rule files are static. Dynamic content goes in SessionStart additionalContext."

**Brief:** B-FOUND (rule structure convention) + B-QUAL (CI grep) + B-HOOKS (SessionStart placement)

---

### D4. Hook timeouts inconsistent between plugin mode and manual mode

**Severity:** Medium
**Origin:** CONCERNS.md #12
**What goes wrong:** `hooks/hooks.json` (plugin) sets `timeout: 10`. `config/settings.template.json` (manual) does not — manual users get the 60s default. A slow `git log` blocks session start six times longer in manual mode.

**Prevention:**
1. Both files set `timeout: 10` for SessionStart and PostCompact, `timeout: 5` for PreToolUse, `timeout: 5` for PostToolUse.
2. CI gate compares the hook timeouts in both files; mismatch = fail.
3. Both files generated from a single source (a `config/hooks-canonical.json` consumed at install time) → eliminates the duplication entirely.

**Brief:** B-FOUND + B-QUAL

---

### D5. Plugin mode and manual mode UX diverge silently

**Severity:** Critical (PROJECT.md hard constraint: "Plugin-mode == manual-mode UX")
**What goes wrong:** A new feature ships in plugin mode (via `hooks/hooks.json`) and forgets the manual-mode binding (`config/settings.template.json`). Plugin users get the new hook; manual users don't. Bug reports from manual users look like plugin-only regressions.

**Prevention:**
1. Single canonical `config/hooks-canonical.json` listing all hook bindings; both `hooks/hooks.json` and the hooks block of `config/settings.template.json` are *generated* from it at install time (or at PR-CI-time for hooks.json which ships in-repo).
2. CI gate: round-trip both files through the canonical generator; assert no diff.
3. Bats parity test: install plugin mode → snapshot `~/.claude/`; uninstall; install manual mode → snapshot `~/.claude/`; diff snapshots; only allowed differences are intentional (e.g. `.claude-plugin/` symlink).

**Brief:** B-FOUND + B-QUAL

---

### D6. SessionStart hook reads `.planning/STATE.md` but it doesn't exist on consumer projects

**Severity:** Medium
**What goes wrong:** New v2 SessionStart hook (per FOUND) reads `.planning/STATE.md` for current-brief context. On a fresh consumer project, this file doesn't exist. If the hook errors or emits nothing, fine; if it injects a "no state file" warning into every Claude Code session, it's noise.

**Prevention:**
1. Hook checks file existence first; absence is a quiet no-op (no `additionalContext`).
2. Hook differentiates "no `.planning/` directory" (consumer hasn't run `/mission` yet — silent) from "`.planning/` exists but `STATE.md` is malformed" (broken state — surface a one-liner).

**Brief:** B-HOOKS + B-STATE

---

## Category E — Reference-plugin influence (subtle pulls)

### E1. Borrowing GSD's six-level vocabulary "by accident" via copy-pasted prompts

**Severity:** High
**What goes wrong:** When writing `@planner`'s prompt, the temptation is to paraphrase GSD's `@planner` prompt (because it works). A few words leak in: "phase-level breakdown", "story-level tasks". Now our agents speak a hybrid vocabulary.

**Prevention:**
1. New agent prompts written from scratch, with the workflow vocabulary glossary (BRIEF/PLAN/Commit/etc.) attached as context.
2. Vocabulary check (B1's CI gate) catches this.
3. `@spec-reviewer` reads new agent prompts with vocabulary as an explicit checkpoint.

**Brief:** B-AGENTS

---

### E2. Recreating per-task artifact files (TASK.md, EXECUTE.md) "for traceability"

**Severity:** High (PROJECT.md Out of Scope)
**Origin:** PROJECT.md Out of Scope: "Per-task artifact files (TASK.md) — git history IS the execution log."
**What goes wrong:** Someone proposes "but we need to track what each commit does!" → adds `briefs/NN/commits/NN.md` → file proliferation we explicitly chose to avoid.

**Prevention:**
1. `rules/godmode-planning.md`: "Commit messages are the execution log. PLAN.md tracks status (PENDING / DONE / VERIFIED) only. No new files per commit."
2. CI gate from B2 catches forbidden files in brief directory.
3. `@spec-reviewer` rejects any PR that adds a per-task artifact concept.

**Brief:** B-STATE + B-AGENTS

---

### E3. Adding a `/everything` mega-command

**Severity:** Critical (PROJECT.md Out of Scope)
**Origin:** PROJECT.md Out of Scope: "A `/everything` mega-command — hides workflow shape; defeats Core Value."
**What goes wrong:** The convenience pull. "Just run `/everything` and the plugin figures it out." Hides the workflow shape, which IS the value.

**Prevention:**
1. ≤12 slash command cap (PROJECT.md hard constraint) — there's no slot for a mega-command after `/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`. The 12th slot is reserved, not for `/everything`.
2. `commands/` directory CI count: `find commands -name '*.md' -maxdepth 1 | wc -l` must be ≤ 12.
3. Documented in CONTRIBUTING.md.

**Brief:** B-SKILLS + B-QUAL

---

## Category F — Hygiene / lifecycle (Medium severity, easy wins)

### F1. Backup directory accumulation in `~/.claude/backups/`

**Severity:** Medium
**Origin:** CONCERNS.md #13
**Prevention:** Keep last 5 backups; prune older at install time. `uninstall.sh` already finds latest with `sort -r | head -1` — same pattern fits.
**Brief:** B-FOUND

### F2. `.claude/worktrees/` accumulation, no documented cleanup

**Severity:** Low
**Origin:** CONCERNS.md #14
**Prevention:** CONTRIBUTING.md hygiene section with `git worktree prune` recipe; agent system deletes its worktree on completion (where supported).
**Brief:** B-QUAL (docs) + B-AGENTS (cleanup-on-completion)

### F3. README / CHANGELOG / `/godmode` drift on public-surface claims

**Severity:** Medium
**Origin:** CONCERNS.md #21
**Prevention:** Release-time CI gate: README skill list, CHANGELOG, and `commands/godmode.md` enumerated content all match `find skills -name SKILL.md` and `find agents -name '*.md'`. PR template checkbox at version-bump time.
**Brief:** B-QUAL

### F4. `.DS_Store` files committed in subdirs

**Severity:** Low
**Origin:** CONCERNS.md #16
**Prevention:** One-time `find . -name .DS_Store -exec git rm --cached {} \;`; `.gitignore` already covers it.
**Brief:** B-FOUND (one-time) — trivial

### F5. No automated tests at all

**Severity:** High (catches everything else above)
**Origin:** CONCERNS.md #20, TESTING.md
**Prevention:** B-QUAL is the brief — bats round-trip + shellcheck CI + JSON schema validation + frontmatter linter + vocabulary CI gate.
**Brief:** B-QUAL

---

## Phase-specific warning matrix

| Brief | Top pitfalls to watch | Severity |
|-------|----------------------|----------|
| **B-FOUND** (Foundation) | A1 silent overwrite, A3 version drift, A7 uninstall version mismatch, A8 settings merge, D5 plugin/manual parity, F1 backup rotation | Critical / High |
| **B-AGENTS** (Agent layer) | D2 effort xhigh, B1 vocabulary leakage, C3 context drift, C4 verifier trust, E1 borrowed prompts | Critical / High |
| **B-HOOKS** (Hook layer) | A2 JSON injection, A4 hardcoded skill list, A5 cwd reliance, A6 stdin drain, D1 Auto Mode, D4 timeout parity, D6 missing STATE.md | Critical / High |
| **B-SKILLS** (Skills) | C1 plan-without-brief, C2 build-without-plan, C5 silent intent mutation, D1 Auto Mode, E3 /everything, B1 vocabulary | Critical |
| **B-STATE** (.planning/) | B2 file proliferation, C1/C2 hand-off gates, E2 per-task files, D6 STATE.md absence | Critical / High |
| **B-QUAL** (CI / docs) | F5 no tests = catches everything, B1 vocabulary CI, A3 version drift CI, F3 doc drift, A2 hook fuzz tests | High |

---

## Sources

- `.planning/PROJECT.md` (Key Decisions, Out of Scope, Constraints) — confidence HIGH
- `.planning/codebase/CONCERNS.md` (items 1-21) — confidence HIGH (project's own analysis 2026-04-25)
- `.planning/codebase/TESTING.md` — confidence HIGH
- `.planning/codebase/CONVENTIONS.md` — confidence HIGH
- Claude Code primitives (Auto Mode contract, effort levels, prompt cache TTL, hook events) — confidence HIGH (current Anthropic primitives, knowledge cutoff Apr 2026 + system reminders)
- Reference-plugin pitfalls (vocabulary leakage, vendoring temptation, mega-command pull) — confidence MEDIUM (drawn from the v1 → v2 re-init decision rationale in PROJECT.md "This is a re-init")

*Last updated: 2026-04-25*
