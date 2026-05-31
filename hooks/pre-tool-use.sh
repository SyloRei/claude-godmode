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
# Classification model: FIND `git` ANYWHERE + display-verb DENY-LIST (fail-safe).
# Per segment, every token whose basename is `git` (and is not an `X=…` env
# assignment) is treated as a git invocation start; its subcommand is resolved by
# walking forward past the git globals, and if the subcommand is exactly `commit`
# the tokens AFTER it are scanned for a bypass flag and the git-global region for
# an attached `-c…hooksPath`. There is NO wrapper allow-list: any unknown leading
# word (`flock`/`chrt`/`taskset`/`randomcmd`/…) defaults to SCAN — the model fails
# CLOSED, so an unenumerated wrapper can never drop a segment unscanned. A short
# CLOSED deny-list of display/data verbs (`echo printf print man grep egrep fgrep
# rg ag ls cat which type awk`) as a segment's FIRST word marks it not-a-git-
# invocation and skips it, recovering legitimate cases like `echo git commit -n`
# and `grep -n commit`. An incomplete deny-list causes at most a rare COSMETIC
# over-block of a contrived `<verb> git commit -n` data-argument command — never a
# bypass. Acknowledged remaining gaps (un-enumerable by a stdin string-scanner):
# git aliases, deeply-nested command substitution, and that rare display-verb-
# with-git-commit-data-arg over-block.
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
#   3. For each quote-stripped segment, apply the fail-closed deny-list gate:
#      determine the segment's FIRST real word (skip leading X=… env assignments,
#      grouping/subshell openers, and redirection tokens; basename-normalize). If
#      that word is in the CLOSED display-verb deny-list it is NOT a git
#      invocation -> skip the segment (allow). EVERY other first word -> the
#      segment IS scanned (fail closed — no wrapper allow-list).
#   4. Within a scanned segment, iterate EVERY token: for each token whose
#      basename is exactly `git` (not an X=… assignment), resolve its subcommand
#      by walking forward past the git globals; if the subcommand is `commit`,
#      scan ONLY the tokens AFTER it for a bypass flag (--no-verify / -n / short
#      cluster containing n) and the pre-subcommand global region for an attached
#      -c…hooksPath that survived the quote strip. Do NOT stop at the first git
#      token — a later `git commit` in the same segment is still found and scanned.
#   5. The QUOTED -c hooksPath bypass (git -c 'core.hooksPath=…' commit) cannot
#      be seen in step 4 — the quote strip erases the value. So a separate RAW
#      pass applies the SAME dual-stream split to the unmodified command and, for
#      each `git` token in a raw segment whose subcommand is `commit`, checks its
#      pre-subcommand global-flag region for a -c carrying hooksPath
#      (case-insensitive). Scoping to genuine commit invocations keeps non-commit
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
#
# Composed from _split_separators (rather than duplicating its five separator
# expressions) plus the extra `(`/`)`/backtick rules. The two rule groups are
# independent — the separator rules never emit a paren/backtick and the extra
# rules never emit a separator — so the split is order-independent and pipe-
# composing yields output identical to a single monolithic sed. The extra sed
# fork only ever runs on the substitution-bearing stream (the cold path); the hot
# substitution-free commit takes the single-stream branch in _emit_segments and
# never reaches here.
_split_subst() {
  _split_separators \
    | sed \
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
#
# The branch decision is taken on a QUOTE-STRIPPED guard view, not the raw input,
# so a paren that appears ONLY inside a quoted span (the very common conventional-
# commit message `git commit -m "fix(scope): msg"`) does NOT needlessly trigger
# the dual-stream pass — that paren is message DATA, never shell grouping syntax.
# The strip is deliberately conservative to stay behavior-preserving: a single-
# quoted span is always erased (no expansion happens inside single quotes, so a
# paren/`$(`/backtick there is pure data), but a DOUBLE-quoted span is erased
# ONLY when it contains neither `$` nor a backtick — a `"$(evil)"` / `` "`evil`" ``
# is a REAL command substitution that must keep the dual-stream pass. So if any
# substitution or grouping delimiter survives in the view (an unquoted `(`/`)`, a
# real `$(`/backtick, or a double-quoted span carrying one), the dual-stream pass
# still runs and the exposing split still catches the nested commit. The split
# work itself runs on the unmodified `$1` (quotes intact) so Pass B's quoted
# hooksPath value stays visible; only the cheap branch test reads the view.
_emit_segments() {
  # Guard view: by default the cheap branch test reads the raw input directly, so
  # the hot substitution-free path (`git commit -m wip`) costs no extra fork. ONLY
  # when the input carries BOTH a grouping/substitution delimiter AND a quote is a
  # quote-stripped view computed — that is the sole case where a delimiter might be
  # message DATA rather than shell syntax. The strip erases single-quoted spans
  # (no expansion inside single quotes) and substitution-FREE double-quoted spans,
  # but preserves a double-quoted span carrying `$`/backtick (a real `"$(evil)"`
  # substitution must keep the dual-stream pass), so the dual-stream pass still
  # runs whenever a real substitution or unquoted grouping delimiter survives.
  _emit_view="$1"
  # The single-quoted `'$('`/`` '`' `` are intentional LITERAL substrings to match,
  # not shell expansions — keep them single-quoted.
  # shellcheck disable=SC2016
  case "$1" in
    *'('* | *')'* | *'`'*)
      case "$1" in
        *'"'* | *"'"*)
          # Substitution-free double-quoted spans -> erased; single-quoted spans
          # -> erased; `"$(…)"`/`` "`…`" `` preserved. `[^"$\`]` is a sed CHARACTER
          # CLASS (literal `"`, `$`, backtick), NOT a shell expansion.
          # shellcheck disable=SC2016
          _emit_view="$(printf '%s' "$1" | sed -e "s/'[^']*'/ /g" -e 's/"[^"$`]*"/ /g')"
          ;;
      esac
      ;;
  esac
  # shellcheck disable=SC2016
  case "$_emit_view" in
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

# first_command_word: given a segment, find its FIRST real command word —
# skipping leading environment assignments (VAR=val), shell-grouping / subshell
# openers ( { $( ` , and redirection tokens (>f, >>f, <f, 2>f, &>f, …),
# normalizing a path to its basename so /usr/bin/echo is recognized as `echo`.
# It does NOT look past command wrappers or shell keywords — under the find-`git`-
# anywhere model the caller never needs to know WHAT precedes `git`; this word is
# used ONLY for the display-verb deny-list gate (a leading display/data verb means
# the segment is not a git invocation). The result is PUBLISHED in the global
# `FCW` (set, not echoed) so the caller need not fork a command-substitution
# subshell per segment on the hot commit path.
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
    # ( { $ ` ) glued to the front of the token, e.g. `$(echo` -> `echo`,
    # `(echo` -> `echo`. The bracket set is a literal character class — no
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
    # Normalize a path to its basename so a fully-qualified /usr/bin/echo
    # classifies as `echo`, then return it as the first real command word.
    FCW="${_fcw_tok##*/}"
    break
  done
}

