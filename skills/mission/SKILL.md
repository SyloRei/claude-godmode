---
name: mission
description: "Initialize project planning: PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, config.json from a 5-question Socratic flow. Idempotent on returning project."
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - AskUserQuestion
---

# /mission

## Connects to

- **Upstream:** /godmode (when `.planning/` does not exist)
- **Downstream:** /brief 1 (after init completes)
- **Reads from:** `${CLAUDE_PLUGIN_ROOT}/templates/.planning/*.tmpl`
- **Writes to:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, `.planning/config.json`

## Auto Mode check

Scan the most recent system reminder for the case-insensitive substring "Auto Mode Active".

When detected:
- Skip per-question prompts; pick the most plausible default for each answer.
- Use the basename of `git rev-parse --show-toplevel` (or `pwd`) as the project name fallback, run through `godmode_slug`.
- Idempotency takes precedence — never overwrite an existing `.planning/PROJECT.md`.
- Surface assumptions inline in PROJECT.md so the user can audit and edit.

See `rules/godmode-skills.md` § Auto Mode Detection for the full convention.

---

## The Job

1. Idempotency check (refuse if `.planning/PROJECT.md` exists).
2. Walk 5 Socratic questions (or apply Auto Mode defaults).
3. Materialize 5 project-level files from templates via `sed -e 's|{{var}}|val|g'`.
4. Update `.planning/STATE.md` to `status: Ready to brief`, `next_command: /brief 1` via the canonical state mutator.
5. Tell the user: "Run `/brief 1` to start the first brief."

---

## Step 1: Idempotency check

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/_lib.sh"

if [ -f .planning/PROJECT.md ]; then
  info "Project already missioned. Run /godmode for status, or rm .planning/PROJECT.md to re-mission."
  exit 0
fi
```

Auto Mode does NOT bypass this check — re-missioning is always explicit.

---

## Step 2: Five Socratic questions

Ask one at a time via `AskUserQuestion` in non-Auto Mode. In Auto Mode, batch all 5 with sensible defaults; surface assumptions inline in PROJECT.md so the user can audit.

1. **Project name** — kebab-case slug + display title.
   - Auto Mode default: `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` → run through `godmode_slug`. Display title: title-case the slug (replace `-` with space, capitalize words).

2. **Core value statement** — one-line "if everything else fails this must hold" sentence.
   - Auto Mode default: "Ship features that work."

3. **Tech stack constraints** — free-form (single-line per template constraint).
   - Auto Mode default: detect from existing files (`package.json` → "Node.js"; `Cargo.toml` → "Rust"; `pyproject.toml` → "Python"; else "TBD — please edit").

4. **Initial milestone** — name + 1-3 sentence goal.
   - Auto Mode default: name = `"v0.1.0"`; goal = "Working baseline."

5. **Initial brief decomposition** — 3-5 brief titles for the milestone (one per line).
   - Auto Mode default: ["Foundation", "Core feature 1", "Core feature 2"].

Validate each answer before substitution:
- Project name → `godmode_slug "$ANSWER"` must produce a non-empty slug.
- All values must be single-line: must NOT contain `|`, `}}`, backslash, or embedded newline (template constraint).
- If validation fails in non-Auto: re-ask. In Auto: substitute the validated default and note the substitution inline in PROJECT.md.

---

## Step 3: Materialize 5 files from templates

Once all 5 answers are in shell variables, materialize:

```bash
TEMPLATES="$ROOT/templates/.planning"

if [ ! -d "$TEMPLATES" ]; then
  error "Templates not found at $TEMPLATES — reinstall the plugin."
fi

DATE=$(date -u +%Y-%m-%d)
FIRST_BRIEF_TITLE=$(printf '%s' "$BRIEF_LIST" | head -1)
FIRST_BRIEF_SLUG=$(godmode_slug "$FIRST_BRIEF_TITLE")
BRIEF_TITLES_RENDERED=$(printf '%s' "$BRIEF_LIST" | sed 's/^/- /')
MODEL_PROFILE="${CLAUDE_PLUGIN_OPTION_MODEL_PROFILE:-balanced}"

mkdir -p .planning

# PROJECT.md
sed -e "s|{{project_name}}|$PROJECT_NAME|g" \
    -e "s|{{display_title}}|$DISPLAY_TITLE|g" \
    -e "s|{{core_value}}|$CORE_VALUE|g" \
    -e "s|{{tech_stack}}|$TECH_STACK|g" \
    -e "s|{{milestone_name}}|$MILESTONE_NAME|g" \
    -e "s|{{date}}|$DATE|g" \
    "$TEMPLATES/PROJECT.md.tmpl" > .planning/PROJECT.md

