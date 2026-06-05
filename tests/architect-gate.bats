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
PLAN_SKILL="$PLUGIN_ROOT/skills/plan/SKILL.md"
AGENTS="$PLUGIN_ROOT/AGENTS.md"

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
# the design-pass step (the `### 5.` heading through the `### 6.` heading
# (inclusive); none of the grep targets match that heading, so the scope is
# effectively step 5) so a stray match elsewhere in the file cannot mask a
# regression.

# AC-7: the design-pass step spawns @architect on a `yes` verdict, and spawns
# nothing on `no`/absent. Pin both halves: the @architect spawn co-located with
# the `yes` condition, AND the fail-cheap no-spawn-on-`no` statement.
@test "brief design-pass step spawns @architect on verdict yes, nothing on no" {
  step="$(sed -n '/^### 5\. Run the architect design pass/,/^### 6\./p' "$BRIEF")"
  # the spawn target and the yes-verdict gate both live in this step
  echo "$step" | grep -qF '@architect'
  echo "$step" | grep -qF '`yes`'
  # fail-cheap: no/absent/empty/unset verdict spawns nothing
  echo "$step" | grep -qiF 'spawn **nothing**'
  echo "$step" | grep -qiF 'Fail-cheap'
}

# AC-7: the step names BOTH branches — an interactive recommendation-backed
# confirm (Recommended / confirm) AND Auto Mode spawning automatically.
@test "brief design-pass step names interactive confirm and Auto Mode auto-spawn" {
  step="$(sed -n '/^### 5\. Run the architect design pass/,/^### 6\./p' "$BRIEF")"
  echo "$step" | grep -qiF 'confirm'
  echo "$step" | grep -qiF 'Recommended'
  echo "$step" | grep -qiF 'Auto Mode'
  echo "$step" | grep -qiF 'spawn automatically'
}

# AC-7: the step states the architect runs at opus and that the model_profile
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

# AC-7: the BRIEF.md template carries a `## Architecture` heading with all
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

# AC-6: the design-pass step forbids a sidecar artifact — the architect output is
# distilled into BRIEF.md's `## Architecture` section ONLY, preserving the
# one-brief-per-unit invariant. Pin the no-sidecar clause (the `ARCHITECT.md`
# token AND the word "sidecar") so a reword cannot reintroduce a second artifact
# without failing this test. Scoped to step 5 via the same sed range.
@test "brief design-pass step forbids a sidecar artifact (distill into BRIEF.md only)" {
  step="$(sed -n '/^### 5\. Run the architect design pass/,/^### 6\./p' "$BRIEF")"
  echo "$step" | grep -qF 'ARCHITECT.md'
  echo "$step" | grep -qiF 'sidecar'
}

# AC-5: the design-pass step pins the fixed Design Risk -> architect -> ACs
# ordering, so the architect pass runs before the acceptance criteria and its
# output can inform them. Pin the explicit ordering statement; scoped to step 5.
@test "brief design-pass step pins the Design Risk -> architect -> ACs ordering" {
  step="$(sed -n '/^### 5\. Run the architect design pass/,/^### 6\./p' "$BRIEF")"
  echo "$step" | grep -qiF 'The ordering is fixed'
}

# --- the architect-in-/plan wiring (unit 3, S2 — advances AC-7) -------------
#
# S1 wired skills/plan/SKILL.md to ACT on the Design Risk verdict /brief
# recorded: a plan-focused design-pass step (`### 2.`) that spawns @architect
# when the verdict is `yes` (and nothing when `no`/absent), asks for the
# plan-focused dimensions (implementation order / sequencing / risks) rather than
# /brief's spec-focused Context/Approach/Tradeoffs, re-invokes every time (never
# reuses the brief's `## Architecture` to skip the spawn), carries the
# Auto-Mode-vs-interactive-confirm behavior, keeps the architect at opus (the
# model_profile resolver must not downgrade it), and feeds a `## Design Notes`
# PLAN.md template. The cases below pin that wiring against the real plan file so
# a later reword cannot hollow it without failing a test. Each scopes its greps
# to the design-pass step (the `### 2.` heading through the `### 3.` heading,
# inclusive; none of the grep targets match the `### 3.` heading, so the scope is
# effectively step 2) so a stray match elsewhere in the file cannot mask a
# regression.

