## Auto-Detection

On first interaction in any project, detect before acting:
- Language/framework: package.json, Cargo.toml, go.mod, pyproject.toml, Gemfile, etc.
- Package manager: pnpm, npm, yarn, bun, pip, uv, cargo, go, bundle
- Test runner: vitest, jest, pytest, go test, cargo test, rspec, phpunit
- Linter: eslint, ruff, clippy, golangci-lint, rubocop
- Formatter: prettier, black, rustfmt, gofmt
- Typechecker: tsc, mypy, pyright, go vet
- Build system: tsup, webpack, vite, cargo, make, gradle, maven
- CI/CD: .github/workflows, .gitlab-ci.yml, Jenkinsfile
- Monorepo: workspaces, lerna, nx, turborepo

Use detected tools for ALL operations. Never assume npm when pnpm exists.

## Coding Standards (Language Agnostic)

- Functions: single responsibility, <40 lines preferred
- Files: <300 lines preferred, split when larger
- Naming: descriptive, consistent with codebase conventions
- Error handling: explicit, never swallow errors silently
- No hardcoded secrets, credentials, API keys — ever
- Types: prefer strong typing where the language supports it
- Imports: follow project ordering conventions
- Comments: only where logic isn't self-evident
- DRY: extract only when pattern repeats 3+ times

## Security Awareness

- Validate all input at system boundaries
- No SQL injection, XSS, path traversal, command injection
- Never log sensitive data (passwords, tokens, PII)
- Use parameterized queries, never string concatenation
- Review dependencies when adding new ones
