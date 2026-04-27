---
name: plan-stories
description: "[Deprecated v2.0] Renamed to /plan N. See migration note below. Old behavior preserved for v1.x users mid-migration."
user-invocable: true
---

<!-- v2.0 DEPRECATION BANNER — display once per install. Marker file gates display. -->

## v2.0 Migration Note

Check the marker file:

```bash
MARKER="$HOME/.claude/.claude-godmode-v1-banner-shown"
if [ ! -f "$MARKER" ]; then
  # Display banner block below
  touch "$MARKER" 2>/dev/null || true
  # Then continue to v1.x body
fi
# If marker exists, skip the banner and proceed straight to v1.x body
```

# ⚠ Deprecated — use `/plan N` instead

This command was renamed in v2.0:

| v1.x | v2.0 |
|---|---|
| `/prd` | `/brief N` |
| `/plan-stories` | `/plan N` |
| `/execute` | `/build N` |

The old body still works for projects on the v1.x layout (`.claude-pipeline/`).
Run `/mission` to migrate to the v2 layout (`.planning/`).

Banner shown once per install — re-display by running:

```bash
rm ~/.claude/.claude-godmode-v1-banner-shown
```

--- v1.x body below ---

# Story Planner

Converts PRDs into stories.json — executable story specifications with auto-detected quality gates, ready for `/execute`.

---

## The Job

1. Read the PRD from `.claude-pipeline/prds/` (or user-provided text)
2. Auto-detect project quality gate commands
3. Convert to stories.json format
4. Ensure `.claude-pipeline/` is in `.gitignore` (see Gitignore Management step below)
5. Save to `.claude-pipeline/stories.json` (create `.claude-pipeline/` dir if needed)

---

## Output Format

