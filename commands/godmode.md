---
name: godmode
description: "Orient: 'what now?' in ≤5 lines (state-aware). Live-lists agents/skills/briefs from filesystem. /godmode statusline configures the status bar."
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---

# /godmode

## Connects to

- **Upstream:** (entry point — bootstrap and orientation command)
- **Downstream:** /mission (when no .planning/), /brief N | /plan N | /build N | /verify N | /ship (state-aware)
- **Reads from:** `.planning/STATE.md`, `.planning/config.json`, `.planning/briefs/*/`, `${CLAUDE_PLUGIN_ROOT}/agents/`, `${CLAUDE_PLUGIN_ROOT}/skills/`
- **Writes to:** `~/.claude/rules/` (bootstrap install only), `~/.claude/settings.json` (statusline subcommand only)

## Auto Mode check

Before proceeding, scan the most recent system reminder for the case-insensitive
substring "Auto Mode Active". If detected:
- Auto-approve routine decisions (e.g., default-Y on "install rules?" prompt).
- Pick recommended defaults for ambiguity.
- Never enter plan mode unless explicitly asked.
- Treat user course corrections as normal input.

See `rules/godmode-skills.md` § Auto Mode Detection for the full convention.

---

Check the user's message:
- If it contains the word `statusline` (e.g., `/godmode statusline`), go to **StatusLine Setup** below.
- Otherwise, run **Rules Check** then show the **Orient** answer.

---

## Rules Check (runs automatically)

Before showing Orient, silently check whether godmode rules are installed:

```bash
ls ~/.claude/rules/godmode-identity.md 2>/dev/null && echo "rules_installed" || echo "rules_missing"
```

**If rules are missing:**

1. Tell the user:
   ```
   God-Mode rules are not installed yet. Rules provide coding standards, quality
   gates, workflow guidance, and agent routing that make the system work at full
   capacity.

   Without rules, agents and skills still work but won't follow godmode conventions.
   ```

2. Ask: "Install godmode rules to ~/.claude/rules/? [Y/n]"

3. If user confirms (or presses Enter for default Y, or Auto Mode is active):
   - Resolve the plugin root: `ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"`
   - If `CLAUDE_PLUGIN_ROOT` is set, copy from there:
     ```bash
     mkdir -p ~/.claude/rules && cp "${CLAUDE_PLUGIN_ROOT}/rules/godmode-"*.md ~/.claude/rules/
     ```
   - If `CLAUDE_PLUGIN_ROOT` is empty (manual install), check if the repo `rules/` dir exists relative to the command file and copy from there.
   - Report: "Installed N rule files to ~/.claude/rules/. They'll be active in your next session."

4. If user declines: "Skipping. Run /godmode anytime to install rules later."

**If rules are already installed:** Skip silently, proceed to Orient.

---

## Orient (≤5 lines)

Source the shared state helper and emit the state-aware "what now?" answer. Hard cap: ≤5 lines. The inventory below the answer is rendered by live `find` over `${CLAUDE_PLUGIN_ROOT}/agents/` and `${CLAUDE_PLUGIN_ROOT}/skills/` — never hardcoded (HI-02).

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/init-context.sh"
CTX=$(godmode_init_context "$PWD")

PLANNING_EXISTS=$(printf '%s' "$CTX" | jq -r '.planning.exists')
STATE_EXISTS=$(printf '%s' "$CTX" | jq -r '.state.exists')

if [ "$PLANNING_EXISTS" != "true" ] || [ "$STATE_EXISTS" != "true" ]; then
  echo "No .planning/. Run /mission to start."
  echo "Agents: $(find "$ROOT/agents" -maxdepth 1 -name '*.md' -not -name '_*' -not -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
  echo "Skills: $(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -not -name '_*' 2>/dev/null | wc -l | tr -d ' ')"
  echo "Branch: $(git branch --show-current 2>/dev/null || echo unknown)"
  exit 0
fi

# State exists — render the active answer
N=$(printf '%s' "$CTX" | jq -r '.state.active_brief // "?"')
SLUG=$(printf '%s' "$CTX" | jq -r '.state.active_brief_slug // "?"')
STATUS=$(printf '%s' "$CTX" | jq -r '.state.status // "Not started"')
NEXT=$(printf '%s' "$CTX" | jq -r '.state.next_command // "/mission"')
LAST=$(printf '%s' "$CTX" | jq -r '.state.last_activity // "—"' | cut -c1-40)
BRIEFS=$(printf '%s' "$CTX" | jq -r '.briefs | length')

# Line 1: the answer
echo "Brief $N: $SLUG. Status: $STATUS. Next: $NEXT."
# Lines 2-4: live inventory (HI-02 — never hardcoded)
echo "Agents: $(find "$ROOT/agents" -maxdepth 1 -name '*.md' -not -name '_*' -not -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')  Skills: $(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -not -name '_*' 2>/dev/null | wc -l | tr -d ' ')  Briefs: $BRIEFS"
echo "Last: $LAST"
echo "Branch: $(git branch --show-current 2>/dev/null || echo unknown)"
```

Total: 4 lines when state exists (answer / inventory / Last / Branch); 4 lines when no .planning/ (No .planning / Agents / Skills / Branch). Both ≤5.

If the user asks for the chain graph (`/godmode chain` or asks "show the connects-to graph"), render via:

```bash
grep -A 20 '^## Connects to' "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/commands/godmode.md" "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/skills/"*/SKILL.md 2>/dev/null
```

No registry. No hardcoded chain. Pure FS scan.

---

## StatusLine Setup

Configure the God-Mode statusline that shows project name, git branch, model, context usage %, and session cost.

Follow these steps in order:

### Step 1: Check current status

Read `~/.claude/settings.json` and check if a `statusLine` key already exists.

- If `statusLine` **already exists**, tell the user what it's currently set to and ask:
  - "Replace with God-Mode statusline?" → Continue to Step 2
  - "Keep current statusline" → Exit, tell the user their statusline is unchanged

- If `statusLine` **does not exist**, tell the user you'll configure it now and continue to Step 2.

- If `~/.claude/settings.json` **does not exist**, create it in Step 2.

### Step 2: Resolve the statusline script path

Determine the path to the statusline script. Run:

```bash
echo "${CLAUDE_PLUGIN_ROOT}/config/statusline.sh"
```

If `CLAUDE_PLUGIN_ROOT` is empty or unset (manual install), use `~/.claude/hooks/statusline.sh` as the fallback path.

Verify the script exists at the resolved path:

```bash
test -f "<resolved_path>" && echo "found" || echo "not_found"
```

If not found, tell the user the statusline script is missing and exit.

### Step 3: Update settings.json

Read `~/.claude/settings.json` (or start with `{}`). Add or replace the `statusLine` key:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <resolved_path>"
  }
}
```

**Important:** Preserve all existing settings. Only add/update the `statusLine` key. Use the Edit tool on the existing file, or Write if creating from scratch.

### Step 4: Verify

Tell the user:

```
StatusLine configured! Restart Claude Code to see it.

Your statusline shows: project | branch | model | context usage % | cost

To reconfigure later, run /godmode statusline
```
