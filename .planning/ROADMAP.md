# Roadmap: claude-godmode v2 — polish mature version

**Created:** 2026-04-26 (re-init)
**Mission:** Replace v1.x's `/prd → /plan-stories → /execute → /ship` pipeline with the locked v2 workflow chain — `/godmode → /mission → /brief → /plan → /build → /verify → /ship` — and harden every High-severity item in `.planning/codebase/CONCERNS.md` so the substrate is durable enough to carry the new surface.
**Vocabulary:** Project → Mission → Brief → Plan → Commit. User-facing surface = 11 slash commands. Two artifact files per active brief (`BRIEF.md` + `PLAN.md`).
**Granularity:** standard. **Parallelization:** within-brief, where dependencies allow.

---

## Build Order Rationale

Five briefs. Order is non-negotiable — each later brief literally cannot stand on the previous one's substrate without it being solid first.

```
Brief 1: FOUNDATION & SAFETY HARDENING
  │  Eight High/Critical CONCERNS items live here. Hooks must emit valid JSON;
  │  installer must never silently overwrite; version must be single-source.
  │  Live-filesystem indexing in PostCompact + statusline lands here too —
  │  it's substrate, not surface.
  ▼
Brief 2: AGENT LAYER MODERNIZATION
  │  Eight existing agents updated (aliases, effort policy, isolation, memory,
  │  maxTurns, Connects to:); four new agents (@planner, @verifier,
  │  @spec-reviewer, @code-reviewer); pure-Bash frontmatter linter.
  │  Skills (Brief 4) cannot wire to agents that don't exist with the right shape.
  ▼
Brief 3: HOOK LAYER EXPANSION
  │  PreToolUse blocks `--no-verify` and secret patterns; PostToolUse surfaces
  │  failed quality-gate exits; SessionStart reads .planning/STATE.md;
  │  prompt-cache-aware rule structure (QUAL-11) lands here because the cache
  │  story is a hook-context concern.
  │  Lands after Brief 2 because the new agent layer depends on the new hook
  │  context shape (additionalContext from SessionStart, additionalContext from
  │  PostToolUse on failed gates).
  ▼
Brief 4: SKILL LAYER & STATE MANAGEMENT
  │  Six new/rewritten user-facing skills (/mission, /brief, /plan, /build,
  │  /verify, /ship), four helpers updated (/debug, /tdd, /refactor,
  │  /explore-repo), /godmode rewritten with live filesystem indexing,
  │  workflow chain (WORKFLOW-01,02,03,05) operationalized, .planning/
  │  templates + init-context.sh shipped.
  │  Lands after Brief 3 because every skill spawns agents (Brief 2) and reads
  │  hook-injected context (Brief 3).
  ▼
Brief 5: QUALITY — CI, TESTS, DOCS PARITY
     GitHub Actions matrix; shellcheck on every *.sh; inline jq schema
     validation; frontmatter linter in CI; bats-core smoke test
     (install → /godmode → uninstall in mktemp -d $HOME); vocabulary CI
     gate; version-drift CI gate; plugin/manual parity gate; README +
     CHANGELOG + /godmode parity; CONTRIBUTING hygiene; CONCERNS.md
     traceability.
     Lands last because tests are meaningful only when all four substrates
     exist.
```

**Within-brief parallelism:** available in Briefs 1, 2, 3, 5. Brief 4 is recommended sequential — each new skill smoke-tested in a temp consumer repo before the next is written.

**Adjustment from user-suggested mapping:** WORKFLOW-04 (live filesystem indexing) is split-mapped — its hook + statusline portions land in Brief 1 (substrate), its `/godmode` portion lands in Brief 4 with SKILL-01 where the user-facing surface is built. Each requirement is mapped to exactly one brief; WORKFLOW-04 is mapped to Brief 4 (the user-facing surface), with Brief 1 supplying the substrate the skill consumes. Documented to make the seam visible.

---

## Coverage Stats

- v1 requirements total: **55** (5 WORKFLOW + 11 FOUND + 8 AGENT + 6 HOOK + 10 SKILL + 4 STATE + 11 QUAL)
- Mapped to briefs: **55**
- Unmapped: **0**

| Brief | Requirements | Count |
|---|---|---|
| 1 — Foundation & Safety Hardening | FOUND-01..11 | 11 |
| 2 — Agent Layer Modernization | AGENT-01..08 | 8 |
| 3 — Hook Layer Expansion | HOOK-01..06, QUAL-11 | 7 |
| 4 — Skill Layer & State Management | WORKFLOW-01..05, SKILL-01..10, STATE-01..04 | 19 |
| 5 — Quality, CI, Tests, Docs Parity | QUAL-01..10 | 10 |
| **Total** | | **55** |

