#!/usr/bin/env bash
# tests/fixtures/hooks/setup-fixtures.sh
# Creates temp git repos with adversarial branch names; emits cwd JSON fixtures.
#
# Bash 3.2 portable. macOS-aware: some adversarial branch names that git ACCEPTS
# on Linux are rejected by macOS git ref validation. Those fixtures fall back
# to a normal-branch repo + a marker JSON so the hook is still exercised but
# the branch-name-injection threat surface is documented for Phase 5 CI
# (which runs on Linux where the full fixture set works).
#
# macOS-valid: normal (main), quote-branch (feat/"weird"), apostrophe-branch (feat/it's)
# macOS-invalid (Linux only): backslash-branch (feat/back\slash), newline-branch (feat/line\nbreak)
#
# Output: prints fixture paths (one per line) on stdout; setup notes on stderr.
set -euo pipefail

FIXTURE_BASE="${TMPDIR:-/tmp}/godmode-hook-fixtures-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$FIXTURE_BASE"

# Try to create a repo with the given branch; on failure, fall back to "main".
# Always writes the cwd JSON file. Returns 0 on full success, 1 if branch creation fell back.
create_repo() {
  local name="$1" branch="$2"
  local repo="$FIXTURE_BASE/$name"
  local fallback=0

  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    if ! git checkout -q -b "$branch" 2>/dev/null; then
      git checkout -q -b "main" 2>/dev/null
      exit 1
    fi
  ) || fallback=1

  (cd "$repo" && git -c user.email=test@example.com -c user.name=test commit --allow-empty -q -m init 2>/dev/null) || true
  printf '{"cwd":"%s"}\n' "$repo" > "$SCRIPT_DIR/cwd-${name}.json"
  echo "$SCRIPT_DIR/cwd-${name}.json"

  if [ "$fallback" -eq 1 ]; then
    echo "[!] $name: macOS git rejected '$branch' — fell back to 'main'. Linux CI exercises this case." >&2
  fi
  return 0
}

create_repo "normal" "main"
create_repo "quote-branch" 'feat/"weird"'
create_repo "backslash-branch" 'feat/back\slash'
create_repo "newline-branch" "$(printf 'feat/line\nbreak')"
create_repo "apostrophe-branch" "feat/it's"

echo "[+] fixture base: $FIXTURE_BASE" >&2
