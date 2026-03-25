# Pipeline Context Detection

Canonical reference for detecting the current pipeline phase. Skills that include a `## Pipeline Context` section should follow this logic.

---

## Phase Detection

Determine the current pipeline phase by checking these conditions in order:

| # | Condition | Phase | Description |
|---|-----------|-------|-------------|
| 1 | `.claude-pipeline/` directory does not exist | **no-pipeline** | No pipeline has been initialized |
| 2 | PRD exists in `.claude-pipeline/prds/` but no `.claude-pipeline/stories.json` | **prd-only** | PRD created, stories not yet planned |
| 3 | `stories.json` exists but `branchName` does not match current git branch | **no-pipeline** | Pipeline belongs to a different feature branch |
| 4 | All stories have `passes: false` | **planning** | Stories planned, none started |
| 5 | Some stories have `passes: true`, some `passes: false` | **executing** | Implementation in progress |
| 6 | All stories have `passes: true` | **complete** | All stories implemented |

### Branch Check

Before evaluating story statuses (steps 4-6), verify that the `branchName` field in `stories.json` matches the current git branch:

```bash
current_branch=$(git branch --show-current)
pipeline_branch=$(jq -r '.branchName' .claude-pipeline/stories.json)
```

If `current_branch` does not match `pipeline_branch`, the phase is **no-pipeline** — the pipeline belongs to a different feature and should not influence the current skill's behavior.

---

## Phase Behaviors

| Phase | Behavior |
|-------|----------|
| **no-pipeline** | Skill operates in standalone mode. No pipeline artifacts are read or written. Zero regression from pre-pipeline behavior. |
| **prd-only** | Skill may reference the PRD for context but does not expect stories.json. |
| **planning** | Skill may reference stories.json for upcoming work context. |
| **executing** | Skill reads `progress.txt` top-level sections (Codebase Patterns, Anti-Patterns, Architecture Decisions) for accumulated project knowledge. Reads `.claude-pipeline/explorations/` for codebase understanding when available. |
| **complete** | Same as executing — accumulated knowledge is still useful. |

---

## Usage in Skills

Skills that adopt this template should:

1. Add a `## Pipeline Context` section with `<!-- canonical: skills/_shared/pipeline-context.md -->` comment
2. Include the phase detection logic above
3. Define phase-specific behaviors relevant to that skill
4. Ensure **no-pipeline** phase preserves exact pre-pipeline behavior (zero regression)
