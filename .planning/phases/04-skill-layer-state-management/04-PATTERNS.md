# Phase 4: Skill Layer & State Management — Pattern Map

**Mapped:** 2026-04-27
**Files analyzed:** 22 (10 new + 12 modified)
**Analogs found:** 19 strong + 2 partial / 22

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `commands/godmode.md` (rewrite) | command/skill orchestrator | request-response | `commands/godmode.md` (v1.x current) + `hooks/post-compact.sh` (live FS scan) | exact (extends) |
| `skills/mission/SKILL.md` (NEW) | Socratic skill orchestrator | request-response + file write | `skills/prd/SKILL.md` | role-match |
| `skills/brief/SKILL.md` (NEW) | Socratic skill orchestrator | request-response + file write | `skills/prd/SKILL.md` | exact |
| `skills/plan/SKILL.md` (NEW) | skill → agent dispatcher | request-response | `skills/plan-stories/SKILL.md` | exact |
| `skills/build/SKILL.md` (NEW) | wave-based parallel orchestrator | event-driven (file polling) | `skills/execute/SKILL.md` (parallel mode, Step 2/2.5) | role-match |
| `skills/verify/SKILL.md` (NEW) | skill → agent + targeted writer | request-response | `skills/execute/SKILL.md` (Step 3, validate) | partial |
| `skills/ship/SKILL.md` (rewrite) | gate runner + git/PR orchestrator | request-response | `skills/ship/SKILL.md` (v1.x current) | exact (extends) |
| `skills/debug/SKILL.md` (modernize) | helper skill | request-response | `skills/debug/SKILL.md` (v1.x current) | exact (modernize) |
| `skills/tdd/SKILL.md` (modernize) | helper skill | request-response | `skills/tdd/SKILL.md` (v1.x current) | exact (modernize) |
| `skills/refactor/SKILL.md` (modernize) | helper skill | request-response | `skills/refactor/SKILL.md` (v1.x current) | exact (modernize) |
| `skills/explore-repo/SKILL.md` (modernize) | helper skill (read-only) | request-response | `skills/explore-repo/SKILL.md` (v1.x current) | exact (modernize) |
| `skills/prd/SKILL.md` (deprecate banner) | deprecated redirect | one-time-marker | (no analog — new pattern; banner mechanic novel) | new pattern |
| `skills/plan-stories/SKILL.md` (deprecate banner) | deprecated redirect | one-time-marker | (no analog — new pattern) | new pattern |
| `skills/execute/SKILL.md` (deprecate banner) | deprecated redirect | one-time-marker | (no analog — new pattern) | new pattern |
| `skills/_shared/init-context.sh` (NEW) | shell library / read helper | transform (FS → JSON) | `hooks/session-start.sh` (STATE.md awk parser) + `hooks/post-compact.sh` (live FS + jq -n --arg) | exact |
| `skills/_shared/state.sh` (NEW) | shell library / write helper | transform (atomic file replace) | `hooks/session-start.sh` (awk YAML extract) + `install.sh prompt_overwrite` (atomic mv pattern) | role-match |
| `skills/_shared/_lib.sh` (NEW, optional) | shell library / colors + helpers | utility | `install.sh` lines 11-18 (color helpers) + `install.sh prune_backups` (helper style) | exact |
| `rules/godmode-skills.md` (touched) | rules doc | static reference | (existing rule files in `rules/godmode-*.md`) | role-match |
| `templates/.planning/PROJECT.md.tmpl` (NEW) | template artifact | substitution source | `.planning/PROJECT.md` (live dev artifact, shape inspiration) + `.planning-archive-v1/briefs/01-*/BRIEF.md` (v1 shape) | new pattern |
| `templates/.planning/REQUIREMENTS.md.tmpl` (NEW) | template artifact | substitution source | `.planning/REQUIREMENTS.md` (live dev) | new pattern |
| `templates/.planning/ROADMAP.md.tmpl` (NEW) | template artifact | substitution source | `.planning/ROADMAP.md` (live dev) | new pattern |
| `templates/.planning/STATE.md.tmpl` (NEW) | template artifact | substitution source | `.planning/STATE.md` (live dev YAML+md hybrid) | new pattern |
| `templates/.planning/config.json.tmpl` (NEW) | template artifact (JSON) | substitution source | `.planning/config.json` (live dev) | new pattern |
| `templates/.planning/briefs/BRIEF.md.tmpl` (NEW) | template artifact | substitution source | `.planning-archive-v1/briefs/01-*/BRIEF.md` (factual v1 shape) | new pattern |
| `templates/.planning/briefs/PLAN.md.tmpl` (NEW) | template artifact | substitution source | `.planning-archive-v1/briefs/01-*/PLAN.md` + per-phase PLAN.md in `.planning/phases/` | new pattern |

---

## Pattern Assignments

### `skills/_shared/init-context.sh` (shell library, FS → JSON)

**Primary analog:** `hooks/session-start.sh` (STATE.md awk parser, lines 5–98)
**Secondary analog:** `hooks/post-compact.sh` (live FS scan + jq -n --arg, lines 1–101)

**Shebang + safety prologue** (lift from `hooks/session-start.sh:1-12`):
```bash
#!/usr/bin/env bash
# Skill shared helper: read .planning/* and emit a JSON context blob.
# Source from any skill body via:  source "$ROOT/skills/_shared/init-context.sh"
# Pure bash 3.2 + jq 1.6+. Never exits non-zero (D-15).

set -euo pipefail
```

