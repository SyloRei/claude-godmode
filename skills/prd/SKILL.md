---
name: prd
description: "Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature, starting a new project, or when asked to create a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out."
user-invocable: true
---

# PRD Generator

Create detailed Product Requirements Documents that are clear, actionable, and ready for the execution pipeline.

---

## The Job

1. Receive a feature description from the user
2. Auto-detect project quality commands (typecheck, lint, test, build)
3. Ask 3-5 essential clarifying questions (with lettered options)
4. Generate a structured PRD based on answers
5. Create output directory if needed: `mkdir -p .claude-pipeline/prds`
6. Save to `.claude-pipeline/prds/prd-[feature-name].md`

**Important:** Do NOT start implementing. Just create the PRD.

**Next steps after PRD:** Suggest `@architect` to review the design, then `/plan-stories` to convert for execution.

---

## Step 1: Auto-Detect Quality Commands

Before asking questions, detect the project's quality gate commands:
- Check package.json scripts, Makefile, Cargo.toml, pyproject.toml, etc.
- Identify: typecheck, lint, test, build, format commands
- Embed these in the PRD's Technical Considerations section

---

## Step 2: Clarifying Questions

Ask only critical questions where the initial prompt is ambiguous. Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?

Format with lettered options so users can respond quickly (e.g., "1A, 2C, 3B").

---

## Step 3: PRD Structure

### 1. Introduction/Overview
Brief description of the feature and the problem it solves.

### 2. Goals
Specific, measurable objectives (bullet list).

### 3. User Stories
Each story needs:
- **Title:** Short descriptive name
- **Description:** "As a [user], I want [feature] so that [benefit]"
- **Acceptance Criteria:** Verifiable checklist

Each story should be small enough to implement in one focused session (one agent context window).

**Format:**
```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] All quality gates pass (typecheck, lint, tests)
```

**Rules:**
- Acceptance criteria must be verifiable. "Works correctly" is bad. "Returns 404 when resource not found" is good.
- EVERY story ends with: "All quality gates pass (typecheck, lint, tests)"
- Size stories so each is completable in one agent session

### 4. Functional Requirements
Numbered: "FR-1: The system must..." — explicit and unambiguous.

### 5. Non-Goals (Out of Scope)
What this feature will NOT include.

### 6. Technical Considerations
- Known constraints or dependencies
- **Detected quality gate commands** (auto-detected in Step 1)
- Integration points with existing systems

### 7. Success Metrics
How will success be measured?

### 8. Open Questions
Remaining questions or areas needing clarification.

---

## Writing for Agents

The PRD reader may be a junior developer or AI agent. Therefore:
- Be explicit and unambiguous
- Avoid jargon or explain it
- Number requirements for easy reference
- Use concrete examples

---

## Output

- **Format:** Markdown (`.md`)
- **Location:** `.claude-pipeline/prds/`
- **Filename:** `prd-[feature-name].md` (kebab-case)

---

## After Saving

Suggest next steps:
1. **Optional:** "Use `@architect` to review the design before proceeding"
2. **Required:** "Use `/plan-stories` to convert this PRD into executable stories"

---

## Checklist

Before saving:
- [ ] Auto-detected project quality commands
- [ ] Asked clarifying questions with lettered options
- [ ] User stories are small enough for one agent session
- [ ] Every story has "All quality gates pass" as final criterion
- [ ] Functional requirements are numbered and unambiguous
- [ ] Non-goals section defines clear boundaries
- [ ] Technical considerations include detected quality commands
- [ ] Saved to `.claude-pipeline/prds/prd-[feature-name].md`
