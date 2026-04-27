# Skills Convention (v2)

This rule documents the v2 user-facing skill surface, frontmatter convention, body
structure, Auto-Mode detection, and shared state-helper sourcing pattern. Every
v2 skill author and reviewer reads this rule.

Skills live in `commands/godmode.md` (the lone command file) and `skills/<name>/SKILL.md`
(everything else). Internal documents — this rule, agents under `agents/`, and rules
under `rules/godmode-*.md` — describe the convention; user-facing skill bodies follow it.

---

## Surface Cap

The v2 user-invocable surface is **exactly 11 skills**, capped at 12, with **1
slot reserved**:

```
/godmode      → orient, "what now?" in ≤5 lines
/mission      → initialize / update PROJECT.md + ROADMAP.md
/brief N      → Socratic brief: why + what + spec → BRIEF.md
/plan N       → tactical breakdown → PLAN.md
/build N      → wave-based parallel execution, atomic commits per task
/verify N     → goal-backward verification, COVERED/PARTIAL/MISSING report
/ship         → quality gates, push, gh pr create

Helpers (cross-cutting, no number argument):
  /debug    /tdd    /refactor    /explore-repo
```

The arrow chain `/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship`
is the single happy path. `/godmode` reads `.planning/STATE.md` and points at the
next command.

> **Slot 12 is reserved.** Adding a 12th skill is a v2.x decision requiring an
> explicit RFC; the cap exists to keep the surface scannable.

The CI vocabulary gate (Phase 5 / QUAL-04) verifies this surface cap by counting
`commands/*.md` plus `skills/*/SKILL.md` and asserting the total is ≤12.

---

## Frontmatter Convention

Every v2 user-invocable skill declares — in this **exact order** — the following
keys in its YAML frontmatter:

1. **`name:`** — lowercase, hyphens only, mirrors directory name (or filename for
   `commands/`). Example: `name: brief`.
2. **`description:`** — one stated goal, ≤200 chars; affects discovery in the
   marketplace. Front-load the key use case (the description + `when_to_use` is
   truncated at 1,536 characters in the skill listing).
3. **`user-invocable: true`** — explicit; the rule applies only to user-invocable
   skills.
4. **`allowed-tools:`** — scoped per skill; **never** the wildcard set. See the
   per-skill allowlist guidance below.
5. **`argument-hint: "[N]"`** — only on the four parameterized skills (`/brief`,
   `/plan`, `/build`, `/verify`).
6. **`arguments: [N]`** — declared on the same four; the body then reads `$N`
   (not `$ARGUMENTS[0]`).
7. **`disable-model-invocation: true`** — only on side-effecting skills (`/build`,
   `/ship`). The user must invoke explicitly.

**Omitted keys (intentionally):**

- **`model:`** and **`effort:`** are NOT declared at the skill level. Per Phase 2's
  locked policy, model + effort are owned by the agent the skill spawns; double-
  controlling at skill level creates drift. Internal docs (`agents/<name>.md`) carry
  these keys.
