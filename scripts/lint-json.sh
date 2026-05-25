#!/usr/bin/env bash
#
# lint-json.sh — validate every *.json file in the repo with `jq -e .`.
#
# Finds all *.json files (excluding VCS, dependency, cache, and runtime
# state dirs) and parses each. Exits non-zero listing any invalid file.
# Pure jq + bash 3.2; no Node, no Python.

set -euo pipefail

# Resolve repo root relative to this script so the linter works from any cwd.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

cd -- "${REPO_ROOT}"

# Emit NUL-delimited json paths, pruning directories we never validate.
find_json_files() {
  find . \
    \( -name .git -o -name node_modules -o -name .claude-pipeline -o -name .claude \) -prune \
    -o -type f -name '*.json' -print0
}

failures=()
checked=0

# Pruned dirs (see find_json_files): .git, node_modules, .claude-pipeline
# (v1.x runtime, gitignored), .claude (local runtime/agent state).
# Read NUL-delimited to survive unusual filenames; bash 3.2 friendly.
while IFS= read -r -d '' file; do
  checked=$((checked + 1))
  if ! jq -e . "${file}" >/dev/null 2>&1; then
    failures+=("${file}")
  fi
done < <(find_json_files)

if [[ ${#failures[@]} -gt 0 ]]; then
  printf 'Invalid JSON (%d of %d files):\n' "${#failures[@]}" "${checked}" >&2
  for file in "${failures[@]}"; do
    printf '  %s\n' "${file}" >&2
  done
  exit 1
fi

printf 'lint-json: %d JSON file(s) valid.\n' "${checked}"
