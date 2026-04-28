---
name: build
description: "Wave-based parallel build: dispatch @executor per item via Agent(run_in_background=true), poll .build/ markers, atomic commit per item with [brief NN.M] token."
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - Task
argument-hint: "[N]"
arguments: [N]
disable-model-invocation: true
---

# /build N

## Connects to

- **Upstream:** /plan N (consumes PLAN.md)
- **Downstream:** /verify N (read-only verification after build), @executor (spawned per item), @code-reviewer (optional, post-build)
- **Reads from:** `.planning/briefs/NN-slug/PLAN.md`, `config/quality-gates.txt`, `git log` (resume detection)
- **Writes to:** `.planning/briefs/NN-slug/.build/{task-NN.M.started,done,failed}`, git commits with `[brief NN.M]` token, `.planning/STATE.md`

## Auto Mode check

Scan the most recent system reminder for the case-insensitive substring "Auto Mode Active".

When detected (per D-10):
- Skip the wave-plan preview confirmation; proceed directly to dispatch.
- Treat user course corrections as normal input.
- Never auto-bypass the per-item atomic commit gate enforced by the PreToolUse hook — `--no-verify` is mechanically blocked.

See `rules/godmode-skills.md` § Auto Mode Detection for the full convention.

---

## How this skill works

For each wave declared in PLAN.md:

1. Check git log for already-completed items (skip on resume — D-44 token grep).
2. Dispatch remaining items in this wave via `Agent(run_in_background=true)` (concurrency cap = 5, hardcoded — D-39).
3. Each subagent prompt enforces marker discipline (touch `.build/task-NN.M.started`, then on success `.done`, on failure `.failed` — CR-08 fallback for the background-stdout race).
4. Orchestrator polls `.build/` every 2s (env-tunable via `GODMODE_POLL_INTERVAL`).
5. On any `.failed` marker: let in-flight items finish, abort starting next wave (D-43).
6. On all `.done` markers for this wave: proceed to next wave.
7. After all waves: update STATE.md, prune `.build/` markers (preserve on failure for debugging).

The marker file system is the ONLY ground truth (CR-08). The Task-tool return JSON cannot be trusted for completion status when subagents run in the background — use the marker files plus the git log.

---

## Step 1: Resolve brief, parse PLAN.md, ensure `.build/` is gitignored

```bash
set -euo pipefail
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/_lib.sh"
source "$ROOT/skills/_shared/init-context.sh"
source "$ROOT/skills/_shared/state.sh"

case "${N:-}" in
  ''|*[!0-9]*) error "Usage: /build N (numeric)." ;;
esac
PADDED=$(printf '%02d' "$N")

CTX=$(godmode_init_context "$PWD")
BRIEF_DIR=$(printf '%s' "$CTX" | jq -r --argjson n "$N" '.briefs[] | select(.n == $n) | .dir' | head -1)
[ -n "$BRIEF_DIR" ] && [ -f "$BRIEF_DIR/PLAN.md" ] \
  || error "PLAN.md not found for brief $N. Run /plan $N first."
SLUG=$(printf '%s' "$BRIEF_DIR" | sed -E 's|.*/[0-9]+-||')
BUILD_DIR="$BRIEF_DIR/.build"
mkdir -p "$BUILD_DIR"

# Idempotent gitignore append for .build/ markers (D-41).
# `*/.build/` matches the marker dirs at any brief depth without leaking other .build/.
if [ -f .planning/.gitignore ]; then
  grep -qxF '*/.build/' .planning/.gitignore || printf '*/.build/\n' >> .planning/.gitignore
else
  printf '*/.build/\n' > .planning/.gitignore
fi
```

Parse PLAN.md to extract wave structure. The contract is that the skill body knows: total waves, items per wave, item IDs in NN.M form. Implementation detail (recommended awk):

```bash
# Emit TSV: wave_num<TAB>task_id<TAB>task_name (one per line)
WAVE_TSV=$(awk '
  /^### Wave [0-9]+/ { match($0, /[0-9]+/); wave = substr($0, RSTART, RLENGTH); next }
  /^#### Task [0-9]+\.[0-9]+/ {
    match($0, /[0-9]+\.[0-9]+/); id = substr($0, RSTART, RLENGTH);
    name = $0; sub(/^#### Task [0-9]+\.[0-9]+[[:space:]—-]*/, "", name);
    print wave "\t" id "\t" name
  }
' "$BRIEF_DIR/PLAN.md")

TOTAL_WAVES=$(printf '%s\n' "$WAVE_TSV" | awk -F'\t' '{print $1}' | sort -u | grep -c .)
```