All 9 High-severity CONCERNS.md items are addressed across Briefs 1, 3, and 5 (see REQUIREMENTS.md "CONCERNS.md Traceability").

---

## Briefs

- [ ] **Brief 1: Foundation & Safety Hardening** — Single-source version, hook JSON safety, installer per-file prompts, backup rotation, shellcheck baseline, live-filesystem substrate.
- [ ] **Brief 2: Agent Layer Modernization** — Modernize 8 agents (aliases, effort, isolation, memory, maxTurns, Connects to); add @planner, @verifier, @spec-reviewer, @code-reviewer; pure-Bash frontmatter linter.
- [ ] **Brief 3: Hook Layer Expansion** — PreToolUse blocking `--no-verify` and secret patterns; PostToolUse surfacing failed quality-gate exits; SessionStart reading STATE.md; prompt-cache-aware rule structure.
- [ ] **Brief 4: Skill Layer & State Management** — Build the 11-command surface (`/mission`, `/brief`, `/plan`, `/build`, `/verify`, `/ship`, helpers, `/godmode` rewrite); ship `.planning/` artifact templates + `init-context.sh`.
- [ ] **Brief 5: Quality — CI, Tests, Docs Parity** — GitHub Actions matrix (macOS + Linux), shellcheck, JSON schema validation, frontmatter linter, bats-core smoke test, vocabulary gate, doc parity, CONTRIBUTING hygiene, CONCERNS.md traceability table closed.

---

## Brief Details

### Brief 1: Foundation & Safety Hardening

**Goal**: The v1.x substrate stops fighting the user — installs preserve customizations, hooks survive adversarial inputs, version drift is impossible, every shell script is shellcheck-clean.
**Depends on**: Nothing (first brief).
**Requirements**: FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06, FOUND-07, FOUND-08, FOUND-09, FOUND-10, FOUND-11
**Success Criteria** (what must be TRUE when this brief lands):
  1. Running `./install.sh` over a `~/.claude/` whose rule, agent, or skill files have been hand-edited never overwrites those edits silently — the installer either prompts (`[d]iff / [s]kip / [r]eplace / [a]ll-replace / [k]eep-all`) or, when stdin isn't a TTY, keeps the customization. A backup is taken regardless and `~/.claude/backups/` retains exactly the last 5.
  2. Every shipped hook (`session-start.sh`, `post-compact.sh`) emits valid JSON when invoked against a git repo whose branch name contains `"`, `\`, or a literal newline; project root is resolved from stdin's `cwd` field; stdin drain failure under `set -euo pipefail` does not abort the hook.
  3. The plugin's version appears in exactly one place — `.claude-plugin/plugin.json:.version`. `install.sh` reads it via `jq -r .version` at runtime; `commands/godmode.md` carries no literal version; the statusline renders the runtime value with a single `jq` invocation per render.
  4. `./uninstall.sh` reads `~/.claude/.claude-godmode-version`, refuses to operate if it doesn't match the script's known version unless `--force` is passed, and emits a clear warning. Detection of `.claude-pipeline/` produces a one-line non-destructive note pointing to `/mission`.
  5. `shellcheck` (v0.11.0) over every `*.sh` in the repo passes with zero errors at the brief's exit; `.shellcheckrc` enumerates any intentional disables (e.g. `SC1091` for sourced files known at install time).
**Plans**: TBD (drafted by `/plan 1`)
**Risks**: per-file prompt UX needs care under bats fixtures (`stdin not a TTY` branch must be exercised); branch-name fuzz fixture set must include the four metacharacters (`"`, `\`, `\n`, `'`).

### Brief 2: Agent Layer Modernization

