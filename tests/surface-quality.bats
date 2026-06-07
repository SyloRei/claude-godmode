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

# --- case 0: live-repo smoke test (real gate vs. real tree) --------------

# Run the REAL gate script against the REAL repo tree (no fixture), mirroring
# cohesion.bats's opening case. The committed surfaces carry no stale CLAUDE.md
# references, so a local `bats` run signals immediately if a real surface
# regresses (a new SKILL.md/agent/command that cites CLAUDE.md). The count is
# derived live rather than hardcoded, so adding/removing a surface never breaks
# this for the wrong reason.
@test "check-surface-quality should exit 0 on the repo as built" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no stale CLAUDE.md references"* ]]
  count=$(ls "$PLUGIN_ROOT"/skills/*/SKILL.md "$PLUGIN_ROOT"/agents/*.md "$PLUGIN_ROOT"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
  [[ "$output" == *"${count} surface(s)"* ]]
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
# NOTE: that merge is bats-core's default `run` behavior (stderr folded into
# $output); these stderr assertions depend on it. A bats-core run with stderr
# separated (e.g. `run --separate-stderr`) would route the failure line to
# $stderr instead and break the substring checks below.
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

# --- case 4: an agents/ surface citing CLAUDE.md is caught -----------------

# The two fail cases above only inject the stale ref into skills/*/SKILL.md, so
# a glob-narrowing regression that scanned only the skills arm would still pass
# them. Place the offending citation on an agents/*.md surface (clean skills +
# commands) and assert exit 1 with the agent path named — proving the agents arm
# is scanned.
@test "check-surface-quality should exit 1 and name an agents/ surface that cites CLAUDE.md" {
  make_fixture
  printf '# y\n\nSee CLAUDE.md for the quality gates.\n' > "$FIXTURE/agents/y.md"

  run "$FIXTURE/scripts/check-surface-quality.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"agents/y.md"* ]]
}

# --- case 5: a commands/ surface citing CLAUDE.md is caught ----------------

# Companion to case 4 for the third surface arm: the offending citation sits on
# a commands/*.md surface (clean skills + agents). Exit 1 with the command path
# named proves the commands arm is scanned too, so all three arms are covered.
@test "check-surface-quality should exit 1 and name a commands/ surface that cites CLAUDE.md" {
  make_fixture
  printf '# z\n\nRun the gates documented in CLAUDE.md.\n' > "$FIXTURE/commands/z.md"

  run "$FIXTURE/scripts/check-surface-quality.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"commands/z.md"* ]]
}

# --- case 6: simultaneous violations on TWO surfaces are ALL named ---------

# Two different surfaces each carry a stale CLAUDE.md ref. The gate must
# accumulate failures across surfaces rather than early-exiting on the first
# hit, so BOTH file paths appear in output. Guards against a regression to
# "exit 1 on first violation" that would still pass the single-surface cases.
@test "check-surface-quality should exit 1 and name every surface when two surfaces cite CLAUDE.md" {
  make_fixture
  printf '# x\n\nQuality gates as defined in CLAUDE.md.\n' > "$FIXTURE/skills/x/SKILL.md"
  printf '# y\n\nProtocol lives in CLAUDE.md.\n' > "$FIXTURE/agents/y.md"

  run "$FIXTURE/scripts/check-surface-quality.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/x/SKILL.md"* ]]
  [[ "$output" == *"agents/y.md"* ]]
}

# --- case 7: zero surfaces is a misconfiguration, not a clean pass ---------

# A run that matches no surfaces (wrong working dir / renamed tree) must fail
# loudly rather than report "all 0 surface(s)" — guards the misconfiguration
# guard at scripts/check-surface-quality.sh against a silent green. Mirrors
# cohesion.bats's equivalent zero-surfaces case.
@test "check-surface-quality should exit 1 when no surfaces are found" {
  mkdir -p "$FIXTURE/scripts"
  cp "$SCRIPT" "$FIXTURE/scripts/check-surface-quality.sh"
  chmod +x "$FIXTURE/scripts/check-surface-quality.sh"
  # No skills/agents/commands trees created — every glob matches nothing.

  run "$FIXTURE/scripts/check-surface-quality.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no surfaces found"* ]]
}
