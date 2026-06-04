#!/usr/bin/env bats
#
# Architect-gate drift coverage (mission 05, unit 1 S3 — advances AC-6).
#
# Pins the unit-1 contract so a later edit cannot silently delete or hollow it:
#   - rules/godmode-routing.md defines the `## Architect Gate` (S1): the gate
#     names /brief and /plan as its two readers, states the fail-cheap default
#     (absent/empty/unset verdict -> treated as `no`), and enumerates the
#     trigger criteria (data model/schema, API, migration, ...).
#   - skills/brief/SKILL.md carries the `## Design Risk` signal template (S2)
#     with its three fields (verdict, triggers fired, rationale).
#
# These are the source-of-truth definitions downstream skills consume; if a
# reword drops a reader, the default rule, a trigger, or a field, the contract
# breaks and one of these @tests must fail. Assertions are read-only `grep`
# against the real repo files under $PLUGIN_ROOT — they never mutate anything.

load test_helper

ROUTING="$PLUGIN_ROOT/rules/godmode-routing.md"
BRIEF="$PLUGIN_ROOT/skills/brief/SKILL.md"

# --- S1: the Architect Gate definition in routing ------------------------

# AC-6: the literal gate heading exists — it is the anchor every reader keys on.
@test "godmode-routing.md defines the literal '## Architect Gate' heading" {
  run grep -F '## Architect Gate' "$ROUTING"
  [ "$status" -eq 0 ]
}

# AC-6: the gate names BOTH /brief and /plan as its readers. Scope the search to
# the gate section (from its heading onward) so a stray /brief elsewhere in the
# file cannot mask a regression inside the gate.
@test "Architect Gate names both /brief and /plan as its readers" {
  gate="$(sed -n '/## Architect Gate/,$p' "$ROUTING")"
  echo "$gate" | grep -qF '/brief'
  echo "$gate" | grep -qF '/plan'
}

# AC-6: the gate states the fail-cheap default — an absent/empty/unset verdict is
# treated as `no`. Anchors on the S1 prose ("default-off and fail-cheap" plus the
# absent/empty/unset -> no treatment).
@test "Architect Gate states the fail-cheap default (absent/empty/unset -> no)" {
  gate="$(sed -n '/## Architect Gate/,$p' "$ROUTING")"
  echo "$gate" | grep -qiF 'fail-cheap'
  echo "$gate" | grep -qiE 'absent, empty, or unset'
}

# AC-6: the gate enumerates trigger criteria — representative tokens S1 wrote.
@test "Architect Gate enumerates trigger criteria (data model/schema, API, migration)" {
  gate="$(sed -n '/## Architect Gate/,$p' "$ROUTING")"
  echo "$gate" | grep -qiE 'data model|schema'
  echo "$gate" | grep -qiF 'API'
  echo "$gate" | grep -qiF 'migration'
}

# --- S2: the Design Risk signal template in the brief skill ---------------

# AC-6: the brief skill carries the literal `## Design Risk` template section.
@test "brief/SKILL.md carries the literal '## Design Risk' section" {
  run grep -F '## Design Risk' "$BRIEF"
  [ "$status" -eq 0 ]
}

# AC-6: the Design Risk template carries its three fields — verdict, triggers
# fired, and rationale. Scope to the section so the fields are pinned where the
# template actually lives.
@test "Design Risk section carries its three fields (verdict, triggers fired, rationale)" {
  section="$(sed -n '/## Design Risk/,/^## /p' "$BRIEF")"
  echo "$section" | grep -qiF 'Verdict'
  echo "$section" | grep -qiF 'Triggers fired'
  echo "$section" | grep -qiF 'Rationale'
}