# segment_is_display_verb: true (return 0) when the segment's FIRST real command
# word is in the CLOSED display/data-verb deny-list — meaning the segment is NOT a
# git invocation and any `git`/`commit`/`-n` token in it is data, not a bypass
# (`echo git commit -n`, `grep -n commit`, `man git commit`). The list is short
# and deliberately closed (see header): `grep`/`rg`/`egrep`/`fgrep`/`ag` are on it
# because the live reproduced false positive is exactly `grep -n`. An unlisted
# display verb falls through to the fail-closed scan (a cosmetic over-block at
# worst, never a bypass). Relies on FCW being set by a prior first_command_word.
segment_is_display_verb() {
  case "$FCW" in
    echo|printf|print|man|grep|egrep|fgrep|rg|ag|ls|cat|which|type|awk)
      return 0 ;;
  esac
  return 1
}

# _scan_git_invocation TOKENS…: given the tokens that FOLLOW a `git` word (the
# git word already shifted off), resolve this invocation's subcommand and, when it
# is `commit`, scan its own args for a bypass. Sets the global BYPASS=1 on a hit.
# Used by Pass A for EACH git token found in a segment (find-`git`-anywhere), so a
# later commit in the same segment (`git log $(true) git commit -n`) is scanned
# too — the flag BEFORE a git word is never read as that commit's arg (AC-14).
#
# Walk 1 (globals -> subcommand): skip git global flags that take a value as a
# SEPARATE token (-c <key=val>, -C <dir>, --git-dir, --work-tree, --namespace,
# --super-prefix) so the value is not misread as the subcommand, and an attached
# -c…hooksPath global (case-insensitive — git config keys are case-insensitive)
# disables hooks -> bypass. Bare `--exec-path` is deliberately NOT a value-flag
# (`git --exec-path` just prints the path; consuming the next token would swallow
# a following `commit`); its attached `--exec-path=…` form falls through the `-*`
# arm. -C is git's change-directory flag (NOT config), so its attached -C<dir>
# form never matches hooksPath — `git -C /home/hooksPath/repo commit` is allowed.
# The first non-flag token is the subcommand; if it is not `commit` this is not a
# commit invocation (return without setting BYPASS).
#
# Walk 2 (commit args): scan ONLY the tokens AFTER the `commit` subcommand for
# --no-verify / --no-verify=* / -n / -n=* / a short cluster containing n, skipping
# the VALUE of -m/-F/-c/-C/--message/--file/--reedit-message/--reuse-message so an
# unquoted value that looks like a flag is not misread as a bypass.
_scan_git_invocation() {
  _gi_skip_val=0
  _gi_sub=""
  while [ "$#" -gt 0 ]; do
    _gi_tok="$1"
    shift
    if [ "$_gi_skip_val" -eq 1 ]; then
      _gi_skip_val=0
      continue
    fi
    case "$_gi_tok" in
      -c|-C|--git-dir|--work-tree|--namespace|--super-prefix)
        _gi_skip_val=1 ;;
      -c*)
        # Attached -c config global; a hooksPath value disables git hooks.
        case "$_gi_tok" in
          *[hH][oO][oO][kK][sS][pP][aA][tT][hH]*) BYPASS=1; return 0 ;;
        esac
        ;;
      -C*)
        : # attached -C<dir> change-directory flag; not config, no value to skip
        ;;
      -*)
        : # other git global flag (-p, -v, --version, --git-dir=…) — skip
        ;;
      *)
        _gi_sub="$_gi_tok"
        break ;;
    esac
  done

  # Only a `git commit` invocation is scanned for bypass flags. Return 0 (not the
  # failing test status) so the bare top-level call does not trip `set -e`.
  [ "$_gi_sub" = "commit" ] || return 0

  _gi_skip_next=0
  while [ "$#" -gt 0 ]; do
    _gi_tok="$1"
    shift
    if [ "$_gi_skip_next" -eq 1 ]; then
      _gi_skip_next=0
      continue
    fi
    case "$_gi_tok" in
      -m|--message|-F|--file|-c|-C|--reedit-message|--reuse-message)
        _gi_skip_next=1 ;;
      -m*|--message=*|-F*|--file=*|-c*|-C*)
        : # attached-value form; value is part of this token, nothing to skip
        ;;
      --no-verify|--no-verify=*)
        BYPASS=1; return 0 ;;
      -n|-n=*)
        BYPASS=1; return 0 ;;
      --*)
        : # other long option, ignore
        ;;
      -[a-zA-Z]*)
        # short-flag cluster, e.g. -nv; an embedded 'n' is --no-verify's short.
        case "$_gi_tok" in
          *n*) BYPASS=1; return 0 ;;
        esac
        ;;
    esac
  done
  return 0
}

