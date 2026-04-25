# Technical Concerns

**Analysis Date:** 2026-04-25

Concerns are grouped by severity and area. Each item lists the specific file/lines and what would go wrong.

## High — install/uninstall safety

### 1. Local rule customizations are silently overwritten

`install.sh:97-110` detects when a user has edited a rule file (`diff -q` against source), warns about the count, and then overwrites anyway:

```bash
if [ "$CUSTOMIZED" -gt 0 ]; then
  warn "${CUSTOMIZED} rule file(s) have local customizations that will be overwritten"
  warn "Originals are backed up at $BACKUP_DIR/rules/"
fi
info "Installing rules (${RULES_COUNT} files)"
mkdir -p "$CLAUDE_DIR/rules"
cp "$RULES_SRC"/godmode-*.md "$CLAUDE_DIR/rules/"
```

**What goes wrong:** A user who edited `~/.claude/rules/godmode-coding.md` to add house style notes loses those notes on the next `./install.sh`. The backup is created, but no prompt is offered.

**Fix direction:** Prompt before overwriting customized files; offer per-file diff/skip/replace.

### 2. Manual-mode install overwrites agents and skills with no per-file check

`install.sh:171-200` (manual mode) blanket-copies all agents and skills with `cp -r`, only emitting a generic warning at line 173-174. There is no `diff` check like the rules path.

**What goes wrong:** A user's local edits to `~/.claude/agents/executor.md` or any `~/.claude/skills/*/SKILL.md` are lost without warning beyond the generic banner.

**Fix direction:** Apply the same `CUSTOMIZED` count and warning pattern as the rules block.

### 3. Settings merge can drop keys silently if the template is malformed

`install.sh:122-158` uses two `jq -s` expressions (one per mode) to merge `$existing * $template`. The `*` operator is recursive merge but only at the top level; nested arrays (e.g. `permissions.allow`) are unioned via explicit `+ unique` logic. If anyone ever adds a new top-level key to `settings.template.json` without updating the merge expression, it will simply not propagate.

**What goes wrong:** New top-level settings (e.g. an `env` block) added to the template won't reach existing users on upgrade.

**Fix direction:** Add a regression test (snapshot diff) for the merge result in both modes; or rewrite the merge as `$existing * $template` for top-level keys, with an explicit allow-list of arrays-to-union.

### 4. No version-mismatch detection between installed `~/.claude/.claude-godmode-version` and incoming `install.sh`

`install.sh:202-203` writes the new version unconditionally. There is no check for downgrade, sidegrade, or "this installer is older than what's on disk" — `uninstall.sh` likewise has no version awareness, so an old uninstaller can erase files that a newer install introduced.

**What goes wrong:** A user with v1.6 installed who runs `./uninstall.sh` from a v1.4 checkout will leave behind v1.5+ files that uninstall doesn't know about (e.g. new agents added after v1.4).

**Fix direction:** Have `uninstall.sh` read `~/.claude/.claude-godmode-version` and refuse to operate (or warn loudly) if it doesn't match the script's known version.

### 5. v1.x migration removes `CLAUDE.md` after one keypress

`install.sh:57-89` reads a single `[y/N]` from `read -rp`, then `rm`s `~/.claude/CLAUDE.md` (a backup is taken first, which is good). The interactive prompt is fine for terminal use but unsafe under `bash install.sh < /dev/null` or piped install patterns — `read` returns empty, `migrate_confirm` is empty, the file is kept; harmless, but the symmetric risk is shells where stdin is fed accidentally.

**What goes wrong:** Probably nothing in practice, but worth noting because the script does a destructive op based on a single character.

**Fix direction:** Require literal `yes` (not `[yY]`); document non-interactive behavior in README.

## High — hook fragility

### 6. Branch names and git output interpolated into hook JSON without escaping

`hooks/session-start.sh:50` and `hooks/post-compact.sh:43-49` build `additionalContext` by string interpolation:

```bash
GIT_RECENT="Branch: ${BRANCH} | Recent: ${GIT_RECENT}"
...
"additionalContext": "...${CONTEXT}..."
```

