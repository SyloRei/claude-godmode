# Phase 5: Quality — CI, Tests, Docs Parity — Pattern Map

**Mapped:** 2026-04-28
**Files analyzed:** 9 (8 NEW + 3 MODIFIED, with `CHANGELOG.md` already present so its row is "MODIFIED" not "NEW")
**Analogs found:** 7 / 9 (plus 2 with no in-repo analog — `ci.yml` and `tests/install.bats`)

This map tells the planner exactly **which existing files each new Phase 5 file should mirror, and which line ranges to lift the helper / pattern from.** Every analog is a file that already shipped in Phase 1–4 — no external pattern-borrowing.

---

## File Classification

| File | New/Modified | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|---|
| `.github/workflows/ci.yml` | NEW | CI workflow (config) | event-driven (PR/push trigger → run jobs) | **none in repo** — `.github/` currently holds only `ISSUE_TEMPLATE/`, `PULL_REQUEST_TEMPLATE.md` | **NO ANALOG** (cite GitHub Actions canonical patterns) |
| `tests/install.bats` | NEW | bats-core test suite | request-response (per-test setup → run → assert → teardown) | **none in repo** — `tests/` currently holds only `fixtures/hooks/` | **NO ANALOG IN REPO** (cite bats-core idioms; `tests/fixtures/hooks/setup-fixtures.sh` is closest skeleton for HOME isolation) |
| `tests/fixtures/branches/quote.json` | NEW | static JSON fixture | file-I/O (read-only, fed to hook stdin) | `tests/fixtures/hooks/cwd-quote-branch.json` | **EXACT** (same role, same data flow, same generator script lineage) |
| `tests/fixtures/branches/backslash.json` | NEW | static JSON fixture | file-I/O | `tests/fixtures/hooks/cwd-backslash-branch.json` | **EXACT** |
| `tests/fixtures/branches/newline.json` | NEW | static JSON fixture | file-I/O | `tests/fixtures/hooks/cwd-newline-branch.json` | **EXACT** |
| `tests/fixtures/branches/apostrophe.json` | NEW | static JSON fixture | file-I/O | `tests/fixtures/hooks/cwd-apostrophe-branch.json` | **EXACT** |
| `scripts/check-parity.sh` | NEW | CI lint script (utility) | request-response (read 2 JSON files → diff → exit 0/1) | `scripts/check-version-drift.sh` | **EXACT** (same role, same data flow, same exit-code contract; both compare a canonical against derived data) |
| `scripts/check-vocab.sh` | NEW | CI lint script (utility) | request-response (walk surface tree → grep tokens → exit 0/1) | `scripts/check-frontmatter.sh` | **EXACT** (same role, same data flow, same per-file walk + per-violation `report_fail` accumulator pattern) |
| `CHANGELOG.md` | **MODIFIED** (already present) | docs (markdown) | request-response (read by humans + check-version-drift.sh) | the file itself (already shipped Phase 1) | **SELF-ANALOG** (extend existing `## [Unreleased]` block to a dated `## [v2.0.0]`; same Keep-a-Changelog structure) |
| `README.md` | MODIFIED | docs (rewrite) | request-response | the file itself (current v1.x README) — **rewrite, not extend**; `IDEA.md` has the locked tagline + the 9-section skeleton spirit | **SELF-ANALOG (structural lift from CONTEXT D-19, IDEA.md)** |
| `.claude-plugin/plugin.json` | MODIFIED | plugin manifest (config) | static data | the file itself | **SELF-ANALOG** (touch only `.description` and `.keywords`; preserve `.userConfig.model_profile` from Phase 1) |
| `CONTRIBUTING.md` | MODIFIED (light touch) | docs (markdown) | request-response | the file itself | **SELF-ANALOG** (insert pointer + tag-protection note; do not rewrite) |

---

## Pattern Assignments

### `scripts/check-parity.sh` (CI lint script, request-response)

**Analog:** `scripts/check-version-drift.sh` (78 lines total). Phase 1 deliverable. Same role (CI gate), same data flow (read canonical → compare → exit 0/1), same shellcheck-clean style.

**Imports / preamble pattern** (lines 1–13):

