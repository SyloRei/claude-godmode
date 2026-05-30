#!/usr/bin/env bats
#
# Skill-scaffolder tests (unit 5, S4 — AC-10).
#
# Drives bin/godmode-skill (the scaffolder from S1/S2) inside a per-test
# temp tree and asserts the BRIEF contract AC-3..AC-8:
#   - AC-3  happy helper: skills/<name>/SKILL.md created, {{name}}/{{description}}
#           substituted, no .bak, scripts/ is an empty dir (no .gitkeep).
#   - AC-5  spine: the godmode:recommend-convention marker is uncommented.
#   - AC-6  existing dir: refuse, write nothing.
#   - AC-7  surface cap: refuse when adding would exceed the gate CAP.
#   - AC-8  name validation: every invalid-name class is rejected.
#   - failed runs leave NO partial files behind.
#
# Isolation: the scaffolder resolves its target tree from ${BASH_SOURCE[0]}
# (the parent of its bin/). Running the COPY at <temp>/bin/godmode-skill makes
# it operate entirely on <temp>/ — never the real repo. Each test builds a
# fresh temp tree (bin/ + templates/skill/ + a STUBBED scripts/
# check-surface-count.sh exposing a CAP= line) so we can set the cap low
# without touching the real gate. The temp skills/ and commands/ dirs are
# seeded so the scaffolder's own surface count is deterministic.

load test_helper

# make_tree [cap] [seed_skills] [seed_commands] — build an isolated temp tree
# and echo its root. Defaults: CAP=19, no seeded surfaces. Seeds N empty skill
# dirs (each with a SKILL.md so the scaffolder counts them) and N command .md
# files so the scaffolder's current_surface() is deterministic.
make_tree() {
  local cap="${1:-19}" seed_skills="${2:-0}" seed_commands="${3:-0}"
  local root i
  root="$(mktemp -d "$TEST_HOME/tree-XXXXXX")"

  mkdir -p "$root/bin" "$root/templates" "$root/scripts" \
           "$root/skills" "$root/commands"

  cp "$PLUGIN_ROOT/bin/godmode-skill" "$root/bin/godmode-skill"
  chmod +x "$root/bin/godmode-skill"
  cp -R "$PLUGIN_ROOT/templates/skill" "$root/templates/skill"

  # Stubbed surface gate: the scaffolder only greps the literal CAP= line from
  # this file (read_cap), so a one-line stub is faithful to how it reads CAP.
  printf 'CAP=%s\n' "$cap" > "$root/scripts/check-surface-count.sh"

  i=0
  while [ "$i" -lt "$seed_skills" ]; do
    mkdir -p "$root/skills/seed-$i"
    printf -- '---\nname: seed-%s\n---\n' "$i" > "$root/skills/seed-$i/SKILL.md"
    i=$((i + 1))
  done

  i=0
  while [ "$i" -lt "$seed_commands" ]; do
    printf -- '---\nname: cmd-%s\n---\n' "$i" > "$root/commands/cmd-$i.md"
    i=$((i + 1))
  done

  printf '%s' "$root"
}

setup() {
  make_temp_home
}

teardown() {
  teardown_temp_home
}

# --- AC-3: happy-path helper ---------------------------------------------

@test "should scaffold a helper skill with a complete SKILL.md when name is valid (AC-3)" {
  local root; root="$(make_tree)"

  run "$root/bin/godmode-skill" new my-skill
  [ "$status" -eq 0 ]

  local md="$root/skills/my-skill/SKILL.md"
  [ -f "$md" ]

  # name: substituted to the skill name.
  run grep -E '^name: my-skill$' "$md"
  [ "$status" -eq 0 ]

  # description: present and non-empty (something after "description: ").
  run grep -E '^description: .+$' "$md"
  [ "$status" -eq 0 ]

  # scripts/ is a directory and is empty (no .gitkeep carried over).
  [ -d "$root/skills/my-skill/scripts" ]
  [ ! -e "$root/skills/my-skill/scripts/.gitkeep" ]
  run find "$root/skills/my-skill/scripts" -mindepth 1
  [ -z "$output" ]
}

# --- AC-5: happy-path spine ----------------------------------------------

