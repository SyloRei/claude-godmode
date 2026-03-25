---
name: plan-stories
description: "Convert PRDs to executable stories.json for the agent pipeline. Use when you have a PRD and need to create executable stories. Triggers on: plan stories, convert prd, create stories, stories json, break down prd."
user-invocable: true
---

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

## Gitignore Management

Ensure `.claude-pipeline/` is listed in the project's `.gitignore` so pipeline artifacts are not committed. This step is **idempotent** — running it multiple times must not duplicate the entry.

**Procedure:**

1. **Git repo check:** Only proceed if inside a git repository:
   ```bash
   git rev-parse --is-inside-work-tree 2>/dev/null
   ```
   If this fails, skip this step entirely.

2. **Opt-out check:** If `.gitignore` exists and contains the line `# claude-godmode: unmanaged`, skip this step entirely:
   ```bash
   grep -qxF '# claude-godmode: unmanaged' .gitignore
   ```

3. **Already present check:** If `.gitignore` already contains the exact line `.claude-pipeline/`, skip — nothing to do:
   ```bash
   grep -qxF '.claude-pipeline/' .gitignore
   ```

4. **Add the entry:** If not present, append it:
   - If `.gitignore` does not exist, create it.
   - If `.gitignore` exists and does not end with a newline, add one first:
     ```bash
     [ -s .gitignore ] && [ "$(tail -c1 .gitignore)" != "" ] && printf '\n' >> .gitignore
     ```
   - Append the comment header and the entry:
     ```bash
     printf '# claude-godmode pipeline artifacts\n.claude-pipeline/\n' >> .gitignore
     ```

---

## Archiving Previous Runs

Before writing `.claude-pipeline/stories.json`, check if one exists from a different feature:
1. Read current `.claude-pipeline/stories.json`
2. If `branchName` differs from new feature:
   - Create archive directory: `.claude-pipeline/archive/YYYY-MM-DD-feature-name/`
   - Copy `stories.json` and `progress.txt` into the archive directory
   - Read the `prdSource` field from the existing `stories.json` to identify the source PRD
   - Copy the source PRD file (the file at the `prdSource` path) into the archive directory
   - Only copy the single PRD referenced by `prdSource` — do NOT copy all PRDs
   - Reset `.claude-pipeline/progress.txt`

---

## After Saving

Suggest next steps:
1. **Optional:** "Use `@architect` to review the design before implementing"
2. **"Run `/execute` to start implementing stories with `@executor` + `@reviewer` agents"**

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