```bash
#!/usr/bin/env bash
# scripts/check-parity.sh
# Asserts hooks/hooks.json[hooks] and config/settings.template.json[hooks] are
# byte-equivalent after path-prefix normalization (${CLAUDE_PLUGIN_ROOT}/... → ~/.claude/...).
# CI gate (Phase 5). Exits non-zero on drift with diff output as evidence.
# Bash 3.2 + jq + diff only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_HOOKS="$REPO_ROOT/hooks/hooks.json"
TEMPLATE="$REPO_ROOT/config/settings.template.json"

[ -f "$PLUGIN_HOOKS" ] || { echo "[x] hooks.json not found at $PLUGIN_HOOKS"; exit 1; }
[ -f "$TEMPLATE" ] || { echo "[x] settings.template.json not found at $TEMPLATE"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[x] jq required but not installed"; exit 1; }
```

Lift verbatim from `check-version-drift.sh` lines 1–13: shebang, comment header (purpose + CI role + bash/tool requirements), `set -euo pipefail`, `SCRIPT_DIR`/`REPO_ROOT` resolution idiom, `[ -f "$X" ] || { echo "[x] ..."; exit 1; }` preflight checks, `command -v jq` preflight.

**Drift accumulator pattern** (analog lines 20, 72–78):

```bash
DRIFT=0

# ... checks set DRIFT=1 on any violation ...

if [ "$DRIFT" -eq 0 ]; then
  echo "[+] hooks/hooks.json and settings.template.json are equivalent"
  exit 0
else
  echo "[x] plugin/manual parity drift — diff above"
  exit 1
fi
```

Same shape as `check-version-drift.sh` lines 20, 72–78 — single `DRIFT` integer accumulator, success line on 0, failure line on non-0. Use `[+]` for success and `[x]` for fatal (matches `install.sh` color helpers without re-importing the colors — these are CI scripts, color is optional).

**Core normalization-and-diff pattern (NEW; no exact analog):**

The closest precedent is the `install.sh` settings-merge `jq -s '.[0] * .[1]'` filter (lines 184–220). For Phase 5's parity check, normalize then diff:

```bash
# Normalize: replace ${CLAUDE_PLUGIN_ROOT} prefix with ~/.claude in plugin-mode JSON,
# then sort keys (-S) for stable comparison. Path-prefix divergence is EXPECTED
# (D-10) — every other field must be byte-identical.
PLUGIN_NORMALIZED=$(jq -S '
  .hooks |
  walk(if type == "string" then gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; "~/.claude") else . end)
' "$PLUGIN_HOOKS")

TEMPLATE_NORMALIZED=$(jq -S '.hooks' "$TEMPLATE")

if ! diff <(printf '%s\n' "$PLUGIN_NORMALIZED") <(printf '%s\n' "$TEMPLATE_NORMALIZED"); then
  DRIFT=1
fi
```

Process substitution `<(...)` is bash 3.2 portable (verified in STACK.md "Bash 3.2 portability" § Safe core constructs). `jq -S` for sorted-key canonicalization. `walk(...)` for the path-prefix substitution.

**Error reporting style** (lines 24–55 of analog):

```bash
echo "[!] hooks.json: $line"
DRIFT=1
```

Use `[!]` for per-violation lines. Use `[i]` for informational (matches analog line 18: `echo "[i] canonical version: $CANONICAL"`).

---

### `scripts/check-vocab.sh` (CI lint script, request-response)

**Analog:** `scripts/check-frontmatter.sh` (152 lines total). Phase 2 deliverable. Same role (CI gate, walks a directory tree), same data flow (per-file iteration → grep → accumulate violations), same `report_fail` pattern.

**Imports / preamble pattern** (analog lines 1–15):

```bash
#!/usr/bin/env bash
# scripts/check-vocab.sh
# Linter for forbidden vocabulary in user-facing surface.
# Tokens: phase, task, story, PRD, gsd-*, cycle, milestone (case-insensitive, word-boundary).
# Surface scanned: commands/*.md, skills/**/SKILL.md, README.md.
# Internal docs (rules/, agents/, .planning/, tests/, scripts/, hooks/, config/, bin/) exempt.
# Per-file allowlist: see ALLOWED_TOKENS_FOR_PATH near top of file.
# Exit 0 on clean; 1 on any hit with file:line:token:excerpt evidence.
# CI gate (Phase 5). Bash 3.2 + grep + jq only.
# Convention authority: rules/godmode-vocabulary.md (Phase 4 D-26).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
```

Lift the comment header style verbatim from `check-frontmatter.sh` lines 1–7: filename, one-line purpose, "Pure bash + grep + jq + awk", "Bash 3.2 portable", exit-code contract, CI role, "Convention authority:".

**`report_fail` accumulator** (analog lines 17–22):

```bash
FAILED=0
report_fail() {
  echo "[!] $1: $2: $3" >&2
  FAILED=$((FAILED + 1))
}
```

