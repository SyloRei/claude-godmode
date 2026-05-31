#!/usr/bin/env bash
# PreToolUse hook: enforce quality-gate discipline on git commits.
#
# Contract (Claude Code hooks):
#   - stdin is the event JSON: { tool_name, tool_input: { command, ... }, cwd, ... }
#   - exit 2  => BLOCK the tool call; stderr is fed back to Claude.
#   - exit 0  => allow; stdout (if valid JSON) is parsed, else added as context.
#
# This hook DISCOURAGES the common ways to skip commit verification: it blocks
# `--no-verify` / `-n` / `--no-verify=...` and the `-c core.hooksPath=...`
# trick. It is a discipline nudge, NOT a security boundary: a determined caller
# can still skip git hooks via a git alias or other config, which a stdin
# string-scanner cannot fully enumerate. The real safety net is the secret-scan
# hook (pre-tool-use-secrets.sh), which runs as a Claude Code PreToolUse hook
# and is unaffected by git's own hook-path settings. This is the first link in
# the PreToolUse chain; additional safety checks append after it.
#
# bash 3.2 compatible. JSON read via jq only — never from pwd, never via
# string interpolation.

set -euo pipefail
# noglob: the unquoted `for tok in $seg` loops rely on word-splitting only.
# Without -f, a trailing `*` (e.g. `git commit -m wip *`) would pathname-expand,
# and a file literally named `-n` in the cwd would surface as a bogus bypass
# token. -f disables globbing but NOT word-splitting; `case` patterns are
# unaffected — the hook only ever pattern-matches, it never relies on a glob.
set -f

# Read the full event from stdin. Guard against early EOF under pipefail.
INPUT="$(cat 2>/dev/null || true)"

# Fail open on empty stdin.
if [ -z "$INPUT" ]; then
  exit 0
fi

# Cheap raw pre-filter (performance): a git-commit bypass always carries the
# substring `commit` somewhere in the event JSON (it is part of the command
# string). If the raw input has no `commit` at all, there is nothing to guard —
# skip the jq parse and every subprocess below. Pure performance gate: it only
# ever lets calls THROUGH (every blockable form contains `commit`), so it adds
# no false negative; it just spares the common non-commit Bash call the
# `command -v jq` and jq forks entirely.
case "$INPUT" in
  *commit*) : ;;
  *) exit 0 ;;
esac

# We need jq to parse the event; fail open if it is unavailable.
if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

# Extract the tool name and the proposed command in a SINGLE jq call. jq emits
# the tool name on the first line and the command (which may legitimately span
# multiple lines, contain backslashes, or carry control bytes) as everything
# after the first newline — `@tsv`/`@csv` would escape those control bytes and
# defeat the carriage-return and line-continuation handling below, so a raw
# newline-joined format string is used instead. // empty keeps absent fields as
# empty strings; a jq failure (garbage stdin) leaves both empty, so the guards
# below fall through to a fail-open exit 0. jq always emits exactly one newline
# between the two fields, so the first line is the tool name and the remainder
# is the command.
_RAW_FIELDS="$(printf '%s' "$INPUT" \
  | jq -r '"\(.tool_name // empty)\n\(.tool_input.command // empty)"' 2>/dev/null || true)"
TOOL_NAME="${_RAW_FIELDS%%$'\n'*}"
COMMAND="${_RAW_FIELDS#*$'\n'}"

# Only inspect Bash tool calls; pass everything else through untouched.
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# Fast pre-filter: a real `git commit` invocation always contains BOTH the
# substrings `git` and `commit` somewhere in the command (even the grouping,
# redirect, and line-continuation forms handled below keep both). A command
# missing either cannot be a commit, so short-circuit it here and spare the
# common non-commit path the sed/tr/mktemp/segment-split work below. This is a
# pure performance gate: it introduces NO false negative (every blockable form
# still contains both substrings) and NO false positive (it only lets commands
# THROUGH; the real classification happens per segment afterward).
case "$COMMAND" in
  *git*commit*) : ;;
  *) exit 0 ;;