**Goal**: The agent layer is the canonical v2 shape — aliases (never pinned IDs), effort tier locked by role, isolation/memory declared explicitly, four new agents in place, and a frontmatter linter that mechanically enforces the conventions.
**Depends on**: Brief 1 (PreToolUse + PostToolUse hooks must be live before agents that write code can be safely worktree-isolated; shellcheck-clean substrate so the new linter runs in CI).
**Requirements**: AGENT-01, AGENT-02, AGENT-03, AGENT-04, AGENT-05, AGENT-06, AGENT-07, AGENT-08
**Success Criteria** (what must be TRUE when this brief lands):
  1. Every agent file under `agents/` declares `model:` from `{opus, sonnet, haiku}` (alias, never pinned ID), explicit `effort:` matching role policy (`high` for `@executor`, `@writer`, `@test-writer`; `xhigh` for `@architect`, `@security-auditor`, `@planner`, `@verifier`), explicit `maxTurns`, and a `Connects to: <upstream> → <self> → <downstream>` line.
  2. Code-writing agents (`@executor`, `@writer`, `@test-writer`) declare `isolation: worktree`. Persistent learners (`@executor`, `@researcher`, `@reviewer`) declare `memory: project`. Read-only audit agents declare `disallowedTools: Write, Edit, MultiEdit`.
  3. Four new agents exist as files: `agents/planner.md` (opus, xhigh, read-only), `agents/verifier.md` (opus, xhigh, read-only), `agents/spec-reviewer.md` (sonnet, high, read-only), `agents/code-reviewer.md` (sonnet, high, read-only). The v1.x `@reviewer` is split into `@spec-reviewer` + `@code-reviewer` with no remaining `@reviewer` references in shipped surface.
  4. `scripts/lint-frontmatter.sh` (pure Bash + awk + jq, no Node, no Python) extracts each agent file's frontmatter and exits non-zero on any of: missing required field, invalid model alias, invalid effort tier, the combination `effort: xhigh` with `Write|Edit|MultiEdit` in `tools`, missing `maxTurns`, malformed `Connects to:`. Run locally over the agent set returns clean.
  5. No agent prompt or description contains forbidden vocabulary (`phase`, `story`, `plan-phase`, `discuss-phase`, `verify-work`, `gsd-sdk`) outside attribution comments.
**Plans**: TBD (drafted by `/plan 2`)
**Risks**: `@verifier` foreground vs. `background: true` is an open `/brief 2` question; the read-only-but-thorough trade-off lands one way and is hard to revisit. The frontmatter linter's YAML-to-JSON awk filter is load-bearing — must be unit-tested with edge cases (multiline values, nested fields).

### Brief 3: Hook Layer Expansion