`tasks_in_wave()` — given a wave number, emit the item IDs:

```bash
tasks_in_wave() {
  printf '%s\n' "$WAVE_TSV" | awk -F'\t' -v w="$1" '$1 == w {print $2}'
}
```

---

## Step 2: Wave dispatch loop

Sequentially across waves; parallel within. The 30-min per-item ceiling matches `@executor`'s `maxTurns` budget.

```bash
INTERVAL="${GODMODE_POLL_INTERVAL:-2}"

for WAVE_NUM in $(seq 1 "$TOTAL_WAVES"); do
  info "Starting Wave $WAVE_NUM..."

  # Filter items: skip already-committed (D-44 resume detection via [brief NN.M] token)
  TASKS_TO_RUN=()
  for TASK_ID in $(tasks_in_wave "$WAVE_NUM"); do
    SUFFIX="${TASK_ID#*.}"
    if git log --oneline --grep="\[brief ${PADDED}\.${SUFFIX}\]" 2>/dev/null | grep -q .; then
      info "Item $PADDED.$SUFFIX already committed — skipping (resume)"
      continue
    fi
    TASKS_TO_RUN+=("$TASK_ID")
  done

  if [ "${#TASKS_TO_RUN[@]}" -eq 0 ]; then
    info "Wave $WAVE_NUM all-resumed — skipping dispatch"
    continue
  fi

  # Concurrency cap = 5 hardcoded (D-39 — OUT-03 deferred for v2.1).
  # @planner should have split waves with >5 parallel items into Xa/Xb already.
  if [ "${#TASKS_TO_RUN[@]}" -gt 5 ]; then
    warn "Wave $WAVE_NUM has ${#TASKS_TO_RUN[@]} items — exceeds cap=5. @planner should have split. Proceeding anyway; behavior may degrade."
  fi

  # Dispatch each item as Agent(run_in_background=true) — see "Per-item subagent prompt" below.
  for TASK_ID in "${TASKS_TO_RUN[@]}"; do
    : # Use the Task tool with run_in_background: true; subagent_type: executor.
      # The Task-tool return reference is informational; marker files are the ground truth.
  done

  # Poll markers (D-40).
  WAVE_SIZE="${#TASKS_TO_RUN[@]}"
  DEADLINE=$(($(date +%s) + 1800))   # 30-min ceiling per wave; per D-40
  FAILED_COUNT=0

  while :; do
    DONE_COUNT=$(find "$BUILD_DIR" -name 'task-*.done' 2>/dev/null | wc -l | tr -d ' ')
    FAILED_COUNT=$(find "$BUILD_DIR" -name 'task-*.failed' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$FAILED_COUNT" -gt 0 ]; then
      warn "Wave $WAVE_NUM: $FAILED_COUNT failure(s). Letting in-flight items finish (D-43)."
      sleep "$INTERVAL"
      break
    fi
    if [ "$DONE_COUNT" -ge "$WAVE_SIZE" ]; then
      info "Wave $WAVE_NUM: all $WAVE_SIZE items done."
      break
    fi
    if [ "$(date +%s)" -gt "$DEADLINE" ]; then
      warn "Wave $WAVE_NUM: deadline (1800s = 30 min) exceeded; some items may be stalled."
      break
    fi
    sleep "$INTERVAL"
  done

  # Inspect failures (D-43): refuse to start next wave; preserve `.build/` for debugging.
  if [ "$FAILED_COUNT" -gt 0 ]; then
    for f in "$BUILD_DIR"/task-*.failed; do
      [ -f "$f" ] && { warn "Failed: $(basename "$f")"; tail -20 "$f"; }
    done
    error "Wave $WAVE_NUM had $FAILED_COUNT failure(s). Refusing to start next wave. Re-run /build $N after fix; completed items will skip via [brief $PADDED.M] git-log grep."
  fi
done
```

