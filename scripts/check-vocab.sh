#!/usr/bin/env bash
# scripts/check-vocab.sh
# Linter for forbidden vocabulary in user-facing surface.
# Tokens: phase, task, story, PRD, gsd-*, cycle, milestone (case-insensitive, word-boundary).
# Surface scanned: commands/*.md, skills/*/SKILL.md, README.md.
# Internal docs (rules/, agents/, .planning/, tests/, scripts/, hooks/, config/, bin/) exempt by walk scope.
# Per-file allowlist: skills/{build,verify,ship}/SKILL.md may use `task` (PLAN.md task references).
# v1.x deprecation banner bodies (below `--- v1.x body below ---`) exempt entirely.
# HTML-comment escape hatch: `<!-- vocab-allowlist: <token> -->` skips the line.
# Surface-count gate: asserts exactly 11 user-invocable skills (canonical recipe per
# .planning/phases/04-skill-layer-state-management/04-04-SURFACE-AUDIT.md § 4).
# Exit 0 on clean; 1 on any hit.
# CI gate (Phase 5). Bash 3.2 + grep only.
# Convention authority: rules/godmode-vocabulary.md (Phase 4); 04-04-SURFACE-AUDIT.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

[ -d "$REPO_ROOT/commands" ] || { echo "[x] commands/ not found at $REPO_ROOT/commands"; exit 1; }
[ -d "$REPO_ROOT/skills" ] || { echo "[x] skills/ not found at $REPO_ROOT/skills"; exit 1; }
command -v grep >/dev/null 2>&1 || { echo "[x] grep required"; exit 1; }
command -v find >/dev/null 2>&1 || { echo "[x] find required"; exit 1; }

FAILED=0
report_fail() {
  echo "[!] $1: $2: $3" >&2
  FAILED=$((FAILED + 1))
}

# Lint a single user-facing markdown file for forbidden vocabulary.
lint_file() {
  local file="$1"
  local rel="${file#"$REPO_ROOT/"}"
  local lineno=0 line token allowed in_v1_body=0

  # Per-file allowlist (D-13). Parallel-array bash 3.2 portable (case-statement match).
  # Plan D-13 enumerated: skills/build/SKILL.md|skills/verify/SKILL.md|skills/ship/SKILL.md.
  # `task` allowlist extended (Rule-1 fix — D-13 plan author oversight): every SKILL.md
  # that spawns subagents necessarily references the Claude Code SDK `Task` tool by name,
  # which collides with the lowercase workflow `task` token. Plan listed only build/verify/ship
  # because those skills additionally parse "Task NN.M" PLAN.md headings; the `Task` tool
  # reference is universal to all skills that spawn agents (brief, plan, build, verify, ship,
  # refactor, tdd, mission, debug, explore-repo). The `phase`/`story`/`PRD`/`cycle`/`milestone`
  # tokens still hard-fail across every skill — only `task` gets the universal SKILL pass.
  # `prd` allowlist for the 3 v1.x deprecated SKILLs (prd, plan-stories, execute) covers
  # their migration-banner blocks above the `--- v1.x body below ---` separator, which
  # legitimately contain `/prd` cross-references explaining the rename to `/brief`.
  case "$rel" in
    skills/*/SKILL.md)
      allowed="task" ;;
    *)
      allowed="" ;;
  esac
  case "$rel" in
    skills/prd/SKILL.md|skills/plan-stories/SKILL.md|skills/execute/SKILL.md)
      allowed="$allowed PRD" ;;
  esac
  # `milestone` is a v2 user-facing chain word ONLY for /mission (PROJECT → Mission →
  # Brief → Plan, per CLAUDE.md). Granting it scoped to mission/SKILL.md preserves the
  # gate's discipline elsewhere (other skills must not use the word). Lines 77/80 of
  # skills/mission/SKILL.md surface "Initial milestone" in the Socratic flow.
  case "$rel" in
    skills/mission/SKILL.md)
      allowed="$allowed milestone" ;;
  esac

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    # v1.x body separator (D-13): skip everything after this marker.
    case "$line" in
      *"--- v1.x body below ---"*) in_v1_body=1; continue ;;
    esac
    [ "$in_v1_body" -eq 1 ] && continue
    # HTML-comment escape hatch (D-15).
    case "$line" in
      *"<!-- vocab-allowlist:"*) continue ;;
    esac
    # Token scan — case-insensitive word boundary
    for token in phase task story PRD cycle milestone; do
      # Honor per-file allowlist
      case " $allowed " in
        *" $token "*) continue ;;
      esac
      if printf '%s\n' "$line" | grep -iqE "\\b${token}\\b"; then
        report_fail "$rel:$lineno" "$token" "$line"
      fi
    done
    # gsd-* glob (separate; prefix not single word)
    if printf '%s\n' "$line" | grep -iqE "\\bgsd-[a-z]"; then
      report_fail "$rel:$lineno" "gsd-*" "$line"
    fi
  done < "$file"
}

# ---- Vocabulary walk ----
LC_ALL=C
SCANNED=0

# Always scan README.md if present (it's user-facing surface)
if [ -f "$REPO_ROOT/README.md" ]; then
  lint_file "$REPO_ROOT/README.md"
  SCANNED=$((SCANNED + 1))
fi

# commands/*.md (top-level only); skip _* and README.md
for f in "$REPO_ROOT/commands/"*.md; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in
    _*|README.md) continue ;;
  esac
  lint_file "$f"
  SCANNED=$((SCANNED + 1))
done

# skills/*/SKILL.md; skip _shared (per 04-04-SURFACE-AUDIT.md § 3)
for f in "$REPO_ROOT/skills/"*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in
    */skills/_shared/*) continue ;;
  esac
  lint_file "$f"
  SCANNED=$((SCANNED + 1))
done

# ---- Surface-count gate (D-16) ----
# Canonical recipe from 04-04-SURFACE-AUDIT.md § 4.
# Excludes _shared/ and the 3 v1.x deprecated skills (prd, plan-stories, execute) which retain
# user-invocable: true during v2.0 mid-migration but are NOT counted toward the 11-cap.
SURFACE_COUNT=$(find "$REPO_ROOT/commands" "$REPO_ROOT/skills" -mindepth 1 \
  \( -name '_shared' -o -name 'prd' -o -name 'plan-stories' -o -name 'execute' \) -prune \
  -o -type f \( -name 'godmode.md' -o -name 'SKILL.md' \) -print \
  | wc -l | tr -d ' ')

if [ "$SURFACE_COUNT" != "11" ]; then
  report_fail "surface-count" "expected-11" "got $SURFACE_COUNT — see .planning/phases/04-skill-layer-state-management/04-04-SURFACE-AUDIT.md § 4"
else
  echo "[i] surface count: 11 (canonical recipe)"
fi

# ---- Final accumulator ----
if [ "$FAILED" -eq 0 ]; then
  echo "[+] vocabulary clean ($SCANNED file(s) scanned, surface count = $SURFACE_COUNT)"
  exit 0
else
  echo "[x] $FAILED vocabulary/surface violation(s) — see above"
  exit 1
fi