# ---------------------------------------------------------------------------
# Pass A (Steps 3-4): the deny-list gate, then find `git` ANYWHERE and scan each
# commit invocation. Fail closed: any non-deny-list leading word -> scan.
# ---------------------------------------------------------------------------
while IFS= read -r seg || [ -n "$seg" ]; do
  [ "$BYPASS" -eq 0 ] || break
  # Skip blank segments (arise from adjacent separators or leading/trailing).
  [ -n "$seg" ] || continue

  # Step 3: deny-list gate. A segment whose FIRST real word is a display/data verb
  # is not a git invocation — its `git`/`commit`/`-n` tokens are data (`echo git
  # commit -n`, `grep -n commit`). Every other leading word -> scan (fail closed).
  first_command_word "$seg"
  if segment_is_display_verb; then
    continue
  fi

  # Step 4: find `git` ANYWHERE. For EACH token whose basename is exactly `git`
  # and is not an X=… env-assignment, scan that invocation (the tokens AFTER it).
  # Iterate every git token — do not stop at the first — so a later `git commit`
  # in the same segment is still scanned (AC-12). Re-tokenize into positional
  # params so each git word's trailing tokens can be handed to _scan_git_invocation
  # by `shift`-ing off the leading run up to and including that git word.
  # shellcheck disable=SC2086
  set -- $seg
  while [ "$#" -gt 0 ]; do
    _pa_tok="$1"
    shift
    case "$_pa_tok" in
      *=*) continue ;;  # env-assignment value (X=mygit) is never the git word
    esac
    case "${_pa_tok##*/}" in
      git)
        # $@ now holds exactly the tokens that follow THIS git word.
        _scan_git_invocation "$@"
        [ "$BYPASS" -eq 0 ] || break
        ;;
    esac
  done
