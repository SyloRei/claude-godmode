## Testing

- Test-first when adding new behavior (see /tdd skill)
- Red-green-refactor cycle for bug fixes
- Run existing test suite before declaring any task complete
- Test behavior, not implementation details
- Name tests descriptively: "should [expected] when [condition]"
- Never mock what you can test directly
- Coverage: maintain or improve existing thresholds

## Debugging Protocol

When fixing bugs (see /debug skill for full workflow):
1. **REPRODUCE** — Get exact error. Confirm the bug exists.
2. **HYPOTHESIZE** — Form 2-3 hypotheses from evidence.
3. **ISOLATE** — Test hypotheses one at a time. Narrow to exact cause.
4. **FIX** — Minimal targeted fix. Write regression test.
5. **VERIFY** — Run quality gates. Confirm fix and no regressions.

## Refactoring Protocol

See /refactor skill for full workflow:
- Never refactor and add features in the same commit
- ALL tests must pass before AND after each step
- If tests break: revert, try smaller step
- Commit after each successful step
