---
name: ship
description: "Run 6 gates from config/quality-gates.txt, refuse on PARTIAL/MISSING (unless --force), push, gh pr create. Never auto-force under Auto Mode."
user-invocable: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Task
disable-model-invocation: true
---

# /ship

## Connects to

- **Upstream:** /verify N (status must be `Ready to ship`)
- **Downstream:** (terminal — produces a PR)
- **Reads from:** `.planning/STATE.md`, `.planning/briefs/NN-slug/{BRIEF.md,PLAN.md}`, `config/quality-gates.txt`
- **Writes to:** git (push), GitHub (PR), `.planning/STATE.md`

## Auto Mode check

Scan the most recent system reminder for the case-insensitive substring "Auto Mode Active".

When detected (per D-10):
- Run gates; refuse on PARTIAL/MISSING.
- NEVER auto-`--force`. `--force` is an explicit user opt-in; Auto Mode does not satisfy that requirement.
- If a gate fails: surface the failure, do not retry, do not bypass.
- Treat user course corrections as normal input.

See `rules/godmode-skills.md` § Auto Mode Detection for the full convention.

---

## The Job

1. Verify STATE.md `status` is `Ready to ship`. Refuse otherwise.
2. Read PLAN.md `## Verification status` + `## Brief success criteria` — refuse on any non-COVERED line (unless `--force`).
3. Run the 6 quality gates from `config/quality-gates.txt`.
4. Git cleanup.
5. Push and `gh pr create`.

`--force` bypasses Step 1 (the PARTIAL/MISSING refusal) ONLY — it never bypasses Step 2 (gate failures). D-50 carry-over.

---

## Step 0: Resolve brief and verify state

```bash
set -euo pipefail
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/_lib.sh"
source "$ROOT/skills/_shared/init-context.sh"
source "$ROOT/skills/_shared/state.sh"

FORCE=0
case "${ARGUMENTS:-}" in
  *--force*) FORCE=1 ;;
esac

CTX=$(godmode_init_context "$PWD")
STATUS=$(printf '%s' "$CTX" | jq -r '.state.status // empty')
N=$(printf '%s' "$CTX" | jq -r '.state.active_brief // empty')
SLUG=$(printf '%s' "$CTX" | jq -r '.state.active_brief_slug // empty')
BRIEF_DIR=$(printf '%s' "$CTX" | jq -r '.state.active_brief_dir // empty')
[ -n "$N" ] && [ -d "$BRIEF_DIR" ] || error "No active brief. Run /godmode."

if [ "$STATUS" != "Ready to ship" ]; then
  error "Status is '$STATUS'. Run /verify $N before /ship."
fi
```

---

## Step 1: Verification gate

```bash
PLAN_FILE="$BRIEF_DIR/PLAN.md"
[ -f "$PLAN_FILE" ] || error "PLAN.md not found at $PLAN_FILE."

NON_COVERED=$(grep -E '^- \[.\].*\b(PARTIAL|MISSING)\b' "$PLAN_FILE" || true)
if [ -n "$NON_COVERED" ]; then
  warn "PLAN.md has non-COVERED criteria:"
  printf '%s\n' "$NON_COVERED"
  if [ "$FORCE" != "1" ]; then
    error "Refusing to ship. Re-run /verify $N (or pass --force with explicit acknowledgment)."
  fi
  warn "[godmode] FORCE-ship requested. PR body will carry an explicit warning."
fi
```

---

## Step 2: Quality Gates (from `config/quality-gates.txt`)

Read the 6 gates from canonical SoT and run each. Auto-detect commands per gate.

| Gate | Auto-detect commands |
|------|----------------------|
| Typecheck | `tsc --noEmit`, `mypy`, `cargo check`, `go vet`, `shellcheck` (.sh files) |
| Lint | `eslint`, `ruff`, `cargo clippy`, `golangci-lint`, `shellcheck` |
| Tests | `vitest`, `pytest`, `cargo test`, `go test`, `bats` |
| No hardcoded secrets | `git diff --staged | grep -E '<patterns>'` (PreToolUse already enforced — re-run as belt-and-suspenders) |
| No regressions | full test suite |
| Changes match requirements | `git log main..HEAD --grep '[brief NN.M]'` — verify every PLAN.md item has a matching commit |

