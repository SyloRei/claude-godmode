## Quality Gates (Canonical — Single Source of Truth)

Before declaring ANY task complete, ALL must pass:
1. Typecheck passes (zero errors)
2. Lint passes (zero errors)
3. All tests pass (existing + new)
4. No hardcoded secrets in diff
5. No regressions in related functionality
6. Changes match the original requirements

If any gate fails: fix it. Don't declare success. Don't skip checks.
All skills and agents reference these gates — this is the only definition.
Project-specific gates (e.g., "build") are auto-detected per project by /plan-stories and /ship.
