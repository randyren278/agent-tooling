#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-contract.XXXXXX")
TEST_ROOT=$(CDPATH= cd -- "$TEST_ROOT" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
/bin/mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/tmux" "$TEST_ROOT/Amphetamine.app" "$TEST_ROOT/work/project with spaces!"
/bin/cp "$PROJECT_ROOT/tests/fixtures/fake-tmux" "$TEST_ROOT/bin/tmux"
/bin/cp "$PROJECT_ROOT/tests/fixtures/fake-osascript" "$TEST_ROOT/bin/osascript"
/bin/chmod +x "$TEST_ROOT/bin/tmux" "$TEST_ROOT/bin/osascript"

export AGENT_TMUX="$TEST_ROOT/bin/tmux"
export AGENT_OSASCRIPT="$TEST_ROOT/bin/osascript"
export AGENT_AMPHETAMINE_APP="$TEST_ROOT/Amphetamine.app"
export AGENT_TEST_TMUX_STATE="$TEST_ROOT/tmux"
export AGENT_TEST_AMPHETAMINE_STATE="$TEST_ROOT/amphetamine-state"
export AGENT_PMSET="$TEST_ROOT/bin/missing-pmset"
export AGENT_LOGIN_SHELL=/bin/zsh
AGENT="$PROJECT_ROOT/bin/agent"

fail() { printf 'test_agent_contract: %s\n' "$*" >&2; exit 1; }
assert_contains() { printf '%s' "$1" | grep -Fq "$2" || fail "missing expected text: $2"; }

help=$("$AGENT" help)
assert_contains "$help" 'agent                Enter this folder'
assert_contains "$help" 'agent wake'

cd "$TEST_ROOT/work/project with spaces!"
"$AGENT" wake
[ "$(cat "$AGENT_TEST_AMPHETAMINE_STATE")" = true ] || fail 'wake did not start Amphetamine'
"$AGENT" wake | grep -Fq 'already active' || fail 'repeated wake was not idempotent'

first=$("$AGENT")
assert_contains "$first" 'Persistent shell: agent-project-with-spaces-'
session_count=$(find "$AGENT_TEST_TMUX_STATE/sessions" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[ "$session_count" = 1 ] || fail "expected one session, got $session_count"
"$AGENT" >/dev/null
session_count=$(find "$AGENT_TEST_TMUX_STATE/sessions" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[ "$session_count" = 1 ] || fail 'repeated entry created another session'

session=$(basename "$AGENT_TEST_TMUX_STATE"/sessions/*)
[ "$(cat "$AGENT_TEST_TMUX_STATE/sessions/$session/created-root")" = "$TEST_ROOT/work/project with spaces!" ] || fail 'canonical root metadata is wrong'
[ "$(cat "$AGENT_TEST_TMUX_STATE/sessions/$session/command")" = 'exec /bin/zsh -l' ] || fail 'tmux did not receive a plain login shell'
! grep -Eq 'claude|codex' "$AGENT_TEST_TMUX_STATE/sessions/$session/command" || fail 'an agent was auto-launched'

status=$("$AGENT" status)
assert_contains "$status" 'Session: '
assert_contains "$status" '(running)'
assert_contains "$status" 'Amphetamine: active'
listed=$("$AGENT" list)
assert_contains "$listed" "$TEST_ROOT/work/project with spaces!"

if "$AGENT" sleep >/dev/null 2>&1; then fail 'sleep succeeded while a managed session remained'; fi
"$AGENT" stop >/dev/null
[ "$(cat "$AGENT_TEST_AMPHETAMINE_STATE")" = false ] || fail 'stopping the last session did not end Amphetamine'
"$AGENT" sleep | grep -Fq 'already inactive' || fail 'repeated sleep was not idempotent'

/bin/mkdir "$AGENT_TEST_TMUX_STATE/sessions/$session"
printf '%s\n' '0' >"$AGENT_TEST_TMUX_STATE/sessions/$session/env-AGENT_HELPER_MANAGED"
if "$AGENT" >/dev/null 2>&1; then fail 'session-name collision succeeded'; fi

if "$AGENT" nonsense >/dev/null 2>&1; then fail 'unknown command succeeded'; fi
printf '%s\n' 'test_agent_contract: PASS'