@test "should uncomment the recommend-convention marker when kind is spine (AC-5)" {
  local root; root="$(make_tree)"

  run "$root/bin/godmode-skill" new my-spine --kind spine
  [ "$status" -eq 0 ]

  local md="$root/skills/my-spine/SKILL.md"
  [ -f "$md" ]

  # Bare token on its own line, as check-recommend.sh matches it.
  run grep -E 'godmode:recommend-convention([^[:alnum:]-]|$)' "$md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"godmode:recommend-convention"* ]]
}

@test "should leave the recommend-convention marker commented for a helper skill (AC-5)" {
  local root; root="$(make_tree)"

  run "$root/bin/godmode-skill" new plain-helper
  [ "$status" -eq 0 ]

  # The marker stays inside the HTML comment for helper skills.
  run grep -F '<!--godmode:recommend-convention-->' "$root/skills/plain-helper/SKILL.md"
  [ "$status" -eq 0 ]
}

# --- AC-3: template substitution -----------------------------------------

@test "should replace every template placeholder and leave no .bak when scaffolding (AC-3)" {
  local root; root="$(make_tree)"

  run "$root/bin/godmode-skill" new subst-skill
  [ "$status" -eq 0 ]

  local md="$root/skills/subst-skill/SKILL.md"

  # No raw placeholders survive.
  run grep -F '{{name}}' "$md"
  [ "$status" -ne 0 ]
  run grep -F '{{description}}' "$md"
  [ "$status" -ne 0 ]

  # No leftover sed backup anywhere under the generated skill.
  run find "$root/skills/subst-skill" -name '*.bak'
  [ -z "$output" ]
}

# --- AC-6: refuse when the target dir already exists ---------------------

@test "should refuse and write nothing when skills/<name>/ already exists (AC-6)" {
  local root; root="$(make_tree)"

  # Pre-create the target with a sentinel so we can prove it is untouched.
  mkdir -p "$root/skills/taken"
  printf 'SENTINEL\n' > "$root/skills/taken/marker.txt"

  run "$root/bin/godmode-skill" new taken
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]

  # The pre-existing dir is unchanged: only the sentinel file remains.
  [ -f "$root/skills/taken/marker.txt" ]
  [ "$(cat "$root/skills/taken/marker.txt")" = "SENTINEL" ]
  run find "$root/skills/taken" -mindepth 1
  [ "$output" = "$root/skills/taken/marker.txt" ]
}

# --- AC-7: refuse when the surface cap would be exceeded ------------------

@test "should refuse and create no skill dir when adding would exceed the surface cap (AC-7)" {
  # CAP=2 with 2 seeded skills => adding one more (2 + 1 = 3) exceeds the cap.
  local root; root="$(make_tree 2 2 0)"

  run "$root/bin/godmode-skill" new over-cap
  [ "$status" -ne 0 ]
  [[ "$output" == *"exceeding the cap"* ]]

  # No skills/<name>/ was created.
  [ ! -e "$root/skills/over-cap" ]

  # The seeded surfaces are still exactly what we put there — nothing partial.
  run find "$root/skills" -mindepth 1 -maxdepth 1 -type d
  [[ "$output" == *"$root/skills/seed-0"* ]]
  [[ "$output" == *"$root/skills/seed-1"* ]]
  [[ "$output" != *"over-cap"* ]]
}

# --- AC-8: invalid-name classes ------------------------------------------
#
# One assertion per class: each refusal must be non-zero, print the validation
# rule, and create no files. We run them through a shared checker so the
# "no files created" + "rule printed" contract is asserted uniformly.

# refuse_invalid <root> <name...> — run the scaffolder with the given args
# (may be empty for the empty-name class), assert non-zero exit, the name rule
# printed, and that no new skills/ dir leaked.
refuse_invalid() {
  local root="$1"; shift

  run "$root/bin/godmode-skill" new "$@"
  [ "$status" -ne 0 ] || { echo "expected non-zero exit; got 0 for name='$*'"; return 1; }

  # The validation rule (the literal ^[a-z]... regex blurb) is printed.
  [[ "$output" == *"name must match"* ]] || {
    echo "rule not printed for name='$*'; output: $output"; return 1
  }

  # Nothing was written under skills/.
  run find "$root/skills" -mindepth 1
  [ -z "$output" ] || { echo "leftover files for name='$*': $output"; return 1; }
}

@test "should reject an empty name (AC-8)" {
  local root; root="$(make_tree)"
  refuse_invalid "$root" ""
}

