#!/usr/bin/env bats
#
# Architect-gate drift coverage (unit 1, S3 — advances AC-6).
#
# Pins the unit-1 contract so a later edit cannot silently delete or hollow it:
#   - rules/godmode-routing.md defines the `## Architect Gate`: the gate names
#     /brief and /plan as its two readers, states the fail-cheap default
#     (absent/empty/unset verdict -> treated as `no`), enumerates the trigger
#     criteria (data model/schema, API, migration, ...), and labels its signal
#     fields (Verdict, Triggers fired, Rationale).
#   - skills/brief/SKILL.md carries the `## Design Risk` signal template with its
#     three fields (Verdict, Triggers fired, Rationale).
#
# These are the source-of-truth definitions downstream skills consume; if a
# reword drops a reader, the default rule, a trigger, or a field, the contract
# breaks and one of these @tests must fail. Assertions are read-only `grep`
# against the real repo files under $PLUGIN_ROOT — they never mutate anything.

load test_helper

ROUTING="$PLUGIN_ROOT/rules/godmode-routing.md"
BRIEF="$PLUGIN_ROOT/skills/brief/SKILL.md"

# --- the Architect Gate definition (routing.md) ---------------------------

# AC-6: the literal gate heading exists — it is the anchor every reader keys on.
@test "godmode-routing.md defines the literal '## Architect Gate' heading" {
  grep -qF '## Architect Gate' "$ROUTING"
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
# treated as `no`. Anchors on the prose ("default-off and fail-cheap" plus the
# absent/empty/unset -> no treatment).
@test "Architect Gate states the fail-cheap default (absent/empty/unset -> no)" {
  gate="$(sed -n '/## Architect Gate/,$p' "$ROUTING")"
  echo "$gate" | grep -qiF 'fail-cheap'
  echo "$gate" | grep -qiE 'absent, empty, or unset'
}

# AC-6: the gate enumerates trigger criteria — representative tokens it wrote.
@test "Architect Gate enumerates trigger criteria (data model/schema, API, migration)" {
  gate="$(sed -n '/## Architect Gate/,$p' "$ROUTING")"
  echo "$gate" | grep -qiE 'data model|schema'
  echo "$gate" | grep -qiF 'API'
  echo "$gate" | grep -qiF 'migration'
}

# AC-6: the gate's signal-format names all three canonical fields — Verdict,
# Triggers fired, Rationale. This pins the source-of-truth labels against the
# brief template (## Design Risk) so the two cannot drift apart.
@test "Architect Gate signal format names all three fields (Verdict, Triggers fired, Rationale)" {
  gate="$(sed -n '/## Architect Gate/,$p' "$ROUTING")"
  echo "$gate" | grep -qF 'Verdict'
  echo "$gate" | grep -qF 'Triggers fired'
  echo "$gate" | grep -qF 'Rationale'
}

# --- the Design Risk signal (brief skill) ---------------------------------

# AC-6: the brief skill carries the literal `## Design Risk` template section.
@test "brief/SKILL.md carries the literal '## Design Risk' section" {
  grep -qF '## Design Risk' "$BRIEF"
}

# AC-6: the Design Risk template carries its three fields — Verdict, Triggers
# fired, and Rationale. Scope to the section (hard-bounded at the next `## `
# heading, exclusive) so the fields are pinned where the template actually lives.
@test "Design Risk section carries its three fields (Verdict, Triggers fired, Rationale)" {
  section="$(awk '/^## Design Risk/{f=1;next} /^## /{f=0} f' "$BRIEF")"
  echo "$section" | grep -qF 'Verdict'
  echo "$section" | grep -qF 'Triggers fired'
  echo "$section" | grep -qF 'Rationale'
}

# --- the architect-in-/brief wiring (unit 2, S2 — advances AC-7) -----------
#
# S1 wired skills/brief/SKILL.md to ACT on the Design Risk verdict: a Process
# step that spawns @architect when the verdict is `yes` (and nothing when
# `no`/absent), with Auto-Mode-vs-interactive-confirm behavior, an opus tier the
# model_profile resolver must not downgrade, and a `## Architecture` template the
# pass feeds. The cases below pin that wiring against the real brief file so a
# later reword cannot hollow it without failing a test. Each scopes its greps to
# the design-pass step (the `### 5.` heading through the `### 6.` heading,
# exclusive) so a stray match elsewhere in the file cannot mask a regression.

# AC-7 (a): the design-pass step spawns @architect on a `yes` verdict, and spawns
# nothing on `no`/absent. Pin both halves: the @architect spawn co-located with
# the `yes` condition, AND the fail-cheap no-spawn-on-`no` statement.
@test "brief design-pass step spawns @architect on verdict yes, nothing on no" {
  step="$(sed -n '/^### 5\. Run the architect design pass/,/^### 6\./p' "$BRIEF")"
  # the spawn target and the yes-verdict gate both live in this step
  echo "$step" | grep -qF '@architect'
  echo "$step" | grep -qiE '`yes`'
  # fail-cheap: no/absent/empty/unset verdict spawns nothing
  echo "$step" | grep -qiF 'spawn **nothing**'
  echo "$step" | grep -qiF 'Fail-cheap'
}

# AC-7 (b): the step names BOTH branches — an interactive recommendation-backed
# confirm (Recommended / confirm) AND Auto Mode spawning automatically.
@test "brief design-pass step names interactive confirm and Auto Mode auto-spawn" {
  step="$(sed -n '/^### 5\. Run the architect design pass/,/^### 6\./p' "$BRIEF")"
  echo "$step" | grep -qiF 'confirm'
  echo "$step" | grep -qiF 'Recommended'
  echo "$step" | grep -qiF 'Auto Mode'
  echo "$step" | grep -qiF 'spawn automatically'
}

# AC-7 (c): the step states the architect runs at opus and that the model_profile
# / godmode-model resolver must NOT downgrade or suppress it. Pin the opus tier,
# the resolver-bypass directive, and the "sole" cost-control / "does not
# downgrade" wording.
@test "brief design-pass step keeps architect at opus, model_profile must not downgrade it" {
  step="$(sed -n '/^### 5\. Run the architect design pass/,/^### 6\./p' "$BRIEF")"
  echo "$step" | grep -qiF 'opus'
  echo "$step" | grep -qF 'godmode-model'
  echo "$step" | grep -qiF 'does not downgrade'
  echo "$step" | grep -qiF 'sole'
}

# AC-7 (d): the BRIEF.md template carries a `## Architecture` heading with all
# three parts — Context, Recommended Approach, Tradeoffs. Scope to the section
# (bounded at the next `## ` heading, exclusive) so the parts are pinned where
# the template actually lives.
@test "brief template carries a '## Architecture' section with Context, Recommended Approach, Tradeoffs" {
  grep -qF '## Architecture' "$BRIEF"
  section="$(awk '/^## Architecture/{f=1;next} /^## /{f=0} f' "$BRIEF")"
  echo "$section" | grep -qF '### Context'
  echo "$section" | grep -qF '### Recommended Approach'
  echo "$section" | grep -qF '### Tradeoffs'
}