**STATE.md YAML front-matter parsing** (lift VERBATIM from `hooks/session-start.sh:60-62` — Phase 3 idiom, already production-tested):
```bash
# Source: hooks/session-start.sh:60-62 (VERBATIM lift per D-18 + research § "Standard Stack")
STATE_PHASE=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^milestone:/ {sub(/^milestone:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
STATE_STATUS=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^status:/ {sub(/^status:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
```
For v2 keys (`active_brief`, `active_brief_slug`, `next_command`, `last_activity`), use the SAME awk pattern with the matching key name. v1.x compat (D-18): try `godmode_state_version` then fall back to `gsd_state_version`.

**Live FS scan for briefs[]** (lift from `hooks/post-compact.sh:18-22`):
```bash
# Source: hooks/post-compact.sh:18-22 (FOUND-11 substrate, VERIFIED in production)
LC_ALL=C
BRIEFS_RAW=$(find ".planning/briefs" -mindepth 1 -maxdepth 1 -type d \
             -not -name '_*' -not -name '.*' 2>/dev/null | sort)
```
Then build the briefs JSON array via `jq -Rs '. | split("\n") | map(select(length>0))'` per D-14 (single jq invocation).

**JSON output construction** (lift from `hooks/post-compact.sh:99-100` and `hooks/session-start.sh:94-95`):
```bash
# Source: hooks/post-compact.sh:99-100 — jq -n --arg discipline (FOUND-04, CR-02-safe)
jq -n \
  --argjson v 1 \
  --arg root "$PROJECT_ROOT" \
  --argjson planning_exists "$P_EXISTS" \
  --arg state_path ".planning/STATE.md" \
  --arg active "$ACTIVE" \
  --arg slug "$SLUG" \
  --arg status "$STATUS" \
  --arg next_cmd "$NEXT_CMD" \
  --argjson briefs "$BRIEFS_JSON" \
  --argjson v1x "$V1X_DETECTED" \
  '{schema_version: $v, project_root: $root, planning: {exists: $planning_exists, state_path: $state_path}, state: {active_brief: ($active|tonumber? // null), active_brief_slug: $slug, status: $status, next_command: $next_cmd}, briefs: $briefs, v1x_pipeline_detected: $v1x}'
```
**Anti-pattern (NEVER):** heredoc + variable interpolation. CR-02 violation; breaks on quotes/backslashes/newlines.

**Function-wrapper convention** (NEW — no existing analog; design per D-11):
```bash
# Wrap the entire body in a function so sourcing skills don't pollute their env.
# Run real work in a subshell to keep variables from leaking.
godmode_init_context() {
  (
    local PROJECT_ROOT="${1:-$PWD}"
    cd "$PROJECT_ROOT" 2>/dev/null || { jq -n '{schema_version:1, project_root:"."}'; return 0; }
    # ... awk/find/jq above, all inside the subshell ...
  )
}
```

**Stdin tolerance** (lift from `hooks/session-start.sh:8`): `INPUT=$(cat || true)` — only relevant if init-context.sh ever reads stdin (current design takes argv only).

**v1.x `.claude-pipeline/` detection** (lift from `hooks/session-start.sh:71-75`):
```bash
# Source: hooks/session-start.sh:71-75
V1X_DETECTED=false
[ -d ".claude-pipeline" ] && V1X_DETECTED=true
```

**Cwd-from-argv** (NOT cwd-from-stdin like hooks; D-11 takes argv): documented adaptation from `hooks/post-compact.sh:14-15`.

---

### `skills/_shared/state.sh` (shell library, atomic file replace)

**Primary analog:** `hooks/session-start.sh:60-62` (awk YAML extract)
**Secondary analog:** `install.sh prompt_overwrite()` (lines 27-80) — pattern of "extract → present → atomic replace"
**Tertiary analog:** Research § "Pattern 2: STATE.md atomic-replace mutation" (already provides the recipe)

**Function shape** (NEW; recipe locked in research, lift verbatim):
```bash
# Source: research/04-RESEARCH.md § Pattern 2 + D-17
godmode_state_update() {
  local active_brief="$1" active_brief_slug="$2" status="$3" next_cmd="$4" audit_line="$5"
  local state_file=".planning/STATE.md"
  local tmp_file
  tmp_file=$(mktemp -t godmode-state.XXXXXX) || return 1

  # 1. Build new YAML front matter via jq (NEVER heredoc — CR-02)
  local new_fm
  new_fm=$(jq -nr \
    --argjson v 1 \
    --argjson n "$active_brief" \
    --arg slug "$active_brief_slug" \
    --arg s "$status" \
    --arg c "$next_cmd" \
    --arg a "$(date -u +%Y-%m-%dT%H:%M:%SZ) — $audit_line" \
    '"---\ngodmode_state_version: \($v)\nactive_brief: \($n)\nactive_brief_slug: \($slug)\nstatus: \($s)\nnext_command: \($c)\nlast_activity: \"\($a)\"\n---"')

  # 2. Preserve audit log body via awk (skip prior front matter, keep rest)
  local body
  body=$(awk '/^---$/{c++; if(c==2){next} if(c==1){next}} c>=2' "$state_file" 2>/dev/null || echo "")

  # 3. Compose
  printf '%s\n\n%s\n- %s — %s\n' "$new_fm" "$body" "$(date -u +%Y-%m-%d)" "$audit_line" > "$tmp_file"

  # 4. Atomic replace (POSIX rename = atomic on same filesystem)
  mv "$tmp_file" "$state_file"
}
```

**Atomic-mv idiom** (lift from `install.sh` general style): `install.sh` performs `mkdir -p` + copy with backup, never edits in place — same discipline. State.sh's `mv tmp final` mirrors that contract.

