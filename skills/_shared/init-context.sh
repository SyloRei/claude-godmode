#!/usr/bin/env bash
# skills/_shared/init-context.sh
# Read .planning/* and emit a JSON context blob (schema_version 1, D-12).
# Source from any skill body via:
#   source "$ROOT/skills/_shared/init-context.sh"
#   CTX=$(godmode_init_context "$PWD")
#
# Pure bash 3.2 + jq 1.6+. Never exits non-zero (D-15) — sourcing must not abort
# a calling skill that runs `set -e`. STATE.md awk parser lifted from
# hooks/session-start.sh:60-62. Live FS scan lifted from hooks/post-compact.sh:18-22.
# Divergence from hooks: takes argv ($1 = project root), NOT stdin (D-11).

set -euo pipefail

# godmode_init_context: emit JSON context blob to stdout.
# Args: $1 = project root (default $PWD)
# Stdout: JSON conforming to schema_version 1 (D-12)
# Exit: ALWAYS 0 (D-15) — even on malformed STATE.md, emits JSON with state.exists=false.
#
# The function body is wrapped in a subshell `( ... )` so sourced callers don't
# see local variable leakage and a `cd` inside doesn't change their cwd.
godmode_init_context() {
  (
    set +e  # D-15: never propagate failures up to a caller that runs `set -e`
    local PROJECT_ROOT="${1:-$PWD}"

    # Resolve absolute path; if cd fails, emit a minimal JSON and return 0.
    if ! cd "$PROJECT_ROOT" 2>/dev/null; then
      jq -n --arg root "$PROJECT_ROOT" \
        '{schema_version: 1, project_root: $root, planning: {exists: false}, state: {exists: false}, config: {exists: false}, briefs: [], v1x_pipeline_detected: false}'
      return 0
    fi
    PROJECT_ROOT=$(pwd)

    # ── .planning/ presence detection ────────────────────────────────────
    local P_EXISTS="false"
    [ -d ".planning" ] && P_EXISTS="true"

    # ── STATE.md parsing (awk YAML front-matter, lifted from hooks/session-start.sh:60-62) ──
    local S_EXISTS="false"
    local ACTIVE_BRIEF=""
    local ACTIVE_SLUG=""
    local STATUS=""
    local NEXT_CMD=""
    local LAST_ACTIVITY=""
    local STATE_VERSION=""
    local STATE_ERRORS_JSON="[]"

    if [ -f ".planning/STATE.md" ]; then
      S_EXISTS="true"

      # Try v2 keys first (godmode_state_version, active_brief, active_brief_slug, ...)
      STATE_VERSION=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^godmode_state_version:/ {sub(/^godmode_state_version:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
      ACTIVE_BRIEF=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^active_brief:/ {sub(/^active_brief:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
      ACTIVE_SLUG=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^active_brief_slug:/ {sub(/^active_brief_slug:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
      STATUS=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^status:/ {sub(/^status:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
      NEXT_CMD=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^next_command:/ {sub(/^next_command:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
      LAST_ACTIVITY=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^last_activity:/ {sub(/^last_activity:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)

      # D-18 forward-compat: accept gsd_state_version + GSD-style keys.
      # If the v2 key set is empty, try v1.x equivalents (milestone, stopped_at).
      if [ -z "$STATE_VERSION" ]; then
        STATE_VERSION=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^gsd_state_version:/ {sub(/^gsd_state_version:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
      fi
      if [ -z "$STATUS" ]; then
        STATUS=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^milestone:/ {sub(/^milestone:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
      fi
      if [ -z "$LAST_ACTIVITY" ]; then
        LAST_ACTIVITY=$(awk '/^---$/{c++; if(c==2)exit} c==1 && /^stopped_at:/ {sub(/^stopped_at:[[:space:]]*/,""); print; exit}' .planning/STATE.md 2>/dev/null || true)
      fi

      # Strip YAML quoting on last_activity if present
      LAST_ACTIVITY=$(printf '%s' "$LAST_ACTIVITY" | sed -E 's/^"//; s/"$//')

      # Errors: STATE.md present but ALL fields empty -> unparseable
      if [ -z "$STATE_VERSION" ] && [ -z "$ACTIVE_BRIEF" ] && [ -z "$STATUS" ] && [ -z "$NEXT_CMD" ] && [ -z "$LAST_ACTIVITY" ]; then
        STATE_ERRORS_JSON='["STATE.md present but front matter unparseable"]'
      fi
    fi

    # ── config.json parsing ──────────────────────────────────────────────
    local C_EXISTS="false"
    local MODEL_PROFILE="balanced"
    local AUTO_ADVANCE="false"
    if [ -f ".planning/config.json" ]; then
      C_EXISTS="true"
      MODEL_PROFILE=$(jq -r '.model_profile // "balanced"' .planning/config.json 2>/dev/null || echo "balanced")
      AUTO_ADVANCE=$(jq -r '.auto_advance // false' .planning/config.json 2>/dev/null || echo "false")
    fi

    # ── briefs[] live FS scan (lifted from hooks/post-compact.sh:18-22) ──
    # Single find pass piped to per-row jq -nc; slurped with jq -s for one final array.
    local BRIEFS_JSON="[]"
    if [ -d ".planning/briefs" ]; then
      LC_ALL=C
      BRIEFS_JSON=$(
        find ".planning/briefs" -mindepth 1 -maxdepth 1 -type d \
             -not -name '_*' -not -name '.*' 2>/dev/null \
          | sort \
          | while IFS= read -r dir; do
              [ -n "$dir" ] || continue
              local base n slug has_brief has_plan
              base=$(basename "$dir")
              # Parse "NN-slug" — N may be multi-digit
              n=$(printf '%s' "$base" | sed -E 's/^([0-9]+)-.*$/\1/' 2>/dev/null || echo "")
              slug=$(printf '%s' "$base" | sed -E 's/^[0-9]+-//' 2>/dev/null || echo "")
              has_brief="false"; [ -f "$dir/BRIEF.md" ] && has_brief="true"
              has_plan="false";  [ -f "$dir/PLAN.md" ]  && has_plan="true"
              # Per-row JSON via jq -nc (CR-02 discipline; never heredoc)
              jq -nc \
                --arg n "$n" \
                --arg slug "$slug" \
                --arg dir "$dir" \
                --argjson hb "$has_brief" \
                --argjson hp "$has_plan" \
                '{n: ($n | tonumber? // null), slug: $slug, dir: $dir, has_brief: $hb, has_plan: $hp}'
            done \
          | jq -s '.' 2>/dev/null || echo "[]"
      )
      # Defensive: if pipeline yielded empty, normalize to []
      [ -z "$BRIEFS_JSON" ] && BRIEFS_JSON="[]"
    fi

    # ── v1.x pipeline detection (lifted from hooks/session-start.sh:71-75) ──
    local V1X="false"
    [ -d ".claude-pipeline" ] && V1X="true"

    # ── active_brief_dir: derived from briefs_dir + zero-padded N + slug ──
    local ACTIVE_BRIEF_DIR=""
    if [ -n "$ACTIVE_BRIEF" ] && [ -n "$ACTIVE_SLUG" ]; then
      local padded
      padded=$(printf '%02d' "$ACTIVE_BRIEF" 2>/dev/null || echo "")
      [ -n "$padded" ] && ACTIVE_BRIEF_DIR=".planning/briefs/${padded}-${ACTIVE_SLUG}"
    fi

    # ── Final JSON construction: ONE jq -n invocation (D-13, CR-02) ──
    jq -n \
      --argjson v 1 \
      --arg root "$PROJECT_ROOT" \
      --argjson p_exists "$P_EXISTS" \
      --argjson s_exists "$S_EXISTS" \
      --argjson c_exists "$C_EXISTS" \
      --arg active "$ACTIVE_BRIEF" \
      --arg slug "$ACTIVE_SLUG" \
      --arg active_dir "$ACTIVE_BRIEF_DIR" \
      --arg status "$STATUS" \
      --arg next_cmd "$NEXT_CMD" \
      --arg last_activity "$LAST_ACTIVITY" \
      --arg model_profile "$MODEL_PROFILE" \
      --argjson auto_advance "$AUTO_ADVANCE" \
      --argjson briefs "$BRIEFS_JSON" \
      --argjson v1x "$V1X" \
      --argjson errors "$STATE_ERRORS_JSON" \
      '{
        schema_version: $v,
        project_root: $root,
        planning: (
          if $p_exists then
            {exists: true, config_path: ".planning/config.json", state_path: ".planning/STATE.md", briefs_dir: ".planning/briefs"}
          else
            {exists: false}
          end
        ),
        state: (
          if $s_exists then
            {
              exists: true,
              active_brief: ($active | tonumber? // null),
              active_brief_slug: $slug,
              active_brief_dir: $active_dir,
              status: $status,
              next_command: $next_cmd,
              last_activity: $last_activity,
              errors: $errors
            }
          else
            {exists: false, errors: []}
          end
        ),
        config: (
          if $c_exists then
            {exists: true, model_profile: $model_profile, auto_advance: $auto_advance}
          else
            {exists: false}
          end
        ),
        briefs: $briefs,
        v1x_pipeline_detected: $v1x
      }' 2>/dev/null

    # If jq itself somehow failed, emit a minimal valid blob so callers always get JSON.
    local jq_rc=$?
    if [ "$jq_rc" -ne 0 ]; then
      jq -n --arg root "$PROJECT_ROOT" \
        '{schema_version: 1, project_root: $root, planning: {exists: false}, state: {exists: false, errors: ["jq assembly failed"]}, config: {exists: false}, briefs: [], v1x_pipeline_detected: false}'
    fi
    return 0
  )
}
