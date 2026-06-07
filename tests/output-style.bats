#!/usr/bin/env bats
#
# Output-style coverage (mission 07-workflow-cohesion, unit 5). Two concerns:
#
#   AC-6  — the bundled `outputStyles/godmode-terse.md` style file exists with
#           name/description frontmatter, and the plugin manifest references the
#           outputStyles directory.
#   AC-10 — scripts/check-output-style.sh, the gate that enforces the in-skill
#           output-block convention on every result-printing surface.
#
# --- AC-10 gate contract ---------------------------------------------------
# The gate asserts that every in-scope surface signals adherence two ways it can
# grep mechanically:
#   1. an Output section heading — `## Output` or `## Output Format`; and
#   2. the exact, fixed marker token `godmode:output-convention` in its body.
# Scope is two tiers: a universal glob over skills/*/SKILL.md (14) + commands/*.md
# (4), plus an additive 3-agent allow-list (verifier, planner, doc-writer) — 21
# in-scope surfaces total. Contract under test:
#   - all in-scope surfaces carry BOTH heading and marker -> exit 0, names each ok
#   - a present in-scope surface missing the heading       -> exit 1, names it
#   - a present in-scope surface missing the marker        -> exit 1, names it
#   - a suffix-superset marker (...-convention-v2)         -> exit 1, marker unmet
#   - an absent tier-2 agent                                -> skipped, not failed
#   - an agent NOT on the allow-list lacking the pair       -> ignored (out of scope)
#   - zero skills/commands surfaces                         -> exit 1, fails loudly
#
# The gate resolves its own REPO_ROOT from BASH_SOURCE and cd's there, then globs
# THAT tree. So the failure/fixture cases build a TEMP repo: the script is copied
# into a temp dir alongside a minimal surface tree and the COPY is run. The real
# repo files are never mutated. The OUTPUT_AGENTS allow-list lives in the script
# itself, so a fixture surface is classified purely by its path.

load test_helper

STYLE="$PLUGIN_ROOT/outputStyles/godmode-terse.md"
SCRIPT="$PLUGIN_ROOT/scripts/check-output-style.sh"
MARKER='godmode:output-convention'

setup() {
  FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/godmode-output.XXXXXX")"
}

teardown() {
  if [ -n "${FIXTURE:-}" ] && [ -d "$FIXTURE" ]; then
    rm -rf "$FIXTURE"
  fi
}

# Build a fixture repo: copy the gate script in and lay down a minimal surface
# tree that PASSES by default — one skill and one command, each carrying both the
# Output heading and the marker. Individual cases overwrite a file (or add an
# agent) to isolate exactly the condition under test. Agents are deliberately NOT
# created here so the absent-agent case can assert the skip path out of the box.
make_fixture() {
  mkdir -p "$FIXTURE/scripts"
  cp "$SCRIPT" "$FIXTURE/scripts/check-output-style.sh"
  chmod +x "$FIXTURE/scripts/check-output-style.sh"

  mkdir -p "$FIXTURE/skills/x" "$FIXTURE/commands"
  printf '# x\n\n## Output\n\nEmits a result block. <!-- %s -->\n' "$MARKER" > "$FIXTURE/skills/x/SKILL.md"
  printf '# z\n\n## Output\n\nEmits a result block. <!-- %s -->\n' "$MARKER" > "$FIXTURE/commands/z.md"
}

# === AC-6: the bundled terse output style file ============================

@test "godmode-terse.md style file exists" {
  [ -f "$STYLE" ]
}

@test "godmode-terse.md frontmatter has a name line" {
  run grep -E '^name:' "$STYLE"
  [ "$status" -eq 0 ]
}

@test "godmode-terse.md frontmatter has a description line" {
  run grep -E '^description:' "$STYLE"
  [ "$status" -eq 0 ]
}

@test "plugin manifest references ./outputStyles/" {
  run jq -r '.outputStyles' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [ "$output" = "./outputStyles/" ]
}

# === AC-10: the check-output-style.sh gate ================================

# --- case 1: pass on the repo as built (healthy, all 21) ------------------

# AC-10: the real repo exits 0, reports each in-scope surface as `output: ok`,
# and emits the all-present summary naming the in-scope surface count. The count
# is derived live (14 skills + 4 commands + present allow-list agents) rather
# than hardcoded, so adding/removing a surface never breaks this for the wrong
# reason. Sampling one skill, one command, and all three tier-2 agents proves
# every scope tier is scanned.
@test "check-output-style should exit 0 and report every in-scope surface as ok on the repo as built" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"output: ok"* ]]
  [[ "$output" == *"in-scope surface(s)"* ]]

  sk=$(ls "$PLUGIN_ROOT"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  cmd=$(ls "$PLUGIN_ROOT"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
  ag=0
  for a in verifier planner doc-writer; do
    [ -f "$PLUGIN_ROOT/agents/$a.md" ] && ag=$((ag + 1))
  done
  count=$((sk + cmd + ag))
  [[ "$output" == *"all ${count} in-scope surface(s)"* ]]

  # Sample one surface per scope tier to prove all three are scanned.
  [[ "$output" == *"output: ok mission"* ]]
  [[ "$output" == *"output: ok adr"* ]]
  [[ "$output" == *"output: ok verifier"* ]]
  [[ "$output" == *"output: ok planner"* ]]
  [[ "$output" == *"output: ok doc-writer"* ]]
}

# --- case 2: fail when an in-scope surface lacks the Output heading --------

# A present in-scope surface carrying the marker but NO `## Output` heading ->
# exit 1, named under the missing-heading failure header. Operates on a TEMP
# copy; the real repo files are never touched. `run` captures both stdout and
# stderr into $output, so the failure line (written to stderr) is asserted there.
@test "check-output-style should exit 1 and name the file when an in-scope surface lacks the Output heading" {
  make_fixture
  # Marker present, but no `## Output` / `## Output Format` heading anywhere.
  printf '# x\n\nNo output heading here.\n\n<!-- %s -->\n' "$MARKER" > "$FIXTURE/skills/x/SKILL.md"

  run "$FIXTURE/scripts/check-output-style.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing heading"* ]]
  [[ "$output" == *"skills/x/SKILL.md"* ]]
}

