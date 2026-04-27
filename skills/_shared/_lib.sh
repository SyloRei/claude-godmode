#!/usr/bin/env bash
# skills/_shared/_lib.sh
# Shared color helpers, slug derivation, and atomic file replace.
# Pure bash 3.2 + POSIX sed/tr. Sourced by init-context.sh and state.sh.
# No `set -e` here — sourced by callers that own their own pipefail discipline.
#
# Lifted from install.sh:10-18 (D-55: UX consistency with installer).

# Color codes (lifted VERBATIM from install.sh:10-18 per D-55)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1" 1>&2; exit 1; }

# godmode_slug: free-form title -> kebab-case slug. Bash 3.2 portable (no ${var,,}).
# Algorithm per RESEARCH § "Brief slug derivation (D-22)" and PITFALLS CR-04:
#   1. tr [:upper:] [:lower:]
#   2. sed: replace any run of non-[a-z0-9] with single -
#   3. sed: strip leading/trailing -
godmode_slug() {
  printf '%s' "${1:-}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+|-+$//g'
}

# godmode_atomic_replace: write content to target via mktemp+mv (POSIX atomic).
# Args: $1 = content (string); $2 = target path
# If $1 is the literal string "-" read content from stdin instead.
godmode_atomic_replace() {
  local content="$1" target="$2" tmp
  tmp=$(mktemp -t godmode-atomic.XXXXXX) || return 1
  if [ "$content" = "-" ]; then
    cat > "$tmp"
  else
    printf '%s' "$content" > "$tmp"
  fi
  mv "$tmp" "$target"
}