esac

# Detect a --no-verify / -n bypass attempt using per-segment, commit-scoped
# detection.
#
# Strategy (each numbered step is implemented in order below):
#   1. Fold backslash-newline line continuations, then strip quoted strings and
#      normalize stray control whitespace.
#   2. Split the command into pipeline/compound segments. To handle command
#      substitutions WITHOUT chopping a flag away from its `git commit` when a
#      substitution sits between them, classify TWO derived streams of the
#      command (see _emit_segments): a substitution-COLLAPSED stream (each
#      $(...) / `...` span blanked to a space, then split on shell separators
#      ONLY — parens kept intact) and a substitution-EXPOSING stream (split on
#      the substitution delimiters $( ) ` too, so an inner nested commit becomes
#      its own segment). A bypass in EITHER stream blocks.
#   3. For each quote-stripped segment, classify whether it is a `git commit`
#      invocation (drop leading env assignments / grouping / redirect tokens and
#      command wrappers like command/exec/env/sudo and shell keywords; basename-
#      normalize a path so /usr/bin/git counts; first command word must be `git`;
#      first non-global token must be `commit`).
#   4. Only within a commit segment, scan for bypass flags (--no-verify / -n /
#      short clusters containing n / an attached -c…hooksPath that survived the
#      quote strip).
#   5. The QUOTED -c hooksPath bypass (git -c 'core.hooksPath=…' commit) cannot
#      be seen in step 4 — the quote strip erases the value. So a separate RAW
#      pass applies the SAME dual-stream split to the unmodified command and, for
#      each raw segment that is itself a git-commit invocation, checks its
#      pre-subcommand global-flag region for a -c carrying hooksPath
#      (case-insensitive). Scoping to genuine commit segments keeps non-commit
#      commands (git -c core.hooksPath=x log/status/fetch, and a
#      `git -c … diff | grep commit` pipeline) allowed, and scoping to the
#      global region keeps a commit MESSAGE that merely mentions the word
#      hooksPath allowed.
#   6. If no segment triggers a bypass, exit 0.

# Step 1a: fold backslash-newline continuations. `git \<newline>commit …` is ONE
# command to bash, but the bare newline would otherwise be read as a segment
# separator in Step 2. A backslash immediately followed by a newline is the
# continuation; collapse the pair to a single space so the command rejoins. A
# bare newline (no preceding backslash) is left intact — it stays a real
# separator. awk joins a line ending in an odd-positioned trailing backslash to
# the next (BSD/macOS awk safe: no GNU extensions).
#
# Performance: a backslash-newline continuation REQUIRES a literal backslash in
# the command. The overwhelmingly common commit form has none, so gate the awk
# fork behind a cheap in-shell backslash-presence test — when there is no `\` at
# all there is nothing to fold and JOINED is just COMMAND. This is behavior-
# preserving (the awk pass is an identity transform on backslash-free input) and
# spares the hot path one fork.
case "$COMMAND" in
  *\\*)
    JOINED="$(printf '%s' "$COMMAND" | awk '
      { line = $0
        # Strip a single trailing backslash that continues onto the next line.
        if (substr(line, length(line), 1) == "\\") {
          printf "%s ", substr(line, 1, length(line) - 1)
        } else {
          printf "%s\n", line
        }
      }')"
    ;;
  *)
    JOINED="$COMMAND"
    ;;
esac