@test "should reject a name with uppercase letters (AC-8)" {
  local root; root="$(make_tree)"
  refuse_invalid "$root" "My-Skill"
}

@test "should reject a name starting with a hyphen (AC-8)" {
  local root; root="$(make_tree)"
  # Pass via -- so the leading '-' is a value, not an option.
  run "$root/bin/godmode-skill" new -- "-foo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"name must match"* ]]
  run find "$root/skills" -mindepth 1
  [ -z "$output" ]
}

@test "should reject a name starting with an underscore (AC-8)" {
  local root; root="$(make_tree)"
  refuse_invalid "$root" "_foo"
}

@test "should reject a name containing a slash (AC-8)" {
  local root; root="$(make_tree)"
  refuse_invalid "$root" "foo/bar"
}

@test "should reject a name containing a space (AC-8)" {
  local root; root="$(make_tree)"
  refuse_invalid "$root" "foo bar"
}

@test "should reject a name longer than the 31-char limit (AC-8)" {
  local root; root="$(make_tree)"
  # 32 chars: a + 31 more => exceeds the max-31 rule (^[a-z][a-z0-9-]{0,30}$).
  refuse_invalid "$root" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

@test "should reject a name with a non-[a-z0-9-] character (AC-8)" {
  local root; root="$(make_tree)"
  refuse_invalid "$root" "foo.bar"
}

# --- failed run leaves no partial files ----------------------------------

@test "should leave no partial skill dir after a refused run (AC-6/AC-7/AC-8)" {
  local root; root="$(make_tree)"

  # An invalid name is refused before anything is written.
  run "$root/bin/godmode-skill" new "Bad Name"
  [ "$status" -ne 0 ]

  # skills/ has no partial <name>/ dir whatsoever.
  run find "$root/skills" -mindepth 1
  [ -z "$output" ]
}

# --- accepted boundaries -------------------------------------------------
#
# The refusal classes are covered above; these pin the ACCEPTED edges so an
# off-by-one in the regex bound or the cap comparison cannot pass silently.

@test "should accept a name at exactly the 31-char maximum (AC-8 boundary)" {
  local root; root="$(make_tree)"

  # ^[a-z][a-z0-9-]{0,30}$ => 1 + 30 = 31 chars is the longest valid name.
  local name="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"   # 31 chars
  [ "${#name}" -eq 31 ]

  run "$root/bin/godmode-skill" new "$name"
  [ "$status" -eq 0 ]
  [ -f "$root/skills/$name/SKILL.md" ]
}

@test "should accept scaffolding when total + 1 is exactly the cap (AC-7 boundary)" {
  # CAP=3 with 2 seeded skills => 2 + 1 = 3 == cap, so this must be ACCEPTED
  # (the guard refuses only when total + 1 > cap).
  local root; root="$(make_tree 3 2 0)"

  run "$root/bin/godmode-skill" new at-cap
  [ "$status" -eq 0 ]
  [ -f "$root/skills/at-cap/SKILL.md" ]
}

# --- --kind argument handling --------------------------------------------

@test "should accept the --kind=spine equals form (AC-5)" {
  local root; root="$(make_tree)"

  run "$root/bin/godmode-skill" new eq-spine --kind=spine
  [ "$status" -eq 0 ]

  # Equals form must uncomment the marker just like the space form.
  run grep -E 'godmode:recommend-convention([^[:alnum:]-]|$)' \
    "$root/skills/eq-spine/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "should reject an invalid --kind value and write nothing" {
  local root; root="$(make_tree)"

  run "$root/bin/godmode-skill" new bad-kind --kind bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"--kind must be"* ]]

  run find "$root/skills" -mindepth 1
  [ -z "$output" ]
}

@test "should reject a --kind flag with no value and write nothing" {
  local root; root="$(make_tree)"

  run "$root/bin/godmode-skill" new no-kind-value --kind
  [ "$status" -ne 0 ]
  [[ "$output" == *"--kind requires a value"* ]]

  run find "$root/skills" -mindepth 1
  [ -z "$output" ]
}

# --- subcommand dispatch -------------------------------------------------

@test "should reject an unknown subcommand and write nothing" {
  local root; root="$(make_tree)"

  run "$root/bin/godmode-skill" frobnicate
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown subcommand"* ]]

  run find "$root/skills" -mindepth 1
  [ -z "$output" ]
}