**Stdin tolerance + jq -n --arg** — same as init-context.sh.

---

### `skills/_shared/_lib.sh` (optional; color helpers + utilities)

**Primary analog:** `install.sh:10-18` (color codes + info/warn/error)

**Color + status emitters** (lift VERBATIM from `install.sh:10-18`):
```bash
# Source: install.sh:10-18 (already production-shipped; UX consistency with installer per D-55)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }
```

**Slug derivation** (NEW; design recipe — bash 3.2 portable):
```bash
# Bash 3.2 only: tr instead of ${var,,} (which is bash 4+; PITFALLS CR-04)
godmode_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}
```

**Atomic file replace** (factor out from state.sh if `_lib.sh` exists):
```bash
godmode_atomic_replace() {
  local content="$1" target="$2" tmp
  tmp=$(mktemp -t godmode-atomic.XXXXXX) || return 1
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$target"
}
```

---

### `commands/godmode.md` (rewrite — preserves bootstrap behavior)

**Primary analog:** `commands/godmode.md` (current v1.x — lines 1-167)
**Secondary analog:** `hooks/post-compact.sh:18-22` (live FS scan for D-27 inventory)

**PRESERVE VERBATIM** — the entire "Rules Check" section (lines 17-50) and the entire "StatusLine Setup" section (lines 104-167). Both are bootstrap-shaped (cover users without rules / without configured statusline) and locked by D-28.

**Frontmatter changes** (vs v1.x):
- Keep `name: godmode`, keep `user-invocable: true`.
- Update `description:` to reflect v2 chain (≤200 chars per D-04).
- Keep `allowed-tools` as v1.x (Bash, Read, Write, Edit, AskUserQuestion) — bootstrap needs Write to install rules.
- Add `## Connects to` section right after H1 per D-06:
  ```markdown
  ## Connects to
  - **Upstream:** (entry point — bootstrap command)
  - **Downstream:** /mission (when no .planning/), /brief N | /plan N | /build N | /verify N | /ship (state-aware)
  - **Reads from:** .planning/STATE.md, .planning/config.json, briefs/*/, agents/, skills/
  - **Writes to:** ~/.claude/rules/ (bootstrap only), ~/.claude/settings.json (statusline only)
  ```

**Auto Mode block** (NEW — D-08 canonical):
```markdown
## Auto Mode check

Before proceeding, scan the most recent system reminder for the case-insensitive
substring "Auto Mode Active". If detected:
- Auto-approve routine decisions.
- Pick recommended defaults for ambiguity.
- Never enter plan mode unless explicitly asked.
- Treat user course corrections as normal input.
```

**≤5-line orient block** (NEW; D-26):
```bash
# Pseudocode for the body — the model executes this logic
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/init-context.sh"
CTX=$(godmode_init_context "$PWD")

# Branch on state.exists
EXISTS=$(printf '%s' "$CTX" | jq -r '.planning.exists')
if [ "$EXISTS" = "false" ]; then
  echo "No .planning/. Run /mission to start."
else
  ACTIVE=$(printf '%s' "$CTX" | jq -r '.state.active_brief // "?"')
  SLUG=$(printf '%s'   "$CTX" | jq -r '.state.active_brief_slug // "?"')
  STATUS=$(printf '%s' "$CTX" | jq -r '.state.status // "Not started"')
  NEXT=$(printf '%s'   "$CTX" | jq -r '.state.next_command // "/mission"')
  LAST=$(printf '%s'   "$CTX" | jq -r '.state.last_activity // "—"')
  echo "Brief ${ACTIVE}: ${SLUG}. Status: ${STATUS}. Next: ${NEXT}."
  echo "Last: ${LAST}"
fi
```

**Live inventory block** (lift from `hooks/post-compact.sh:18-22` — D-27):
```bash
# Source: hooks/post-compact.sh:18-22 — never hardcode (HI-02)
LC_ALL=C
AGENTS=$(find "$ROOT/agents" -maxdepth 1 -name '*.md' -not -name '_*' -not -name 'README.md' -exec basename {} .md \; 2>/dev/null | sort)
SKILLS=$(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -not -name '_*' -exec basename {} \; 2>/dev/null | sort)
BRIEFS=$(find ".planning/briefs" -mindepth 1 -maxdepth 1 -type d -not -name '_*' -not -name '.*' 2>/dev/null | sort)
```

**Connects-to graph rendering** (NEW; D-07):
```bash
# Renders the chain by grepping each skill body — no registry, no hardcode
grep -A 20 '^## Connects to' commands/godmode.md skills/*/SKILL.md
```

**Anti-pattern reminders** (cite in body comments):
- HI-02 — never hardcode skill/agent list. Always `find`.
- D-04 — never carry literal version (statusline does that).

---

### `skills/mission/SKILL.md` (NEW — Socratic init)

**Primary analog:** `skills/prd/SKILL.md` (Socratic-question structure, lines 13-49)

**Frontmatter** (D-04 convention — derive from `skills/prd/SKILL.md:1-5` shape):
```yaml
---
name: mission
description: "Initialize project planning state: PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, config.json. Idempotent on returning project."
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion]
---
```
**Note:** NO `model:` / `effort:` keys (D-05). NO `argument-hint` / `arguments` (`/mission` takes no N argument).

**Body opens with H1 + Connects to + Auto Mode check** (per D-06, D-08):
```markdown
# Mission

## Connects to
- **Upstream:** /godmode (when state.exists==false)
- **Downstream:** /brief 1 (after init)
- **Reads from:** templates/.planning/*.tmpl
- **Writes to:** .planning/{PROJECT,REQUIREMENTS,ROADMAP,STATE}.md, .planning/config.json

## Auto Mode check
[D-08 canonical block — verbatim]
```

