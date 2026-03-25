# Gitignore Management

Canonical procedure for ensuring `.claude-pipeline/` is listed in the project's `.gitignore` so pipeline artifacts are not committed. This procedure is **idempotent** — running it multiple times must not duplicate the entry.

---

## Procedure

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
