# Feature Landscape — claude-godmode v2 (Re-Init Pass, 2026-04-26)

**Domain:** Claude Code plugin (rules + agents + skills + hooks + statusline + permissions) shipped as a coherent senior-engineering-team workflow.
**Mode:** Ecosystem (project research, Features dimension)
**Vocabulary:** brief / plan / commit; `/godmode`, `/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`. No `phase`/`task`/`PRD`/`story`/`milestone` in user-facing surface.

## How to read

| Field | Meaning |
|---|---|
| **ID** | `F-NN` table stakes; `D-NN` differentiator; `A-NN` anti-feature. Stable; feeds REQUIREMENTS.md. |
| **Stage** | orient / mission / brief / plan / build / verify / ship / helper / cross-cutting |
| **Complexity** | S (≤½ day shell), M (1–3 days integration), L (multi-day design+integration+tests) |
| **Depends on** | Other features required first |
| **Milestone area** | M1 Foundation / M2 Agent / M3 Hook / M4 Skill / M5 Quality |
| **Ref-plugin coverage** | Whether GSD / Superpowers / everything-claude-code (ECC) ship a version, and how ours differs |
| **Confidence** | HIGH / MEDIUM / LOW |

Cross-references: PROJECT.md Active section; IDEA.md "Five must-have properties"; `.planning-archive-v1/research/FEATURES.md` (prior pass); `.planning-archive-v1/codebase/CONCERNS.md` 9 Highs.

---

## 1. Table stakes — must ship in v2

### Workflow surface — single happy path

#### F-01. Locked 11-command surface, ≤12 cap, 1 reserved
- **Stage:** cross-cutting · **Complexity:** M · **Milestone:** M4
- **Depends on:** F-02..F-08
- **Ref coverage:** GSD ships ~80 `/gsd-*` commands; Superpowers ~20; ECC ~15. Ours is the lone strict cap. None reserve a slot.
- **Closes IDEA property:** "One arrow chain"
- **Confidence:** HIGH