```json
{
  "project": "[Project Name]",
  "branchName": "[feature-name-kebab-case]",
  "description": "[Feature description]",
  "prdSource": ".claude-pipeline/prds/prd-feature-name.md",
  "maxParallel": 3,
  "qualityGates": {
    "typecheck": "[detected command, e.g. pnpm type-check]",
    "lint": "[detected command, e.g. pnpm lint]",
    "test": "[detected command, e.g. pnpm test]",
    "build": "[detected command, e.g. pnpm build]"
  },
  "stories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2",
        "All quality gates pass"
      ],
      "dependsOn": [],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

---

## Auto-Detect Quality Gates

Before converting, detect project quality commands:

| Gate | Check for |
|------|-----------|
| typecheck | `tsc --noEmit`, `mypy`, `pyright`, `cargo check`, `go vet` |
| lint | `eslint`, `ruff check`, `cargo clippy`, `golangci-lint` |
| test | `vitest`, `jest`, `pytest`, `cargo test`, `go test` |
| build | `tsup`, `cargo build`, `go build`, `webpack` |

Read package.json scripts, Makefile, Cargo.toml, pyproject.toml to detect exact commands.

---

## Story Size: The Number One Rule

**Each story must be completable in ONE agent session (one context window).**

### Right-sized:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

### Too big (split these):
- "Build the entire dashboard" → schema, queries, UI components, filters
- "Add authentication" → schema, middleware, login UI, session handling

**Rule of thumb:** If you cannot describe the change in 2-3 sentences, split it.

---

## Story Ordering: Dependencies First

1. Schema/database changes (migrations)
2. Server actions / backend logic
3. UI components that use the backend
4. Dashboard/summary views that aggregate data

Earlier stories must NOT depend on later ones.

---

## Dependency Analysis

Every story must include a `dependsOn` field — an array of story IDs it depends on. Stories with no dependencies get `dependsOn: []`.

### Heuristics (declare a dependency when):

| Signal | Example |
|--------|---------|
| **Shared files** — two stories modify any of the same files | US-002 and US-003 both modify `agents/executor.md` → later one depends on earlier |
| **API/schema/type producer-consumer** — a story produces an API, schema, or type that another consumes | US-001 creates a DB table → US-002 writes queries against it |
| **Shared infrastructure** — a story modifies test helpers, config, build scripts, or shared utilities | US-001 updates test fixtures → US-003 uses those fixtures |
| **PRD-stated ordering** — the PRD explicitly states one feature requires another | "Search requires the index built in Story 1" |

### Conservative by default

When uncertain whether a dependency exists, **declare it**. Safety over speed — a false dependency only reduces parallelism, but a missed dependency causes merge conflicts or broken builds.

### Backward compatibility

Existing `stories.json` files without `dependsOn` fields continue to work. Consumers (e.g., `/execute`) fall back to sequential execution when `dependsOn` is absent.

---

## Acceptance Criteria: Must Be Verifiable

**Good:** "Add `status` column with default 'pending'" / "Filter dropdown has options: All, Active, Completed"
**Bad:** "Works correctly" / "Good UX" / "Handles edge cases"

**Every story MUST end with:** `"All quality gates pass"`

This aligns with the canonical quality gates defined in CLAUDE.md.

---

## Conversion Rules

1. Each user story → one JSON entry
2. IDs: Sequential (US-001, US-002, ...)
3. Priority: dependency order first, then document order
4. All stories: `passes: false`, empty `notes`
5. branchName: derived from feature, kebab-case
6. qualityGates: auto-detected project commands
7. Final criterion always: "All quality gates pass"
8. prdSource: path to the PRD file consumed
9. dependsOn: array of story IDs using dependency heuristics (see Dependency Analysis); empty array `[]` if no dependencies
10. maxParallel: optional top-level integer (default 3) — max concurrent agent sessions for `/execute`

---

<!-- canonical: skills/_shared/gitignore-management.md -->
## Gitignore Management

See `skills/_shared/gitignore-management.md` for the canonical procedure. Apply before saving any pipeline artifact.

---

## Archiving Previous Runs

Before writing `.claude-pipeline/stories.json`, check if one exists from a different feature:
1. Read current `.claude-pipeline/stories.json`
2. If `branchName` differs from new feature:
   - Create archive directory: `.claude-pipeline/archive/YYYY-MM-DD-feature-name/`
   - Copy `stories.json` and `progress.md` into the archive directory
   - Read the `prdSource` field from the existing `stories.json` to identify the source PRD
   - Copy the source PRD file (the file at the `prdSource` path) into the archive directory
   - Only copy the single PRD referenced by `prdSource` — do NOT copy all PRDs
   - Reset `.claude-pipeline/progress.md` with the scaffold:
     ```
     # Progress

     ## Knowledge Base

     ### Codebase Patterns

     ### Anti-Patterns

     (none yet)

     ### Architecture Decisions

     ---

     ## Story Log
     ```

---

## After Saving

Suggest next steps:
1. **Optional:** "Use `@architect` to review the design before implementing"
2. **"Run `/execute` to start implementing stories with `@executor` + `@reviewer` agents"**

---

## Agent Routing

| Phase | Agent | Purpose |
|-------|-------|---------|
| After Saving | Suggest @architect for design review (optional) | Review story breakdown, dependency graph, and sizing before execution |

**Rule:** Never explore the codebase inline when @researcher can do it in parallel.

---

## Pipeline Context

<!-- canonical: skills/_shared/pipeline-context.md -->

On activation, detect the current pipeline phase:

| # | Condition | Phase |
|---|-----------|-------|
| 1 | `.claude-pipeline/` does not exist | **no-pipeline** |
| 2 | PRD exists but no `stories.json` | **prd-only** |
| 3 | `stories.json` exists but `branchName` does not match current git branch | **no-pipeline** |
| 4 | All stories have `passes: false` | **planning** |
| 5 | Some `passes: true`, some `passes: false` | **executing** |
| 6 | All stories have `passes: true` | **complete** |

### Branch Check

```bash
current_branch=$(git branch --show-current)
pipeline_branch=$(jq -r '.branchName' .claude-pipeline/stories.json)
```

If branches differ, phase is **no-pipeline** — the pipeline belongs to a different feature.

### Phase Behaviors

| Phase | Behavior |
|-------|----------|
| **no-pipeline** | Operate in standalone mode. No pipeline artifacts read or written. Zero regression from pre-pipeline behavior. |
| **prd-only** | Normal operation — this is the expected phase. Read the PRD and convert to stories. |
| **planning** | Stories already exist for this feature. Check if the user wants to regenerate or amend existing stories before overwriting. |
| **executing** | Implementation is in progress. Warn the user before overwriting stories.json — in-progress work may be lost. Read `progress.md` for context on completed stories. |
| **complete** | All stories are done. If re-planning, archive the previous run first (see Archiving Previous Runs). |

### Exploration Awareness

When `.claude-pipeline/explorations/` contains files:
- Read exploration findings for quality gate command detection — use discovered commands instead of re-running auto-detection when available
- Reference architecture patterns and constraints from explorations when sizing stories and analyzing dependencies

---

## Related

- **/prd** — preceding step: create a PRD before converting to stories
- **/explore-repo** — exploration findings inform quality gate detection
- **@architect** — review story plan design before execution
- **/execute** — next step: implement stories with @executor + @reviewer agents

**Pipeline:** consumes PRD from `.claude-pipeline/prds/`, exploration files for gate detection. Produces `stories.json` and `progress.md`. Preceding step: `/prd`. Next: `/execute`.

---

## Checklist

- [ ] `.claude-pipeline/` is in `.gitignore` (or opt-out marker present)
- [ ] Previous run archived with source PRD (if `.claude-pipeline/stories.json` exists with different branch)
- [ ] Quality gates auto-detected and populated
- [ ] Each story completable in one agent session
- [ ] Stories ordered by dependency
- [ ] Every story has a `dependsOn` field (array of story IDs, or `[]`)
- [ ] Dependencies follow heuristics: shared files, API/schema, infrastructure, PRD ordering
- [ ] When uncertain, dependency is declared (conservative)
- [ ] Every story ends with "All quality gates pass"
- [ ] Acceptance criteria are verifiable (not vague)
- [ ] No story depends on a later story