# Step 1b: replace every single- and double-quoted segment with a PLACEHOLDER
# word, then normalize stray control whitespace to spaces. [^"]* / [^']* are
# BSD-compatible (no PCRE). The placeholder ` _GMQUOTED_ ` (NOT deletion) erases
# the bypass-shaped TEXT of a quoted message (AC-4) while keeping a WORD where the
# value was — mirroring _GMSUBST_ for substitutions. This matters for an empty or
# erased value-flag argument: `git commit -m "" --no-verify` deletion-stripped to
# `git commit -m  --no-verify`, so `-m`'s value-skip swallowed the real
# `--no-verify`; with the placeholder it becomes `git commit -m _GMQUOTED_
# --no-verify`, `-m` consumes the placeholder, and `--no-verify` is still scanned
# (BLOCK). AC-4 still passes: `git commit -m "…-n…--no-verify…"` ->
# `git commit -m _GMQUOTED_` -> `-m` consumes the placeholder, nothing else is a
# flag (exit 0). The placeholder is non-flag, non-`git`, non-`commit`, so it never
# classifies a segment nor trips the scan on its own. This applies to the SCAN
# (Pass A) stream ONLY; Pass B walks the quote-intact $JOINED so the quoted
# hooksPath value stays visible there. The `tr` maps carriage return (\015),
# vertical tab (\013) and form feed (\014) to spaces so a control char adjacent
# to `git`/`commit` cannot split the subcommand token and dodge the equality
# check. Newline (\n) is deliberately NOT mapped — it is a real segment separator
# (Step 2). Normalization only ever errs toward blocking: a segment must still
# classify as a genuine `git commit` invocation to be scanned, so it cannot
# create a false positive.
SCAN="$(printf '%s' "$JOINED" \
  | sed -e 's/"[^"]*"/ _GMQUOTED_ /g' -e "s/'[^']*'/ _GMQUOTED_ /g" \
  | tr '\015\013\014' '   ')"

# Step 2: split into segments. Two temp files: the quote-stripped SCAN segments
# (classification + -n scan, Steps 3-4) and the RAW segments (the quoted-
# hooksPath pass, Step 5). Writing to files lets the while loops read via a
# redirect so variable assignments (BYPASS) stay in this shell, not a subshell
# (bash 3.2 / BSD: no mapfile/readarray, no process substitution).
_SEGTMP="$(mktemp)"
_RAWTMP="$(mktemp)"
# Double-quoted so the captured paths are expanded at trap-definition time (the
# values we just created), not re-evaluated at trap-firing time.
# shellcheck disable=SC2064
trap "rm -f '$_SEGTMP' '$_RAWTMP'" EXIT INT TERM

# Separator-only split: translate the shell separators &&, ||, |, ;, &, and
# literal newlines to newline — LONGEST/compound separators first (&& before a
# lone &; || before |) so the compound operator is consumed before its single-
# char form matches and only a genuine background & remains. Parens and backtick
# are deliberately NOT split here.
_split_separators() {
  sed \
    -e 's/&&/\
/g' \
    -e 's/&/\
/g' \
    -e 's/||/\
/g' \
    -e 's/|/\
/g' \
    -e 's/;/\
/g'
}

# Substitution-exposing split: the separator split PLUS the grouping /
# substitution delimiters `(`, `)`, and a backtick, so a `git commit` nested
# inside a substitution (e.g. `echo $(git commit --no-verify)`) becomes its OWN
# clean segment and is classified — without the split its outer word
# (`echo`/`foo=`) would mask the commit, and a closing `)` glued to the final
# flag token (`--no-verify)`) would dodge the exact-match bypass scan. After the
# quote strip these characters are always shell syntax, never data, so splitting
# on them is safe; over-splitting only ever produces more segments, each still
# independently classified — it cannot manufacture a false positive. The bracket
# classes [(] / [)] match the literal parens without sed BRE metacharacter
# ambiguity.
_split_subst() {
  sed \
    -e 's/&&/\
/g' \
    -e 's/&/\
/g' \
    -e 's/||/\
/g' \
    -e 's/|/\
/g' \
    -e 's/;/\
/g' \
    -e 's/[(]/\
/g' \
    -e 's/[)]/\
/g' \
    -e 's/`/\
/g'
}

# Substitution-COLLAPSED stream feed: replace each command-substitution span —
# `$(...)` and a backtick pair — with a single placeholder TOKEN so the
# surrounding command rejoins intact. This is the stream that keeps
# `git commit $(true) --no-verify` whole (-> `git commit _GMSUBST_ --no-verify`,
# still a scannable commit) WITHOUT the paren split that would otherwise chop the
# flag away from the commit segment. A placeholder WORD (not a bare space) is
# used so that when a value-flag's argument was itself a substitution
# (`git commit -m $(echo hi) --no-verify`), the flag consumes the placeholder —
# not the real `--no-verify` that follows — and the bypass is still scanned. The
# placeholder is non-flag, non-`git`, non-`commit`, so it never classifies a
# segment nor trips the scan on its own. Conversely `echo $(git commit
# --no-verify)` collapses to `echo _GMSUBST_` (no commit) on THIS stream — the
# EXPOSING stream below catches that inner case instead. BSD/macOS sed, non-PCRE:
# [^)] / [^`] stop at the first closing delimiter, so a single un-nested
# substitution per span is collapsed. Nested substitutions `$( … $( … ) … )`
# remain an acknowledged un-enumerable gap (see header).
_collapse_subst() {
  # The sed scripts are single-quoted on purpose: `\$(` and the backtick pair are
  # sed REGEX literals (a literal `$`, `(`, and backtick), NOT shell expansions.
  # shellcheck disable=SC2016
  sed \
    -e 's/\$([^)]*)/ _GMSUBST_ /g' \
    -e 's/`[^`]*`/ _GMSUBST_ /g'
}

# _emit_segments: write the derived segment stream(s) of $1 to stdout. A bypass
# in EITHER stream is caught because the caller classifies+scans every line. Used
# for both SCAN (Pass A) and RAW (Pass B).
#
# Performance: the substitution-COLLAPSE and substitution-EXPOSING work only ever
# differs from a plain separator split when the input actually contains a command
# substitution or grouping delimiter — `$(`, a backtick, or a literal paren. With
# none of those present, `_collapse_subst` is an identity transform and
# `_split_subst` produces the exact same lines as `_split_separators` (they
# differ only in the extra `(` `)` backtick rules). So when the input carries no
# such delimiter, emit a SINGLE separator-split stream — skipping the
# `_collapse_subst` sed fork and the entire second (exposing) stream. This is
# behavior-preserving: the dual streams collapse to one identical stream on
# substitution-free input. The common `git commit -m wip` / `git log | grep
# commit` path takes this branch and saves several forks.
_emit_segments() {
  # The single-quoted `'$('` is an intentional LITERAL substring to match (a
  # dollar followed by a paren), not a shell expansion — keep it single-quoted.
  # shellcheck disable=SC2016
  case "$1" in
    *'$('* | *'`'* | *'('* | *')'*)
      printf '%s\n' "$1" | _collapse_subst | _split_separators
      printf '%s\n' "$1" | _split_subst
      ;;
    *)
      printf '%s\n' "$1" | _split_separators
      ;;
  esac
}