# AC-7: the plan design-pass step spawns @architect on a `yes` verdict, and spawns
# nothing on `no`/absent. Pin both halves: the @architect spawn co-located with
# the `yes` condition, AND the fail-cheap no-spawn statement.
@test "plan design-pass step spawns @architect on verdict yes, nothing on no" {
  step="$(sed -n '/^### 2\. Run the architect design pass/,/^### 3\./p' "$PLAN_SKILL")"
  echo "$step" | grep -qF '@architect'
  echo "$step" | grep -qF '`yes`'
  # fail-cheap: no/absent/empty/unset verdict spawns nothing
  echo "$step" | grep -qiF 'spawn **nothing**'
  echo "$step" | grep -qiF 'Fail-cheap'
}

# AC-7: the step states it always re-invokes (never reuses the brief's
# `## Architecture` to skip the spawn) and asks for the plan-focused dimensions.
# Pin the always-re-invoke directive, the distinctive 'implementation order'
# framing, and that the brief's `## Architecture` is handed in as context.
@test "plan design-pass step always re-invokes and asks for plan-focused framing" {
  step="$(sed -n '/^### 2\. Run the architect design pass/,/^### 3\./p' "$PLAN_SKILL")"
  echo "$step" | grep -qiF 'always re-invoke'
  echo "$step" | grep -qiF 'implementation order'
  echo "$step" | grep -qiF 'sequencing'
  echo "$step" | grep -qiF 'risks'
  echo "$step" | grep -qF '## Architecture'
  # AC-7(b): the brief's `## Architecture` is handed in distinctively *as context*
  # (an input), not merely mentioned. `as context` is unique to the hands-as-context
  # sentence, so this pins the input semantic the bare `## Architecture` grep cannot.
  echo "$step" | grep -qiF 'as context'
}

# AC-7: the step names BOTH branches — an interactive recommendation-backed
# confirm (Recommended / confirm) AND Auto Mode spawning automatically.
@test "plan design-pass step names interactive confirm and Auto Mode auto-spawn" {
  step="$(sed -n '/^### 2\. Run the architect design pass/,/^### 3\./p' "$PLAN_SKILL")"
  echo "$step" | grep -qiF 'confirm'
  echo "$step" | grep -qiF 'Recommended'
  echo "$step" | grep -qiF 'Auto Mode'
  echo "$step" | grep -qiF 'spawn automatically'
}

# AC-7: the step states the architect runs at opus and that the model_profile
# / godmode-model resolver must NOT downgrade or suppress it. Pin the opus tier,
# the resolver-bypass directive, and the "sole" cost-control / "does not
# downgrade" wording.
@test "plan design-pass step keeps architect at opus, model_profile must not downgrade it" {
  step="$(sed -n '/^### 2\. Run the architect design pass/,/^### 3\./p' "$PLAN_SKILL")"
  echo "$step" | grep -qiF 'opus'
  echo "$step" | grep -qF 'godmode-model'
  echo "$step" | grep -qiF 'does not downgrade'
  echo "$step" | grep -qiF 'sole'
}

# AC-7: the PLAN.md template carries a `## Design Notes` heading — the section the
# plan-focused architect output is distilled into. Scope to the artifact template
# block (from its `# Plan NN` header onward) so the heading is pinned where the
# template actually lives, mirroring how case 13 scopes `## Architecture`.
@test "plan template carries a '## Design Notes' section" {
  # Scope to the artifact template block only — an unscoped file-wide grep would
  # pass on the prose mention in step 2 rather than the actual template heading.
  template="$(sed -n '/^# Plan NN/,$p' "$PLAN_SKILL")"
  echo "$template" | grep -qF '## Design Notes'
}

# --- the reconciled /mission delegation row (unit 4, S3 — advances AC-6, AC-7) ---
#
# A prior draft of the `## Skill → Agent delegation map` falsely paired `/mission`
# with `@architect` (roadmap shaping) — but roadmap shaping is the /mission skill's
# own work and spawns no agent. S1 corrected the routing rule's row to name no
# agent, and S2 regenerated AGENTS.md so its mirrored table carries the same
# corrected row. The two cases below pin that reconciled state so the false row
# cannot silently reappear in EITHER the source rule or the generated mirror: each
# extracts the delegation-map section (bounded at the next `## ` heading, exclusive,
# matching the Design Risk case above), isolates the single `/mission` table row
# within it, and asserts that row names no `architect` (case-insensitive). Read-only
# greps; nothing is mutated.

