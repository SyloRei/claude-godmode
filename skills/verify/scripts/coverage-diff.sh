#!/usr/bin/env bash
#
# coverage-diff.sh — language-agnostic coverage-delta helper.
#
# Compares a BASELINE coverage value against a CURRENT one, prints the signed
# delta, and signals (via exit code) whether coverage regressed beyond an
# allowed tolerance. Coverage values may be decimals (e.g. 87.5), so arithmetic
# is done with awk — integer-only bash math is insufficient. No Python/Node/Ruby
# dependency: pure POSIX shell + awk.
#
# Usage:
#   coverage-diff.sh <baseline> <current> [tolerance]
#   coverage-diff.sh --baseline N --current M [--tolerance T]
#
#   tolerance defaults to 0.
#
# Output:
#   Prints the signed delta on stdout (e.g. "+5", "0", "-5"). Non-negative
#   deltas are sign-prefixed ("+5", "0") for readability.
#
# Exit codes:
#   0  — current >= baseline - tolerance (no regression beyond tolerance).
#   1  — current <  baseline - tolerance (regression beyond tolerance).
#   2  — usage error: missing, empty, or non-numeric input (message on stderr).
#
# Examples:
#   coverage-diff.sh 80 80   -> "0",  exit 0
#   coverage-diff.sh 80 75   -> "-5", exit 1
#   coverage-diff.sh 80 85   -> "+5", exit 0
#   coverage-diff.sh         -> stderr message, exit 2
#
# Pure bash + awk. No Node, no Python, no Ruby.

set -eu

PROG=$(basename -- "$0")

usage_error() {
  echo "${PROG}: $1" >&2
  echo "usage: ${PROG} <baseline> <current> [tolerance]" >&2
  echo "       ${PROG} --baseline N --current M [--tolerance T]" >&2
  exit 2
}

baseline=""
current=""
tolerance=""

# Parse flag form and positional form. Flags may be interleaved; bare values
# fill baseline then current then tolerance in order.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --baseline)
      [ "$#" -ge 2 ] || usage_error "--baseline requires a value"
      baseline="$2"
      shift 2
      ;;
    --baseline=*)
      baseline="${1#--baseline=}"
      shift
      ;;
    --current)
      [ "$#" -ge 2 ] || usage_error "--current requires a value"
      current="$2"
      shift 2
      ;;
    --current=*)
      current="${1#--current=}"
      shift
      ;;
    --tolerance)
      [ "$#" -ge 2 ] || usage_error "--tolerance requires a value"
      tolerance="$2"
      shift 2
      ;;
    --tolerance=*)
      tolerance="${1#--tolerance=}"
      shift
      ;;
    -h|--help)
      usage_error "help requested"
      ;;
    -*)
      usage_error "unknown flag: $1"
      ;;
    *)
      if [ -z "$baseline" ]; then
        baseline="$1"
      elif [ -z "$current" ]; then
        current="$1"
      elif [ -z "$tolerance" ]; then
        tolerance="$1"
      else
        usage_error "too many positional arguments"
      fi
      shift
      ;;
  esac
done

[ -z "$tolerance" ] && tolerance="0"

# Validate presence.
[ -n "$baseline" ] || usage_error "missing baseline value"
[ -n "$current" ] || usage_error "missing current value"

# Validate numeric (integer or decimal, optional leading sign).
is_number() {
  case "$1" in
    "" ) return 1 ;;
  esac
  printf '%s\n' "$1" | awk '
    {
      if ($0 ~ /^[+-]?[0-9]+(\.[0-9]+)?$/ || $0 ~ /^[+-]?\.[0-9]+$/) exit 0
      exit 1
    }'
}

is_number "$baseline" || usage_error "baseline is not a number: ${baseline}"
is_number "$current" || usage_error "current is not a number: ${current}"
is_number "$tolerance" || usage_error "tolerance is not a number: ${tolerance}"

# Compute the signed delta and the regression verdict with awk (decimal-safe).
# Print delta on stdout; emit the verdict (0 ok / 1 regression) on a final line
# we capture, so the script's own exit code reflects it.
verdict=$(
  awk -v b="$baseline" -v c="$current" -v t="$tolerance" '
    BEGIN {
      delta = c - b
      # Format with a fixed number of decimals (never %g, which emits
      # scientific notation like "1e-05" for tiny deltas and breaks the
      # +5 / 0 / -5 stdout contract). %f gives plain decimal across the
      # coverage range (~ -100..100); then trim trailing zeros and any
      # trailing dot so integers print without a decimal part ("5"), real
      # decimals keep theirs ("2.5"), and there is never a dangling ".".
      s = sprintf("%.6f", delta)
      sub(/\.?0+$/, "", s)
      # Sign-prefix non-negative values; "+0"/"-0" normalise to "0".
      if (s == "0" || s == "-0") s = "0"
      else if (delta > 0) s = "+" s
      print s
      # Regression when current < baseline - tolerance.
      if (c < b - t) print "1"; else print "0"
    }'
)

delta=$(printf '%s\n' "$verdict" | sed -e '1!d')
regressed=$(printf '%s\n' "$verdict" | sed -e '2!d')

printf '%s\n' "$delta"

[ "$regressed" = "1" ] && exit 1
exit 0