_emit_segments "$SCAN" > "$_SEGTMP"
# RAW segments come from the line-continuation-folded command so the same
# `git \<newline>commit` form rejoins here too; quotes are intact so the
# hooksPath value is visible.
_emit_segments "$JOINED" > "$_RAWTMP"

BYPASS=0

# first_command_word: given a segment, find its first real command word —
# skipping leading environment assignments (VAR=val), shell-grouping / subshell
# openers ( { $( ` , redirection tokens (>f, >>f, <f, 2>f, &>f, …), and known
# command wrappers (command/exec/env/sudo/…) — normalizing a path to its
# basename so /usr/bin/git is recognized as git. Used by both passes so
# `( git commit … )`, `$(git commit …)`, `` `git commit …` ``, `>f git commit …`,
# `command git commit …`, and `/usr/bin/git commit …` are all still recognized
# as git invocations. The result is PUBLISHED in the global `FCW` (set, not
# echoed) so the caller need not fork a command-substitution subshell per
# segment on the hot commit path.
#
# Wrappers that carry their OWN option grammar before the wrapped command
# (`timeout 5 git …`, `nice -n 5 git …`, `sudo -u bob git …`, `xargs -I {} git
# …`, `ionice -c2 git …`, `env -i VAR=v git …`) are handled by consuming the
# wrapper's leading run of `-*` options, the one VALUE token of a known separate-
# value option (`-n`/`-u`/`-g`/`-I`/`-c`/…), and — for a wrapper that takes a
# bare leading POSITIONAL like `timeout`'s DURATION — exactly one bare token,
# before resolving the wrapped command word. Without this the wrapper's option or
# its value (`5`, `-n`, `bob`) was read AS the command word, so `git` was never
# seen and the commit bypass was never scanned (the regression this closes).
# Realistic agent-emitted forms are covered; full POSIX wrapper-option grammars
# stay an acknowledged un-enumerable gap (see header).
first_command_word() {
  FCW=""
  # Re-tokenize the segment into positional params; -f (set globally) keeps `*`
  # from pathname-expanding here. IFS word-splitting still applies.
  # shellcheck disable=SC2086
  set -- $1
  while [ "$#" -gt 0 ]; do
    _fcw_tok="$1"
    shift
    # Strip any leading run of shell-grouping / subshell-opener characters
    # ( { $ ` ) glued to the front of the token, e.g. `$(git` -> `git`,
    # `(git` -> `git`. The bracket set is a literal character class — no
    # expansion happens inside it — so a glued opener is removed regardless of
    # how the openers stack.
    while :; do
      case "$_fcw_tok" in
        ['({$`']*) _fcw_tok="${_fcw_tok#?}" ;;
        *) break ;;
      esac
    done
    # Checked BEFORE basename normalization so an assignment whose value is a
    # path (FOO=/a/b) is not mistaken for a command word.
    case "$_fcw_tok" in
      # Empty after stripping (a bare opener like `(` or `$(`), or an
      # environment assignment (FOO=bar) — skip to the next token.
      "" | *=*) continue ;;
      # Redirection token, e.g. >f, >>f, <f, 2>f, &>f — skip; the value is part
      # of the same token (>file) so nothing else needs consuming.
      [\>\<]* | [0-9][\>\<]* | "&"[\>\<]*) continue ;;
    esac
    # Normalize a path to its basename so a fully-qualified /usr/bin/git
    # classifies as `git`, then look PAST known command wrappers AND leading
    # shell keywords so a wrapped `command git commit --no-verify` /
    # `sudo git commit -n`, or a keyword-led `if true; then git commit
    # --no-verify; fi` / `while x; do git commit -n; done`, is still scanned.
    # After `;` splitting the commit segment's first word is the keyword
    # (then/do/…); skipping it like a wrapper exposes the real `git` word.
    _fcw_tok="${_fcw_tok##*/}"
    case "$_fcw_tok" in
      command|exec|env|sudo|doas|time|nice|nohup|setsid|stdbuf|ionice|builtin|xargs|timeout)
        # Consume this wrapper's leading option/value preamble so the NEXT
        # resolved command word (not the wrapper's `5`/`-n`/`bob`) is returned.
        # `timeout` (and BSD `nice` with no -n) take a bare leading POSITIONAL
        # value; the others take only options. _consume_wrapper_preamble shifts
        # the in-scope positional params ($@) past that preamble.
        _consume_wrapper_preamble "$_fcw_tok" "$@"
        # _consume_wrapper_preamble republishes the trimmed list in _WP_REST as a
        # single space-joined string; re-split it back into $@ for the next loop.
        # shellcheck disable=SC2086
        set -- $_WP_REST
        continue ;;
      then|do|else|elif|fi|done|"esac"|"{")
        continue ;;
      *) FCW="$_fcw_tok"; break ;;
    esac
  done
}

