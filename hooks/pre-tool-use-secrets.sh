#!/usr/bin/env bash
# PreToolUse secret-scan hook: block `git commit` when the STAGED diff contains
# obvious secrets so credentials never get committed.
#
# Contract:
#   - Reads the PreToolUse event JSON from STDIN (tool_name, tool_input.command, cwd).
#   - Only acts when tool_name == "Bash" AND the command is a `git commit`.
#     Everything else passes through untouched (exit 0).
#   - Scans `git diff --cached` (added lines only) for secret patterns.
#   - On a hit: exit 2 with a STDERR message naming the file + matched pattern
#     CATEGORY only — never the secret value itself.
#   - Clean diff: exit 0.
#
# Patterns detected:
#   - AWS access key IDs            (AKIA / ASIA + 16 base32 chars)
#   - Private key headers           (-----BEGIN ... PRIVATE KEY-----)
#   - GitHub tokens                 (ghp_ / gho_ / ghu_ / ghs_ / ghr_ + chars)
#   - High-entropy secret-ish assignments:
#       token / api_key / apikey / secret / password = "<12+ chars>"
#
# False-positive tuning:
#   This hook intentionally errs toward blocking. Two escape hatches exist for
#   legitimate cases (test fixtures, documentation examples, rotated/placeholder
#   values):
#     1. Line marker — append `# godmode:allow-secret` to the offending added
#        line. That single line is excluded from the scan.
#     2. Env var — set GODMODE_ALLOW_SECRETS=1 to skip the scan entirely for a
#        commit (e.g. `GODMODE_ALLOW_SECRETS=1 git commit ...`). Use sparingly.
#   The secret-assignment pattern requires 12+ chars and a quoted value to avoid
#   tripping on short config like `password = ""` or `token = x`.
#
# bash 3.2+ / jq only. BSD-safe (no GNU-only flags). No secrets in this file.

set -euo pipefail

# --- Read and parse the hook event from STDIN -------------------------------
INPUT=""
INPUT="$(cat || true)"

# Default-safe extraction. `// empty` so missing fields yield empty strings.
TOOL_NAME=""
COMMAND=""
CWD=""
if command -v jq > /dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi

# --- Gate: only Bash `git commit` calls are in scope ------------------------
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# Match `git commit` allowing leading env assignments / flags before it.
case "$COMMAND" in
  *"git commit"*) : ;;
  *) exit 0 ;;
esac

# --- Escape hatch: env var skips the scan entirely --------------------------
if [ "${GODMODE_ALLOW_SECRETS:-}" = "1" ]; then
  exit 0
fi

# --- Locate the repo via cwd ------------------------------------------------
# Proper if-form (not `A && B || C`, which SC2015 flags as ambiguous): scan the
# repo at the event's cwd; a missing/odd cwd just leaves us where we are.
if [ -n "$CWD" ]; then
  cd "$CWD" 2>/dev/null || true
fi

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  # Not a git repo we can read — nothing to scan, don't block.
  exit 0
fi

# --- Collect the added lines of the staged diff -----------------------------
# Only added lines ('+' prefix, excluding the '+++' file header). Strip the
# leading '+'. Lines carrying the allow marker are dropped before scanning.
DIFF=""
DIFF="$(git diff --cached --unified=0 2>/dev/null || true)"

if [ -z "$DIFF" ]; then
  exit 0
fi

# --- Pattern categories (extended regex, BSD grep -E compatible) ------------
AWS_RE='(AKIA|ASIA)[0-9A-Z]{16}'
PRIVKEY_RE='-----BEGIN [A-Z ]*PRIVATE KEY-----'
GH_RE='gh[pousr]_[0-9A-Za-z]{20,}'
ASSIGN_RE='(token|api[_-]?key|apikey|secret|password)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{12,}["'"'"']'

# Track the current file as we walk the diff so we can name it on a hit.
CUR_FILE=""
HIT_FILE=""
HIT_CATEGORY=""

# Walk diff line by line. bash 3.2 compatible read loop.
while IFS= read -r line; do
  # Track file headers: "+++ b/path/to/file"
  case "$line" in
    '+++ b/'*)
      CUR_FILE="${line#+++ b/}"
      continue
      ;;
    '+++ /dev/null'*)
      CUR_FILE=""
      continue
      ;;
    '+++ '*)
      CUR_FILE="${line#+++ }"
      continue
      ;;
  esac

  # Only consider added content lines (single leading '+', not '+++').
  case "$line" in
    '+'*) : ;;
    *) continue ;;
  esac

  added="${line#+}"

  # Escape hatch: per-line allow marker.
  case "$added" in
    *'# godmode:allow-secret'*) continue ;;
  esac

  # Pass each pattern via -e so leading '-' (private key header) is not parsed
  # as a grep option on BSD grep.
  CATEGORY=""
  if printf '%s' "$added" | grep -Eq -e "$AWS_RE"; then
    CATEGORY="AWS access key"
  elif printf '%s' "$added" | grep -Eq -e "$PRIVKEY_RE"; then
    CATEGORY="private key header"
  elif printf '%s' "$added" | grep -Eq -e "$GH_RE"; then
    CATEGORY="GitHub token"
  elif printf '%s' "$added" | grep -Eiq -e "$ASSIGN_RE"; then
    CATEGORY="high-entropy secret assignment"
  fi

  if [ -n "$CATEGORY" ]; then
    HIT_FILE="${CUR_FILE:-<unknown file>}"
    HIT_CATEGORY="$CATEGORY"
    break
  fi
done <<EOF
$DIFF
EOF

# --- Verdict ----------------------------------------------------------------
if [ -n "$HIT_CATEGORY" ]; then
  # Exit 2 is the blocking signal. STDERR is fed back to Claude. Never print the
  # matched value — only the file and the category.
  {
    printf 'BLOCKED: possible secret in staged diff.\n'
    printf '  File:     %s\n' "$HIT_FILE"
    printf '  Category: %s\n' "$HIT_CATEGORY"
    printf '\n'
    printf 'Remove the credential before committing. If this is a false positive\n'
    printf '(test fixture, placeholder, docs), either append "# godmode:allow-secret"\n'
    printf 'to the offending line, or run with GODMODE_ALLOW_SECRETS=1 to skip the scan.\n'
  } >&2
  exit 2
fi

# Clean diff — emit empty JSON object and pass.
jq -n '{}' 2>/dev/null || printf '{}\n'
exit 0