done < "$_SEGTMP"

# _scan_raw_git_hookspath TOKENS…: given the tokens that FOLLOW a `git` word in a
# RAW (quote-intact) segment, collect this invocation's pre-subcommand global-flag
# region and, when its subcommand is `commit`, block on a -c global there carrying
# hooksPath (case-insensitive). Sets the global BYPASS=1 on a hit.
#
# A -c/-C global takes a SEPARATE value token (checked too); --git-dir/--work-tree/
# --namespace/--super-prefix likewise take a value (consumed so it is not read as
# the subcommand — its value can never carry a -c hooksPath, so adding it to the
# region is harmless). ONLY -c sets config: -C is git's change-directory flag, so
# `git -C /home/hooksPath/repo commit` is allowed even though its dir mentions
# hooksPath; the `-c` prefix in the match below excludes it. The region only ever
# holds global flags and their values, so a commit MESSAGE word (which comes after
# `commit`) can never reach the match.
_scan_raw_git_hookspath() {
  _rg_skip_val=0
  _rg_sub=""
  _rg_region=""
  while [ "$#" -gt 0 ]; do
    _rg_tok="$1"
    shift
    if [ "$_rg_skip_val" -eq 1 ]; then
      _rg_skip_val=0
      _rg_region="$_rg_region $_rg_tok"
      continue
    fi
    case "$_rg_tok" in
      -c|-C|--git-dir|--work-tree|--namespace|--super-prefix)
        _rg_skip_val=1
        _rg_region="$_rg_region $_rg_tok" ;;
      -*)
        _rg_region="$_rg_region $_rg_tok" ;;
      *)
        _rg_sub="$_rg_tok"
        break ;;
    esac
  done

  # Only a genuine `git commit` invocation is in scope. Return 0 (not the failing
  # test status) so the bare top-level call does not trip `set -e`.
  [ "$_rg_sub" = "commit" ] || return 0

  case "$_rg_region" in
    *-c*[hH][oO][oO][kK][sS][pP][aA][tT][hH]*)
      BYPASS=1 ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# Pass B (Step 5): the QUOTED -c hooksPath bypass. The quote strip in Step 1b
# erased the quoted value, so Pass A cannot see it. Walk the RAW segments (split
# on the SAME separators) and, for EACH `git` token whose subcommand is `commit`,
# inspect ONLY its pre-subcommand global-flag region for a -c global carrying
# hooksPath (case-insensitive). Ported to the same find-`git`-anywhere model as
# Pass A so a wrapper-prefixed form (`flock /tmp/x git -c core.hooksPath=… commit`)
# is still caught. Scoping to a genuine commit invocation keeps non-commit forms
# allowed (git -c core.hooksPath=x log/status/fetch and a `git -c … diff | grep
# commit` pipeline); scoping to the global region keeps a commit message mentioning
# hooksPath allowed (the word comes AFTER `commit`).
# ---------------------------------------------------------------------------
while IFS= read -r rawseg || [ -n "$rawseg" ]; do
  [ "$BYPASS" -eq 0 ] || break
  [ -n "$rawseg" ] || continue

  # Find `git` ANYWHERE in the raw segment; hand each git word's trailing tokens
  # to _scan_raw_git_hookspath (iterate every git token, not just the first).
  # shellcheck disable=SC2086
  set -- $rawseg
  while [ "$#" -gt 0 ]; do
    _pb_tok="$1"
    shift
    case "$_pb_tok" in
      *=*) continue ;;  # env-assignment value is never the git word
    esac
    case "${_pb_tok##*/}" in
      git)
        _scan_raw_git_hookspath "$@"
        [ "$BYPASS" -eq 0 ] || break
        ;;
    esac
  done
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