# _consume_wrapper_preamble WRAPPER TOKENS…: given the wrapper name in $1 and the
# REMAINING tokens (after the wrapper word) in $2…, drop the wrapper's leading
# options, one value of each known separate-value option, and — for a wrapper
# that takes a bare leading positional (timeout) — one bare token. Publishes the
# surviving tokens, space-joined, in the global _WP_REST (set, not echoed, so no
# per-segment subshell fork on the hot path).
#
# Examples (wrapper word already shifted off): `timeout` over `5 git commit …`
# drops the bare `5` -> `git commit …`; `nice` over `-n 5 git commit …` drops
# `-n` then its value `5` -> `git commit …`; `sudo` over `-u bob git commit …`
# drops `-u` then `bob`; `grep` is NOT a wrapper, so `timeout 5 grep -n x` ->
# wrapper=timeout drops `5`, resolves `grep` (FCW=grep, not git) -> not scanned.
_consume_wrapper_preamble() {
  _wp_wrapper="$1"
  shift
  # timeout (and bare `nice`/`ionice` adjustment) take a leading positional VALUE
  # when it is not introduced by an option; allow consuming exactly one bare token.
  _wp_bareval=0
  case "$_wp_wrapper" in
    timeout) _wp_bareval=1 ;;
  esac
  while [ "$#" -gt 0 ]; do
    case "$1" in
      # A known separate-value wrapper option: drop the option AND its value.
      # Covers nice/ionice -n, sudo -u/-g/-p/-C/-r/-h/-T/-U, xargs -I/-n/-L/-P,
      # env -u, ionice -c, timeout -s/-k. Unknown to a given wrapper is harmless:
      # consuming one extra value only ever skips MORE preamble, and the wrapped
      # command word still resolves next.
      -n|-u|-g|-p|-C|-r|-h|-T|-U|-I|-L|-P|-c|-s|-k|--adjustment|--user|--group|--signal)
        shift
        [ "$#" -gt 0 ] && shift
        ;;
      # Any other option token (attached value -n5/-c2/-oL, long --foo, flags
      # -i/-s): drop just the option, keep scanning the preamble.
      -*)
        shift ;;
      # An env-assignment (env VAR=val): drop and keep scanning.
      *=*)
        shift ;;
      # First bare non-option token. For a positional-taking wrapper (timeout),
      # this is the wrapper's VALUE (the DURATION) — drop it once, then the NEXT
      # bare token is the wrapped command. For every other wrapper this bare token
      # IS the wrapped command — stop so the caller resolves it.
      *)
        if [ "$_wp_bareval" -eq 1 ]; then
          _wp_bareval=0
          shift
        else
          break
        fi
        ;;
    esac
  done
  _WP_REST="$*"
}