```bash
GATES_FILE="$ROOT/config/quality-gates.txt"
[ -f "$GATES_FILE" ] || error "Quality gates SoT missing at $GATES_FILE."

GATE_NUM=0
ALL_PASSED=1
while IFS= read -r gate_desc || [ -n "$gate_desc" ]; do
  GATE_NUM=$((GATE_NUM + 1))
  info "Gate $GATE_NUM: $gate_desc"
  # Per-gate logic: auto-detect command from project files; run; capture exit code.
  # On any non-zero exit code: ALL_PASSED=0; warn the gate description; continue
  # (so the user sees the full failure list, not just the first).
done < "$GATES_FILE"

if [ "$ALL_PASSED" != "1" ]; then
  error "One or more gates failed. Refusing to ship. (--force does NOT bypass gate failures — D-50.)"
fi
```

**If ANY gate fails:**
- Use `/debug` to diagnose test/typecheck failures.
- Use `@writer` agent for complex fixes.
- For lint: run auto-fix if available, otherwise fix manually.
- Do NOT skip. Do NOT push with failures. The PreToolUse hook (Phase 3 D-01) already blocks `--no-verify`; this skill enforces gates regardless.

---

## Step 3: Git Cleanup

- Check for uncommitted changes — commit or stash.
- Ensure branch is up to date with the base branch.
- Review commit history — atomic and well-messaged?
- If messy: suggest rebase (ask the user first; in Auto Mode, do NOT auto-rebase).

Security scan as a part of cleanup: scan the diff for hardcoded secrets, API keys, tokens, passwords, .env files, credentials, sensitive data in logs or error messages. If found: STOP. Remove them. Never push secrets. (Belt-and-suspenders — Gate 4 already covered this; the PreToolUse hook also blocks at commit time.)

---

## Step 4: Push & PR

```bash
BRANCH=$(git branch --show-current)
git push -u origin "$BRANCH"
```

Create PR. Body templated from BRIEF.md (Why → "## Summary"; What → "## Changes"; Spec → "## Test plan"). Heredoc here is fine — single-quoted `'EOF'` prevents shell expansion of the body content (T-04-30 mitigation):

```bash
PR_TITLE="<concise, less than 70 chars>"   # derived from brief title

if [ "$FORCE" = "1" ]; then
  FORCE_LINE='[godmode] FORCE-shipped with PARTIAL/MISSING criteria — review before merge.'
else
  FORCE_LINE=""
fi

gh pr create --title "$PR_TITLE" --body "$(cat <<'EOF'
## Summary
<Why from BRIEF.md>

## Changes
<What from BRIEF.md>

## Test plan
<Spec from BRIEF.md>
EOF
)"
```

If `$FORCE_LINE` is non-empty, prepend it to the PR body so reviewers see the explicit warning.

---

## Step 5: Update STATE.md

```bash
PR_URL=$(gh pr view --json url -q .url 2>/dev/null || echo "(unknown)")
NEXT_N=$((N + 1))
godmode_state_update "$N" "$SLUG" "Shipped $PR_URL" "/brief $NEXT_N" "Shipped $PR_URL"
info "Shipped: $PR_URL"
info "Run /brief $NEXT_N to start the next brief."
```

---

## Agent Routing

| Step | Agent | Purpose |
|------|-------|---------|
| Step 2 (Gate failure) | Spawn `@writer` for complex fixes | Fix typecheck, lint, or test failures that need multi-file changes |
| Step 3 (Cleanup) | MAY spawn `@reviewer` for deep code review | Validate all changes match acceptance criteria before pushing |
| Step 3 (Cleanup) | MAY spawn `@security-auditor` for comprehensive audit | Scan for vulnerabilities, secrets, injection risks before shipping |

**Rule:** Never perform code review or security audit inline — always spawn the designated agent if depth is needed.

---

## Constraints

- `--force` bypasses Step 1 (PARTIAL/MISSING refusal) ONLY — never bypasses Step 2 (gate failures).
- Auto Mode NEVER auto-forces (D-10). The user must explicitly pass `--force`.
- Gates source is `config/quality-gates.txt` (Phase 1 D-26 / Phase 3 D-15) — never duplicated inline.
- Vocabulary: only the v2 user-facing terms. The token "Task NN.M" is the documented exception inside PLAN.md headings (D-35 template constraint) — this skill body parses those headings to verify Step 2 Gate 6 (every item has a matching commit). Body prose still uses "item" or "criterion".
- All STATE.md mutations go through `godmode_state_update` from `skills/_shared/state.sh`.

---

## See Also

- `rules/godmode-skills.md` — frontmatter convention, Connects-to layout, Auto Mode block.
- `skills/_shared/init-context.sh` — `godmode_init_context` returns the JSON context blob.
- `skills/_shared/state.sh` — `godmode_state_update` is the only sanctioned STATE.md writer.
- `config/quality-gates.txt` — canonical 6-gate list (single source of truth).
- `agents/writer.md` — code-touching agent for gate-failure fixes.
- `agents/reviewer.md`, `agents/security-auditor.md` — deep review and audit (optional).