# REQUIREMENTS.md
sed -e "s|{{milestone_name}}|$MILESTONE_NAME|g" \
    -e "s|{{date}}|$DATE|g" \
    "$TEMPLATES/REQUIREMENTS.md.tmpl" > .planning/REQUIREMENTS.md

# ROADMAP.md
# brief_titles is multi-line; BSD awk forbids newlines in `-v` values, so we
# splice the block in by writing the rendered list to a temp file and using
# awk to substitute on the placeholder line.
BRIEF_TMP=$(mktemp -t godmode-brief-titles.XXXXXX)
printf '%s\n' "$BRIEF_TITLES_RENDERED" > "$BRIEF_TMP"

# First pass: substitute single-line vars via sed.
# Second pass: replace the {{brief_titles}} placeholder line with the file body.
sed -e "s|{{display_title}}|$DISPLAY_TITLE|g" \
    -e "s|{{milestone_name}}|$MILESTONE_NAME|g" \
    -e "s|{{date}}|$DATE|g" \
    "$TEMPLATES/ROADMAP.md.tmpl" \
  | awk -v f="$BRIEF_TMP" '
      /\{\{brief_titles\}\}/ {
        while ((getline line < f) > 0) print line
        close(f); next
      }
      { print }
    ' > .planning/ROADMAP.md
rm -f "$BRIEF_TMP"

# STATE.md (initial seed; will be re-written by godmode_state_update below for canonical audit-line append)
sed -e "s|{{active_brief}}|1|g" \
    -e "s|{{active_brief_slug}}|$FIRST_BRIEF_SLUG|g" \
    -e "s|{{status}}|Ready to brief|g" \
    -e "s|{{next_command}}|/brief 1|g" \
    -e "s|{{last_activity}}|Project missioned|g" \
    -e "s|{{date}}|$DATE|g" \
    "$TEMPLATES/STATE.md.tmpl" > .planning/STATE.md

# Strip the leading <!-- TEMPLATE VARIABLES ... --> comment block from STATE.md (the template's
# own note says the HTML comment is stripped before write; only the YAML+md hybrid ships).
awk 'BEGIN{skip=1} /^---$/ && skip {skip=0} !skip {print}' .planning/STATE.md > .planning/STATE.md.tmp \
  && mv .planning/STATE.md.tmp .planning/STATE.md

# config.json
sed -e "s|{{model_profile}}|$MODEL_PROFILE|g" \
    "$TEMPLATES/config.json.tmpl" > .planning/config.json
```

**Validation discipline (D-20 single-line constraint):** every user-typed value must reject `|`, `}}`, backslash, and embedded newline BEFORE entering sed. Reject and re-ask in non-Auto; substitute default in Auto.

---

## Step 4: Confirm STATE seed via the canonical mutator

The `sed`-generated STATE.md is correct, but to keep mutation discipline consistent and append the canonical audit line, also run `godmode_state_update`:

```bash
source "$ROOT/skills/_shared/state.sh"
godmode_state_update 1 "$FIRST_BRIEF_SLUG" "Ready to brief" "/brief 1" "Project missioned"
```

The mutator is idempotent — its atomic-replace preserves the file structure. The audit log gains one canonical `YYYY-MM-DD — Project missioned` entry below the seed entry from the template.

---

## Step 5: Tell the user what to do next

```bash
info "Project missioned. Wrote 5 files under .planning/."
info "Run /brief 1 to start the first brief: '$FIRST_BRIEF_TITLE'"
```

---

## Constraints

- **Single-line value enforcement:** `|`, `}}`, backslash, and embedded newline are rejected on every Socratic answer before substitution.
- **Template path resolution:** `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/templates/.planning/`. If the templates directory is missing, error with "Templates not found at $TEMPLATES — reinstall the plugin."
- **Vocabulary discipline:** this skill body uses the v2 chain words (`brief`, `mission`, `milestone`, `plan`, `build`, `verify`, `ship`). The v1.x leakage tokens enumerated in `rules/godmode-skills.md` and enforced by the Phase 5 CI vocabulary gate must not appear in user-facing prose.
- **No agent dispatch:** `/mission` is purely Socratic + sed substitution. It does NOT spawn agents — that begins at `/brief N`.
- **Frontmatter discipline:** no `model:` or `effort:` keys (those live on agents); no `argument-hint` / `arguments` (mission takes no `N`).