# ---------------------------------------------------------------------------
# Pass A (Steps 3-4): classify each quote-stripped segment and, inside a commit
# segment, scan for --no-verify / -n / short-cluster / attached-hooksPath.
# ---------------------------------------------------------------------------
while IFS= read -r seg || [ -n "$seg" ]; do
  [ "$BYPASS" -eq 0 ] || break
  # Skip blank segments (arise from adjacent separators or leading/trailing).
  [ -n "$seg" ] || continue

  # Step 3: the first real command word must be `git`.
  first_command_word "$seg"
  [ "$FCW" = "git" ] || continue

  # Walk the remaining tokens to find git's subcommand. Skip git global flags
  # that take a value as a SEPARATE token (-c <key=val>, -C <dir>, and the long
  # globals --git-dir, --work-tree, --namespace, --super-prefix) so the value is
  # not misread as the subcommand. Without this,
  # `git --git-dir /tmp commit --no-verify` would read `/tmp` as the subcommand,
  # misclassify the segment, and skip the bypass scan. Bare `--exec-path` is
  # deliberately NOT listed — `git --exec-path` (no value) just prints the path,
  # so consuming the next token would wrongly swallow a following `commit`. Its
  # attached `--exec-path=...` form (and every other attached `--flag=val`
  # global) already falls through the `-*` arm below without consuming a token.
  _subcmd=""
  _past_git=0
  _skip_val=0
  for tok in $seg; do
    if [ "$_past_git" -eq 0 ]; then
      # Skip everything up to and including the `git` word (grouping/redirect
      # noise was already accounted for by first_command_word). An env-assignment
      # token (X=mygit) is skipped, and the git word is matched by BASENAME
      # exactly (==git) — so a path /usr/bin/git still classifies while `mygit`,
      # `legit`, or an assignment VALUE ending in `git` does NOT trip the scan.
      case "$tok" in
        *=*) : ;;
        *) case "${tok##*/}" in git) _past_git=1 ;; esac ;;
      esac
      continue
    fi
    if [ "$_skip_val" -eq 1 ]; then
      _skip_val=0
      continue
    fi
    case "$tok" in
      -c|-C|--git-dir|--work-tree|--namespace|--super-prefix)
        _skip_val=1
        ;;
      -c*|-C*)
        : # attached-value form (-ccore.hooksPath=…); no next token consumed
        ;;
      -*)
        : # other git global flag (-p, -v, --version, --git-dir=…) — skip
        ;;
      *)
        _subcmd="$tok"
        break
        ;;
    esac
  done

  # If the subcommand is not `commit`, this segment is not a commit invocation.
  [ "$_subcmd" = "commit" ] || continue

  # Step 4: this segment IS a git commit invocation — scan it for bypass flags.
  _skip_next=0
  for tok in $seg; do
    if [ "$_skip_next" -eq 1 ]; then
      _skip_next=0
      continue
    fi
    case "$tok" in
      -m|--message|-F|--file|-c|-C|--reedit-message|--reuse-message)
        # Value is the next separate token — skip it so an unquoted value that
        # looks like a flag (e.g. -m wip_-n) is not misread as a bypass.
        _skip_next=1
        ;;
      -c*)
        # Attached-value config global (-ccore.hooksPath=… or -c'…' after quote
        # strip). ONLY -c sets config; a -c carrying hooksPath disables git hooks.
        # Scope the check to this token (case-insensitive — git config keys are
        # case-insensitive) so a plain message word never trips it. -C is git's
        # change-directory flag, NOT config, so it is handled as a value-skip
        # above and a no-op below — a legit `git -C /home/hooksPath/repo commit`
        # must NOT be blocked.
        case "$tok" in
          *[hH][oO][oO][kK][sS][pP][aA][tT][hH]*) BYPASS=1; break ;;
        esac
        ;;
      -C*)
        : # attached -C<dir> change-directory flag; not config, nothing to skip
        ;;
      -m*|--message=*|-F*|--file=*)
        : # attached-value form; value is part of this token, nothing to skip
        ;;
      --no-verify|--no-verify=*)
        BYPASS=1; break
        ;;
      -n|-n=*)
        BYPASS=1; break
        ;;
      --*)
        : # other long option, ignore
        ;;
      -[a-zA-Z]*)
        # short-flag cluster, e.g. -nv ; an embedded 'n' is --no-verify's short.
        case "$tok" in
          *n*) BYPASS=1; break ;;
        esac
        ;;
    esac
  done