# AC-6: the routing rule's delegation-map `/mission` row spawns no agent — it must
# not name `architect`. Scope to the map section (exclusive of the heading and the
# next section's heading), then isolate the `/mission` table row by its cell anchor
# (`| `/mission``) so a `/mission`-prefixed sibling like `/mission-extended` can't
# fold into the match and an unrelated `architect` row elsewhere can't trip a false
# failure. Then assert the section never pairs `/mission` with `@architect` at all —
# any reworded reintroduction (with or without the original parenthetical) is caught.
@test "routing delegation map: /mission row carries no @architect" {
  map="$(awk '/^## Skill → Agent delegation map/{f=1;next} /^## /{f=0} f' "$ROUTING")"
  row="$(echo "$map" | grep -F '| `/mission`')"
  # exactly the one /mission table row, and it names no architect
  [ -n "$row" ]
  echo "$row" | grep -qiv 'architect'
  # no reworded false pairing anywhere in the map section
  ! echo "$map" | grep -qiE '/mission.*@architect'
}

# AC-7: the AGENTS.md mirror of the delegation map must carry the SAME corrected
# `/mission` row — a stale regen reintroducing a `/mission`→`@architect` pairing is
# caught here. Same scoping discipline as the routing case.
@test "AGENTS.md delegation map mirror: /mission row carries no @architect" {
  map="$(awk '/^## Skill → Agent delegation map/{f=1;next} /^## /{f=0} f' "$AGENTS")"
  row="$(echo "$map" | grep -F '| `/mission`')"
  [ -n "$row" ]
  echo "$row" | grep -qiv 'architect'
  ! echo "$map" | grep -qiE '/mission.*@architect'
}

# --- the reconciled /brief + /plan delegation rows (unit 5, S4 — advances AC-8, AC-9) ---
#
# The same `## Skill → Agent delegation map` that falsely paired /mission with
# @architect ALSO, before this unit, listed /brief and /plan WITHOUT @architect —
# omitting the gated design pass S1–S3 wired in. S1 reconciled the routing rule's
# /brief and /plan rows to name `@architect` with its "gated on Design Risk"
# qualifier, and S2 regenerated AGENTS.md so its mirror carries the same rows. The
# two cases below pin that reconciled state so neither row can silently regress to
# its stale, @architect-less form in EITHER the source rule or the generated
# mirror. They are the inverse of the unit-4 /mission pins: PRESENCE assertions
# (each row MUST name @architect AND carry the gating qualifier), using the same
# exclusive-bound section extraction and cell-anchored row isolation. Each row is
# guarded non-empty so a row rename cannot vacuously pass. Read-only greps; nothing
# is mutated. (AC-9 keeps this change confined to the test file.)

# AC-8: the routing rule's delegation-map /brief and /plan rows each name
# @architect AND carry the gating qualifier (design risk / gated). Scope to the map
# section (exclusive of the heading and the next section's heading), then isolate
# each row by its full cell anchor (`| `/brief N`` / `| `/plan N``) so a sibling
# can't fold in and a stray @architect elsewhere can't mask a
# regression. Non-empty guard catches a row rename; the @architect + qualifier
# greps catch a revert to the stale, architect-less form.
@test "routing delegation map: /brief and /plan rows name gated @architect" {
  map="$(awk '/^## Skill → Agent delegation map/{f=1;next} /^## /{f=0} f' "$ROUTING")"
  brief_row="$(echo "$map" | grep -F '| `/brief N`')"
  plan_row="$(echo "$map" | grep -F '| `/plan N`')"
  [ -n "$brief_row" ]
  [ -n "$plan_row" ]
  echo "$brief_row" | grep -qF '@architect'
  echo "$brief_row" | grep -qiE 'design risk|gated'
  echo "$plan_row" | grep -qF '@architect'
  echo "$plan_row" | grep -qiE 'design risk|gated'
}

# AC-8: the AGENTS.md mirror of the delegation map must carry the SAME reconciled
# /brief and /plan rows — a stale regen dropping @architect from either row is
# caught here. Same scoping discipline as the routing case.
@test "AGENTS.md delegation map mirror: /brief and /plan rows name gated @architect" {
  map="$(awk '/^## Skill → Agent delegation map/{f=1;next} /^## /{f=0} f' "$AGENTS")"
  brief_row="$(echo "$map" | grep -F '| `/brief N`')"
  plan_row="$(echo "$map" | grep -F '| `/plan N`')"
  [ -n "$brief_row" ]
  [ -n "$plan_row" ]
  echo "$brief_row" | grep -qF '@architect'
  echo "$brief_row" | grep -qiE 'design risk|gated'
  echo "$plan_row" | grep -qF '@architect'
  echo "$plan_row" | grep -qiE 'design risk|gated'
}