**Socratic questions section** (adapt from `skills/prd/SKILL.md:38-49`):
```markdown
## Step 1: Five questions (one at a time via AskUserQuestion in non-Auto)

1. Project name (kebab-case slug + display title)
2. One-line core value statement
3. Tech stack constraints (free-form)
4. Initial milestone — name + 1-3 sentence goal
5. Initial brief decomposition — 3-5 brief titles
```
**Auto Mode behavior** (D-10): batch all 5 with sensible defaults; never re-prompt; idempotent.

**Idempotency check** (D-31; pattern from `skills/_shared/gitignore-management.md:9-23`):
```bash
# Source: skills/_shared/gitignore-management.md:20-23 (idempotent file-mutation idiom)
if [ -f .planning/PROJECT.md ]; then
  echo "Project already missioned. Run /godmode for status, or rm .planning/PROJECT.md to re-mission."
  exit 0
fi
```

**Template materialization** (NEW pattern — D-21):
```bash
# Substitute via sed -e 's|{{var}}|val|g' (| delimiter — vars may contain /)
TEMPLATES="$ROOT/templates/.planning"
sed -e "s|{{project_name}}|$PROJECT_NAME|g" \
    -e "s|{{core_value}}|$CORE_VALUE|g" \
    "$TEMPLATES/PROJECT.md.tmpl" > .planning/PROJECT.md
```

**State seed via state.sh** (D-30 next-step pointer):
```bash
source "$ROOT/skills/_shared/state.sh"
godmode_state_update 1 "$FIRST_BRIEF_SLUG" "Ready to brief" "/brief 1" "Project missioned"
echo "Run /brief 1 to start the first brief."
```

---

### `skills/brief/SKILL.md` (NEW — Socratic brief)

**Primary analog:** `skills/prd/SKILL.md` (lines 1-100; clarifying-questions shape, output-file pattern)

**Frontmatter** (D-04; parameterized — has `argument-hint` + `arguments`):
```yaml
---
name: brief
description: "Socratic brief authoring: why + what + falsifiable spec → BRIEF.md. Optional @researcher and @spec-reviewer."
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, Task]
argument-hint: "[N]"
arguments: [N]
---
```

**Body shape** — model on `skills/prd/SKILL.md:11-110` but with v2 vocabulary:
- "## Connects to" + "## Auto Mode check" (top of body — D-06, D-08).
- "## The Job" section (mirror `skills/prd/SKILL.md:13-26`): list of numbered steps.
- Socratic questions section: title (slug derived) → why → what → spec.
- "## Spec verifiability rules" — adapt from `skills/plan-stories/SKILL.md:127-134` ("Acceptance Criteria: Must Be Verifiable") — falsifiable, CLI-checkable.
- Optional `@researcher` / `@spec-reviewer` spawn via Task tool — see "Agent Routing" pattern in `skills/prd/SKILL.md:135-142`.

**Slug derivation** (D-22, D-32 — use `_lib.sh` helper):
```bash
SLUG=$(godmode_slug "$BRIEF_TITLE")
PADDED=$(printf '%02d' "$N")
BRIEF_DIR=".planning/briefs/${PADDED}-${SLUG}"
mkdir -p "$BRIEF_DIR"
```

**Output via template + sed** — see `/mission` template materialization pattern above.

**State update** (D-33):
```bash
source "$ROOT/skills/_shared/state.sh"
godmode_state_update "$N" "$SLUG" "Ready to plan" "/plan $N" "Brief $N drafted"
```

---

### `skills/plan/SKILL.md` (NEW — agent dispatcher)

**Primary analog:** `skills/plan-stories/SKILL.md` (already orchestrates a structured-output transform)
**Secondary analog:** `skills/execute/SKILL.md:62-77` (Task spawn shape with prompt context)

**Frontmatter** (D-04):
```yaml
---
name: plan
description: "Read BRIEF.md, spawn @planner, write PLAN.md with waves + verification status."
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Task]
argument-hint: "[N]"
arguments: [N]
---
```

**Spawn @planner via Task** (lift shape from `skills/execute/SKILL.md:62-77`):
```markdown
Spawn `@planner` agent with context:

```
Read .planning/briefs/NN-slug/BRIEF.md and produce PLAN.md following the
template at templates/.planning/briefs/PLAN.md.tmpl.

Wave heuristic: tasks touching disjoint file sets with no logical dependency
are eligible for the same wave. Concurrency cap = 5 (D-39); split larger waves
as Xa/Xb.

Each task must include:
- Task name and number (NN.M)
- Files touched
- Verification criterion (CLI-checkable)
- Steps (numbered)
```
```

**State update** (D-37): `godmode_state_update "$N" "$SLUG" "Ready to build" "/build $N" "Plan $N drafted"`.

---

### `skills/build/SKILL.md` (NEW — most complex; wave-based parallel)

**Primary analog:** `skills/execute/SKILL.md` (parallel mode — Step 2 lines 79-99, Step 2.5 lines 102-110, Step 5 lines 189-209)
**Secondary analog:** Research § "Pattern 4: Agent(run_in_background=true) with file-polling fallback"

**Frontmatter** (D-04, D-07; side-effecting → `disable-model-invocation: true`):
```yaml
---
name: build
description: "Wave-based parallel execution: dispatch @executor per task via Agent(run_in_background=true), poll .build/ markers, atomic commit per task."
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Task]
argument-hint: "[N]"
arguments: [N]
disable-model-invocation: true
---
```