# --- case 3: fail when an in-scope surface lacks the marker ----------------

# A present in-scope surface carrying the `## Output` heading but NO marker ->
# exit 1, named under the missing-marker failure header.
@test "check-output-style should exit 1 and name the file when an in-scope surface lacks the marker" {
  make_fixture
  # Heading present, but the marker token is absent from the body.
  printf '# x\n\n## Output\n\nEmits a result block, but with no convention marker.\n' > "$FIXTURE/skills/x/SKILL.md"

  run "$FIXTURE/scripts/check-output-style.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing marker"* ]]
  [[ "$output" == *"skills/x/SKILL.md"* ]]
}

# --- case 4: a suffix-superset marker does NOT satisfy the marker ----------

# The marker boundary is exact: `godmode:output-convention-v2` is a suffix-
# extended superset, and the gate's trailing non-[alnum-] boundary must reject
# it. Heading is present, so only the marker check fails -> exit 1 naming the
# file. Guards against a regression that drops the boundary (bare substring
# grep), which would wrongly accept the v2 superset and flip this to exit 0.
@test "check-output-style should exit 1 when an in-scope surface carries a suffix-superset marker" {
  make_fixture
  printf '# x\n\n## Output\n\nEmits a result block. <!-- %s-v2 -->\n' "$MARKER" > "$FIXTURE/skills/x/SKILL.md"

  run "$FIXTURE/scripts/check-output-style.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing marker"* ]]
  [[ "$output" == *"skills/x/SKILL.md"* ]]
}

# --- case 5: an absent tier-2 agent is skipped, not failed -----------------

# Resilience (mirrors check-recommend.sh / check-cohesion.sh): an in-scope
# allow-list agent that is simply not present must be skipped, not treated as a
# violation. The fixture creates only a passing skill+command and NO agents, so
# all three OUTPUT_AGENTS are absent -> the run still exits 0 and reports each as
# skipped. Guards against a regression that fails solely because an opt-in agent
# file is missing.
@test "check-output-style should exit 0 and skip an absent in-scope agent rather than fail" {
  make_fixture
  # make_fixture creates no agents/ tree at all.

  run "$FIXTURE/scripts/check-output-style.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verifier (not present, skipped)"* ]]
  [[ "$output" == *"planner (not present, skipped)"* ]]
  [[ "$output" == *"doc-writer (not present, skipped)"* ]]
}

# --- case 6: an agent NOT on the allow-list is out of scope -----------------

# Additive-agent contract (AC-7 scope): only the three OUTPUT_AGENTS opt in; the
# other ~15 agents are out of scope by design. An agent file that is NOT on the
# allow-list (e.g. agents/code-reviewer.md) carrying neither heading nor marker
# must NOT cause a failure — the gate never inspects it. Guards against a
# regression that widens tier 2 into a glob over agents/*.md, which would wrongly
# require the convention on every agent and fail here.
@test "check-output-style should exit 0 and ignore an agent that is not on the allow-list" {
  make_fixture
  mkdir -p "$FIXTURE/agents"
  # code-reviewer is not one of the three OUTPUT_AGENTS; it has no heading/marker.
  printf '# code-reviewer\n\nNo output heading and no convention marker.\n' > "$FIXTURE/agents/code-reviewer.md"

  run "$FIXTURE/scripts/check-output-style.sh"
  [ "$status" -eq 0 ]
  # The out-of-scope agent is never named in any failure line.
  [[ "$output" != *"code-reviewer"* ]]
  [[ "$output" == *"in-scope surface(s)"* ]]
}

# --- case 7: zero skills/commands surfaces is a misconfiguration ------------

# A run whose tier-1 glob matches no surfaces (wrong working dir / renamed tree)
# must fail loudly rather than report "all 0 in-scope surface(s)" — guards
# against a silent green. Mirrors check-cohesion.sh's no-surfaces guard.
@test "check-output-style should exit 1 when no skills or commands surfaces are found" {
  mkdir -p "$FIXTURE/scripts"
  cp "$SCRIPT" "$FIXTURE/scripts/check-output-style.sh"
  chmod +x "$FIXTURE/scripts/check-output-style.sh"
  # No skills/ or commands/ trees created — the tier-1 glob matches nothing.

  run "$FIXTURE/scripts/check-output-style.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no surfaces found"* ]]
}
