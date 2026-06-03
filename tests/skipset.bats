#!/usr/bin/env bats
#
# godmode-skipset — transitive descendant closure over a step-dependency graph.
#
# When a build step fails, every step that (transitively) dependsOn it must be
# skipped. godmode-skipset reads a `dependsOn` adjacency on stdin and a failed
# step argument, then prints the descendant closure: every step that must be
# skipped, one per line, sorted/de-duplicated, EXCLUDING the failed step itself.
#
# This suite locks AC-3 (the closure algorithm) — transitive reach, leaf
# behaviour, deterministic prefix-safe output, and termination on a cyclic
# adjacency — so the pure-function contract cannot silently regress.

load test_helper

SKIPSET="$PLUGIN_ROOT/bin/godmode-skipset"

# The canonical adjacency used by most cases:
#   S1: none      S2: none      S3 dependsOn S1      S4 dependsOn S3
# so failing S1 must skip S3 (direct) and S4 (transitive), but never S2.
ADJ='S1: none
S2: none
S3: S1
S4: S3'

@test "AC-3: transitive closure — failing S1 skips S3 and S4, not S2" {
  run bash -c "printf '%s\n' '$ADJ' | '$SKIPSET' S1"
  [ "$status" -eq 0 ]
  # Output is exactly the two sorted lines S3 and S4.
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "S3" ]
  [ "${lines[1]}" = "S4" ]
  # The independent step S2 is never in the closure.
  [[ "$output" != *"S2"* ]]
}

@test "AC-3: leaf failure — S2 has no dependents -> empty output, exit 0" {
  run bash -c "printf '%s\n' '$ADJ' | '$SKIPSET' S2"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC-3: leaf failure — S4 is a sink -> empty output, exit 0" {
  run bash -c "printf '%s\n' '$ADJ' | '$SKIPSET' S4"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC-3: direct vs transitive — failing S3 skips only S4" {
  run bash -c "printf '%s\n' '$ADJ' | '$SKIPSET' S3"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "S4" ]
}

@test "AC-3: deterministic order — multiple dependents yield a sorted, unique list" {
  # S3 and S5 both depend directly on S1; S4 depends on S3. Failing S1 must skip
  # all three in sorted, de-duplicated order regardless of adjacency line order.
  adj='S2: none
S5: S1
S3: S1
S4: S3
S1: none'
  run bash -c "printf '%s\n' '$adj' | '$SKIPSET' S1"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "S3" ]
  [ "${lines[1]}" = "S4" ]
  [ "${lines[2]}" = "S5" ]
}

@test "AC-3: prefix safety — S1 closure never includes S10 via substring match" {
  # S10 depends on S2 (independent of S1). A naive substring membership test
  # ("S1" in "S10") would wrongly pull S10 into S1's closure.
  adj='S1: none
S2: none
S3: S1
S4: S3
S10: S2'
  run bash -c "printf '%s\n' '$adj' | '$SKIPSET' S1"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "S3" ]
  [ "${lines[1]}" = "S4" ]
  [[ "$output" != *"S10"* ]]
}

@test "AC-3: cyclic adjacency terminates — closure does not loop forever" {
  # A cycle S1 -> S2 -> S1 (each dependsOn the other) plus S3 dependsOn S2.
  # The BFS relies on the membership set to stop re-expanding; this proves it
  # terminates (the test would hang otherwise) and yields the reachable set.
  adj='S1: S2
S2: S1
S3: S2'
  run bash -c "printf '%s\n' '$adj' | '$SKIPSET' S1"
  [ "$status" -eq 0 ]
  # Failing S1: S2 dependsOn S1 (direct), S3 dependsOn S2 (transitive); S1 is
  # excluded from its own closure even though the cycle points back at it.
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "S2" ]
  [ "${lines[1]}" = "S3" ]
  [[ "$output" != *"S1"* ]]
}

@test "AC-3: unknown failed step — not a key in the adjacency -> empty, exit 0" {
  # A failed step that nothing depends on (and that is absent as a key) has an
  # empty closure; the contract is an empty output and a clean exit.
  run bash -c "printf '%s\n' '$ADJ' | '$SKIPSET' S99"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC-3: missing argument — no failed step -> non-zero exit, usage to stderr" {
  run bash -c "printf '%s\n' '$ADJ' | '$SKIPSET'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}