**Parallel agent spawn** (lift shape from `skills/execute/SKILL.md:79-99`, adapt to `Agent(run_in_background=true)` and marker-file contract):
```markdown
For each task in current wave, spawn @executor via Task tool with run_in_background=true:

Prompt template:
```
Implement task NN.M from .planning/briefs/NN-slug/PLAN.md.

Marker discipline (CR-08 fallback):
1. On entry: touch .planning/briefs/NN-slug/.build/task-NN.M.started
2. On success: touch .planning/briefs/NN-slug/.build/task-NN.M.done
3. On failure: write stderr tail to .planning/briefs/NN-slug/.build/task-NN.M.failed and exit non-zero

Commit format (D-38): <type>(<scope>): <task-name> [brief NN.M]

Quality gates run on commit (Phase 3 PreToolUse hook). --no-verify is BLOCKED.
```
```

**Polling loop** (NEW recipe — research § Pattern 4):
```bash
# Source: research § Pattern 4 + D-40 + CR-08
WAVE_DIR=".planning/briefs/${PADDED}-${SLUG}/.build"
mkdir -p "$WAVE_DIR"

INTERVAL="${GODMODE_POLL_INTERVAL:-2}"
DEADLINE=$(($(date +%s) + 1800))  # 30 min/task ceiling
WAVE_SIZE="$1"  # number of tasks dispatched in this wave
while :; do
  done_count=$(find "$WAVE_DIR" -name '*.done' 2>/dev/null | wc -l | tr -d ' ')
  failed_count=$(find "$WAVE_DIR" -name '*.failed' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$failed_count" -gt 0 ]; then break; fi      # D-43: let in-flight finish
  if [ "$done_count" -ge "$WAVE_SIZE" ]; then break; fi
  if [ "$(date +%s)" -gt "$DEADLINE" ]; then break; fi
  sleep "$INTERVAL"
done
```

**Resume detection** (D-44 — grep git log for `[brief NN.M]` token):
```bash
# Skip already-committed tasks on resume
if git log --oneline --grep="\[brief ${PADDED}\.${M}\]" | grep -q .; then
  echo "Task ${PADDED}.${M} already committed — skipping"
  continue
fi
```

**Concurrency cap** (D-39 — hardcoded 5; reuse `skills/execute/SKILL.md` Step 1 batch-cap pattern at lines 36-42).

**Failure handling** (lift shape from `skills/execute/SKILL.md:243-256` — Parallel-Mode Failures table; adapt to v2 vocab: brief/wave/task instead of story/batch).

**.build/ gitignore** (D-41 — pattern from `skills/_shared/gitignore-management.md:25-34`):
```bash
# Source: skills/_shared/gitignore-management.md:25-34 — idempotent append
grep -qxF '*/.build/' .planning/.gitignore 2>/dev/null || \
  printf '*/.build/\n' >> .planning/.gitignore
```

**State update** (D-45).

---

### `skills/verify/SKILL.md` (NEW — read-only agent + targeted writer)

**Primary analog:** `skills/execute/SKILL.md` Step 3 (lines 113-134) — review pattern
**Secondary analog:** `agents/planner.md` frontmatter (lines 1-9) — `disallowedTools: Write, Edit` discipline

**Frontmatter** — narrow Write capability per D-47:
```yaml
---
name: verify
description: "Spawn @verifier (read-only); orchestrator mutates PLAN.md verification section in place."
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Task]
argument-hint: "[N]"
arguments: [N]
---
```
**Note:** Write is allowed at the SKILL level so the orchestrator (skill body) can patch PLAN.md; @verifier itself is `disallowedTools: Write, Edit` per its own frontmatter (Phase 2 D-15).

**Spawn @verifier with structured-report contract** (lift shape from `skills/execute/SKILL.md:117-127`):
```markdown
Spawn @verifier with prompt:
```
Verify .planning/briefs/NN-slug/BRIEF.md success criteria + PLAN.md task verifications
against working tree state.

Return a structured markdown report with COVERED / PARTIAL / MISSING per criterion + per task.
DO NOT write to PLAN.md — orchestrator owns the mutation.
```
```

**Orchestrator-driven PLAN.md mutation** (NEW; D-47 — narrow scope to PLAN.md only):
```bash
# Patch the "Verification status" section in place via awk + atomic replace
# (same atomic-mv discipline as state.sh)
PLAN=".planning/briefs/${PADDED}-${SLUG}/PLAN.md"
TMP=$(mktemp -t godmode-plan.XXXXXX) || exit 1
awk -v rep="$NEW_VERIF_SECTION" '
  /^## Verification status/ { in=1; print; print rep; next }
  /^## / && in { in=0 }
  !in { print }
' "$PLAN" > "$TMP"
mv "$TMP" "$PLAN"
```

**State update** (D-48): COVERED-all → `next_command=/ship`; else → `next_command=/build N`.

---

### `skills/ship/SKILL.md` (rewrite — preserve structure, swap vocabulary + gates source)

**Primary analog:** `skills/ship/SKILL.md` (current v1.x — preserve structure of Steps 1-5, swap pipeline-context for STATE.md + brief vocab)

**PRESERVE STRUCTURE** — Steps 1-5 (Quality Gates / Requirements / Security / Git Cleanup / Push & PR) at lines 23-103. The shape is sound.

