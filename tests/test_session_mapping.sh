#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-mapping.XXXXXX")
TEST_ROOT=$(CDPATH= cd -- "$TEST_ROOT" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
/bin/mkdir -p "$TEST_ROOT/one/same name!" "$TEST_ROOT/two/same name!"
/bin/ln -s "$TEST_ROOT/one/same name!" "$TEST_ROOT/linked-project"

AGENT_TMUX=/usr/bin/false
export AGENT_TMUX
. "$PROJECT_ROOT/lib/sessions.sh"

fail() { printf 'test_session_mapping: %s\n' "$*" >&2; exit 1; }

first=$(session_name_for_root "$TEST_ROOT/one/same name!")
again=$(session_name_for_root "$TEST_ROOT/one/same name!")
linked=$(session_name_for_root "$TEST_ROOT/linked-project")
second=$(session_name_for_root "$TEST_ROOT/two/same name!")

[ "$first" = "$again" ] || fail 'same root was not deterministic'
[ "$first" = "$linked" ] || fail 'symlink did not map to canonical root'
[ "$first" != "$second" ] || fail 'duplicate basenames collided'
case "$first" in
    agent-same-name-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) fail "unsafe or unreadable session name: $first" ;;
esac

printf '%s\n' 'test_session_mapping: PASS'
