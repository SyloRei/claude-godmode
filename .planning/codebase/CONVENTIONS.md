# Coding Conventions

**Analysis Date:** 2026-04-25

## Naming Patterns

**Files:**
- Markdown files: lowercase, hyphenated (e.g., `godmode-coding.md`, `session-start.sh`)
- Agents: lowercase with hyphens in filename (e.g., `security-auditor.md`)
- Skills: directory with SKILL.md inside (e.g., `skills/plan-stories/SKILL.md`)
- Hooks: lowercase, hyphenated shell scripts (e.g., `session-start.sh`, `post-compact.sh`)
- Rules: `godmode-{concern}.md` pattern (e.g., `godmode-testing.md`, `godmode-quality.md`)

**Frontmatter Fields:**
Agent and skill markdown files use YAML frontmatter with these fields:
```yaml
---
name: [lowercase-hyphenated-name]
description: "[Single-line description of purpose]"
model: [model name - opus or sonnet]
tools: [comma-separated list]
isolation: [worktree or project scope]
memory: [project, user, or local]
effort: [default, high, or max]
maxTurns: [safety limit for code-writing agents]
disallowedTools: [Read-only agents restrict Write/Edit]
background: [true for non-blocking parallel work]
user-invocable: [true for skills meant to be called directly]
---
```

**Variables:**
- Environment variables: UPPERCASE with underscores (e.g., `CLAUDE_DIR`, `SCRIPT_DIR`, `BACKUP_DIR`)
- Shell script variables: UPPERCASE for constants/configuration, lowercase for derived/computed values
- Boolean returns: use exit codes (0 = success, non-zero = failure), avoid "true"/"false" strings

**Sections/Headers:**
- Markdown: hierarchical (H2 for major sections, H3 for subsections)
- Rule files: H2 headers only (lowercase concern names as content)
- Agent/skill descriptions: start with purpose statement

## Code Style

**Markdown Formatting:**
- Line length: prefer <100 chars but not strict (readability over line wrapping)
- Code blocks: use triple backticks with language identifier (bash, json, yaml, typescript)
- Tables: use markdown table format with pipes
- Lists: use dashes for unordered, numbers for ordered
- Emphasis: use **bold** for important terms, `backticks` for inline code/paths, `code blocks` for multi-line

**Shell Script Idioms:**
- Header: `#!/usr/bin/env bash` (shebang with env)
- Error handling: `set -euo pipefail` (exit on error, undefined vars, pipe failures)
- Colors: use ANSI escape codes (stored in uppercase variables: `GREEN`, `RED`, `YELLOW`, `NC`)
- Functions: use `function_name() { ... }` syntax (not `function name`)
- Logging: helper functions (`info()`, `warn()`, `error()`) with colored prefix
- JSON parsing: use `jq` for parsing, with error fallback handling
- Quoting: quote all variables `"$VAR"` unless intentional word-splitting needed
- Comments: explain WHY not WHAT; use `#` not `## ` for single-line comments

**JSON Files:**
- Format: human-readable with proper indentation (typically 2 spaces)
- Comments: not supported in JSON; use descriptive field names instead
- Schema: declare optional vs required fields in documentation

## Import Organization

**Markdown File Ordering (within files):**
1. Frontmatter (YAML in agents/skills only)
2. Breadcrumb/navigation comment (e.g., `<!-- canonical: skills/_shared/pipeline-context.md -->`)
3. Main title (H1)
4. Introduction/overview paragraph
5. Core content (sections)
6. References/links (if any)

**Markdown Cross-References:**
- Path references: always use backticks around file paths (e.g., `skills/execute/SKILL.md`)
- Link format: `[text](/path/to/file)` for internal links (relative from project root)
- Never hardcode full paths in links — use relative paths

## Error Handling

**Shell Scripts:**
- Pattern: `command || error "message"`
- Graceful degradation: fallback to sensible defaults (e.g., when `jq` is unavailable, fall back to generic output)
- Exit codes: 0 for success, 1 for errors
- Stderr: error messages go to stderr; informational to stdout
- Prefixes: use `[+]` for info, `[!]` for warnings, `[x]` for errors (colored)

**Markdown Documentation:**
- Pattern: call out edge cases explicitly in separate sections
- Fallback behavior: document what happens when tools/dependencies are missing
- Links to troubleshooting: point users to relevant docs when documenting failures

## Logging

**Shell Scripts:**
- Use helper functions: `info()`, `warn()`, `error()`
- Format: `[PREFIX] message` with color coding
- No timestamps (Claude Code provides context)
- Emoji: avoid in scripts; use text prefixes instead

**Markdown Documentation:**
- Pattern: call out important notes with blockquotes or sections
- Example: `warn()` in script comments explains what warnings mean

## Comments

**Markdown Comments:**
- Use `<!-- comment -->` syntax
- Reserved use: canonical file references (e.g., `<!-- canonical: skills/_shared/pipeline-context.md -->`)
- Avoid inline HTML comments in regular content

**Shell Script Comments:**
- Single-line: `# Explain WHY you're doing this`
- Avoid explaining WHAT the code does (if unclear, simplify code instead)
- Function comments: brief one-liner above the function
- Complex logic: add 1-2 lines explaining the approach

## Function Design

**Shell Functions:**
- Size: prefer <50 lines
- Parameters: document with inline comments
- Return value: use exit codes (0 = success) or stdout for output
- Side effects: avoid if possible; document if necessary

**Markdown Content Structure:**
- Depth: avoid nesting more than 3 levels (H1, H2, H3)
- Length: break long documents into sections with clear anchors
- Examples: always show actual code/config from codebase with backtick paths

## Module Design

**Agent Files (`agents/*.md`):**
- Single responsibility: clear job statement in intro
- Process: numbered steps with clear phases (CONTEXT → PLAN → IMPLEMENT → TEST → etc.)
- Output format: explicit example showing exactly what the agent should produce
- Rules section: constraints and guardrails for the agent
- Handoffs: suggest appropriate next tools/skills

**Skill Files (`skills/*/SKILL.md`):**
- Structure: Job → Process (numbered steps) → Output Format → Related (links to dependent skills/agents)
- Triggering: document command aliases that trigger the skill
- Dependencies: list related skills/agents in Related section

**Rule Files (`rules/godmode-*.md`):**
- Focus: single concern (identity, coding, testing, etc.)
- Length: target <80 lines for clarity
- No frontmatter: rules are referenced by the installer, not parsed as separate files
- Tone: declarative (do X, not do Y) rather than explanatory

## Configuration Files

**settings.template.json:**
- Purpose: configuration template installed alongside rules
- Format: JSON with comments (via documentation, not inline JSON comments)
- Defaults: provide sensible fallbacks
- Variables: environment variables referenced as strings

**hooks.json:**
- Structure: nested object with hook event names as keys (SessionStart, PostCompact)
- Command refs: use `${CLAUDE_PLUGIN_ROOT}` for plugin-relative paths
- Timeout: set per hook (typical: 10 seconds for init hooks)

---

*Convention analysis: 2026-04-25*
