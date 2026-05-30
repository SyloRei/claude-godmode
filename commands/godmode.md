---
name: godmode
description: "Orient in five lines: where you are, what's done, and the exact next command to run. Reads workflow state and the live skill/agent inventory."
user-invocable: true
allowed-tools: Bash, Read
---

# /godmode — orient

Answer one question in **5 lines or fewer**: *where am I, what's done, and what is the single next command to run?* Derive everything below from the live filesystem and the recorded workflow state — never from a memorized list.

---

## 1. Resolve paths (plugin / manual / repo modes)

The same logic runs whether God-Mode is installed as a plugin, installed manually into `~/.claude/`, or run from a repo checkout. Resolve the plugin root, then the manifest:

```bash
# Plugin mode sets CLAUDE_PLUGIN_ROOT. Manual install lives under ~/.claude.
# Repo checkout: the command file's own tree. Pick the first that has plugin.json.
ROOT=""
for cand in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" "$(pwd)"; do
  [ -n "$cand" ] || continue
  if [ -f "$cand/.claude-plugin/plugin.json" ] || [ -d "$cand/agents" ]; then
    ROOT="$cand"
    break
  fi
done
[ -n "$ROOT" ] && echo "root: $ROOT" || echo "root: (unresolved — using repo-relative fallbacks)"
```

If `ROOT` stays empty, fall back to the repo-relative dirs `agents/`, `skills/`, `commands/` and `.claude-plugin/plugin.json` from the current working directory.

## 2. Read the canonical version

`.claude-plugin/plugin.json:.version` is the single source of truth — read it at runtime, never hardcode:

```bash
MANIFEST="$ROOT/.claude-plugin/plugin.json"
[ -f "$MANIFEST" ] || MANIFEST=".claude-plugin/plugin.json"
VERSION=$(jq -r '.version // "unknown"' "$MANIFEST" 2>/dev/null || echo "unknown")
echo "version: $VERSION"
```

## 3. Read the workflow state

`/mission` records the workflow keys via `bin/godmode-state` — including the active **mission** (`mission_id` + human-readable `mission_name`). Read them to derive the next action. Resolve the helper from the plugin root, then `~/.claude`, then the repo:

```bash
STATE_BIN=""
for cand in "$ROOT/bin/godmode-state" "$HOME/.claude/bin/godmode-state" "bin/godmode-state"; do
  if [ -x "$cand" ]; then STATE_BIN="$cand"; break; fi
done
if [ -n "$STATE_BIN" ] && [ -f .planning/STATE.md ]; then
  MISSION_ID=$("$STATE_BIN" get mission_id)
  MISSION_NAME=$("$STATE_BIN" get mission_name)
  ACTIVE=$("$STATE_BIN" get active_unit)
  STATUS=$("$STATE_BIN" get status)
  NEXT=$("$STATE_BIN" get next_command)
  echo "mission_id: $MISSION_ID"
  echo "mission_name: $MISSION_NAME"
  echo "active_unit: $ACTIVE"
  echo "status: $STATUS"
  echo "next_command: $NEXT"
else
  echo "cold_start: true"   # no .planning/STATE.md yet
fi
```

**Cold start** (no `.planning/STATE.md`, or no state recorded): the project has no recorded direction — there is no active mission yet. For an unfamiliar repo, recommend `/onboard` first to orient, then `/mission`; after that, `/brief 1`.

**Warm start**: `next_command` from state *is* the answer. If it is empty but `active_unit` is set, infer from `status` along the spine `/mission → /brief N → /plan N → /build N → /verify N → /ship`.

## 4. Scan the live inventory

Generate the available-command inventory by scanning the filesystem — **never** print a memorized list (it would drift as the repo evolves). Each skill directory under `skills/` and each `commands/*.md` is a slash command; each `agents/*.md` is an agent:

```bash
echo "skills:   $(ls -1 "$ROOT/skills" 2>/dev/null | grep -v '^_' | tr '\n' ' ')"
echo "commands: $(ls -1 "$ROOT/commands" 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')"
echo "agents:   $(ls -1 "$ROOT/agents" 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')"
```

If `$ROOT` is unresolved, run the same scan against the repo-relative `skills/`, `commands/`, `agents/` directories. The `grep -v '^_'` skips any internal `_`-prefixed skill directories.

## 5. Print the orientation (≤ 5 lines)

Compose at most five lines. Lead with the next command — it is the one thing the user came for. A good shape:

```
God-Mode v<VERSION> · <available-skill-count> skills, <agent-count> agents
Mission: <mission_id> (<mission_name>) · unit <active_unit> · next: <next_command>
Where: work unit <active_unit> — <status>     (or: "uninitialized — no roadmap yet")
Next:  <next_command>                         (cold start: /mission, then /brief 1)
Spine: /mission → /brief N → /plan N → /build N → /verify N → /ship
Helpers: <helper skills from the scan above — i.e. scanned skills minus the spine commands; never a memorized list>
```

The **Mission** line names the active mission from state (`mission_id` + `mission_name`) and the mission-scoped next command. On **cold start** there is no active mission, so omit the Mission line entirely and let the Next line point at `/mission`.

Keep the whole output well under 10,000 characters — five short lines is the target. Do not dump the full inventory tables; the scan counts and the next command are what matter. If the user wants the full list, point them at `/<command> --help` or the inventory scan above.

---

## Related

`/godmode` points users *into* the workflow — every pointer here is a next step it recommends.

- **/mission** — start the spine: name the mission and lay down the roadmap. The cold-start recommendation.
- **/brief N** — capture the why + what for the active work unit; the warm-start next step after a mission exists.
- **/ship** — the spine's final step, once a unit is built and verified.
- **skill add `<name>`** — scaffold a new helper skill from your terminal; run `bin/godmode-skill new <name>` (the `/godmode` orientation is read-only, so this one runs in the shell, not as a slash command).

**Spine:** `/mission` → `/brief N` → `/plan N` → `/build N` → `/verify N` → `/ship`. `/godmode` reads the recorded state and tells the user which step is next.
