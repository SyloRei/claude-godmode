# `scripts/` — bundled deterministic helpers

## Purpose

`scripts/` holds bundled deterministic helpers that this skill's `SKILL.md`
*invokes* rather than re-derives in prose. The goal is mechanical enforcement
over instruction: load-bearing logic lives in a versioned, tested script the
skill runs, not in prose the model re-improvises (and risks drifting) each run.

## Path resolution

A skill resolves a bundled script across the three install modes, in this order:

1. `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/scripts/<name>` — plugin install
2. `$HOME/.claude/skills/<skill>/scripts/<name>` — manual `~/.claude` install
3. `skills/<skill>/scripts/<name>` — repo-relative (running from a checkout)

Use the first path that exists.

## Quality bar

Every script under `scripts/`:

- is `shellcheck`-clean (pinned v0.11.0, respecting the repo `.shellcheckrc`),
- is POSIX / bash-3.2 compatible (no bashisms newer than 3.2), and
- is covered by a bats test under `tests/`.

## Intended scripts

- `roadmap-renumber.sh` — renumber roadmap units after an insert or
  reorder, keeping references consistent. **Planned / not yet implemented.**
