#!/usr/bin/env bats
#
# Regression: godmode skills must resolve the bin/godmode-* helpers across
# install modes — they must NEVER call them by a bare relative path.
#
# A bare `bin/godmode-state` resolves against the *consumer's* working
# directory when a skill runs inside another project, where it does not exist
# ("godmode can't find bin"). The fix: every skill resolves the helper dir into
# $gm (plugin root -> ~/.claude -> repo-relative) and invokes
# "$gm/godmode-<name>". This suite guards that contract so the bug can't return.

load test_helper

# Skills that drive the workflow spine via the bin/godmode-* helpers.
HELPER_SKILLS="verify build brief mission refine plan ship"

# The canonical resolver line every helper skill's bash blocks must carry.
RESOLVER_PREFIX='gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .'

# Print only the contents of fenced ```bash code blocks from a SKILL.md.
extract_bash_blocks() {
  awk '/```bash/{b=1;next} /```/{b=0} b' "$1"
}

@test "no helper skill invokes a bin/godmode-* helper by a bare relative path" {
  bad=""
  for s in $HELPER_SKILLS; do
    f="$PLUGIN_ROOT/skills/$s/SKILL.md"
    [ -f "$f" ] || { bad="$bad
$s: SKILL.md missing"; continue; }
    # A bare invocation is `bin/godmode-` NOT preceded by a slash. The resolver
    # probe ("$c/bin/godmode-state") has a leading slash, and the resolved call
    # form ("$gm/godmode-<name>") has no `bin/` segment at all — both excluded.
    hits=$(extract_bash_blocks "$f" | grep -nE '(^|[^/])bin/godmode-' || true)
    if [ -n "$hits" ]; then
      bad="$bad
$s:
$hits"
    fi
  done
  [ -z "$bad" ] || { printf 'bare bin/godmode-* invocation(s) found:%s\n' "$bad"; false; }
}

@test "every helper skill defines the gm resolver in its bash blocks" {
  for s in $HELPER_SKILLS; do
    f="$PLUGIN_ROOT/skills/$s/SKILL.md"
    extract_bash_blocks "$f" | grep -Fq "$RESOLVER_PREFIX" \
      || { echo "skills/$s/SKILL.md: gm resolver not found in any bash block"; false; }
  done
}

@test "the gm resolver locates godmode-state from a foreign working directory" {
  # Reproduce the original bug's environment: the working directory is some
  # other project, but CLAUDE_PLUGIN_ROOT points at the installed plugin. The
  # resolver must still locate the helper rather than looking in ./bin.
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/godmode-foreign.XXXXXX")"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" HOME=/nonexistent bash -c '
    cd "'"$tmp"'" || exit 1
    gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
    [ -x "$gm/godmode-state" ] && echo OK
  '
  rm -rf "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]]
}

@test "the gm resolver falls back to repo-relative bin in-tree (no plugin root)" {
  # In-tree development / CI: neither CLAUDE_PLUGIN_ROOT nor ~/.claude is set,
  # so the resolver must fall back to ./bin when run from the repo root.
  run env -u CLAUDE_PLUGIN_ROOT HOME=/nonexistent bash -c '
    cd "'"$PLUGIN_ROOT"'" || exit 1
    gm=$(for c in "${CLAUDE_PLUGIN_ROOT:-}" "$HOME/.claude" .; do [ -x "$c/bin/godmode-state" ] && { echo "$c/bin"; break; }; done)
    [ -x "$gm/godmode-state" ] && echo OK
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]]
}
