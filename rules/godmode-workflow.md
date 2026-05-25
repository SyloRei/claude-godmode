## Workflow cycle

Every non-trivial task follows this five-step cycle:

1. **UNDERSTAND** — Read relevant files, grep patterns, check tests, understand the domain
2. **PLAN** — State approach in 3-5 bullets before coding. For multi-file changes, use plan mode.
3. **EXECUTE** — Small atomic changes, one concern per change
4. **VERIFY** — Run quality gates (see `rules/godmode-quality.md`). Show evidence.
5. **SHIP** — Clean commits, PR-ready state

Skip steps only for trivial work (typo fixes, single-line changes).

## Workflow spine

For any feature, the single happy path is the spine — each command has one
goal and one output artifact. `/godmode` reads recorded state and tells you
the next command:

```
/godmode → /mission → /brief N → /plan N → /build N → /verify N → /ship
```

| Command | Goal |
|---|---|
| `/godmode` | Orient — "what now?" in five lines |
| `/mission` | Initialize / update the project + roadmap |
| `/brief N` | Why + what + spec for work unit N |
| `/plan N` | Tactical breakdown for unit N |
| `/build N` | Wave-based execution, atomic commits |
| `/verify N` | Goal-backward COVERED / PARTIAL / MISSING |
| `/ship` | Quality gates, push, open PR |

### Entry points

Not every task starts at `/mission`. Choose the right entry:

```
New to a codebase   → /onboard → /mission → /brief N → /plan N → /build N → /verify N → /ship
Feature from scratch → /mission → /brief N → /plan N → /build N → /verify N → /ship
Found a bug         → /debug → fold the fix into /brief N (or /build N directly)
Need to refactor    → /refactor → fold steps into /plan N → /build N
TDD a new behavior  → /tdd → red tests → /build N to make them green
```

### Course corrections

```
/build N hits test failures        → /debug to diagnose → fix → resume /build N
/build N gets a @code-reviewer CRITICAL on structure  → /refactor → resume /build N
/build N gets a @code-reviewer CRITICAL on security   → @security-auditor → fix → resume /build N
/verify N reports MISSING coverage → /plan N to add the gap → /build N
```

Helpers (`/debug`, `/tdd`, `/refactor`, `/onboard`) feed the spine —
they never replace it. See `rules/godmode-routing.md` for the canonical
command-to-owner and skill-to-agent maps.