**REPLACE the gates source** (D-49 — read from `config/quality-gates.txt`, not hardcoded):
```bash
# Source: config/quality-gates.txt (6 lines). Bash 3.2 portable read (no mapfile).
GATES_FILE="$ROOT/config/quality-gates.txt"
while IFS= read -r gate || [ -n "$gate" ]; do
  echo "Running gate: $gate"
  # ... auto-detect command for this gate, run it, capture exit code ...
done < "$GATES_FILE"
```

**REPLACE pipeline-context** (lines 122-156) with STATE.md + PLAN.md verification check (D-49):
```bash
source "$ROOT/skills/_shared/init-context.sh"
CTX=$(godmode_init_context "$PWD")
STATUS=$(printf '%s' "$CTX" | jq -r '.state.status')
[ "$STATUS" = "Ready to ship" ] || error "Status is '$STATUS'. Run /verify N first."

# Check PLAN.md for non-COVERED lines
if grep -E '^- \[ \].*\*\*(SC|Task)' "$PLAN" | grep -vqE 'COVERED'; then
  [ "$FORCE" = "1" ] || error "PARTIAL/MISSING criteria in PLAN.md. Re-run /verify or pass --force."
fi
```

**`gh pr create`** — preserve verbatim from `skills/ship/SKILL.md:91-103` (heredoc body is fine here — no JSON, no untrusted interpolation).

**Frontmatter** (D-04; side-effecting → `disable-model-invocation: true`):
```yaml
---
name: ship
description: "Run 6 quality gates from config/quality-gates.txt, push, gh pr create. --force bypasses PARTIAL refusal only."
user-invocable: true
allowed-tools: [Read, Bash, Grep, Glob, Task]
disable-model-invocation: true
---
```

**State update** (D-51): `status=Shipped {pr_url}`.

---

### `skills/{debug,tdd,refactor,explore-repo}/SKILL.md` (modernize)

**Primary analog:** the SAME file (current v1.x — bodies preserved per D-53)

**Modernization checklist** (per D-52):
1. Frontmatter: scope `allowed-tools` (no wildcards). Example for `/refactor`:
   ```yaml
   allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
   ```
2. Add `## Connects to` section right after H1 (D-06):
   ```markdown
   ## Connects to
   - **Upstream:** (entry point — cross-cutting helper)
   - **Downstream:** @architect (refactor) | @test-writer (tdd) | freeform (debug, explore-repo)
   - **Reads from:** working tree
   - **Writes to:** working tree (refactor, tdd, debug) | none (explore-repo)
   ```
3. Add `## Auto Mode check` block (D-09; SHOULD include for helpers).
4. Strip pipeline-context blocks (lines like 122-156 in `skills/refactor/SKILL.md`) — replace with init-context.sh source if state-aware behavior needed.
5. Vocab gate: remove any `phase`, `task`, `story`, `PRD`, `gsd-*`, `cycle`, `milestone` literals from user-facing prose (rules/agents docs are exempt).
6. `argument-hint` if parameterized — none of the 4 helpers are parameterized in v2.0; omit.

**Body content stays semantically identical** (D-53) — the 4-phase debug protocol, 5-step refactor process, etc., are preserved.

---

### `skills/{prd,plan-stories,execute}/SKILL.md` (deprecation banner)

**No direct codebase analog** — D-23/D-24 banner mechanic is novel. Reference `~/.claude/.claude-godmode-v1-banner-shown` marker file pattern; closest existing analog is `install.sh` install-marker style.

**Banner block prepended** (D-23 — verbatim from CONTEXT.md):
```markdown
---
name: prd
description: "[Deprecated v2.0] Renamed to /brief N. See migration note below. Old behavior preserved for v1.x users mid-migration."
user-invocable: true
---

# ⚠ Deprecated — use `/brief N` instead

This command was renamed in v2.0:

| v1.x | v2.0 |
|---|---|
| `/prd` | `/brief N` |
| `/plan-stories` | `/plan N` |
| `/execute` | `/build N` |

The old body still works for projects on the v1.x layout (`.claude-pipeline/`).
Run `/mission` to migrate to the v2 layout (`.planning/`).

Banner shown once per install — re-display: `rm ~/.claude/.claude-godmode-v1-banner-shown`.

--- v1.x body below ---

[original v1.x content preserved verbatim]
```

**Marker check** (D-24 — pattern lifted from `skills/_shared/gitignore-management.md` idempotent-check style):
```bash
# Source: skills/_shared/gitignore-management.md:20-23 (idempotent check idiom)
MARKER="$HOME/.claude/.claude-godmode-v1-banner-shown"
if [ ! -f "$MARKER" ]; then
  cat <<'BANNER'
[deprecation banner text]
BANNER
  touch "$MARKER"
fi
```
**Note:** Marker lives at `$HOME/.claude/`, NOT `${CLAUDE_PLUGIN_DATA}` — the marker is genuinely user-scoped (must persist across plugin reinstalls but is not plugin-config; D-24 explanation).

---

### `templates/.planning/*.tmpl` (NEW — no direct analog)

**No codebase analog.** Reference inspiration:
- `.planning/PROJECT.md` (live dev artifact — current shape we use under GSD).
- `.planning-archive-v1/briefs/01-foundation-and-safety-hardening/BRIEF.md` (factual v1.x BRIEF shape — for `briefs/BRIEF.md.tmpl`).
- `.planning-archive-v1/briefs/01-foundation-and-safety-hardening/PLAN.md` (factual v1.x PLAN shape — for `briefs/PLAN.md.tmpl`).
- `.planning/STATE.md` (live YAML+md hybrid — exact shape for `STATE.md.tmpl` per D-16).

