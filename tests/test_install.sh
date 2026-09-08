#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-install.XXXXXX")
TEST_ROOT=$(CDPATH= cd -- "$TEST_ROOT" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

HOME=$TEST_ROOT
export HOME
INSTALLER=$PROJECT_ROOT/scripts/install.sh

"$INSTALLER" >/dev/null
"$INSTALLER" >/dev/null
"$INSTALLER" --check >/dev/null
[ -L "$HOME/.local/bin/agent" ] || { printf '%s\n' 'test_install: symlink was not created' >&2; exit 1; }

"$INSTALLER" --uninstall >/dev/null
[ ! -e "$HOME/.local/bin/agent" ] || { printf '%s\n' 'test_install: uninstall left the symlink' >&2; exit 1; }

printf '%s\n' occupied >"$HOME/.local/bin/agent"
if "$INSTALLER" >/dev/null 2>&1; then
    printf '%s\n' 'test_install: installer overwrote an unrelated file' >&2
    exit 1
fi
[ "$(cat "$HOME/.local/bin/agent")" = occupied ] || { printf '%s\n' 'test_install: unrelated file changed' >&2; exit 1; }

printf '%s\n' 'test_install: PASS'