done < "$_SEGTMP"

# ---------------------------------------------------------------------------
# Pass B (Step 5): the QUOTED -c hooksPath bypass. The quote strip in Step 1b
# erased the quoted value, so Pass A cannot see it. Walk the RAW segments (split
# on the SAME separators) and, for each raw segment that is itself a git-commit
# invocation, inspect ONLY its pre-subcommand global-flag region for a -c/-C
# global carrying hooksPath (case-insensitive). Scoping to a genuine commit
# segment keeps non-commit forms allowed (git -c core.hooksPath=x log/status/
# fetch and a `git -c … diff | grep commit` pipeline); scoping to the global
# region keeps a commit message mentioning hooksPath allowed (the word comes
# AFTER `commit`).
# ---------------------------------------------------------------------------
while IFS= read -r rawseg || [ -n "$rawseg" ]; do
  [ "$BYPASS" -eq 0 ] || break
  [ -n "$rawseg" ] || continue

  first_command_word "$rawseg"
  [ "$FCW" = "git" ] || continue

  # Collect the global-flag region (tokens after `git`, up to and excluding the
  # first non-global token = the subcommand). A -c/-C global there (separate- or
  # attached-value) whose value carries hooksPath is the bypass. Track whether
  # the immediately preceding global was a separate-value -c/-C so its value
  # token is checked too.
  _raw_past_git=0
  _raw_sub=""
  _raw_skip_val=0
  _raw_region=""
  for tok in $rawseg; do
    if [ "$_raw_past_git" -eq 0 ]; then
      # Skip env-assignments (X=mygit); match the git word by basename exactly so
      # /usr/bin/git classifies while mygit/legit/an assignment value do not.
      case "$tok" in
        *=*) : ;;
        *) case "${tok##*/}" in git) _raw_past_git=1 ;; esac ;;
      esac
      continue
    fi
    if [ "$_raw_skip_val" -eq 1 ]; then
      # This token is the separate value of a preceding -c/-C global.
      _raw_skip_val=0
      _raw_region="$_raw_region $tok"
      continue
    fi
    case "$tok" in
      -c|-C)
        _raw_skip_val=1
        _raw_region="$_raw_region $tok"
        ;;
      -c*|-C*)
        _raw_region="$_raw_region $tok"
        ;;
      --git-dir|--work-tree|--namespace|--super-prefix)
        # Separate-value global, not -c/-C; consume its value so it is not read
        # as the subcommand. Reuse _raw_skip_val as a generic "skip next value"
        # flag (the value can never carry a -c hooksPath, so adding it to the
        # region is harmless to the match below).
        _raw_skip_val=1
        _raw_region="$_raw_region $tok"
        ;;
      -*)
        _raw_region="$_raw_region $tok"
        ;;
      *)
        _raw_sub="$tok"
        break
        ;;
    esac
  done

  # Only a genuine `git commit` segment is in scope.
  [ "$_raw_sub" = "commit" ] || continue

  # A -c config global in the region carrying hooksPath (case-insensitive) is the
  # bypass. ONLY -c sets config; -C is git's change-directory flag, so it is NOT
  # matched here — a legit `git -C /home/hooksPath/repo commit` must pass even
  # though its dir mentions hooksPath. -C is still value-skipped above so its
  # directory argument is not read as the subcommand. The region only ever
  # contains global flags and their values, so a commit message word can never
  # reach here.
  case "$_raw_region" in
    *-c*[hH][oO][oO][kK][sS][pP][aA][tT][hH]*)
      BYPASS=1
      ;;
  esac
done < "$_RAWTMP"

if [ "$BYPASS" -eq 1 ]; then
  # Exit 2 blocks the call; stderr is surfaced back to Claude.
  printf '%s\n' "BLOCKED: 'git commit' with --no-verify / -n bypasses the quality gates." >&2
  printf '%s\n' "claude-godmode requires all six quality gates to run on every commit:" >&2
  if [ -f "${CLAUDE_PLUGIN_ROOT:-.}/config/quality-gates.txt" ]; then
    while IFS= read -r gate || [ -n "$gate" ]; do
      [ -n "$gate" ] && printf '  - %s\n' "$gate" >&2
    done < "${CLAUDE_PLUGIN_ROOT:-.}/config/quality-gates.txt"
  fi
  printf '%s\n' "Re-run the commit without --no-verify, after the gates pass." >&2
  exit 2
fi

# Allowed: emit an empty JSON object (matching pre-tool-use-secrets.sh) and pass.
# printf, not `jq -n`, so the allow path costs no extra subprocess fork.
printf '{}\n'
exit 0