The final heredoc emits this directly inside double-quoted JSON. If a branch name contains `"`, `\`, or a literal newline, the emitted JSON is invalid and Claude Code will discard the hook output (best case) or misinterpret it.

**What goes wrong:** A branch like `feat/"quoted"` (legal in git, rare but possible) breaks the hook's contract.

**Fix direction:** Build the `additionalContext` value with `jq -Rs` or `jq -n --arg ctx "$CONTEXT" '...'` instead of string interpolation. Same fix applies to commit messages in `GIT_RECENT`.

### 7. Hooks rely on `cwd` being the project root

Both hooks check `package.json`, `Cargo.toml`, etc. relative to the current directory (`hooks/session-start.sh:13-43`, `hooks/post-compact.sh:14-30`). The Claude Code SessionStart contract does set cwd to the project, but the hooks have no fallback.

**What goes wrong:** If invoked from a subdirectory or an unusual cwd, both hooks silently report nothing detected. The `.claude-pipeline/` lookup likewise uses a relative path (`hooks/session-start.sh:55`, `hooks/post-compact.sh:34`).

**Fix direction:** Read `cwd` from the hook's stdin JSON (Claude Code provides it) and `cd` into it explicitly, or scan upward from `pwd` for a project marker.

### 8. Hardcoded skill and agent lists in `post-compact.sh`

`hooks/post-compact.sh:70` embeds:
```
Available Skills: /prd, /plan-stories, /execute, /ship, /debug, /tdd, /refactor, /explore-repo
Available Agents: @researcher, @reviewer, @architect, @writer, @executor, @security-auditor, @test-writer, @doc-writer
```

This list is duplicated against `commands/godmode.md` and the actual contents of `agents/` and `skills/`. Adding a new agent or skill requires remembering to update this hook.

**What goes wrong:** Drift. New agents added to `agents/` won't be advertised after compaction.

**Fix direction:** Generate the list at hook-execution time by scanning `${CLAUDE_PLUGIN_ROOT}/agents/*.md` and `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md`.

### 9. Quality gates duplicated between `rules/godmode-quality.md` and `hooks/post-compact.sh`

`hooks/post-compact.sh:70` hardcodes the six quality gates. `rules/godmode-quality.md` (the canonical source per the `commands/godmode.md` quick reference) likely says the same — but if one is updated, the other will go stale.

**Fix direction:** Have the hook read the gates list from `rules/godmode-quality.md` (or some structured source) at runtime.

## Medium — drift and consistency

### 10. Plugin metadata version (`1.6.0`) does not match installer version (`1.4.1`)

- `.claude-plugin/plugin.json:4` declares `"version": "1.6.0"`.
- `install.sh:8` declares `VERSION="1.4.1"`.
- `commands/godmode.md:13` says `# Claude God-Mode v1.4.1`.

These three should not disagree.

**What goes wrong:** The plugin registry advertises 1.6.0; users running `./install.sh` write `1.4.1` to `~/.claude/.claude-godmode-version`; CHANGELOG and README claims may be inconsistent.

**Fix direction:** Single source of truth. Either bump `install.sh` and `commands/godmode.md` to `1.6.0`, or bump only one and pull from it everywhere (e.g., `install.sh` reads version from `.claude-plugin/plugin.json` via `jq`).

### 11. Manual-mode hook bindings and plugin-mode hook bindings are maintained in two files

- Manual mode: `config/settings.template.json:91-111`.
- Plugin mode: `hooks/hooks.json`.

Both list `SessionStart` and `PostCompact`. If a third hook is ever added, both files must be updated.

**Fix direction:** Generate one from the other at install time, or document the duplication explicitly with a comment.

### 12. `hooks.json` (plugin mode) sets a `timeout: 10`; `settings.template.json` (manual mode) does not

`hooks/hooks.json:10` and `:21` both pass `"timeout": 10`. The manual-mode binding (`config/settings.template.json:91-111`) omits `timeout`, so manual users get Claude Code's default (currently 60s).

**What goes wrong:** A hook that hangs (e.g. waiting on a slow `git log`) blocks session start or compaction recovery for longer in manual mode than in plugin mode. Inconsistent UX.

**Fix direction:** Add `"timeout": 10` to the manual-mode binding.

## Medium — disk and lifecycle hygiene

### 13. Backup accumulation in `~/.claude/backups/`

`install.sh:11-12` creates a fresh `godmode-<timestamp>/` directory on every run. There is no rotation, no cap, no cleanup hook.

**What goes wrong:** Frequent reinstalls (or a CI loop) silently fill `~/.claude/backups/`. For one user this is small; for a developer who reinstalls weekly, it's measurable over years.

**Fix direction:** Keep the last N backups (e.g. 5), prune older ones at install time. `uninstall.sh:124` already finds the latest backup with `sort -r | head -1`, so the cap pattern fits naturally.

### 14. `.claude/worktrees/` not cleaned up

The repo currently contains 27 directories under `.claude/worktrees/` totaling ~6.4 MB. These are leftovers from agent isolation runs. There's no documented cleanup command, no `.gitignore` rule for them — they aren't committed (they don't appear in `git status`) but they do live on disk.

**What goes wrong:** Slow accumulation, occasional confusion when a worktree is mistakenly inspected as if it were live.

**Fix direction:** Add a periodic cleanup script, document a `git worktree prune` recipe in CONTRIBUTING.md, or have the agent system delete worktrees on completion.

### 15. `.claude-pipeline/archive/` keeps every completed cycle forever

`.claude-pipeline/archive/` contains 8 archived cycles (296 KB). Same pattern as backups — useful history, but unbounded growth.

**Fix direction:** Document expected hygiene; consider a maximum count.

## Low — fragile assumptions and minor gotchas

### 16. `.DS_Store` files committed in subdirs

`.gitignore:1` lists `.DS_Store`, but `skills/.DS_Store` (8196 bytes, mtime Apr 24) is on disk and likely tracked. `git status` would confirm; if tracked, it's noise on cross-platform clones.

**Fix direction:** `find . -name .DS_Store -exec git rm --cached {} \;` once, then trust `.gitignore`.

### 17. `install.sh` requires `jq` but does not install it

`install.sh:26` errors out if `jq` is missing. Fine for explicit dependency, but the README should make this prominent — Linux users without `jq` will fail late, not at the README stage.

**Fix direction:** Document `jq` prerequisite at the top of README and in the plugin manifest.

### 18. `set -euo pipefail` everywhere is good — except where stdin must be consumed

`hooks/session-start.sh:8` runs `cat > /dev/null` to consume stdin. Under `pipefail`, if Claude Code closes stdin before `cat` completes (rare but possible), the script aborts before doing useful work.

**Fix direction:** Allow `cat > /dev/null || true`. Same applies in `hooks/post-compact.sh:8`.

### 19. `statusline.sh` swallows all errors silently

`config/statusline.sh:22-25` uses `2>/dev/null || echo "—"` for every `jq` call. That's appropriate for a statusline (don't break the prompt) but it also masks any genuine breakage, e.g. if Claude Code's status JSON shape changes.

**Fix direction:** Optionally log to a debug file (`/tmp/godmode-statusline.log`) when input parsing fails, so issues are diagnosable without breaking the line.

### 20. No automated test coverage at all

See `TESTING.md`. The project has no `bats`, no `shellcheck` in CI, no JSON schema validation, and no GitHub Actions workflow. Every concern in this document would be much cheaper to catch with even a minimal test suite.

**Fix direction:** Start with `shellcheck` in CI (one workflow file, ~10 minutes of setup) — it would surface several of the fragility items above without writing a single new test.

### 21. README and CHANGELOG drift

`README.md` is 18 KB, last touched 2026-04-04. `CHANGELOG.md` last touched 2026-04-04. Plugin metadata claims 1.6.0; installer says 1.4.1. There's likely doc-vs-code drift.

**Fix direction:** Audit README + CHANGELOG against actual `agents/`, `skills/`, `commands/` lists at version-bump time.

## Security

The codebase distributes shell scripts that run during Claude Code sessions and at install time. Real concerns are limited because:

- Hooks run with the user's own permissions (no escalation).
- No network calls except via Claude Code's permitted commands.
- Permissions list (`config/settings.template.json:7-89`) is curated and includes a deny-list (`Bash(rm -rf /)`, `Bash(git push --force *)`, `Bash(* DROP TABLE *)`, etc.) — though deny rules pattern-matching is fragile and easy to bypass with creative quoting.

**Watch items:**

- **Permission deny patterns are pattern-matched, not parsed.** `Bash(rm -rf /)` blocks the literal substring; `rm   -rf  /` (extra spaces) or `rm -r -f /` would not match. This is Claude Code's behavior, not this repo's bug, but it's worth surfacing.
- **No file-permission setting on installed files.** `install.sh:199` does `chmod +x` on hook scripts; rules and agents are world-readable by default umask. On multi-user systems, sensitive notes a user puts into a rule file are readable by other users on the same machine.
- **No signature / checksum verification.** `install.sh` runs whatever `rules/godmode-*.md` is on disk. A user who clones an untrusted fork has no in-repo way to verify they got the upstream content.

**Fix directions:**
- Document the permission-pattern caveat in README.
- Set restrictive permissions (`chmod 600`) when copying rule files.
- Optionally publish a checksums file (`SHA256SUMS`) and have `install.sh` verify it.

## Performance

Not a meaningful concern at this scale. Installation runs in under a second on a modern machine. Hooks run in <100 ms typically; the 10-second timeout in `hooks/hooks.json` is plenty. Statusline runs every render; `jq` is invoked four times per render (`config/statusline.sh:22-25`), which is fine but could be collapsed into one `jq` invocation if anyone profiles it as hot.

---

*Concerns analysis: 2026-04-25*