**Substitution syntax** (D-20 — locked):
- `{{variable}}` mustache-style placeholders.
- Replaced via `sed -e 's|{{var}}|val|g'` (use `|` delimiter — variables may contain `/`).
- Variables documented at top of each template as a comment block, e.g.:
  ```markdown
  <!-- Variables:
  {{project_name}}    — kebab-case slug
  {{display_title}}   — Title Case display name
  {{core_value}}      — one-line core value statement
  -->
  ```

**`STATE.md.tmpl` shape** (D-16 — verbatim spec):
```markdown
---
godmode_state_version: 1
active_brief: {{active_brief}}
active_brief_slug: {{active_brief_slug}}
status: {{status}}
next_command: {{next_command}}
last_activity: "{{last_activity}}"
---

# Audit Log

- {{date}} — Project missioned via `/mission`.
```

**`briefs/PLAN.md.tmpl` shape** (D-35 — verbatim from CONTEXT.md spec):
```markdown
# Plan: {{brief_title}}

## Waves

### Wave 1 (parallel-safe)

#### Task 1.1 — {{task_name}}
**Verification:** {{verification}}
**Files touched:** {{files}}
**Steps:**
 1. ...

## Verification status
- [ ] **Task 1.1** — STATUS (set by /verify)

## Brief success criteria
- [ ] **SC-1** — STATUS (set by /verify)
```

---

### `rules/godmode-skills.md` (touched)

**Primary analog:** existing `rules/godmode-*.md` files (style + structure).

**Sections to add** (D-02, D-08, D-09):
- Reserved-slot doctrine (D-02): "Slot 12 is reserved. Adding a 12th skill is a v2.x decision requiring an explicit RFC; the cap exists to keep the surface scannable."
- Auto Mode detection canonical block (D-08).
- Frontmatter convention reference (D-04, D-05).

---

## Shared Patterns

### Pattern: `set -euo pipefail` + stdin tolerance

**Source:** `hooks/session-start.sh:5-8`, `hooks/post-compact.sh:6-8`
**Apply to:** `skills/_shared/init-context.sh`, `skills/_shared/state.sh`, `skills/_shared/_lib.sh`

```bash
set -euo pipefail
INPUT=$(cat || true)  # stdin tolerance under set -e (FOUND-05)
```

---

### Pattern: jq -n --arg JSON construction (CR-02 discipline)

**Source:** `hooks/post-compact.sh:99-100`, `hooks/session-start.sh:94-95`, `hooks/pre-tool-use.sh:21-23`, `hooks/post-tool-use.sh:32-33`
**Apply to:** every JSON emission in `init-context.sh`, `state.sh`, and any skill body that emits JSON

```bash
# CORRECT — variables interpolated by jq, never by shell
jq -n --arg key "$VAL" --argjson n "$NUM" '{key: $key, n: $n}'
```

**NEVER (CR-02 violation):** heredoc + variable interpolation:
```bash
# WRONG — breaks on quotes/backslashes/newlines in $VAL
cat <<EOF
{"key": "$VAL"}
EOF
```

---

### Pattern: STATE.md awk YAML extract

**Source:** `hooks/session-start.sh:60-62` (lifted into both `init-context.sh` for reads and `state.sh` for round-trip preservation)
**Apply to:** all skills via `init-context.sh` (read) and `state.sh` (write)

```bash
KEY=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^KEY:/ {sub(/^KEY:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
```

**v1.x compat** (D-18): try v2 key first, fall back to v1 key:
```bash
VER=$(awk '...c==1 && /^godmode_state_version:/...' || true)
[ -z "$VER" ] && VER=$(awk '...c==1 && /^gsd_state_version:/...' || true)
```

---

### Pattern: Live FS scan (FOUND-11; never hardcode lists)

**Source:** `hooks/post-compact.sh:18-22`
**Apply to:** `commands/godmode.md` (D-27 inventory), `skills/_shared/init-context.sh` (briefs[] enumeration)

```bash
LC_ALL=C  # deterministic ordering across macOS / Linux
find "$DIR" -mindepth 1 -maxdepth 1 -type d -not -name '_*' -not -name '.*' 2>/dev/null | sort
```

**Anti-pattern (HI-02):** hardcoded list of skills/agents/briefs anywhere in `commands/godmode.md` or `skills/*/SKILL.md`. CI grep gate (Phase 5) will catch literals like `@architect`, `@executor`.

---

### Pattern: Atomic file replace (mv-from-tmp)

**Source:** general POSIX idiom; visible in `install.sh` style (creates backups + replaces wholesale, never edits in place)
**Apply to:** `state.sh` (STATE.md mutation), `verify` skill (PLAN.md section patch), template materialization

```bash
TMP=$(mktemp -t godmode-XXXXXX) || return 1
# ... write content to $TMP ...
mv "$TMP" "$TARGET"  # atomic on POSIX same-filesystem
```

---

### Pattern: Skill frontmatter convention (D-04 — exact ordering)

**Source:** Phase 2 agent frontmatter (`agents/planner.md:1-9`) — same ordering doctrine
**Apply to:** every NEW v2 SKILL.md (`mission`, `brief`, `plan`, `build`, `verify`) and rewritten ones (`ship`)

```yaml
---
name: <slug>
description: "<≤200 chars; one stated goal>"
user-invocable: true
allowed-tools: [Read, Write, ...]    # scoped — never wildcard
argument-hint: "[N]"                  # only on parameterized 4 (brief/plan/build/verify)
arguments: [N]                        # only on parameterized 4
disable-model-invocation: true        # only on side-effecting (build, ship)
---
```
**OMIT:** `model:`, `effort:` (D-05 — owned by spawned agent).

