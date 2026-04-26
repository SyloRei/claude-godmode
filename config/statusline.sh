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
GRAY='\033[90m'

# Read JSON from stdin
INPUT=$(cat)

# Parse fields in one jq call (was 4 invocations — collapsed for performance, FOUND-06)
# Switch to \x1f if cwd ever observed with literal tab
IFS=$'\t' read -r MODEL COST CTX_PCT CWD < <(
  printf '%s' "$INPUT" | jq -r '[(.model.display_name // "—"), (.cost.total_cost_usd // 0), (.context_window.used_percentage // 0), (.cwd // "")] | @tsv' 2>/dev/null \
  || printf '—\t0\t0\t\n'
)

# Project name from directory
PROJECT=$(basename "$CWD" 2>/dev/null || echo "—")

# Git branch (fast, no network)
BRANCH=$(cd "$CWD" 2>/dev/null && git branch --show-current 2>/dev/null || echo "")

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