---

## Per-item subagent prompt (D-40 marker discipline)

For each item in a wave, spawn `@executor` via the Task tool with `run_in_background: true`. Prompt template:

```
Implement item ${PADDED}.${SUFFIX} from .planning/briefs/${PADDED}-${SLUG}/PLAN.md.

MARKER DISCIPLINE (CR-08 fallback — non-negotiable):
1. AS YOUR FIRST ACTION:
   touch .planning/briefs/${PADDED}-${SLUG}/.build/task-${PADDED}.${SUFFIX}.started
2. ON SUCCESS (after the atomic commit lands):
   touch .planning/briefs/${PADDED}-${SLUG}/.build/task-${PADDED}.${SUFFIX}.done
3. ON FAILURE (any error path):
   write the stderr tail to
   .planning/briefs/${PADDED}-${SLUG}/.build/task-${PADDED}.${SUFFIX}.failed
   and EXIT NON-ZERO.

COMMIT FORMAT (D-38):
  <type>(<scope>): <item-name> [brief ${PADDED}.${SUFFIX}]

Quality gates run on commit (PreToolUse hook):
- --no-verify is BLOCKED — do not attempt to bypass.
- Hardcoded secrets are BLOCKED — use env vars.
- All 6 gates from config/quality-gates.txt must pass.

You have isolation: worktree. The orchestrator owns concurrency
(cap = 5) and the per-wave 30-min deadline.

Read the matching item section in PLAN.md for the specifics: files touched,
verification criterion, numbered steps.
```

---

## Step 3: Update STATE.md

```bash
COMMIT_COUNT=$(git log --oneline --grep="\[brief ${PADDED}\." main..HEAD 2>/dev/null | wc -l | tr -d ' ')
godmode_state_update "$N" "$SLUG" "Ready to verify" "/verify $N" "Build $N: $COMMIT_COUNT commits"
info "Build $N complete: $COMMIT_COUNT commits."
info "Run /verify $N to walk back from BRIEF.md success criteria."
```

---

## Step 4: Prune `.build/` markers (on success only)

On full success: `rm -rf "$BUILD_DIR"`. On any failure: PRESERVE the directory for debugging (D-43 — failed-marker contents are the diagnostic).

---

## Constraints

- Marker-file discipline is the ONLY ground truth (CR-08). Never trust the Task-tool return JSON for completion status of background subagents.
- The PreToolUse hook blocks `git commit --no-verify` — `/build` does not need extra defense; the hook is the safety net.
- Concurrency cap = 5 hardcoded (D-39). Any future config knob is OUT-03 / v2.1.
- Polling interval default 2s, env-tunable via `GODMODE_POLL_INTERVAL` (undocumented in v2.0 per OUT-06).
- Per-wave deadline: 30 min (1800s) hardcoded (D-40, matches `@executor` `maxTurns: 100`).
- Resume detection greps `git log --grep '[brief NN.M]'`. The token is the durable evidence; markers are convenience (T-04-22 mitigation: dual-source).
- Vocabulary: only the v2 user-facing terms. The token "Task NN.M" is the documented exception inside PLAN.md headings (D-35 template constraint) — this skill body parses those headings, so the token unavoidably appears in awk patterns and grep arguments. The CI vocabulary gate allowlists `task` for `skills/build/SKILL.md`. Body prose still uses "item" or "step".
- `--force` does not exist for `/build`; the only way to bypass a failed wave is to fix the failure and re-run (resume skips committed items via the git-log grep).
- All STATE.md mutations go through `godmode_state_update` from `skills/_shared/state.sh`.

---

## See Also

- `rules/godmode-skills.md` — frontmatter convention, Connects-to layout, Auto Mode block.
- `skills/_shared/init-context.sh` — `godmode_init_context` returns the JSON context blob.
- `skills/_shared/state.sh` — `godmode_state_update` is the only sanctioned STATE.md writer.
- `skills/_shared/gitignore-management.md` — idempotent-append idiom for `.build/`.
- `agents/executor.md` — code-touching agent with `isolation: worktree`.
- `agents/code-reviewer.md` — optional post-build review.
- `config/quality-gates.txt` — the 6 gates the PreToolUse hook enforces on commit.
