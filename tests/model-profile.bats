#!/usr/bin/env bats
#
# Resolver matrix for bin/godmode-model <agent> [profile] (unit 1, S3).
#
# The resolver prints "<model> <effort>" on one line. Profiles:
#   balanced -> echoes the agent's own frontmatter model/effort
#   quality  -> code-writers {writer,executor,test-writer} capped at "opus high",
#               every other agent -> "opus xhigh"
#   budget   -> any agent -> "haiku default"
# Profile resolution: no profile arg reads CLAUDE_PLUGIN_OPTION_MODEL_PROFILE;
# unset/empty/invalid env -> balanced (silent, exit 0). A bad profile passed as
# an explicit arg, or an unknown agent, exits non-zero.

load test_helper

MODEL="$PLUGIN_ROOT/bin/godmode-model"

# AC-2: balanced echoes the agent's frontmatter model/effort.
@test "balanced should echo opus high when agent is writer" {
  run "$MODEL" writer balanced
  [ "$status" -eq 0 ]
  [ "$output" = "opus high" ]
}

@test "balanced should echo sonnet high when agent is perf-reviewer" {
  run "$MODEL" perf-reviewer balanced
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet high" ]
}

@test "balanced should echo sonnet high when agent is convention-reviewer" {
  run "$MODEL" convention-reviewer balanced
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet high" ]
}

@test "balanced should echo sonnet high when agent is test-reviewer" {
  run "$MODEL" test-reviewer balanced
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet high" ]
}

@test "balanced should echo opus xhigh when agent is architect" {
  run "$MODEL" architect balanced
  [ "$status" -eq 0 ]
  [ "$output" = "opus xhigh" ]
}

# AC-3: quality maps every non-code-writer to "opus xhigh".
@test "quality should map architect to opus xhigh when agent is non-code-writer" {
  run "$MODEL" architect quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus xhigh" ]
}

@test "quality should map planner to opus xhigh when agent is non-code-writer" {
  run "$MODEL" planner quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus xhigh" ]
}

@test "quality should map verifier to opus xhigh when agent is non-code-writer" {
  run "$MODEL" verifier quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus xhigh" ]
}

@test "quality should map security-auditor to opus xhigh when agent is non-code-writer" {
  run "$MODEL" security-auditor quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus xhigh" ]
}

@test "quality should map perf-reviewer to opus xhigh when agent is non-code-writer" {
  run "$MODEL" perf-reviewer quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus xhigh" ]
}

@test "quality should map code-reviewer to opus xhigh when agent is non-code-writer" {
  run "$MODEL" code-reviewer quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus xhigh" ]
}

@test "quality should map spec-reviewer to opus xhigh when agent is non-code-writer" {
  run "$MODEL" spec-reviewer quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus xhigh" ]
}

@test "quality should map doc-writer to opus xhigh when agent is non-code-writer" {
  run "$MODEL" doc-writer quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus xhigh" ]
}

@test "quality should map researcher to opus xhigh when agent is non-code-writer" {
  run "$MODEL" researcher quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus xhigh" ]
}

# AC-4: quality caps code-writers at "opus high" (never xhigh).
@test "quality should cap writer at opus high when agent is a code-writer" {
  run "$MODEL" writer quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus high" ]
}

@test "quality should cap executor at opus high when agent is a code-writer" {
  run "$MODEL" executor quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus high" ]
}

@test "quality should cap test-writer at opus high when agent is a code-writer" {
  run "$MODEL" test-writer quality
  [ "$status" -eq 0 ]
  [ "$output" = "opus high" ]
}

# AC-5: budget maps any agent to "haiku default".
@test "budget should map writer to haiku default when profile is budget" {
  run "$MODEL" writer budget
  [ "$status" -eq 0 ]
  [ "$output" = "haiku default" ]
}

@test "budget should map architect to haiku default when profile is budget" {
  run "$MODEL" architect budget
  [ "$status" -eq 0 ]
  [ "$output" = "haiku default" ]
}

@test "budget should map perf-reviewer to haiku default when profile is budget" {
  run "$MODEL" perf-reviewer budget
  [ "$status" -eq 0 ]
  [ "$output" = "haiku default" ]
}

# AC-6: env fallback to balanced when no profile arg is given.
@test "should fall back to balanced when CLAUDE_PLUGIN_OPTION_MODEL_PROFILE is unset" {
  unset CLAUDE_PLUGIN_OPTION_MODEL_PROFILE
  run "$MODEL" writer
  [ "$status" -eq 0 ]
  [ "$output" = "opus high" ]
}

@test "should fall back to balanced when CLAUDE_PLUGIN_OPTION_MODEL_PROFILE is empty" {
  export CLAUDE_PLUGIN_OPTION_MODEL_PROFILE=""
  run "$MODEL" writer
  [ "$status" -eq 0 ]
  [ "$output" = "opus high" ]
}

@test "should fall back to balanced when CLAUDE_PLUGIN_OPTION_MODEL_PROFILE is invalid" {
  export CLAUDE_PLUGIN_OPTION_MODEL_PROFILE="garbage"
  run "$MODEL" writer
  [ "$status" -eq 0 ]
  [ "$output" = "opus high" ]
}

# AC-1: error exits for unknown agent and for an explicit bad profile arg.
@test "should exit non-zero when agent is unknown" {
  run "$MODEL" nosuch balanced
  [ "$status" -ne 0 ]
}

@test "should exit non-zero when an explicit profile arg is invalid" {
  run "$MODEL" writer bogus
  [ "$status" -ne 0 ]
}