- `paths:` — unused in v2.0 (skills don't auto-activate on path globs).
- `context: fork` / `agent:` — used only on `/explore-repo` (read-only research).

**Recommended `allowed-tools` per skill** (per RESEARCH § "Recommended `allowed-tools`"):

| Skill | allowed-tools |
|-------|---------------|
| `/godmode` | `Bash, Read, Write, Edit, AskUserQuestion` (Write needed for rules-bootstrap) |
| `/mission` | `Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion` |
| `/brief` | `Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, Task` |
| `/plan` | `Read, Write, Edit, Bash, Grep, Glob, Task` |
| `/build` | `Read, Write, Edit, Bash, Grep, Glob, Task` (+ `disable-model-invocation: true`) |
| `/verify` | `Read, Write, Edit, Bash, Grep, Glob, Task` |
| `/ship` | `Read, Bash, Grep, Glob, Task` (+ `disable-model-invocation: true`) |
| `/debug` | `Read, Bash, Grep, Glob` |
| `/tdd` | `Read, Write, Edit, Bash, Grep, Glob, Task` |
| `/refactor` | `Read, Write, Edit, Bash, Grep, Glob` |
| `/explore-repo` | `Read, Bash, Grep, Glob` (read-only) |

---

## `Connects to` Body Section

Every workflow skill body includes a `## Connects to` section **right after the
H1 title** (before any other content), structurally identical to the agent
convention:

```markdown
## Connects to
- **Upstream:** <previous skill in arrow chain or "(entry point)">
- **Downstream:** <next skill or agent it spawns>
- **Reads from:** <files it consumes>
- **Writes to:** <files it produces>
```

`/godmode` renders the chain at runtime by:

```bash
grep -A 20 '^## Connects to' commands/godmode.md skills/*/SKILL.md
```

No registry, no hardcoded list — drift is impossible because the chain is
parsed from the live filesystem.

---

## Auto Mode Detection

Detect Auto Mode by scanning system reminders for "Auto Mode Active" (case-insensitive).
When detected:
 - Auto-approve routine decisions (e.g., file overwrite confirms in `/mission`).
 - Pick recommended defaults for ambiguity (don't ask).
 - Never enter plan mode unless the user explicitly asked.
 - Course corrections from the user are normal input — handle without complaint.

The 7 workflow skills (`/godmode`, `/mission`, `/brief`, `/plan`, `/build`,
`/verify`, `/ship`) **MUST** include this block at the top of the body (right
after `## Connects to`). The 4 helpers (`/debug`, `/tdd`, `/refactor`,
`/explore-repo`) **SHOULD** include it. Phase 5's vocabulary gate greps
`commands/` + `skills/*/SKILL.md` for the canonical detection phrase to enforce
the contract.

---

## Recommended Defaults Under Auto Mode

When Auto Mode is active, each skill picks the recommended default rather than
prompting:

| Skill | Auto-Mode behavior |
|-------|--------------------|
| `/mission` | Scaffold all 5 project files using sensible defaults; if the user later objects, `/mission` is idempotent enough to re-run. |
| `/brief N` | Pick the first plausible interpretation of the user's intent; surface assumptions inline in BRIEF.md so they can be edited. |
| `/plan N` | Produce a single-wave plan unless 3+ atomic tasks exist that don't depend on each other — then promote to wave-2. |
| `/build N` | Skip the "preview wave plan" confirmation; proceed. |
| `/verify N` | Report COVERED/PARTIAL/MISSING without asking for clarification. |
| `/ship` | Run the 6 gates; refuse on PARTIAL/MISSING; **never** auto-`--force`. |

Under Auto Mode, recommended-default selection must match what a user would
actually want — never auto-pick a destructive option just because it's first
in a list (PITFALLS CR-06).

---

## State Helper Sourcing Convention

Workflow skills `source` two shared helpers to read and mutate state. Read path
is side-effect-free and safe from any skill (including the read-only `/godmode`):

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
source "$ROOT/skills/_shared/init-context.sh"
CTX=$(godmode_init_context "$PWD")
# Access fields via jq:
ACTIVE=$(printf '%s' "$CTX" | jq -r '.state.active_brief // empty')
STATUS=$(printf '%s' "$CTX" | jq -r '.state.status // "Not started"')
```

`godmode_init_context()` returns JSON conforming to schema_version 1. It NEVER
exits non-zero (sourcing it must not abort a calling skill that runs `set -e`).
On malformed STATE.md or absent `.planning/`, it emits a valid JSON blob with
`state.exists: false` so consumers can branch cleanly.

State **mutations** go through the sibling helper:

```bash
source "$ROOT/skills/_shared/state.sh"
godmode_state_update "$N" "$SLUG" "Ready to plan" "/plan $N" "Brief $N drafted"
```

`godmode_state_update()` rewrites `.planning/STATE.md` atomically (mktemp + jq -n
--arg + mv). The audit-log body is preserved verbatim; the new audit line is
appended (never edited in place — D-16 append-only contract). Skills NEVER write
to STATE.md by other means.

Splitting reads from writes makes the read path safe to source from any skill
without inadvertent side effects.

---

## See Also

- `rules/godmode-routing.md` — model + effort routing for agents the skills spawn.
- `rules/godmode-workflow.md` — workflow phases (UNDERSTAND/PLAN/EXECUTE/VERIFY/SHIP).
- `rules/godmode-quality.md` — quality gates (read from `config/quality-gates.txt`).
- `agents/<name>.md` — agent frontmatter (model + effort live here, not on skills).
