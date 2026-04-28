# claude-godmode

> Senior engineering team, in a plugin.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude_Code-2.1.111+-blueviolet)](https://docs.claude.com/en/docs/claude-code)

A Claude Code plugin that makes Claude behave like a senior engineering team out of the box. One workflow chain. 11 user-facing slash commands. Mechanical quality gates. Bash 3.2 + jq only — no Node, no Python, no SDK.

## Quick start (2-minute tutorial)

1. **Install** (one of two paths — see [Installation](#installation) for full options):

   ```bash
   git clone https://github.com/sylorei/claude-godmode.git
   cd claude-godmode && ./install.sh
   ```

2. **Open Claude Code** in any repo you own.

3. **Type** `/godmode`. Within 5 lines, you'll see what to do next.

4. **Initialize a project** with `/mission`. Answers a 5-question Socratic flow, writes `.planning/{PROJECT,REQUIREMENTS,ROADMAP,STATE}.md`.

5. **Follow the chain**: `/brief 1 → /plan 1 → /build 1 → /verify 1 → /ship`. Each command leaves a single auditable artifact and atomic commits in your git log.

That's the whole onboarding. Re-run `/godmode` any time you lose context — it reads `.planning/STATE.md` and tells you the next command.

## What you get

A single, opinionated workflow where every agent, skill, and tool is connected and named for your intent. The chain renders directly from the live filesystem — no hardcoded lists, no registry edits to upgrade. Auto Mode aware: every workflow skill detects continuous-execution context and picks reasonable defaults instead of asking. Hook gates are mechanical (PreToolUse blocks `--no-verify`, PostToolUse surfaces failed exit codes). Plugin-mode and manual-mode installs are parity-tested in CI.

```
/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship
+ helpers: /debug  /tdd  /refactor  /explore-repo
```

## Installation

Two paths, same result. Both write to `~/.claude/`. Plugin-mode and manual-mode are byte-equivalent on hooks, permissions, and timeouts (CI parity gate enforces).

### Plugin marketplace

Open Claude Code. Browse the plugin marketplace. Install `claude-godmode`. Restart Claude Code. Done. The marketplace listing carries the canonical version metadata; updates are one click.

### Manual install

```bash
git clone https://github.com/sylorei/claude-godmode.git
cd claude-godmode
./install.sh             # idempotent; per-file diff/skip/replace prompt for customizations
./install.sh --force     # accept all replacements without prompting
```

The installer backs up your `~/.claude/` to `~/.claude/backups/godmode-<timestamp>/` (last 5 retained), then merges. Your `~/.claude/CLAUDE.md` is never read or modified. Settings merge is deep — top-level keys you've added are preserved.

To remove: `./uninstall.sh`. Refuses on version mismatch unless `--force`.

## The /godmode arrow chain

One artifact per skill. The git log is the execution log.

- `/godmode` — orient: prints "what now?" in ≤5 lines, reading `.planning/STATE.md`.
- `/mission` — initialize a project's `.planning/` artifacts (`PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`) via a 5-question Socratic flow. Idempotent on returning projects.
- `/brief N` — Socratic brief authoring → `.planning/briefs/NN-name/BRIEF.md` (why + what + falsifiable spec). Spawns `@spec-reviewer`.
- `/plan N` — tactical breakdown → `.planning/briefs/NN-name/PLAN.md` (atomic items + verification status). Spawns `@planner`.
- `/build N` — wave-based parallel execution; one atomic commit per item with `[brief NN.M]` token. Dispatches `@executor` per item; polls `.build/` markers.
- `/verify N` — goal-backward verification by `@verifier` (read-only). Reports COVERED / PARTIAL / MISSING per success criterion; mutates the plan's `## Verification status` section in place.
- `/ship` — runs the 6 quality gates from `config/quality-gates.txt`, refuses on PARTIAL/MISSING (unless `--force`), pushes, opens a PR via `gh pr create`. Never auto-forces under Auto Mode.
- `/debug` — structured debug protocol: reproduce → isolate → fix → verify (helper).
- `/tdd` — test-first development: red → green → refactor (helper).
- `/refactor` — safe refactoring with test verification: identify smell → propose change → verify behavior (helper).
- `/explore-repo` — deep read-only repo exploration in a forked context (helper).

## Auto Mode

When Claude Code is in Auto Mode (`permission_mode: "auto"`), every workflow skill detects the `## Auto Mode Active` system reminder and routes accordingly. `/build` and `/ship` skip confirmation prompts and proceed on default choices. `/brief` and `/plan` pick reasonable defaults rather than asking clarifying questions, surfacing assumptions inline. Helpers (`/debug`, `/refactor`, `/tdd`, `/explore-repo`) drop their clarifying-question loops. Course-corrections at any point are treated as normal input. Auto Mode is not a license to destroy — destructive operations (deleting data, force-pushing) still pause for confirmation.

## Customization

Behavior comes from rule files in `~/.claude/rules/`. Edit, remove, or add files freely — the rules system loads everything it finds.

- **Edit** `~/.claude/rules/godmode-*.md` to change a specific concern (identity, quality gates, routing, etc.). Each file is one concern; they don't fight.
- **One user-tunable knob:** `userConfig.model_profile` in `.claude-plugin/plugin.json` selects `quality | balanced | budget`. Substituted into hook commands as `${user_config.model_profile}` and exported as `CLAUDE_PLUGIN_OPTION_MODEL_PROFILE` to subprocesses.
- **Author your own** agents, skills, hooks, or rules — see [CONTRIBUTING.md](CONTRIBUTING.md) for the file shapes and frontmatter contracts.

Your personal `~/.claude/CLAUDE.md` is never read, modified, or replaced.

## Troubleshooting

- **`bash: 3.2.x` is fine.** The plugin is bash 3.2 portable by design — no `mapfile`, no associative arrays, no GNU-only flags.
- **`jq: command not found`** — install via `brew install jq` (macOS) or `sudo apt install jq` (Debian/Ubuntu). The plugin requires `jq` 1.6+.
- **Reinstall overwrote my customization** — non-TTY default keeps customizations. If you ran with `--force`, your prior copy is in `~/.claude/backups/godmode-<timestamp>/`.
- **Hooks not firing** — verify `~/.claude/settings.json` has the `hooks` block. Re-run `./install.sh` to re-merge.
- **Statusline not showing** — restart Claude Code; the statusline registers at session start.
- **`/godmode` says "no project found"** — run `/mission` first to initialize `.planning/`.
- **Hook output looks corrupted under adversarial branch names** — fixed in v2; if you're seeing this, you're on v1.x. Reinstall.

## FAQ

- **How is this different from other Claude Code plugins?** One workflow chain (not a kit), mechanical quality gates (PreToolUse + PostToolUse hooks block bypass), bash + jq only at runtime (no Node, no Python, no helper binary).
- **Does it work on Windows?** WSL2: yes. Native PowerShell: no — out of scope. The bash 3.2 floor is firm.
- **Can I cherry-pick individual skills?** No. The plugin is intentionally cohesive — every skill expects the others to exist. Cherry-picking breaks the chain assumption.
- **How do I upgrade from v1.x?** Re-run `./install.sh`. v1.x deprecation banners on the old skill names guide migration; the installer detects the old layout and prompts.
- **Where do I file bugs?** [github.com/sylorei/claude-godmode/issues](https://github.com/sylorei/claude-godmode/issues).
- **Does it phone home?** Never. No telemetry. No network calls outside the tools you authorize.
- **What is the license?** MIT — see [LICENSE](LICENSE). No copyleft dependencies.

## Contributing & development

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
