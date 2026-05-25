#!/usr/bin/env bash
# God-Mode Status Line — context %, model, cost, project, branch
# Receives JSON via stdin from Claude Code with session data.

set -euo pipefail

# Colors
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
WHITE='\033[37m'

# Read JSON from stdin
INPUT=$(cat)

# Parse ALL fields in one pass (TSV: model, cost, ctx%, cwd).
# Use control-char-free defaults; tabs separate fields, so empty cwd is fine.
TSV=$(printf '%s' "$INPUT" | jq -r '
  [ (.model.display_name // "—"),
    (.cost.total_cost_usd // 0 | tostring),
    (.context_window.used_percentage // 0 | tostring),
    (.cwd // "")
  ] | @tsv' 2>/dev/null || printf '—\t0\t0\t')

# Split TSV into fields (bash 3.2 portable; tab-delimited).
IFS=$'\t' read -r MODEL COST CTX_PCT CWD <<EOF
$TSV
EOF
MODEL=${MODEL:-—}
COST=${COST:-0}
CTX_PCT=${CTX_PCT:-0}

# Project name + git branch from CWD. Guard against an absent/empty cwd so we
# never fall back to the hook process's own directory (which would show the
# wrong project/branch).
PROJECT="—"
BRANCH=""
if [ -n "$CWD" ]; then
  PROJECT=$(basename "$CWD" 2>/dev/null || echo "—")
  BRANCH=$(cd "$CWD" 2>/dev/null && git branch --show-current 2>/dev/null || echo "")
fi

# Format cost
if command -v awk &>/dev/null; then
  COST_FMT=$(awk "BEGIN{printf \"%.2f\", $COST}" 2>/dev/null || echo "$COST")
else
  COST_FMT="$COST"
fi

# Context bar (10 chars wide)
CTX_INT=${CTX_PCT%.*}  # Remove decimal
CTX_INT=${CTX_INT:-0}
FILLED=$((CTX_INT / 10))
EMPTY=$((10 - FILLED))

BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="█"; done
for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

# Context color based on threshold
if [ "$CTX_INT" -ge 80 ]; then
  CTX_COLOR="$RED"
  CTX_ICON=" !"
elif [ "$CTX_INT" -ge 60 ]; then
  CTX_COLOR="$YELLOW"
  CTX_ICON=""
else
  CTX_COLOR="$GREEN"
  CTX_ICON=""
fi

# Separator
SEP="${DIM} │ ${RESET}"

# Build status line
LINE=""
LINE+="${BOLD}${CYAN} ${PROJECT}${RESET}"

if [ -n "$BRANCH" ]; then
  LINE+="${SEP}${WHITE} ${BRANCH}${RESET}"
fi

LINE+="${SEP}${WHITE}${MODEL}${RESET}"
LINE+="${SEP}${CTX_COLOR}${BAR} ${CTX_INT}%${CTX_ICON}${RESET}"
LINE+="${SEP}${GREEN}\$${COST_FMT}${RESET}"

echo -e "$LINE"
