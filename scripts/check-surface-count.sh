#!/usr/bin/env bash
#
# check-surface-count.sh — enforce the locked user-facing command surface.
#
# v2 locks the surface to AT MOST 14 user-facing slash commands, with 1 slot
# reserved (so 13 in active use). A user-facing command is either:
#   - a skill directory under skills/ (one SKILL.md == one /command), OR
#   - a command file under commands/ (one *.md == one /command).
# Directories prefixed with "_" (e.g. skills/_shared) are internal scaffolding,
# not user-facing, and are excluded from the count.
#
# This gate counts both sources and asserts total <= 14. It reports the count
# and the reserved-slot headroom. Exit 1 if the cap is exceeded.
#
# Pure bash 3.2 + find. No Node, no Python.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

cd -- "${REPO_ROOT}"

CAP=14

# Count skill commands: immediate subdirectories of skills/ that are NOT
# underscore-prefixed and contain a SKILL.md.
skill_count=0
if [ -d skills ]; then
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    base=$(basename -- "$dir")
    case "$base" in
      _*) continue ;;
    esac
    [ -f "$dir/SKILL.md" ] || continue
    skill_count=$((skill_count + 1))
  done < <(find skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

# Count command files: *.md directly under commands/.
command_count=0
if [ -d commands ]; then
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    command_count=$((command_count + 1))
  done < <(find commands -mindepth 1 -maxdepth 1 -type f -name '*.md' 2>/dev/null)
fi

total=$((skill_count + command_count))

echo "surface: ${skill_count} skill command(s) + ${command_count} command file(s) = ${total} user-facing command(s)"

if [ "$total" -gt "$CAP" ]; then
  echo "surface FAILURE: ${total} user-facing command(s) exceeds the cap of ${CAP}." >&2
  exit 1
fi

reserved=$((CAP - total))
echo "surface: within cap of ${CAP} (${reserved} slot(s) of headroom, incl. the 1 reserved slot)."
exit 0
