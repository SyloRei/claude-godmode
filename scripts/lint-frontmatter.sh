#!/usr/bin/env bash
#
# lint-frontmatter.sh — validate YAML frontmatter of plugin authoring files.
#
# Checks agents/*.md, skills/*/SKILL.md, and commands/*.md:
#   - a leading `---` ... `---` frontmatter block must exist
#   - required top-level keys must be present:
#       agents    -> name, description
#       skills    -> description
#       commands  -> name, description
#
# Pure bash 3.2 + awk + jq. No Node, no Python, no yaml binary.
# Exits non-zero listing every offending file and its missing keys.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

cd -- "${REPO_ROOT}"

# Extract the top-level keys of a leading frontmatter block.
# Prints one key per line to stdout. Exit status:
#   0 = frontmatter block found
#   1 = no leading `---`...`---` block
# Only the FIRST `---`-delimited block at the very top of the file counts.
extract_keys() {
  awk '
    NR == 1 {
      if ($0 != "---") { exit 1 }   # no leading frontmatter
      infront = 1
      found = 1
      next
    }
    infront && $0 == "---" { infront = 0; exit 0 }   # end of block
    infront {
      # match top-level "key:" — no leading whitespace (so nested keys ignored)
      if (match($0, /^[A-Za-z0-9_-]+:/)) {
        key = substr($0, 1, RLENGTH - 1)
        print key
      }
    }
    END {
      if (found != 1 || infront == 1) { exit 1 }   # no opening --- OR unclosed block
    }
  ' "$1"
}

# Returns 0 if $1 (a key) appears in newline-list $2.
has_key() {
  printf '%s\n' "$2" | grep -qx -- "$1"
}

failures=()
checked=0

check_file() {
  # $1 = file path, $2 = space-separated required keys
  local file="$1" required="$2" keys missing="" k
  checked=$((checked + 1))

  if ! keys=$(extract_keys "${file}"); then
    failures+=("${file}: missing leading --- ... --- frontmatter block")
    return
  fi

  for k in ${required}; do
    if ! has_key "${k}" "${keys}"; then
      missing="${missing} ${k}"
    fi
  done

  if [[ -n "${missing}" ]]; then
    failures+=("${file}: missing key(s):${missing}")
  fi
}

# Agents: require name + description.
for file in agents/*.md; do
  [[ -e "${file}" ]] || continue
  check_file "${file}" "name description"
done

# Skills: require description. SKILL.md only (skip helper docs like _shared/*).
for file in skills/*/SKILL.md; do
  [[ -e "${file}" ]] || continue
  check_file "${file}" "description"
done

# Commands: require name + description.
for file in commands/*.md; do
  [[ -e "${file}" ]] || continue
  check_file "${file}" "name description"
done

if [[ ${#failures[@]} -gt 0 ]]; then
  printf 'Frontmatter errors (%d):\n' "${#failures[@]}" >&2
  for line in "${failures[@]}"; do
    printf '  %s\n' "${line}" >&2
  done
  exit 1
fi

printf 'lint-frontmatter: %d file(s) valid.\n' "${checked}"
