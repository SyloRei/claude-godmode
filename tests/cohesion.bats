#!/usr/bin/env bats
#
# Workflow-cohesion gate (unit 24, S5 — advances AC-5 and AC-7).
#
# Exercises scripts/check-cohesion.sh, which enforces that every user-facing
# surface (skills/*/SKILL.md, agents/*.md, commands/*.md) carries an onward-
# pointer section: `## Related` OR `## Handoffs`. Contract under test:
#   - all surfaces carry the section -> exit 0, names each `cohesion: ok` (AC-7)
#   - a surface missing the section  -> exit 1, names the offending file  (AC-5)
#   - either heading alone satisfies the gate                            (AC-6)
#
# The gate resolves its own REPO_ROOT from BASH_SOURCE and cd's there, so the
# fixture cases build a TEMP repo: the script is copied into a temp dir
# alongside a minimal skills/agents/commands tree and the COPY is run. The real
# repo files are never mutated.

load test_helper

SCRIPT="$PLUGIN_ROOT/scripts/check-cohesion.sh"

setup() {
  FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/godmode-cohesion.XXXXXX")"
}

teardown() {
  if [ -n "${FIXTURE:-}" ] && [ -d "$FIXTURE" ]; then
    rm -rf "$FIXTURE"
  fi
}

# Build a fixture repo: copy the gate script in and create a minimal surface
# tree. Each surface carries an onward-pointer section by default:
#   skills/x/SKILL.md -> ## Related
#   agents/y.md       -> ## Handoffs
#   commands/z.md     -> ## Related
# Individual cases overwrite a file to remove or vary its section.
make_fixture() {
  mkdir -p "$FIXTURE/scripts"
  cp "$SCRIPT" "$FIXTURE/scripts/check-cohesion.sh"
  chmod +x "$FIXTURE/scripts/check-cohesion.sh"

  mkdir -p "$FIXTURE/skills/x" "$FIXTURE/agents" "$FIXTURE/commands"
  printf '# x\n\n## Related\n\n- /y\n' > "$FIXTURE/skills/x/SKILL.md"
  printf '# y\n\n## Handoffs\n\n- @z\n' > "$FIXTURE/agents/y.md"
  printf '# z\n\n## Related\n\n- /x\n' > "$FIXTURE/commands/z.md"
}

# --- case 1: pass on the repo as built (AC-7) ----------------------------

# AC-7: the real repo exits 0, reports each surface as `cohesion: ok`, and
# emits the all-present summary naming the surface count.
@test "check-cohesion should exit 0 and report every surface as ok on the repo as built" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cohesion: ok"* ]]
  [[ "$output" == *"surface(s)"* ]]
  [[ "$output" == *"all 36 surface(s)"* ]]
  # Sample one agent and one skill to prove both surface kinds are scanned.
  [[ "$output" == *"cohesion: ok agents/writer.md"* ]]
  [[ "$output" == *"cohesion: ok skills/ship/SKILL.md"* ]]
}

# --- case 2: fail when a surface lacks the section (AC-5) ------------------

# AC-5: a present surface missing both headings -> exit 1 naming the file.
# Operates on a TEMP copy; the real repo files are never touched. `run`
# captures both stdout and stderr into $output, so the failure line (written
# to stderr by the gate) is asserted there.
@test "check-cohesion should exit 1 and name the file when a surface lacks an onward-pointer section" {
  make_fixture
  # Strip every section from one surface in the fixture only.
  printf '# y\n\n(no onward-pointer section here)\n' > "$FIXTURE/agents/y.md"

  run "$FIXTURE/scripts/check-cohesion.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"agents/y.md"* ]]
}

# --- case 3: either heading satisfies (AC-6) ------------------------------

# AC-6: Handoffs alone (on the agent) and Related alone (on the skill) both
# satisfy the gate, so a fixture using each exclusively still exits 0.
@test "check-cohesion should exit 0 when surfaces use Handoffs or Related interchangeably" {
  make_fixture
  # make_fixture already gives agents/y.md only ## Handoffs and
  # skills/x/SKILL.md only ## Related — exactly the cross-check we want.
  run "$FIXTURE/scripts/check-cohesion.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cohesion: ok agents/y.md"* ]]
  [[ "$output" == *"cohesion: ok skills/x/SKILL.md"* ]]
}