Exactly: `/godmode`, `/mission`, `/brief N`, `/plan N`, `/build N`, `/verify N`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`. v1.x's `/prd`, `/plan-stories`, `/execute` removed with one-time deprecation banners.

#### F-02. `/godmode` — orient + statusline + state-aware "what now?" in ≤5 lines
- **Stage:** orient · **Complexity:** M · **Milestone:** M4
- **Depends on:** F-15, F-20
- **Ref coverage:** GSD `/gsd-status` is similar but verbose (~20 lines, multi-section). Superpowers/ECC have no equivalent. Ours is the only ≤5-line state-aware orient.
- **Closes IDEA property:** "One arrow chain"
- **Confidence:** HIGH

Three jobs only: (1) print 5-line "what now?" from `.planning/STATE.md` (or `run /mission` if absent); (2) live-list agents+skills+briefs from filesystem; (3) one-shot statusline setup if not enabled. **Never** prints a literal version string (statusline carries it).

#### F-03. `/mission` — Socratic mission init writing `.planning/PROJECT.md` + ROADMAP + STATE
- **Stage:** mission · **Complexity:** M · **Milestone:** M4
- **Depends on:** F-18
- **Ref coverage:** GSD `/gsd-new-project` is closest; uses different vocabulary ("project", "milestone") and produces 6+ files. Ours produces 5 named for our model (PROJECT/REQUIREMENTS/ROADMAP/STATE/config.json).
- **Closes:** Project-level grounding for `/brief N`
- **Confidence:** HIGH

Explicit Socratic discussion (no silent prompt mutation). Idempotent — on returning project, no-ops with "mission already defined; run /brief N".

#### F-04. `/brief N` — Socratic brief → single `BRIEF.md` (why+what+spec+research summary)
- **Stage:** brief · **Complexity:** M · **Milestone:** M4
- **Depends on:** F-03, F-21, F-22
- **Ref coverage:** GSD `/gsd-discuss-phase` writes CONTEXT.md (multiple files: CONTEXT, CONCERNS, etc.). Ours collapses to one file. ECC/Superpowers have nothing equivalent.
- **Closes IDEA property:** "Two artifact files per brief"
- **Confidence:** HIGH

Optional `@researcher` and `@spec-reviewer` spawns. Single file output: `.planning/briefs/NN-name/BRIEF.md`.

#### F-05. `/plan N` — atomic, parallelizable PLAN.md with verification section
- **Stage:** plan · **Complexity:** M · **Milestone:** M4
- **Depends on:** F-04, F-23
- **Ref coverage:** GSD `/gsd-plan-phase` writes PLAN.md (similar but separate VERIFICATION.md/REVIEW.md). Ours folds verification status into PLAN.md itself.
- **Confidence:** HIGH

`@planner` produces atomic tasks with parallelism boundaries (waves) and per-task verification criteria. Reserves a "Verification status" section that `/verify` mutates in place.

#### F-06. `/build N` — wave-based parallel execution, atomic commit per task
- **Stage:** build · **Complexity:** L · **Milestone:** M4
- **Depends on:** F-05, F-25, D-08
- **Ref coverage:** GSD `/gsd-execute-phase` runs sequentially mostly (waves are an optional pattern, not enforced). Superpowers/ECC sequential. Ours: waves are first-class.
- **Closes IDEA property:** "Mechanically enforced quality" (atomic commits)
- **Confidence:** HIGH

Reads `PLAN.md`. Within wave: parallel via `run_in_background`. Across waves: sequential. Per-task atomic commit. File-polling fallback when stdout races corrupt parallel agent output.

#### F-07. `/verify N` — read-only goal-backward verification
- **Stage:** verify · **Complexity:** M · **Milestone:** M4
- **Depends on:** F-06, F-24
- **Ref coverage:** GSD `/gsd-verify-work` is similar; ours is stricter (read-only mechanically via `disallowedTools: Write, Edit` on `@verifier`).
- **Confidence:** HIGH

Walks back from BRIEF.md success criteria to working tree + git log. Reports COVERED / PARTIAL / MISSING per criterion into PLAN.md verification section.

#### F-08. `/ship` — quality gates, push, `gh pr create` (refuses on non-COVERED)
- **Stage:** ship · **Complexity:** S · **Milestone:** M4
- **Depends on:** F-07
- **Ref coverage:** GSD `/gsd-ship` similar. ECC `/ship` similar. Ours adds a hard refusal on PARTIAL/MISSING verification.
- **Confidence:** HIGH

No magic prompt mutation; sequences git operations and `gh`. Hard gate: refuses to operate unless PLAN.md verification section is all-COVERED.

### Helpers (cross-cutting)

#### F-31. `/debug`, `/tdd`, `/refactor`, `/explore-repo` — cross-cutting helpers
- **Stage:** helper · **Complexity:** M (4 × S) · **Milestone:** M4
- **Depends on:** F-25
- **Ref coverage:** All three reference plugins ship variants of these. Ours integrates with the live-indexed agent registry and follows the new frontmatter convention.
- **Confidence:** HIGH

Inherited from v1.x; rewritten to new shape with auto-mode awareness and Connects-to chain.

### Foundation — version, hardening, parity (M1)

#### F-09. `.claude-plugin/plugin.json:.version` is canonical; `install.sh` reads via `jq` at runtime
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M1
- **Depends on:** —
- **Ref coverage:** Superpowers tracks version in install.sh literal. GSD has version-drift protection via SDK. ECC similar to Superpowers. Ours: jq-only single source.
- **Closes:** CONCERNS #10 (three files, three versions)
- **Confidence:** HIGH

`commands/godmode.md` removes literal version (statusline carries it). CI gate (F-32) fails on any other file containing a version string except CHANGELOG.

#### F-10. Hooks emit valid JSON under adversarial inputs (`jq -n --arg`)
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M1
- **Depends on:** —
- **Ref coverage:** ECC's hooks use proper jq construction (we lift this idiom). v1.x hooks use heredoc string interpolation.
- **Closes:** CONCERNS #6 (branch-name fuzz), #18 (stdin drain under set -e)
- **Confidence:** HIGH

All hook output via `jq -n --arg ctx "$CONTEXT"`. Stdin drain tolerates closure (`cat > /dev/null || true`). Resolves project root from stdin's `cwd` field, not `pwd` (closes CONCERNS #7).

#### F-11. Per-file diff/skip/replace prompt in `install.sh` for customized files
- **Stage:** cross-cutting · **Complexity:** M · **Milestone:** M1
- **Depends on:** —
- **Ref coverage:** Superpowers has per-file prompts with diff (we lift the idiom). GSD/ECC use blanket overwrite with backup.
- **Closes:** CONCERNS #1 (rule customizations), #2 (agent/skill customizations)
- **Confidence:** HIGH

Prompt: `[d]iff / [s]kip / [r]eplace / [a]ll-replace / [k]eep-all`. Non-TTY default = keep customizations. Backup always taken regardless.

#### F-12. Backup rotation — keep last 5 in `~/.claude/backups/`
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M1
- **Depends on:** —
- **Ref coverage:** Superpowers caps backups; GSD/ECC unbounded.
- **Closes:** CONCERNS #13
- **Confidence:** HIGH

#### F-13. Uninstaller version-mismatch detection
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M1
- **Depends on:** F-09
- **Ref coverage:** None of the reference plugins do this. Differentiator-quality, but listed as table stakes because PROJECT.md Active.
- **Closes:** CONCERNS #4
- **Confidence:** HIGH

`uninstall.sh` reads `~/.claude/.claude-godmode-version`; refuses on mismatch unless `--force`.

#### F-14. v1.x migration is detection-only (one-line note, never destroys)
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M1
- **Depends on:** —
- **Ref coverage:** N/A (legacy migration is plugin-specific).
- **Closes:** CONCERNS #5 (`rm` after one keypress)
- **Confidence:** HIGH

Detects `.claude-pipeline/` and v1.x rule names; emits non-blocking pointer to `/mission`. Never deletes. Old `/prd`/`/plan-stories`/`/execute` ship with one-time deprecation banners pointing to new commands; banners removed in v2.x.

#### F-15. Live filesystem indexing — agents, skills, commands, briefs all enumerated at runtime
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M1 (and M3, M4 consumers)
- **Depends on:** —
- **Ref coverage:** GSD has partial live indexing (some lists hardcoded in templates). Superpowers/ECC: hardcoded lists.
- **Closes:** CONCERNS #8; IDEA property "live indexing, no drift"
- **Confidence:** HIGH

`/godmode`, `hooks/post-compact.sh`, statusline all `find` at runtime. Adding an agent = drop a file, restart. No registry edits.

#### F-16. `shellcheck` clean across every shipped `*.sh`
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M1 (then enforced in M5 CI)
- **Depends on:** —
- **Ref coverage:** ECC enforces shellcheck. GSD partial. Superpowers no.
- **Closes:** CONCERNS #20 (no automated test coverage at all)
- **Confidence:** HIGH

Includes a `.shellcheckrc` shipped in repo. Initial run fixes all existing warnings; CI gate (F-32) prevents regression.

### Agents — modernized layer (M2)

#### F-17. Agent frontmatter convention: aliases, effort tier, isolation, memory, maxTurns, Connects-to
- **Stage:** cross-cutting · **Complexity:** M · **Milestone:** M2
- **Depends on:** —
- **Ref coverage:** GSD has frontmatter conventions but pins numeric model IDs. Ours: aliases only. None enforce `Connects to:` chain.
- **Confidence:** HIGH

Every agent declares: `model: opus|sonnet|haiku` (alias, never numeric); `effort: high|xhigh` (high for code-touching to avoid Opus 4.7 rule-skipping pitfall, xhigh for design/audit); `isolation: worktree` (code-touching) or `memory: project` (persistent learners); `maxTurns: <N>` defensively; `Connects to: <upstream> → <self> → <downstream>`.

#### F-18. New `@planner` agent (brief → tactical plan)
- **Stage:** plan · **Complexity:** S · **Milestone:** M2
- **Depends on:** F-17
- **Ref coverage:** GSD `@planner` exists; ours has explicit Connects-to and our PLAN.md shape.
- **Confidence:** HIGH

Opus, `effort: xhigh` (design work, no code-touching). Read-mostly; writes only to PLAN.md.

#### F-19. New `@verifier` agent (read-only goal-backward verification)
- **Stage:** verify · **Complexity:** S · **Milestone:** M2
- **Depends on:** F-17
- **Ref coverage:** GSD `@verifier` exists; ours mechanically read-only via `disallowedTools: Write, Edit`.
- **Confidence:** HIGH

#### F-20. Two-stage review: split v1.x `@reviewer` into `@spec-reviewer` (pre) and `@code-reviewer` (post)
- **Stage:** brief, build · **Complexity:** S · **Milestone:** M2
- **Depends on:** F-17
- **Ref coverage:** None of the three split this way. Differentiator promoted to table stakes by PROJECT.md.
- **Confidence:** HIGH

Both read-only. Spec reviewer catches scope/criteria issues at `/brief` time (10× cheaper than code review). Code reviewer at `/build` time per-task.

#### F-21. Frontmatter linter — pure-Bash CI script
- **Stage:** cross-cutting · **Complexity:** M · **Milestone:** M2 (enforced in M5)
- **Depends on:** F-17
- **Ref coverage:** GSD has SDK-based linter (Node). Ours: Bash + jq only.
- **Confidence:** HIGH

Refuses commits with malformed agent metadata. Asserts every agent has all required fields and a valid Connects-to chain.

#### F-22. Existing v1.x agents modernized to F-17 convention
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M2
- **Depends on:** F-17
- **Ref coverage:** N/A (this is migration, not addition).
- **Confidence:** HIGH

`@writer`, `@executor`, `@architect`, `@security-auditor`, `@test-writer`, `@doc-writer`, `@researcher` all rewritten to new frontmatter convention.

### Hooks — expanded layer (M3)

#### F-23. `PreToolUse` hook blocks `Bash(git commit --no-verify*)` and quality-gate-bypass patterns
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M3
- **Depends on:** —
- **Ref coverage:** ECC has similar patterns. GSD has rule-level "never use --no-verify" but no hook enforcement. Ours mechanical.
- **Closes IDEA property:** "Mechanically enforced quality"
- **Confidence:** HIGH

Patterns blocked: `--no-verify`, `--no-gpg-sign`, `-c commit.gpgsign=false`, `git push --force` to main/master. Pattern-match caveat (CONCERNS #19) documented; mitigation = combine with regex anchors.

#### F-24. `PreToolUse` hook scans tool input for hardcoded secret patterns
- **Stage:** cross-cutting · **Complexity:** M · **Milestone:** M3
- **Depends on:** —
- **Ref coverage:** None of the reference plugins do mechanical secret scanning at PreToolUse time.
- **Confidence:** MEDIUM (false-positive tradeoffs need brief-time tuning)

AWS keys, GitHub PATs, `(api_key|secret|password)\s*=\s*['"][^'"]+['"]` heuristic. Refuses with clear remediation pointer (env var, `.env`).

#### F-25. `PostToolUse` hook surfaces failed quality-gate exit codes in next assistant turn
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M3
- **Depends on:** —
- **Ref coverage:** None do this consistently.
- **Confidence:** MEDIUM

When typecheck/lint/test commands return non-zero, inject context note: "Last quality-gate command failed: <cmd> exited <code>. Address before continuing."

#### F-26. `SessionStart` hook reads `.planning/STATE.md`, injects active-brief context
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M3
- **Depends on:** F-30, F-15
- **Ref coverage:** GSD has session-start state injection but tied to GSD's vocabulary. Ours injects brief #, status, next command.
- **Confidence:** HIGH

#### F-27. `PostCompact` reads agents+skills from live filesystem and gates from `config/quality-gates.txt`
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M3
- **Depends on:** F-15, F-28
- **Ref coverage:** ECC's PostCompact reads from filesystem (lifted idiom). v1.x hardcodes (CONCERNS #8).
- **Closes:** CONCERNS #8, #9
- **Confidence:** HIGH

#### F-28. Single source of quality gate definitions (`config/quality-gates.txt`)
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M1 (consumed by M3)
- **Depends on:** —
- **Ref coverage:** None centralize this way (gates duplicated across rules + hooks in all three).
- **Closes:** CONCERNS #9
- **Confidence:** HIGH

Canonical: `config/quality-gates.txt`. PostCompact reads from it; rules render from it; CI vocab gate asserts no other file embeds the gate list verbatim.

### Skills — rebuild + state management (M4)

#### F-29. All 11 user-facing skills rewritten / freshly authored to new shape
- **Stage:** cross-cutting · **Complexity:** L · **Milestone:** M4
- **Depends on:** F-01..F-08, F-31, F-17, F-30
- **Ref coverage:** GSD/Superpowers/ECC each have their own skill catalogs; ours is independently authored.
- **Confidence:** HIGH

Includes deprecation banners on `/prd`, `/plan-stories`, `/execute` that map old → new and pointer to migration note.

#### F-30. State management via `.planning/STATE.md` (machine-mutated, user-readable)
- **Stage:** cross-cutting · **Complexity:** M · **Milestone:** M4
- **Depends on:** F-18 (templates)
- **Ref coverage:** GSD has STATE.md (lifted idiom; our shape is different — brief # + name + status + next command in 4 lines).
- **Closes IDEA property:** "Latest-Claude-Code-native" (compaction survival)
- **Confidence:** HIGH

Skills mutate by appending an audit line + replacing the header block. User can hand-edit between commands; format is YAML-front-matter-style for parseability.

#### F-31b. Auto-mode awareness in every skill (detects "Auto Mode Active" reminder)
- **Stage:** cross-cutting · **Complexity:** S (per skill × 11) · **Milestone:** M4
- **Depends on:** —
- **Ref coverage:** None consistently. GSD partially adapted; Superpowers/ECC not.
- **Closes IDEA property:** "Latest-Claude-Code-native"
- **Confidence:** MEDIUM (auto-mode integration patterns still evolving)

Detects the system reminder; auto-approves routine decisions; minimizes interruptions; never enters plan mode unless explicitly asked.

#### F-32b. `init-context` shared helper (pure bash + jq)
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M4
- **Depends on:** F-30
- **Ref coverage:** GSD's `gsd-sdk` is the equivalent (Node). Ours is bash-native — hard PROJECT.md constraint.
- **Confidence:** HIGH

`skills/_shared/init-context.sh` reads `.planning/config.json` and STATE.md, returns a JSON blob. Skills source it instead of re-implementing parsing.

#### F-33. `.planning/` artifact templates ship with the plugin
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M4
- **Depends on:** —
- **Ref coverage:** GSD ships templates (different shape). Ours: PROJECT, REQUIREMENTS, ROADMAP, STATE, config.json, BRIEF.md, PLAN.md.
- **Confidence:** HIGH

`/mission` initializes the project-level templates; `/brief N` and `/plan N` use brief-level templates.

### Quality — CI, tests, parity, docs (M5)

#### F-34. GitHub Actions: shellcheck + frontmatter lint + version drift + parity gate + vocab gate
- **Stage:** cross-cutting (CI) · **Complexity:** M · **Milestone:** M5
- **Depends on:** F-09, F-16, F-21, F-28
- **Ref coverage:** ECC ships shellcheck CI; GSD ships SDK-based test CI. Ours combines bash-native lints in one workflow.
- **Closes:** CONCERNS #20
- **Confidence:** HIGH

Vocabulary gate is novel: greps user-facing surface (commands/, skills/, README) for `phase` / `task` / `story` / `PRD` / `milestone` and fails on hits. Internal docs (rules/, agents/) exempt.

#### F-35. `bats-core` smoke test of install → uninstall → reinstall → adversarial-input hook fixtures
- **Stage:** cross-cutting (CI) · **Complexity:** M · **Milestone:** M5
- **Depends on:** F-34
- **Ref coverage:** None ship bats smoke for the install round-trip. Differentiator-quality.
- **Confidence:** HIGH

Temporary `$HOME` per test. Adversarial fixtures: branch with quote, branch with newline, commit message with backslash, path with space.

#### F-36. CI parity gate: plugin-mode vs manual-mode hook bindings, permissions, timeouts
- **Stage:** cross-cutting (CI) · **Complexity:** M · **Milestone:** M5
- **Depends on:** F-34
- **Ref coverage:** No reference plugin ships two install modes. Differentiator promoted to table stakes by PROJECT.md.
- **Closes:** CONCERNS #11, #12
- **Confidence:** HIGH

Diffs derived hook bindings between `hooks/hooks.json` (plugin) and `config/settings.template.json` (manual). Asserts equivalent.

#### F-37. README ≤ 500 lines, no duplication with CONTRIBUTING; CHANGELOG dated; marketplace metadata polished
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M5
- **Depends on:** —
- **Ref coverage:** All three have larger READMEs.
- **Closes:** CONCERNS #21
- **Confidence:** HIGH

#### F-38. Statusline collapses to single `jq` invocation per render
- **Stage:** cross-cutting · **Complexity:** S · **Milestone:** M1
- **Depends on:** —
- **Ref coverage:** ECC similar. v1.x calls jq 4× per render (CONCERNS #19 perf note).
- **Confidence:** HIGH

---

## 2. Differentiators — best-in-class promises

These are PROJECT.md Active requirements. Each emerges from constraints (≤11 commands, jq-only, two-files-per-brief, mature internals). They cost little incremental implementation once table stakes are in.

#### D-01. Single happy path that fits in five lines
- **Complexity:** Constraint (zero cost beyond F-02) · **Milestone:** M4
- **Depends on:** F-02
- **Ref coverage:** No reference plugin ships a ≤5-line orient.
- **IDEA property:** #1
- **Confidence:** HIGH

#### D-02. Two artifact files per brief, never more
- **Complexity:** Constraint · **Milestone:** M4
- **Depends on:** F-04, F-05, F-07
- **Ref coverage:** GSD ships 4–5 files per phase. Ours strictly two: BRIEF.md, PLAN.md.
- **Confidence:** HIGH

#### D-03. Bash 3.2+ + jq only, no helper binary, no SDK
- **Complexity:** Constraint · **Milestone:** all (M1 enforces, M2-M5 honor)
- **Depends on:** F-32b
- **Ref coverage:** GSD requires `gsd-sdk` (Node). Superpowers shell-only. ECC shell-only. Ours is the strictest stance.
- **IDEA property:** "Latest-Claude-Code-native" (no install pain)
- **Confidence:** HIGH

#### D-04. Live filesystem indexing — no hardcoded inventories
- **Complexity:** S · **Milestone:** M1, M3
- **Depends on:** F-15
- **Ref coverage:** GSD partial; Superpowers/ECC hardcoded.
- **IDEA property:** #2 ("live indexing, no drift")
- **Confidence:** HIGH

#### D-05. Mechanical (not aspirational) quality gates
- **Complexity:** M · **Milestone:** M3
- **Depends on:** F-23, F-24, F-25, F-28
- **Ref coverage:** GSD/Superpowers/ECC describe gates in rule files; only ours enforces via PreToolUse + PostToolUse hooks.
- **IDEA property:** #3
- **Confidence:** HIGH

#### D-06. Plugin-mode == manual-mode UX parity, mechanically asserted
- **Complexity:** M · **Milestone:** M5
- **Depends on:** F-36
- **Ref coverage:** No reference plugin ships two install modes (and thus can't assert parity).
- **Confidence:** HIGH

#### D-07. Goal-backward verification before shipping
- **Complexity:** M · **Milestone:** M2 + M4
- **Depends on:** F-07, F-19
- **Ref coverage:** GSD `@verifier` similar; ours mechanically read-only.
- **Confidence:** HIGH

#### D-08. Atomic commits per workflow gate, enforced
- **Complexity:** S · **Milestone:** M3
- **Depends on:** F-23
- **Ref coverage:** All three reference plugins recommend; only ours enforces via PreToolUse `--no-verify` block.
- **IDEA property:** #4 ("adversarial-safe substrate" extends to here)
- **Confidence:** HIGH

#### D-09. Auto Mode awareness in every skill
- **Complexity:** S × 11 · **Milestone:** M4
- **Depends on:** F-31b
- **Ref coverage:** None consistently. We're the first to make it a per-skill convention.
- **IDEA property:** #5
- **Confidence:** MEDIUM

#### D-10. Wave-based parallel build with file-polling fallback
- **Complexity:** M · **Milestone:** M4
- **Depends on:** F-06
- **Ref coverage:** GSD has parallel pattern but not wave-structured; Superpowers/ECC sequential.
- **Confidence:** MEDIUM (race-handling needs care)

#### D-11. Two-stage read-only review (`@spec-reviewer` then `@code-reviewer`)
- **Complexity:** S · **Milestone:** M2
- **Depends on:** F-20
- **Ref coverage:** None split this way.
- **Confidence:** HIGH

#### D-12. Adversarial-safe hooks (branch-name fuzz survives)
- **Complexity:** S (covered by F-10) · **Milestone:** M1
- **Depends on:** F-10
- **Ref coverage:** ECC adversarial-safe. v1.x not. Ours: tested via bats fixtures.
- **IDEA property:** #4 ("adversarial-safe substrate")
- **Confidence:** HIGH

#### D-13. Vocabulary discipline — no `phase`/`task`/`story`/`PRD` leakage in user-facing surface
- **Complexity:** S (covered by F-34 vocab gate) · **Milestone:** M5
- **Depends on:** F-34
- **Ref coverage:** N/A (other plugins use these terms freely). Differentiator born of our reference-as-inspiration-only stance.
- **Confidence:** HIGH

#### D-14. Single source of truth for version (`plugin.json` + jq runtime read)
- **Complexity:** S (covered by F-09) · **Milestone:** M1
- **Depends on:** F-09
- **Ref coverage:** No reference plugin uses runtime jq read.
- **Confidence:** HIGH

#### D-15. Per-file customization preservation on reinstall
- **Complexity:** M (covered by F-11) · **Milestone:** M1
- **Depends on:** F-11
- **Ref coverage:** Superpowers similar; GSD/ECC overwrite.
- **Confidence:** HIGH

#### D-16. Connects-to chain rendered from agent frontmatter
- **Complexity:** S · **Milestone:** M2 (consumed by M4)
- **Depends on:** F-17
- **Ref coverage:** None render an agent dependency graph from frontmatter.
- **Confidence:** HIGH

`/godmode` reads agent frontmatter `Connects to:` lines and renders the upstream→self→downstream chain. Power users can modify any agent without breaking the indexer.

#### D-17. Prompt-cache-aware rule and agent prompt structure
- **Complexity:** M · **Milestone:** M2
- **Depends on:** F-17
- **Ref coverage:** None tune for 5-min cache hits explicitly.
- **Confidence:** MEDIUM (improvement, hard to measure win)

Static preamble first (no dates, no branch, no dynamic content); dynamic context after. Maximizes prompt-cache hit rate.

---

## 3. Anti-features — explicitly NOT building

Each has one-line reasoning. PROJECT.md Out of Scope items are marked.

#### A-01. Cross-runtime support (Codex, Gemini, OpenCode adapters)
PROJECT.md Out of Scope. Claude Code only — adds enormous surface for fractional benefit and dilutes Opus 4.7 / hook-contract specificity.

#### A-02. Workspace / multi-repo orchestration (worktree management as user feature)
PROJECT.md Out of Scope. Single repo, single workflow, single mental model. (Worktree isolation for agents is internal, not a user feature.)

#### A-03. External CLI dependency (Node, Python, custom binary, gsd-sdk equivalent)
PROJECT.md Out of Scope, Constraints. Bash 3.2+ + jq is the runtime budget; F-32b init-context.sh replaces the SDK.

#### A-04. Native Windows shell (cmd / PowerShell)
PROJECT.md Out of Scope. WSL2 is the supported path; native ports are a separate effort with no validated demand.

#### A-05. Telemetry / phone-home / opt-in metrics
PROJECT.md Out of Scope. Trust killer — no-network is the brand.

#### A-06. Cloud features (ultraplan-to-cloud, remote review, scheduled background agents)
PROJECT.md Out of Scope. The user's runtime already provides `ScheduleWakeup`/`/schedule`.

#### A-07. Copyleft dependencies
PROJECT.md Constraints. MIT-only licensing.

#### A-08. Vendored copies of reference plugin code
PROJECT.md Out of Scope. Read freely, copy nothing structural — output is ours.

#### A-09. ≥12 user-facing slash commands
PROJECT.md Constraints. The cap IS the differentiator; every command past 12 dilutes the surface.

#### A-10. Six-level workflow vocabulary (project / milestone / roadmap / phase / plan / task)
PROJECT.md Out of Scope. Ours collapses to five (Project / Mission / Brief / Plan / Commit) with two artifact files.

#### A-11. Per-task artifact files (TASK.md, EXECUTE.md, equivalents)
PROJECT.md Out of Scope. The git log IS the execution log.

#### A-12. `/everything` mega-command running the full workflow
Hides the workflow shape; defeats Core Value (single happy path, visible).

#### A-13. v1.x backwards compatibility beyond a one-time installer migration
Old commands get deprecation banners then removed in v2.x; carrying both indefinitely doubles surface.

#### A-14. Auto-installing required tools (`brew install jq`, etc.)
Privilege escalation + package-manager assumptions. Preflight check + clear error is the right call.

#### A-15. Auto-prompt-engineering of user requests (silent intent mutation)
Trust killer. Explicit `/brief` Socratic discussion makes intent clarification visible and consensual.

#### A-16. Bundled MCP server
Keeps plugin shape pure (rules / agents / skills / hooks / statusline / permissions). MCP servers live in their own repos.

#### A-17. Domain-specific scaffolding (Next.js starters, Rails templates)
Plugin shapes how Claude works, not what users build. Scaffolding belongs in `cookiecutter`/`create-*`.

#### A-18. Graphical UI / web dashboard
Surface is the terminal; statusline is the only visual primitive.

#### A-19. Cloud sync of `.planning/` state
git is the user's sync mechanism; cloud sync adds auth + service + data residency questions out of scope.

#### A-20. Plugin-internal package manager / skill marketplace
Skills are markdown files; users add by editing `~/.claude/skills/`. A registry is a different product.

#### A-21. Built-in LLM proxy / model abstraction layer
Claude Code already abstracts the model. Aliases (`opus`, `sonnet`, `haiku`) are the routing primitive.

#### A-22. AI-generated commit messages by default
Claude Code already does this on request. Per-commit auto-generation risks unhelpful messages and obscures intent.

#### A-23. Per-skill cherry-pick installation
Plugin is opinionated and cohesive. Cherry-picking turns it into a kit, which Core Value rejects.

#### A-24. Inline AI assistant for `.planning/` files
Claude Code IS the assistant. A separate "edit BRIEF.md with AI" feature is redundant.

---

## Feature dependency graph (high level)

```
F-09 (version SoT) ──→ F-13 (uninstaller version check)
F-15 (live indexing) ──→ F-02 (/godmode), F-27 (PostCompact), F-26 (SessionStart state)
F-33 (templates) ──→ F-32b (init-context) ──→ F-26 (SessionStart state) ──→ F-30 (STATE.md)
F-17 (frontmatter convention) ──→ F-18, F-19, F-20, F-22 (all agents) ──→ F-21 (linter), D-16, D-17

