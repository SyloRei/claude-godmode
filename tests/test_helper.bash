# shellcheck shell=bash
#
# Shared bats harness for the claude-godmode test suite.
#
# Bash 3.2 compatible (macOS default shell). No bash 4+ constructs.
#
# Harness shape for US-017b and later stories:
#   - PLUGIN_ROOT points at the repo root (one level up from tests/).
#   - make_temp_home  -> creates an isolated $HOME under a fresh mktemp -d,
#                        sets TEST_HOME, and exports HOME so install.sh /
#                        uninstall.sh round-trip tests cannot touch the real
#                        user's ~/.claude. Call from a test's `setup`.
#   - teardown_temp_home -> removes TEST_HOME. Call from a test's `teardown`.
#
# Typical US-017b usage (install/uninstall round trip):
#
#   load test_helper
#
#   setup() {
#     make_temp_home
#   }
#
#   teardown() {
#     teardown_temp_home
#   }
#
#   @test "install then uninstall leaves $HOME clean" {
#     run "$PLUGIN_ROOT/install.sh"
#     [ "$status" -eq 0 ]
#     # ... assertions against "$TEST_HOME/.claude" ...
#   }

# Resolve the repo root from this helper's own location so tests work
# regardless of the directory bats is invoked from.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PLUGIN_ROOT

# Create an isolated temporary $HOME and point HOME at it.
# Sets the global TEST_HOME and exports HOME.
make_temp_home() {
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/godmode-test-home.XXXXXX")"
  export TEST_HOME
  ORIG_HOME="${HOME:-}"
  export ORIG_HOME
  export HOME="$TEST_HOME"
}

# Remove the temporary $HOME created by make_temp_home and restore HOME.
teardown_temp_home() {
  if [ -n "${ORIG_HOME:-}" ]; then
    export HOME="$ORIG_HOME"
  fi
  if [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ]; then
    rm -rf "$TEST_HOME"
  fi
}
