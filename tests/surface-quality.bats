#!/usr/bin/env bats
#
# Surface-quality gate (mission 07-workflow-cohesion, unit 3).
#
# Exercises scripts/check-surface-quality.sh, the dead-reference deny-list gate
# (AC-8/AC-10) that enforces that no user-facing surface (skills/*/SKILL.md,
# agents/*.md, commands/*.md) cites `CLAUDE.md` as a source of quality gates or
# godmode protocol — those citations are stale, the canonical sources are
# config/quality-gates.txt + rules/godmode-*.md.
# Contract under test:
#   - a surface tree with no CLAUDE.md references -> exit 0, reports the count
#   - a surface naming CLAUDE.md -> exit 1, names the offending file (and line)
#
# The gate resolves its own REPO_ROOT from BASH_SOURCE and cd's there, so the
# fixture cases build a TEMP repo: the script is copied into a temp dir
# alongside a minimal skills/agents/commands tree and the COPY is run. The real
# repo files are never mutated.

load test_helper

SCRIPT="$PLUGIN_ROOT/scripts/check-surface-quality.sh"

setup() {
  FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/godmode-surface-quality.XXXXXX")"
}

teardown() {
  if [ -n "${FIXTURE:-}" ] && [ -d "$FIXTURE" ]; then
    rm -rf "$FIXTURE"
  fi
}

# Build a fixture repo: copy the gate script in and create a minimal surface
# tree (one skill, one agent, one command), each with clean prose that names no
# CLAUDE.md reference. Individual cases overwrite a file to introduce a stale
# citation.
make_fixture() {
  mkdir -p "$FIXTURE/scripts"
  cp "$SCRIPT" "$FIXTURE/scripts/check-surface-quality.sh"
  chmod +x "$FIXTURE/scripts/check-surface-quality.sh"

  mkdir -p "$FIXTURE/skills/x" "$FIXTURE/agents" "$FIXTURE/commands"
  printf '# x\n\nRun the gates in config/quality-gates.txt before committing.\n' > "$FIXTURE/skills/x/SKILL.md"
  printf '# y\n\nFollow the protocols in rules/godmode-coding.md.\n' > "$FIXTURE/agents/y.md"
  printf '# z\n\nA clean command surface with no stale citations.\n' > "$FIXTURE/commands/z.md"
}

# --- case 1: pass when no surface cites CLAUDE.md -------------------------

# A surface tree carrying zero CLAUDE.md references exits 0 and reports the
# number of surfaces checked.
@test "check-surface-quality should exit 0 and report the count when no surface cites CLAUDE.md" {
  make_fixture

  run "$FIXTURE/scripts/check-surface-quality.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no stale CLAUDE.md references"* ]]
  [[ "$output" == *"3 surface(s)"* ]]
}

# --- case 2: fail when a surface cites CLAUDE.md, naming the file ----------

# A surface holding a `CLAUDE.md` citation -> exit 1, and the offending file
# path is named in output. `run` captures both stdout and stderr into $output,
# so the failure line (written to stderr by the gate) is asserted there.
@test "check-surface-quality should exit 1 and name the file when a surface cites CLAUDE.md" {
  make_fixture
  # Introduce a stale citation on one surface only.
  printf '# x\n\nRun the quality gates as defined in CLAUDE.md before committing.\n' > "$FIXTURE/skills/x/SKILL.md"

  run "$FIXTURE/scripts/check-surface-quality.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/x/SKILL.md"* ]]
}

# --- case 3: the reported line number appears in output -------------------

# Beyond naming the file, the gate reports the line on which the stale citation
# sits (grep -n), so the reader can jump straight to it. Place the citation on a
# known line (line 5) and assert that line number is named.
@test "check-surface-quality should report the line number of the stale CLAUDE.md citation" {
  make_fixture
  # Lines: 1='# x', 2='', 3='intro', 4='', 5=citation -> the stale hit is line 5.
  printf '# x\n\nintro\n\nquality gates as defined in CLAUDE.md\n' > "$FIXTURE/skills/x/SKILL.md"

  run "$FIXTURE/scripts/check-surface-quality.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/x/SKILL.md:5"* ]]
}