F-04 (/brief) ──→ F-05 (/plan) ──→ F-06 (/build) ──→ F-07 (/verify) ──→ F-08 (/ship)
F-20 (@spec-reviewer) ──→ F-04 (/brief)
F-18 (@planner) ──→ F-05 (/plan)
F-19 (@verifier) ──→ F-07 (/verify)

F-23 (PreToolUse blocker) ──→ D-08 (atomic commits enforced)
F-28 (gates SoT) ──→ F-25 (PostToolUse), F-27 (PostCompact)
F-16 (shellcheck) ──→ F-34 (CI), F-35 (bats), F-37 (docs parity)
F-09 ──→ F-34 (version-drift CI)
```

---

## Milestone area assignment summary

| Area | Table-stakes features | Differentiators delivered |
|------|----------------------|---------------------------|
| **M1 Foundation & Safety** | F-09, F-10, F-11, F-12, F-13, F-14, F-15, F-16, F-28, F-38 | D-03, D-04, D-12, D-14, D-15 (foundation) |
| **M2 Agent Layer** | F-17, F-18, F-19, F-20, F-21, F-22 | D-07, D-11, D-16, D-17 |
| **M3 Hook Layer** | F-23, F-24, F-25, F-26, F-27 | D-05, D-08 |
| **M4 Skill + State** | F-01..F-08, F-29, F-30, F-31b, F-32b, F-33, F-31 | D-01, D-02, D-09, D-10 |
| **M5 Quality CI/Tests/Docs** | F-34, F-35, F-36, F-37 | D-06, D-13 |

---

## CONCERNS.md High-severity coverage map

| CONCERNS # | What | Closed by |
|---|---|---|
| 1 | Rule customizations silently overwritten | F-11 |
| 2 | Manual-mode agent/skill overwrite without check | F-11 |
| 3 | Settings merge can drop top-level keys silently | F-34 (regression test) + F-35 (snapshot) |
| 4 | No version-mismatch detection on uninstall | F-13 |
| 5 | v1.x migration `rm`s after one keypress | F-14 |
| 6 | Branch names interpolated into hook JSON | F-10, D-12 |
| 7 | Hooks rely on cwd being project root | F-10 (cwd from stdin) |
| 8 | Hardcoded skill/agent lists in PostCompact | F-15, F-27 |
| 9 | Quality gates duplicated rules ↔ post-compact | F-28 |

All 9 Highs covered. Mediums (10–15) and Lows (16–21) covered by F-09, F-12, F-16, F-34, F-35, F-37, F-38.

---

## IDEA.md "Five must-have properties" coverage map

| IDEA property | Falsifiable check | Features delivering |
|---|---|---|
| 1. One arrow chain | `/godmode` ≤5 lines, state-aware | F-02, D-01 |
| 2. Live indexing, no drift | Drop file in `agents/`, restart, indexer picks it up | F-15, D-04 |
| 3. Mechanically enforced quality | PreToolUse blocks `--no-verify`; PostToolUse surfaces failed gates | F-23, F-25, F-28, D-05, D-08 |
| 4. Adversarial-safe substrate | Bats fixtures (quote, newline, backslash branches) survive; per-file customization preserved; backup rotation; uninstaller version check; shellcheck-clean | F-10, F-11, F-12, F-13, F-16, F-35, D-12, D-15 |
| 5. Latest-Claude-Code-native | Opus 4.7 aliases, effort tier discipline, auto-mode awareness, background subagents | F-17, F-31b, D-09, D-17 |

All five properties covered with falsifiable Active requirements.

---

## Confidence summary

| Section | Confidence | Notes |
|---|---|---|
| Workflow surface (F-01..F-08) | HIGH | Locked by PROJECT.md Active + Key Decisions |
| Foundation (F-09..F-16, F-28, F-38) | HIGH | All directly addressing CONCERNS High items |
| Agent layer (F-17..F-22) | HIGH | All explicit in PROJECT.md Active |
| Hook layer (F-23..F-27) | MEDIUM-HIGH | F-24 (secret scanning) FP/FN tradeoffs need brief-time tuning; F-25 (PostToolUse surfacing) integration pattern still being validated |
| Skill layer (F-29..F-33, F-31b, F-32b) | HIGH | Pure-bash + jq scope clear |
| Quality CI (F-34..F-37) | HIGH | Standard CI patterns; bats smoke is well-trodden |
| Differentiators D-01..D-08 | HIGH | Direct restatements of IDEA properties / PROJECT.md decisions |
| D-09 Auto Mode | MEDIUM | Documented primitive; per-skill integration patterns evolving |
| D-10 Wave parallel | MEDIUM | `run_in_background` documented; race-handling needs care |
| D-11..D-16 | HIGH | Explicit PROJECT.md decisions |
| D-17 Cache-aware prompts | MEDIUM | Improvement, hard to measure win directly |
| Anti-features A-01..A-24 | HIGH | All direct PROJECT.md Out of Scope items or constraints |

**Overall confidence: HIGH.**

---

## MVP recommendation — staged shipping order

If v2 ships in stages:

**v2.0 (must-have, the credible "polish mature version"):**
- M1 in full (F-09..F-16, F-28, F-38)
- M2 in full (F-17..F-22)
- M3 in full (F-23..F-27)
- M4 partial: F-01..F-08, F-29, F-30, F-32b, F-33, F-31 (sequential `/build` if F-06 wave-parallel slips)
- M5 partial: F-34 (shellcheck + frontmatter + version drift + vocab gate); F-37
- All differentiators except D-09, D-10, D-17 (these are incremental polish)

**v2.1 (polish polish):**
- F-35 (bats smoke) if slipped
- F-36 (parity gate) if slipped
- D-09 Auto Mode awareness rolled out skill-by-skill
- D-10 Wave-based parallel `/build`
- D-17 Cache-aware prompt structure tuning

This matches PROJECT.md's M1–M5 ordering without restructuring.