Lift verbatim. The 3 args are file/line, rule-name, evidence — perfect fit for D-15's `<file>:<line>:<token>:<excerpt>` output format.

**Per-file walk pattern** (analog lines 124–138):

```bash
LC_ALL=C
if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    [ -f "$arg" ] || { report_fail "$arg" "not-found" "file does not exist"; continue; }
    lint_file "$arg"
  done
else
  for f in "$REPO_ROOT/commands/"*.md "$REPO_ROOT/skills/"*/SKILL.md "$REPO_ROOT/README.md"; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
      _*|README.md) ;;  # README.md ALLOWED here — it IS user-facing surface
    esac
    lint_file "$f"
  done
fi
```

Lift the `LC_ALL=C` + arg-vs-walk dual-mode from analog 124–138. The walk targets change (commands + skills/*/SKILL.md + README.md instead of agents/), but the structure is identical — explicit args allow `bash check-vocab.sh skills/build/SKILL.md` to lint one file (CI failure-debugging UX win, same as `check-frontmatter.sh`).

**Final accumulator-check pattern** (analog lines 140–151):

```bash
if [ "$FAILED" -eq 0 ]; then
  echo "[+] vocabulary clean (N file(s) scanned)"
  exit 0
else
  echo "[x] $FAILED vocabulary violation(s) — see above"
  exit 1
fi
```

Lift verbatim, change "frontmatter" → "vocabulary".

**Per-file token-walk (NEW logic — no exact analog, but close to analog `lint_agent` shape lines 40–121):**

```bash
lint_file() {
  local file="$1"
  local rel="${file#"$REPO_ROOT/"}"
  local lineno=0 line token

  # Skip lines below `--- v1.x body below ---` separator (D-13: Phase 4 deprecation
  # banner exception — preserved v1.x bodies are exempt).
  local in_v1_body=0

  # Per-file allowlist (D-13/D-14): parallel arrays for bash 3.2 portability.
  # Pattern → space-separated allowed tokens.
  local allowed=""
  case "$rel" in
    skills/build/SKILL.md|skills/verify/SKILL.md|skills/ship/SKILL.md)
      allowed="task" ;;
  esac

  while IFS= read -r line; do
    lineno=$((lineno + 1))
    case "$line" in
      *"--- v1.x body below ---"*) in_v1_body=1; continue ;;
    esac
    [ "$in_v1_body" -eq 1 ] && continue
    # HTML-comment escape hatch (D-15): <!-- vocab-allowlist: <token> -->
    case "$line" in *"<!-- vocab-allowlist:"*) continue ;; esac
    # Token scan — case-insensitive word boundary
    for token in phase task story PRD cycle milestone; do
      case " $allowed " in *" $token "*) continue ;; esac
      if echo "$line" | grep -iqE "\\b${token}\\b"; then
        report_fail "$rel:$lineno" "$token" "$line"
      fi
    done
    # gsd-* glob (separate because it's a prefix, not a single word)
    if echo "$line" | grep -iqE "\\bgsd-[a-z]"; then
      report_fail "$rel:$lineno" "gsd-*" "$line"
    fi
  done < "$file"
}
```

Mirrors `lint_agent`'s shape: local var declarations at top, per-rule case statements, `report_fail` for each violation. The "skip below v1.x separator" + "HTML-comment escape" + "per-file allowlist" are NEW logic specific to D-13/D-14/D-15, but they slot into the analog's structure cleanly.

**Inline surface-count gate (D-16/D-17 — keep inline if <30 lines):**

Pattern source: `hooks/post-compact.sh` lines 19–20 (the live FS scan):

```bash
# From post-compact.sh — analog for find pattern:
AGENTS_LIST=$(find "$PLUGIN_ROOT/agents" -maxdepth 1 -name '*.md' -not -name '_*' -not -name 'README.md' ...)
```

Apply the surface-audit canonical recipe from `04-04-SURFACE-AUDIT.md` (already documented):

```bash
# Surface-count gate (D-16) — assert exactly 11 user-invocable skills.
# Canonical recipe from 04-04-SURFACE-AUDIT.md § 4. Excludes _shared/ and the 3 v1.x
# deprecated skills (prd, plan-stories, execute) which retain user-invocable: true
# during v2.0 mid-migration but are NOT counted toward the 11-cap.
SURFACE_COUNT=$(find "$REPO_ROOT/commands" "$REPO_ROOT/skills" -name '*.md' -type f \
  -not -path '*/skills/_shared/*' \
  -not -path '*/skills/prd/*' \
  -not -path '*/skills/plan-stories/*' \
  -not -path '*/skills/execute/*' \
  | wc -l | tr -d ' ')
if [ "$SURFACE_COUNT" != "11" ]; then
  echo "[x] surface count = $SURFACE_COUNT (expected 11) — see .planning/phases/04-skill-layer-state-management/04-04-SURFACE-AUDIT.md"
  FAILED=$((FAILED + 1))
fi
```

The `find -not -path` filter pattern matches `post-compact.sh` line 19 style (`-not -name '_*' -not -name 'README.md'`). The `wc -l | tr -d ' '` idiom matches `install.sh` lines 162, 235, 248 (`find ... | wc -l | tr -d ' '`).

---

### `tests/fixtures/branches/{quote,backslash,newline,apostrophe}.json` (4 static fixtures, file-I/O)

**Analog:** `tests/fixtures/hooks/cwd-{quote,backslash,newline,apostrophe}-branch.json` (Phase 1 deliverables, all single-line JSON, all generated by `tests/fixtures/hooks/setup-fixtures.sh`).

**Existing fixture content (analog `cwd-quote-branch.json`, line 1):**

```json
{"cwd":"/var/folders/3n/fk3wlklj0v7dfbcxydk9skz80000gn/T//godmode-hook-fixtures-37395/quote-branch"}
```

**Decision for Phase 5:** Phase 1's fixtures are *generated at test time* by `setup-fixtures.sh` (because they need real on-disk git repos with adversarial branch names). Phase 5's `tests/fixtures/branches/*.json` per CONTEXT D-07 should be **static** files (committed to the repo) that contain the *adversarial JSON payloads themselves*, fed via `cat fixture.json | bash hooks/<hook>.sh` in the bats test.

**Pattern: each file is a one-line minimum hook stdin envelope** (per STACK.md hook contract):

```json
{"cwd":"/tmp/repo","hook_event_name":"PostCompact","trigger":"manual","branch_hint":"feat/\"weird\""}
```

Above is illustrative; concrete shape is the planner's call (CONTEXT § Discretion). Required fields per STACK.md `Hook contract` § "Common stdin envelope": `cwd` (always present); event-specific fields per the event the fixture targets (PostCompact uses `trigger`, SessionStart uses `source`).

**Generator vs static — use static for these 4:**

The Phase 1 generator (`setup-fixtures.sh` lines 22–46) is the analog for any fixture that needs a *live git repo*. For `tests/fixtures/branches/*.json`, the test only needs the JSON string fed to the hook's stdin — no real git operations. Static commit.

**Newline fixture special case (CONTEXT § Specifics):**

> Adversarial-branch JSON fixtures use literal Unicode escape for `\n`. Don't try to embed a literal newline in a JSON value — bats reads the file via `cat`, then pipes to `jq` which handles the escape.

Concrete: `newline.json` should contain the JSON-escape `\n` inside the string value, NOT a literal byte-0x0A. Example: `{"branch":"feat/line\nbreak"}` — when `jq` parses this, the resulting string contains a real newline character. This matches Phase 1's `setup-fixtures.sh` line 51 use of `printf 'feat/line\nbreak'`.

---

### `tests/install.bats` (bats-core test suite, request-response)

**Analog:** **NONE in repo.** No prior bats file exists. The closest skeleton-shaped artifact is `tests/fixtures/hooks/setup-fixtures.sh` (Phase 1, 55 lines) — it shows the `mktemp -d` HOME isolation idiom and per-test setup function pattern used in the same `tests/` directory tree.

**External canonical pattern** (cite STACK.md "Dev-time tooling" → bats-core 1.13.0):

```bash
#!/usr/bin/env bats
# tests/install.bats
# Smoke tests: install → uninstall → reinstall round-trip + adversarial fixtures + settings merge.
# Each test runs in a mktemp -d $HOME — never touches the real ~/.claude/.
# Bash 3.2 portable. bats-core v1.13.0 idioms only (no bats-assert / bats-support deps).
# CI gate (Phase 5). See QUAL-02 + .planning/phases/05-quality-ci-tests-docs-parity/05-CONTEXT.md D-05..D-08.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEMP_HOME="$(mktemp -d)"
  export HOME="$TEMP_HOME"
  mkdir -p "$HOME/.claude"
}

teardown() {
  [ -n "${TEMP_HOME:-}" ] && [ -d "$TEMP_HOME" ] && rm -rf "$TEMP_HOME"
}

@test "install over fresh ~/.claude/" {
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/.claude-godmode-version" ]
  [ -d "$HOME/.claude/rules" ]
}

@test "settings merge preserves user keys" {
  # QUAL-07 / D-30 — regression test
  echo '{"theme":"dark","customKey":"customValue"}' > "$HOME/.claude/settings.json"
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  run jq -r '.customKey' "$HOME/.claude/settings.json"
  [ "$output" = "customValue" ]
  run jq -r '.permissions.allow | length' "$HOME/.claude/settings.json"
  [ "$output" -gt 0 ]
}

@test "hook fixture: branch with quote" {
  run bash -c "cat '$REPO_ROOT/tests/fixtures/branches/quote.json' | bash '$REPO_ROOT/hooks/post-compact.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.' >/dev/null
}
```

**Idiom sources** (no in-repo file; from bats-core README + Phase 1 fixtures):

| Idiom | Source | Notes |
|---|---|---|
| `setup()` / `teardown()` per-test | bats-core builtin | Runs around each `@test`. Use `setup_file`/`teardown_file` for once-per-file. |
| `BATS_TEST_DIRNAME` to find repo root | bats-core builtin | `$(cd "$BATS_TEST_DIRNAME/.." && pwd)` mirrors Phase 1 setup-fixtures.sh line 18: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` |
| `mktemp -d` for HOME | STACK.md "bats-core" row | "Each in `mktemp -d` `$HOME`" — never touch real `~/.claude/` |
| `run <command>` | bats-core builtin | Captures `$status` + `$output`; never `set -e` aborts on failure |
| `[ "$status" -eq 0 ]` assertions | bats-core idiom | Plain bash test; `bats-assert`/`bats-support` deferred per CONTEXT § Deferred |
| `jq -e` for JSON validity | `check-version-drift.sh` line 13, STACK.md "jq patterns" § "Validation in jq" | Same one-shot-assert pattern repurposed in tests |
| HOME isolation per test | `tests/fixtures/hooks/setup-fixtures.sh` lines 17–19 | `mkdir -p "$FIXTURE_BASE"` shows the temp-dir-per-test-run shape |

**The 11 `@test` scenarios from D-05** the planner must enumerate (verbatim from CONTEXT.md):

1. `install over fresh ~/.claude/`
2. `install over ~/.claude/ with hand-edited rules` (per-file diff/skip/replace prompt; non-TTY default = keep)
3. `uninstall on installed plugin`
4. `uninstall refuses on version mismatch (no --force)`
5. `reinstall preserves customizations`
6. `settings merge: top-level keys not in template survive reinstall` (QUAL-07)
7. `hook fixture: branch name contains "` (adversarial)
8. `hook fixture: branch name contains \` (adversarial)
9. `hook fixture: branch name contains \n` (adversarial)
10. `hook fixture: branch name contains '` (adversarial)

Each test reads one fixture from `tests/fixtures/branches/*.json` for tests 7–10, pipes to a hook script, asserts `jq -e '.'` on the output (closes CONCERNS #6 mechanically — same hardening intent as Phase 1 substrate, now exercised in CI).

---

### `.github/workflows/ci.yml` (GitHub Actions workflow, event-driven)

**Analog:** **NONE in repo.** `.github/workflows/` is currently empty. The closest in-repo `.yml` files are `.github/ISSUE_TEMPLATE/feature_request.yml` and `bug_report.yml` — these are issue-form schemas, not workflows; same YAML syntax, different semantic.

**External canonical pattern** (cite STACK.md "Dev-time tooling" → `actions/checkout@v4`, `ludeeus/action-shellcheck@master`):

```yaml
name: CI
on: [push, pull_request]

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ludeeus/action-shellcheck@master

  frontmatter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/check-frontmatter.sh

  version-drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/check-version-drift.sh

  parity:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/check-parity.sh

  vocab:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/check-vocab.sh

  bats:
    strategy:
      matrix:
        os: [macos-latest, ubuntu-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Install bats-core
        run: |
          if [ "$RUNNER_OS" = "macOS" ]; then
            brew install bats-core
          else
            sudo apt-get update && sudo apt-get install -y bats
          fi
      - run: bats tests/install.bats
```

**Constraints from CONTEXT D-01..D-04 (non-negotiable):**

| Constraint | Source | Enforcement |
|---|---|---|
| One job per lint gate | D-01 + QUAL-01 SC #1 | each gate runs independently — fail-isolation |
| `actions/checkout@v4` + `ludeeus/action-shellcheck@master` only | D-02 + STACK.md | NO `setup-node`, `setup-python`, `setup-ruby` |
| Each job invokes the SHIPPED script (`bash scripts/<name>.sh`), not inline | D-03 | local-vs-CI parity: dev runs same script CI runs |
| Order: shellcheck → frontmatter → version-drift → parity → vocab → bats | D-04 | failure-likelihood gradient; reads top-down like a debug session |
| bats matrix: `[macos-latest, ubuntu-latest]` only | D-08 + STACK.md | macOS bash 3.2 floor + Linux primary |
| bats install: native package manager per runner | D-08 | `brew install bats-core` (macOS), `apt-get install -y bats` (Linux). No `npm install -g bats`. |

---

### `README.md` (rewrite, docs/marketing front door)

**Analog:** **SELF (current README.md) — STRUCTURAL REWRITE, NOT EXTEND.**

Current README.md (~500 lines as of file-size metadata: 18511 bytes) was authored for v1.x — references `/prd → /plan-stories → /execute → /ship`, `8 agents 8 skills`, "Pipeline" as a section name, "Standalone Workflows", "Agent Memory" as a section. **All of that is forbidden vocabulary for v2** (D-12 forbids `phase`/`task`/`story`/`PRD` etc.). The rewrite is *to the 9-section skeleton in CONTEXT D-19*, not to extend the v1.x shape.

**Skeleton lift (CONTEXT D-19, locked):**

```markdown
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

**Tagline lift (locked from PROJECT.md, mirrored in `IDEA.md`):**

> Senior engineering team, in a plugin.

**Arrow chain lift (CONTEXT D-20, IDEA.md, CLAUDE.md, locked verbatim):**

```
/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship
```

Plus underneath:

```
+ helpers: /debug  /tdd  /refactor  /explore-repo
```

**Hard cap:** ≤500 lines including blanks (CONTEXT D-19). Inline gate suggestion: `wc -l README.md` step in CI vocab job (planner's call per D-19 — could be inline in the vocab job since it's one line).

**Anti-pattern (re-state from CONTEXT § Anti-patterns):**

- Do NOT duplicate content in README + CHANGELOG + CONTRIBUTING. Link, don't copy (D-21, PITFALLS § ME-04).
- Do NOT copy current README badge block as-is — ensure all v1.x vocabulary (`/prd`, `/plan-stories`, `/execute`, `Pipeline` heading) is removed.

---

### `CHANGELOG.md` (modify — extend existing Unreleased block to dated v2.0.0 entry)

**Analog:** **SELF (current `CHANGELOG.md`).** Already shipped Phase 1; uses Keep-a-Changelog format (verified at file lines 1–7: `# Changelog`, "All notable changes...", "format is based on [Keep a Changelog](...)", "Semantic Versioning"). Phase 5 extends, not rewrites.

**Existing structure (lines 1–8):**

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased] — milestone v2.0.0 in progress
```

**Phase 5 transformation:**

1. Replace `## [Unreleased] — milestone v2.0.0 in progress` with `## [v2.0.0] — 2026-04-DD` (concrete date filled at tag time, per D-23).
2. Add v2.0.0 release-summary paragraph at top of section (one paragraph; covers 5 milestone areas).
3. Reorganize Phase 1–5 sub-blocks under the v2.0.0 heading using `### Added` / `### Changed` / `### Fixed` / `### Removed` / `### Security` (per D-22).
4. Compress v1.x history into a single trailing `## [v1.x.x]` block (per D-24).

**Existing sub-section style to preserve** (lines 14–30 of analog — `### Added`, `### Changed` are already in use):

```markdown
### Added
- `scripts/check-version-drift.sh` — CI guard ...
- `config/quality-gates.txt` — single source ...

### Changed
- `install.sh` — version sourced from `plugin.json` ...
```

This style **already matches Keep-a-Changelog**. The Phase 5 work is consolidating the 5 phases' bullets under the unified v2.0.0 heading and dating it.

---

### `.claude-plugin/plugin.json` (modify — description + keywords polish only)

**Analog:** **SELF.** Phase 1 set canonical `.version` and (per CONTEXT) `.userConfig.model_profile`. Current file (26 lines) shows everything except `userConfig` is already present.

**Current state (lines 1–25):**

```json
{
  "name": "claude-godmode",
  "description": "Production-grade engineering workflow for Claude Code: 8 specialized agents, 8 skills, rules-based configuration, quality gates, and a full feature pipeline. Language-agnostic.",
  "version": "1.6.0",
  "author": { ... },
  "keywords": [
    "workflow", "agents", "skills", "hooks", "pipeline",
    "engineering", "quality-gates", "code-review", "tdd", "refactoring",
    "prd", "claude-code"
  ],
  ...
}
```

**Phase 5 changes (D-25, D-26):**

1. **`description`** — replace v1.x description with locked v2 string (197 chars, under 200-char marketplace cap):
   ```
   "Senior engineering team, in a plugin. One arrow chain (/godmode → /mission → /brief → /plan → /build → /verify → /ship), 11 skills, mechanical quality gates."
   ```
2. **`keywords`** — polish to v2 set (CONTEXT D-25):
   ```json
   ["workflow","agents","skills","hooks","planning","quality-gates","auto-mode","claude-code"]
   ```
   (REMOVES `pipeline`, `engineering`, `code-review`, `tdd`, `refactoring`, `prd` — all v1.x-shaped or duplicative. ADDS `planning`, `auto-mode`. `prd` removal is also vocab discipline.)
3. **`version`** — bump to `2.0.0` at release-tag time. (Phase 5 PR may bump as part of CHANGELOG date stamping; or planner may defer to a final tag-cut commit.)
4. **PRESERVE** all other top-level keys: `name`, `author`, `homepage`, `repository`, `license`, AND any `userConfig.model_profile` written by Phase 1 (D-26 — "Don't strip it; it's not metadata.").

**Anti-pattern:** Do NOT use `Edit` on the file — re-emit via `jq` to preserve key ordering and avoid trailing-newline drift. Or hand-edit very narrowly. Either is fine; no tooling lock-in.

---

### `CONTRIBUTING.md` (light touch — pointer + tag-protection note)

**Analog:** **SELF.** Current file (134 lines) is from v1.x (line 57 reads "File Structure (v1.4)"). Phase 5 is **light touch** (CONTEXT line 226: "pointer from README; tag protection note"); not a full rewrite.

**Two minimal changes (CONTEXT D-29):**

1. **Insert at top** (after H1, before "Contribution Paths"):
   ```markdown
   > For installation and usage, see [README.md](README.md). This file is the
   > developer manual: how to add agents/skills/hooks/rules, run CI locally,
   > and propose changes.
   ```
   (Closes the "no-duplication" rule of D-21 — README is marketing front door, this is dev manual.)

2. **Insert near the end** (under or near `## PR Process`):
   ```markdown
   ### Tag protection (release process)

   `v*` tags trigger marketplace re-indexing. Repository admins enable tag
   protection in GitHub settings (Settings → Tags → New rule → `v*`).
   Non-admin pushes of `v*` tags are rejected at the GitHub-API level. v2.0
   relies on this UI setting; v2.x may add mechanical enforcement.
   ```

**What NOT to touch in CONTRIBUTING.md (Phase 5 scope discipline):**

- Lines 5–46 (Contribution Paths for agents / skills / rules / hooks) — this is Phase 4-shaped already; updating to v2 vocabulary is OUT-OF-SCOPE for Phase 5 per CONTEXT § Out of scope (CONTRIBUTING is internal-docs, vocab gate exempts it). Future cleanup: v2.x.
- Line 57 "File Structure (v1.4)" — stale heading, but inside the file. Same scope reasoning. OK to fix in passing if planner wants, but not required.

---

## Shared Patterns

These patterns apply to MULTIPLE Phase 5 files — pull from the same source per file.

### Shell-script preamble (applies to: `check-parity.sh`, `check-vocab.sh`)

**Source:** `scripts/check-version-drift.sh` lines 1–13 + `scripts/check-frontmatter.sh` lines 1–15.

```bash
#!/usr/bin/env bash
# scripts/<name>.sh
# <one-line purpose>
# CI gate (Phase 5 wires this into GitHub Actions). Exits non-zero on <X> with file:line evidence.
# Bash 3.2 + <tools> only.
# Convention authority: <reference-rule-or-spec>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# <preflight checks>
[ -f "$X" ] || { echo "[x] X not found at $X"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[x] jq required but not installed"; exit 1; }
```

### Color-helper-style messaging (applies to: all Phase 5 scripts)

**Source:** `install.sh` lines 11–18:

```bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }
```

**Apply to:** Both new scripts (`check-parity.sh`, `check-vocab.sh`). The existing `check-version-drift.sh` and `check-frontmatter.sh` use the bracket-prefix idiom (`[i]`, `[+]`, `[!]`, `[x]`) **without** the color helpers — that is the simplest CI-friendly choice (CI logs render colors poorly in some terminals). **Recommendation: Phase 5 scripts mirror `check-version-drift.sh`'s no-color bracket-prefix style** for visual consistency across all four scripts. The color helpers stay in `install.sh` only (interactive UX context).

### Exit-code contract (applies to: all Phase 5 scripts AND `tests/install.bats` per-test exits)

**Source:** STACK.md "Bash 3.2" + `check-frontmatter.sh` lines 140–151.

- **0** = clean (no violations / all tests pass)
- **1** = violations found / test failed
- **never 2+** unless documented (preserve `set -e` semantics for callers)

### `find` pattern for indexable files (applies to: `check-vocab.sh` surface-count gate)

**Source:** `hooks/post-compact.sh` line 19:

```bash
find "$DIR" -maxdepth 1 -name '*.md' -not -name '_*' -not -name 'README.md' ...
```

The `-not -name '_*'` and `-not -name 'README.md'` filters are the project's canonical indexing convention (mirrored in `check-frontmatter.sh` lines 132–135 where `_*` and `README.md` are skipped). Phase 5's surface-count `find` extends with `-not -path '*/skills/<deprecated>/*'` per `04-04-SURFACE-AUDIT.md` § 4.

### `wc -l | tr -d ' '` count idiom (applies to: surface-count gate, any "how many files" check)

**Source:** `install.sh` lines 162, 235, 248 + `check-frontmatter.sh` line 144:

```bash
COUNT=$(find ... | wc -l | tr -d ' ')
```

The `tr -d ' '` is necessary because BSD `wc` (macOS) prepends spaces to its output; `tr -d ' '` normalizes for portability (STACK.md "Bash 3.2 portability" — implicit).

### `jq -e` for one-shot validation assertions (applies to: `tests/install.bats` JSON-validity asserts)

**Source:** STACK.md "jq patterns" § "Validation in `jq` (for CI lint)":

```bash
jq -e '<filter>' file.json >/dev/null || { echo "<failure>"; exit 1; }
```

Use in bats: `echo "$output" | jq -e '.' >/dev/null` to assert hook output is valid JSON.

### Keep-a-Changelog section taxonomy (applies to: `CHANGELOG.md`)

**Source:** existing `CHANGELOG.md` lines 14–28 (already in use):

```markdown
### Added
- ...

### Changed
- ...

### Fixed
- ...

### Removed
- ...

### Security
- ...
```

Already conformant with https://keepachangelog.com/en/1.1.0/. Phase 5 just consolidates Phase 1–5 bullets under the new dated v2.0.0 heading.

---

## No Analog Found

Files with no close match in the repo (planner uses external/canonical pattern instead):

| File | Role | Data Flow | Reason | Canonical Source |
|---|---|---|---|---|
| `.github/workflows/ci.yml` | CI workflow | event-driven | `.github/workflows/` is empty in v1.x and Phases 1–4. First workflow ever. | GitHub Actions docs (https://docs.github.com/en/actions); STACK.md "Dev-time tooling" row for `actions/checkout@v4` + `ludeeus/action-shellcheck@master`; CONTEXT D-01..D-04 + D-08 for shape |
| `tests/install.bats` | bats-core test suite | request-response | No prior `.bats` file in repo. `tests/fixtures/hooks/setup-fixtures.sh` is the closest skeleton (HOME isolation idiom, per-fixture setup function), but it's a fixture-generator, not a test runner. | bats-core v1.13.0 README idioms (https://github.com/bats-core/bats-core); STACK.md "Dev-time tooling" row; CONTEXT D-05..D-08 + D-30 for shape |

For these two files, the planner should:

1. Cite the canonical external pattern in PLAN.md actions (one-line link).
2. Reference the in-repo idioms that DO carry over (HOME isolation from `setup-fixtures.sh` lines 17–19; `jq -e` validation from STACK.md jq patterns; preamble shape from `check-version-drift.sh`).
3. Treat the file body itself as the analog for any future Phase 6+ work — once written, these become the project's canonical CI/test patterns.

---

## Metadata

**Analog search scope:** `scripts/`, `hooks/`, `config/`, `tests/`, `install.sh`, `uninstall.sh`, `.claude-plugin/`, `CHANGELOG.md`, `README.md`, `CONTRIBUTING.md`, `.shellcheckrc`, `.github/`.
**Files scanned:** ~25 (all of `scripts/`, all of `hooks/`, all of `config/`, all of `tests/fixtures/hooks/`, plus root-level docs).
**Pattern extraction date:** 2026-04-28
**Phase context source:** `.planning/phases/05-quality-ci-tests-docs-parity/05-CONTEXT.md` (D-01..D-31 + canonical_refs)

## PATTERN MAPPING COMPLETE