**Goal**: Hooks are the mechanical enforcement layer — quality gates the rules describe become quality gates the runtime refuses to bypass. SessionStart reads STATE.md and points the user at the next command. Rule files are prompt-cache-friendly; cache hits are repeatable.
**Depends on**: Brief 2 (agent prompts and Connects-to chains exist; SessionStart's additionalContext consumed by agents); Brief 1 substrate (jq-only JSON, cwd-from-stdin, shellcheck-clean) is the foundation every new hook stands on.
**Requirements**: HOOK-01, HOOK-02, HOOK-03, HOOK-04, HOOK-05, HOOK-06, QUAL-11
**Success Criteria** (what must be TRUE when this brief lands):
  1. A new `hooks/pre-tool-use.sh` refuses `Bash(git commit --no-verify*)`, `Bash(git commit -n*)`, `Bash(git commit --no-gpg-sign*)`, `Bash(git -c commit.gpgsign=false*)`, and `Bash(git push --force* main)` / `master`. It emits `hookSpecificOutput.permissionDecision: "deny"` with a clear error pointing at the rule file. Bypass attempts fail; the rule isn't aspirational.
  2. The same `pre-tool-use.sh` scans tool input for hardcoded secret patterns (AWS keys, GitHub PATs, generic `(api_key|secret|password)\s*=\s*['"][^'"]+['"]` heuristic) and refuses with a clear suggestion to use env vars or `.env`. False positives are tolerated; the user can override with explicit acknowledgment.
  3. A new `hooks/post-tool-use.sh` detects non-zero exit codes from typecheck/lint/test/shellcheck Bash invocations and surfaces `additionalContext` in the next assistant turn naming the failing command and exit code.
  4. `hooks/session-start.sh` reads `.planning/STATE.md` if it exists; absence is a silent no-op. When present, it injects current brief number + name + suggested next command (`/plan`, `/build`, `/verify`, or `/ship` depending on STATE.md). `hooks/post-compact.sh` enumerates agents, skills, and briefs from the live filesystem (no hardcoded list anywhere) and reads quality gates from `config/quality-gates.txt` (the single source).
  5. Two consecutive `PostCompact` invocations against the same project state produce byte-identical `additionalContext` output. Rule files (`rules/godmode-*.md`) contain no dates, branch names, paths, or other dynamic content — verified by CI grep against `\b\d{4}-\d{2}-\d{2}\b`, `^Branch:`, and `<!-- generated`. Volatile content lives only in hook-injected `additionalContext`.
**Plans**: TBD (drafted by `/plan 3`)
**Risks**: secret-scanning false-positive rate needs `/brief 3` discussion to balance noise vs. coverage; the `--no-verify` short-form (`-n`) shares the letter with other git flags — the deny pattern must not over-block legitimate uses (`git commit -n -m "..."` is the only collision).

### Brief 4: Skill Layer & State Management

**Goal**: The user types one of 11 commands, sees the workflow chain, and progresses through it. Every artifact has a template; every state transition is mechanical. v1.x skills ship with one-time deprecation banners. The `.planning/` shape is the consumer-side state every skill reads and writes.
**Depends on**: Brief 3 (every skill consumes hook-injected context; SessionStart hook reads STATE.md → skills update STATE.md so the loop closes); Brief 2 (every skill spawns specific named agents); Brief 1 substrate (shellcheck-clean `init-context.sh`).
**Requirements**: WORKFLOW-01, WORKFLOW-02, WORKFLOW-03, WORKFLOW-04, WORKFLOW-05, SKILL-01, SKILL-02, SKILL-03, SKILL-04, SKILL-05, SKILL-06, SKILL-07, SKILL-08, SKILL-09, SKILL-10, STATE-01, STATE-02, STATE-03, STATE-04
**Success Criteria** (what must be TRUE when this brief lands):
  1. Exactly 11 user-invocable slash commands ship: `/godmode`, `/mission`, `/brief N`, `/plan N`, `/build N`, `/verify N`, `/ship`, `/debug`, `/tdd`, `/refactor`, `/explore-repo`. `find commands -name '*.md' -maxdepth 1 | wc -l` plus user-invocable skills under `skills/*/SKILL.md` totals ≤ 12. The 12th slot is reserved (no command occupies it).
  2. `/godmode` answers "what now?" in ≤ 5 lines given any state of `.planning/STATE.md`, lists agents/skills/briefs by live filesystem scan (never hardcoded), and offers one-shot statusline setup if not enabled. It carries no literal version. Running `/godmode` against a v1.x consumer (`.claude-pipeline/` present, `.planning/` absent) emits a one-line non-destructive migration note pointing at `/mission`.
  3. The chain works end-to-end on a fresh consumer repo: `/mission` initializes `.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `config.json` from templates; `/brief 1` writes `.planning/briefs/01-name/BRIEF.md` with `## User Goal (verbatim)` and a `<!-- BRIEF-COMPLETE -->` sentinel; `/plan 1` refuses without the sentinel and otherwise writes `PLAN.md` with `## Tactical Plan` + `## Verification Status`; `/build 1` refuses without `PLAN.md` and otherwise commits per-task atomically; `/verify 1` reports COVERED/PARTIAL/MISSING per success criterion; `/ship` refuses unless verification status is all-COVERED.
  4. Every public skill declares `Connects to: <upstream> → <this> → <downstream>` and detects "Auto Mode Active" — destructive ops (force push, settings.json writes, schema migrations) refuse in Auto Mode with "explicit user confirmation required, exit Auto Mode". `skills/_shared/init-context.sh` is pure bash + jq, returns a JSON blob with project + mission + active-brief context, and is sourced by every skill orchestrator.
  5. v1.x skills (`/prd`, `/plan-stories`, `/execute`) ship one-time deprecation banners pointing to new commands. `/debug`, `/tdd`, `/refactor`, `/explore-repo` retain v1 functionality with frontmatter aligned to v2 conventions. Every brief directory under `.planning/briefs/` contains exactly two files (`BRIEF.md` + `PLAN.md`) — no `EXECUTE.md`, no `TASK.md`, no per-commit files.
**Plans**: TBD (drafted by `/plan 4`)
**Risks**: `/build`'s wave-based parallel execution with `run_in_background` + file-polling fallback is the most complex skill — needs `/brief 4` discussion on concurrency cap (recommendation: hardcoded 5 for v2, config knob deferred); `/mission`'s Socratic discussion shape needs explicit design to avoid "auto-prompt-engineering" anti-pattern; STATE.md mutability (machine-only vs. user-editable) is an open `/brief 4` question.

### Brief 5: Quality — CI, Tests, Docs Parity

**Goal**: Every guardrail described in the previous four briefs is mechanically enforced in CI. A user adding a new agent that violates the effort policy gets a red PR. README, CHANGELOG, and `/godmode` cannot drift. The bats smoke test catches install-path regressions before release. All High-severity CONCERNS.md items have a closed traceability row.
**Depends on**: Brief 4 (smoke test exercises the full surface; vocabulary gate runs against shipped skills/agents/rules; bats round-trip needs a working `/godmode`).
**Requirements**: QUAL-01, QUAL-02, QUAL-03, QUAL-04, QUAL-05, QUAL-06, QUAL-07, QUAL-08, QUAL-09, QUAL-10
**Success Criteria** (what must be TRUE when this brief lands):
  1. `.github/workflows/ci.yml` runs on every PR with a matrix of `[ubuntu-latest, macos-latest]`. Steps: shellcheck (v0.11.0) over every `*.sh`; `bash scripts/lint-json.sh` (inline `jq -e` assertions on `plugin.json`, `hooks.json`, `settings.template.json`, `.planning/config.json` schema); `bash scripts/lint-frontmatter.sh`; `bats tests/`. No Node, no Python in the CI critical path — jq-only constraint preserved.
  2. The bats-core (v1.13.0) smoke test in `tests/install.bats` runs `install.sh` into a `mktemp -d` `$HOME`, asserts `/godmode` lists the live agent/skill/brief inventory correctly, runs `uninstall.sh`, asserts `~/.claude/` is clean, and passes on both runners. A test of plugin-mode and a test of manual-mode produce equivalent post-install snapshots (parity gate).
  3. Two CI gates enforce surface invariants: a vocabulary gate (`scripts/check-vocabulary.sh` greps shipped artifacts for forbidden terms — `phase`, `story`, `plan-phase`, `discuss-phase`, `verify-work`, `gsd-sdk` — outside attribution) and a version-drift gate (every advertised version string in `install.sh`, `commands/godmode.md`, `README.md`, `CHANGELOG.md` matches `plugin.json:.version`). Both gates fail the PR on hits.
  4. README, CHANGELOG, and `/godmode`'s live-indexer output agree exactly on the public surface (agent list, skill list, version string, jq-only runtime claim, plugin/manual-mode parity claim, deny-pattern caveat). CI compares them; mismatch fails the PR. CONTRIBUTING.md ships hygiene recipes (backup rotation policy, `git worktree prune`, frontmatter conventions, per-file diff/skip/replace, command-count check ≤ 12 as a pre-release gate).
  5. The "CONCERNS.md Traceability" table in REQUIREMENTS.md shows every High-severity item with a non-empty resolution column. CI asserts no row in that table has the literal string "TBD" or empty resolution. The brief's closing commit verifies all 9 High items resolved.
**Plans**: TBD (drafted by `/plan 5`)
**Risks**: bats smoke test scope creep — the round-trip test must stay fast (≤ 30s) or CI becomes painful; the vocabulary gate's allowlist (planning artifacts, CHANGELOG, attribution.md) needs to be precisely scoped to avoid blocking legitimate references; README/CHANGELOG/`/godmode` parity check requires `/godmode`'s indexer to expose machine-readable output (one-line-per-skill format) — a small design decision that lands here.

---

## Progress Table

| Brief | Plans Complete | Status | Completed |
|---|---|---|---|
| 1. Foundation & Safety Hardening | 0/0 | Not started | — |
| 2. Agent Layer Modernization | 0/0 | Not started | — |
| 3. Hook Layer Expansion | 0/0 | Not started | — |
| 4. Skill Layer & State Management | 0/0 | Not started | — |
| 5. Quality — CI, Tests, Docs Parity | 0/0 | Not started | — |

Plans counts are filled in by `/plan N` once each brief is decomposed.

---

## Notes

- The **CONCERNS.md High-severity items** are addressed primarily in Brief 1 (substrate) and Brief 3 (hooks), with Brief 5 closing the traceability table mechanically. See REQUIREMENTS.md "CONCERNS.md Traceability" for the per-item map.
- **Why no separate "workflow integration" brief** (which the research SUMMARY proposed as Brief 4): the user's explicit instruction is to fold workflow integration into the skill layer brief. The integration concerns (rule rewrites for new vocabulary, plugin/manual parity, prompt-cache rule structure, v1.x → v2 migration note) are absorbed: rule rewrites and prompt-cache structure live in Brief 3 (where the substrate they describe is); plugin/manual parity is a CI gate in Brief 5; migration detection lives in Brief 4 alongside `/mission` and `/godmode`.
- **Reserved 12th command slot** stays empty in v2.0; future `/resume`, `/audit`, or `/explore` (per FUT-01) candidates wait for proven demand.

---

*Roadmap created: 2026-04-26 by roadmapper after re-init under "inspiration only" principle. 5 briefs, 55 of 55 v1 requirements mapped, build order non-negotiable per research/ARCHITECTURE.md.*
