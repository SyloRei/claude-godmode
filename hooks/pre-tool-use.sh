#!/usr/bin/env bash
# hooks/pre-tool-use.sh
# Mechanical quality-gate enforcement: blocks --no-verify, --no-gpg-sign, force-push to main/master,
# and hardcoded secret patterns in tool input. v2.0 has NO bypass — refusal is final.
# (claude-godmode-force-bypass magic phrase reserved for v2.1.)
# Bash 3.2 portable. CR-02-safe via jq -n --arg for output.
set -euo pipefail

INPUT=$(cat || true)

# Fast-path: only fire on Bash tool dispatch
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ "$TOOL_NAME" = "Bash" ] || { echo '{}'; exit 0; }

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -n "$CMD" ] || { echo '{}'; exit 0; }

# --- Quality-gate-bypass blocker (HOOK-01) ---
deny() {
  local reason="$1" suggestion="$2"
  jq -n --arg ctx "[godmode-pre-tool-use] BLOCKED: $reason. See rules/godmode-quality.md and config/quality-gates.txt. Use the gates-respecting path: $suggestion." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", additionalContext: $ctx}}'
  exit 0
}

case "$CMD" in
  *"git commit"*"--no-verify"*)
    deny "git commit --no-verify bypasses pre-commit hooks" "fix the failing hook, then commit normally"
    ;;
  *"git commit"*"--no-gpg-sign"*|*"git -c commit.gpgsign=false"*"commit"*)
    deny "GPG signing bypass" "if signing is configured, sign your commit; otherwise unset commit.gpgsign in your local config"
    ;;
esac

# git commit -n short form — match the bare flag, not -n as part of other flags
case "$CMD" in
  *"git commit "*" -n"|*"git commit "*" -n "*|*"git commit -n"|*"git commit -n "*)
    deny "git commit -n (short form of --no-verify) bypasses pre-commit hooks" "fix the failing hook, then commit normally"
    ;;
esac

# Force push to main/master
case "$CMD" in
  *"git push"*"--force"*"main"*|*"git push"*"--force"*"master"*|*"git push"*" -f "*"main"*|*"git push"*" -f "*"master"*|*"git push"*"-f main"*|*"git push"*"-f master"*)
    deny "git push --force to main/master rewrites shared history" "open a PR; if you must rewrite, use a feature branch"
    ;;
esac

# --- Secret pattern scan (HOOK-02) ---
INPUT_BLOB=$(printf '%s' "$INPUT" | jq -r '.tool_input // {} | tostring' 2>/dev/null || true)

scan_secret() {
  local pattern="$1" label="$2"
  if printf '%s' "$INPUT_BLOB" | grep -qE "$pattern"; then
    deny "$label detected in tool input" "use an env var or read from .env; never hardcode in source"
  fi
}

# AWS access keys
scan_secret 'AKIA[0-9A-Z]{16}' "AWS access key (AKIA...)"
# AWS secret access keys (40-char base64-ish after assignment)
scan_secret 'aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}' "AWS secret access key"
# GitHub PATs (classic + fine-grained)
scan_secret 'ghp_[A-Za-z0-9]{36}' "GitHub PAT (ghp_...)"
scan_secret 'github_pat_[A-Za-z0-9_]{82}' "GitHub fine-grained PAT (github_pat_...)"
# JWT shape
scan_secret 'ey[A-Za-z0-9_-]{10,}\.ey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' "JWT-shape token"
# Generic API-key heuristic — quoted assignments only (lower false-positive rate)
scan_secret '(api[_-]?key|secret|password|token)[[:space:]]*=[[:space:]]*['"'"'"][^'"'"'"]{8,}['"'"'"]' "hardcoded credential assignment"

# All checks passed — allow by absence
echo '{}'
