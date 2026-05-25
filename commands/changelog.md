---
name: changelog
description: "Draft a Keep a Changelog–style entry (Added / Changed / Fixed / Removed) from commits since the last tag. Standalone helper — does not replace /ship's release step."
user-invocable: true
allowed-tools: Bash, Read
---

# /changelog — draft a changelog entry

Generate a [Keep a Changelog](https://keepachangelog.com)–style entry from the
commits and diff since the last release tag. A reactive helper — it does not
spawn agents and is not part of the spine.

> This is a standalone helper for ad-hoc changelog drafting. It does **not**
> replace the release-time changelog step `/ship` performs as part of shipping a
> version — use `/ship` when you are actually cutting a release.

---

## The Job

1. Find the last tag.
2. Read commits and diff since it.
3. Group changes into Added / Changed / Fixed / Removed.

---

## 1. Find the range

```bash
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
RANGE=${LAST_TAG:+$LAST_TAG..HEAD}
git log --oneline ${RANGE:-} 
git diff --stat ${LAST_TAG:+$LAST_TAG..HEAD}
```

If there is no tag yet, summarize the whole history.

## 2. Group the changes

Classify each meaningful change into one of the four categories. Derive the
category from the commit type/intent, not the literal word:

- **Added** — new features, commands, or capabilities.
- **Changed** — behavior or interface changes to existing features.
- **Fixed** — bug fixes.
- **Removed** — deleted features, deprecations carried out.

Drop noise (merge commits, formatting-only churn, internal refactors with no
user-visible effect).

## 3. Emit the entry

```markdown
## [Unreleased]

### Added
- …

### Changed
- …

### Fixed
- …

### Removed
- …
```

Omit any category with no entries. Phrase each line from the user's point of
view, present tense, terse. Print the entry for the user to paste into
`CHANGELOG.md`.
