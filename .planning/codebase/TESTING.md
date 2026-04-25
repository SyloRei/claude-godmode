# Testing

**Analysis Date:** 2026-04-25

## TL;DR

**This repo has no automated test suite.** It is a configuration/extension distribution for Claude Code: shell scripts, markdown rules, JSON config, agent and skill definitions. Verification is currently manual.

This is a defensible choice given the project shape (no application logic to assert against), but it does leave several real risk surfaces uncovered. They are listed under "Coverage gaps" below.

## Test framework

None. No `package.json`, no `Cargo.toml`, no `pyproject.toml`, no `Gemfile`. Spot checks:

- No `test/`, `tests/`, `__tests__/`, or `*_test.*` files at any depth.
- No `bats` (Bash Automated Testing System) files (`*.bats`).
- No `shellcheck` config or invocation.
- No CI workflow under `.github/workflows/` — only `.github/ISSUE_TEMPLATE/` and `.github/PULL_REQUEST_TEMPLATE.md` exist.

## CI / automation

**None configured.** `.github/` contains only:
- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `.github/ISSUE_TEMPLATE/feature_request.yml`
- `.github/ISSUE_TEMPLATE/config.yml`
- `.github/PULL_REQUEST_TEMPLATE.md`

There is no GitHub Actions workflow file. Pull requests are not gated by automated checks.

## What is currently verified, and how

| Surface | Verification | Where |
|---|---|---|
| `install.sh` behavior | Manual: clone repo, run `./install.sh`, inspect `~/.claude/`. | n/a |
| `uninstall.sh` behavior | Manual. | n/a |
| Hook output JSON | Manual: pipe a fake input to the hook and inspect stdout. e.g. `echo '{}' \| bash hooks/session-start.sh \| jq .`. | n/a |
| Statusline output | Manual: pipe a fake session JSON. e.g. `echo '{"model":{"display_name":"opus"},"cost":{"total_cost_usd":0.5},"context_window":{"used_percentage":42},"cwd":"/tmp"}' \| bash config/statusline.sh`. | n/a |
| Agent / skill / rule format | Loaded by Claude Code at session start; problems surface as session-time failures. | n/a |
| `settings.template.json` validity | `install.sh:160` runs `jq '.'` over the merged result; malformed input from the template would surface here. | `install.sh:120-168` |
| Shell-script safety | All scripts use `set -euo pipefail` (`install.sh:2`, `uninstall.sh:2`, `hooks/session-start.sh:6`, `hooks/post-compact.sh:6`, `config/statusline.sh:5`). | n/a |
| `jq` preflight | `install.sh:26` errors out if `jq` is missing. | `install.sh:26` |

## Manual verification recipes

### Verify a hook's JSON output is well-formed

```bash
echo '{}' | bash hooks/session-start.sh | jq .
echo '{}' | bash hooks/post-compact.sh | jq .
```

A successful run emits a `hookSpecificOutput` object (or `{}` for `session-start.sh` when nothing was detected). A failure surfaces as `parse error` from `jq`.

### Verify the statusline renders

```bash
echo '{"model":{"display_name":"opus"},"cost":{"total_cost_usd":0.12},"context_window":{"used_percentage":35},"cwd":"'"$PWD"'"}' \
  | bash config/statusline.sh
```

Expect: a single line containing the project name, branch (if in a git repo), model, a 10-char context bar with %, and `$0.12`.

### Verify the installer is idempotent

```bash
./install.sh        # first run — backs up prior state, installs
./install.sh        # second run — should produce no destructive changes
diff -r ~/.claude/rules <(ls rules/godmode-*.md)
```

### Verify the uninstaller leaves no traces

```bash
./uninstall.sh
ls ~/.claude/rules/godmode-*.md   # should be gone
test -f ~/.claude/.claude-godmode-version || echo "version file removed"
```

### Verify YAML frontmatter parses

There is no automated check today, but a quick sanity sweep:

```bash
for f in agents/*.md commands/*.md skills/*/SKILL.md; do
  head -1 "$f" | grep -q '^---$' || echo "MISSING FRONTMATTER: $f"
done
```

### Verify cross-references resolve

A quick grep for broken paths in markdown:

```bash
grep -rn '`[a-zA-Z0-9_./-]*\.md`' rules/ agents/ skills/ commands/ | \
  awk -F'`' '{print $2}' | sort -u | \
  while read p; do test -f "$p" || echo "BROKEN: $p"; done
```

## Coverage gaps (worth tests if/when added)

These are the places where a small test suite would catch real bugs.

1. **`install.sh` settings merge** — the `jq -s` expression in `install.sh:122-158` is non-trivial. It is easy to drop a key in `$existing` while merging. A snapshot test against representative `~/.claude/settings.json` inputs would catch regressions.
2. **Hook JSON validity under odd inputs** — branch names containing quotes, backslashes, newlines (`hooks/session-start.sh:50`, `hooks/post-compact.sh:43`) are interpolated unescaped into the `additionalContext` string. A test with adversarial branch names would detect injection bugs.
3. **`stories.json` malformed edge cases** — both hooks parse `stories.json` with `jq` and fall back to a generic message on failure, but the fallback path is currently un-tested.
4. **Plugin-mode vs manual-mode parity** — `install.sh` has two non-trivial code paths (lines 121-167). Tests that diff the resulting `~/.claude/settings.json` for both modes against a fixed input would lock the contract.
5. **Uninstall completeness** — `uninstall.sh` lists files explicitly. A test that installs, captures the file set, uninstalls, and asserts no godmode files remain would catch drift between installer and uninstaller.
6. **Markdown frontmatter contract** — agent/skill loading silently ignores fields Claude Code doesn't recognize. A linter for frontmatter (allowed keys, value types) would prevent typos like `tool:` vs `tools:`.

## Recommended minimum (if testing is added)

In rough order of cost-effectiveness:

1. **Bats** suite covering `install.sh` / `uninstall.sh` round-trips against a temporary `$HOME`. Fast, no fixtures beyond the repo.
2. **shellcheck** in CI on every `*.sh` file. One workflow file, immediate signal.
3. **JSON schema validation** of `config/settings.template.json`, `hooks/hooks.json`, `.claude-plugin/plugin.json` (via `jq -e` or `ajv`).
4. **Frontmatter linter** for `agents/*.md` and `skills/*/SKILL.md` — small Python or Node script.
5. **Hook output golden tests** — feed a fixed input, diff stdout against a checked-in expected output.

## Note for projects that *use* godmode

The rules godmode installs (`rules/godmode-testing.md`, `rules/godmode-quality.md`) prescribe quality gates for *consumer* projects: typecheck, lint, all tests pass, no hardcoded secrets, no regressions, changes match requirements. Those gates are enforced by the `/execute` skill (`skills/execute/SKILL.md`) on each story before commit. They are guidance for the consumer codebase, not for this repo.

---

*Testing analysis: 2026-04-25*