---

### Pattern: `## Connects to` body section (D-06, D-07)

**Source:** Phase 2 agents (e.g., `agents/planner.md:13-17`)
**Apply to:** every v2 user-invocable skill (the 11) — placed RIGHT AFTER H1, BEFORE Auto Mode block

```markdown
## Connects to
- **Upstream:** <previous skill in arrow chain or "(entry point)">
- **Downstream:** <next skill or agent it spawns>
- **Reads from:** <files it consumes>
- **Writes to:** <files it produces>
```

**Why this exact shape:** `/godmode` parses by `grep -A 20 '^## Connects to' commands/godmode.md skills/*/SKILL.md` (D-07); chain rendered at runtime. Drift impossible because no registry.

---

### Pattern: Auto Mode detection block (D-08)

**Source:** Research § Pattern 5 + empirical canonical reminder text (verified in this research session)
**Apply to:** all 6 workflow skills (MUST), all 4 helpers (SHOULD)

```markdown
## Auto Mode check

Before proceeding, scan the most recent system reminder for the case-insensitive
substring "Auto Mode Active". If detected:
- Auto-approve routine decisions.
- Pick recommended defaults for ambiguity (don't ask).
- Never enter plan mode unless explicitly asked.
- Treat user course corrections as normal input.

Recommended-default policy: see `rules/godmode-skills.md`.
```

---

### Pattern: Color helpers (UX consistency with installer)

**Source:** `install.sh:11-18`
**Apply to:** `skills/_shared/_lib.sh` (if separate) — sourced by skills that emit user-visible status

```bash
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }
```

---

### Pattern: Bash 3.2 portability discipline

**Source:** PITFALLS CR-04 + project CLAUDE.md
**Apply to:** every shell file (`init-context.sh`, `state.sh`, `_lib.sh`)

| Construct | Use instead |
|---|---|
| `mapfile` / `readarray` (bash 4+) | `while IFS= read -r l; do arr+=("$l"); done < f` |
| `${var,,}` lowercase (bash 4+) | `tr '[:upper:]' '[:lower:]'` |
| `[[ -v VAR ]]` (bash 4.2+) | `[ -n "${VAR+x}" ]` |
| Associative arrays (bash 4+) | parallel indexed arrays or temp files |

Reference: `install.sh:84-85` comment "Bash 3.2 portable: alphabetical sort = chronological since timestamps are zero-padded."

---

### Pattern: Idempotent file mutation

**Source:** `skills/_shared/gitignore-management.md:8-34`
**Apply to:** `/mission` (D-31 idempotent re-run), `/build` `.build/` gitignore append (D-41), v1.x banner marker check (D-24)

```bash
# Already-present check before append
grep -qxF '<line>' <file> || printf '<line>\n' >> <file>
```

---

## No Analog Found

Files with NO close codebase match — planner should reference RESEARCH.md patterns and CONTEXT.md decisions:

| File | Role | Reason |
|------|------|--------|
| `templates/.planning/PROJECT.md.tmpl` | template | No `templates/` exists yet. Inspiration: live `.planning/PROJECT.md`. |
| `templates/.planning/REQUIREMENTS.md.tmpl` | template | Same — no analog; inspiration `.planning/REQUIREMENTS.md`. |
| `templates/.planning/ROADMAP.md.tmpl` | template | Same — inspiration `.planning/ROADMAP.md`. |
| `templates/.planning/STATE.md.tmpl` | template | Shape locked in D-16 (YAML+md hybrid); inspiration `.planning/STATE.md`. |
| `templates/.planning/config.json.tmpl` | template (JSON) | Inspiration `.planning/config.json`; substitution still uses `{{var}}` per D-20. |
| `templates/.planning/briefs/BRIEF.md.tmpl` | template | Inspiration `.planning-archive-v1/briefs/01-*/BRIEF.md` (factual v1.x shape). |
| `templates/.planning/briefs/PLAN.md.tmpl` | template | Inspiration `.planning-archive-v1/briefs/01-*/PLAN.md` + D-35 verbatim spec. |
| `skills/{prd,plan-stories,execute}/SKILL.md` deprecation banner mechanic | one-time-marker prepend | Novel pattern; closest analog is `install.sh` install-marker style. Recipe locked in D-24. |

For all `templates/.planning/*.tmpl` files: substitution syntax is `{{variable}}` (mustache), replaced via `sed -e 's|{{var}}|val|g'` (D-20). Variables documented at top of each template as a comment block.

---

## Metadata

**Analog search scope:** `commands/`, `skills/`, `hooks/`, `scripts/`, `config/`, `install.sh`, `agents/planner.md`, `.planning/`, `.planning-archive-v1/briefs/01-*/`
**Files scanned:** ~25 files read in full or in extract; 22 phase targets classified
**Pattern extraction date:** 2026-04-27
**Key inheritances:**
- All shell helpers inherit Phase 1/3 hook discipline (`set -euo pipefail`, `cat || true`, `jq -n --arg`, `awk` YAML parsing).
- All v2 skill frontmatter inherits Phase 2 agent ordering convention (D-04 mirrors AGENT-01 for skills).
- `commands/godmode.md` PRESERVES bootstrap (rules check + statusline) — only adds the orient layer + Connects-to block.
- `skills/ship/SKILL.md` PRESERVES Steps 1-5 structure — swaps gates source to `config/quality-gates.txt` and pipeline-context to STATE.md.
- Helper skills (`debug`, `tdd`, `refactor`, `explore-repo`) PRESERVE bodies semantically — only add Connects-to + Auto Mode + scoped allowed-tools.
