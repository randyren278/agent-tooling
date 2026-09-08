#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-safety.XXXXXX")
TEST_ROOT=$(CDPATH= cd -- "$TEST_ROOT" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
/bin/mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/tmux" "$TEST_ROOT/Amphetamine.app" "$TEST_ROOT/a" "$TEST_ROOT/b"
/bin/cp "$PROJECT_ROOT/tests/fixtures/fake-tmux" "$TEST_ROOT/bin/tmux"
/bin/cp "$PROJECT_ROOT/tests/fixtures/fake-osascript" "$TEST_ROOT/bin/osascript"
for tool in pmset uname sw_vers system_profiler mdls; do
    /bin/cp "$PROJECT_ROOT/tests/fixtures/fake-platform" "$TEST_ROOT/bin/$tool"
done
/bin/chmod +x "$TEST_ROOT/bin/"*

export AGENT_TMUX="$TEST_ROOT/bin/tmux"
export AGENT_OSASCRIPT="$TEST_ROOT/bin/osascript"
export AGENT_AMPHETAMINE_APP="$TEST_ROOT/Amphetamine.app"
export AGENT_TEST_TMUX_STATE="$TEST_ROOT/tmux"
export AGENT_TEST_AMPHETAMINE_STATE="$TEST_ROOT/amphetamine-state"
export AGENT_PMSET="$TEST_ROOT/bin/pmset"
export AGENT_UNAME="$TEST_ROOT/bin/uname"
export AGENT_SW_VERS="$TEST_ROOT/bin/sw_vers"
export AGENT_SYSTEM_PROFILER="$TEST_ROOT/bin/system_profiler"
export AGENT_MDLS="$TEST_ROOT/bin/mdls"
export AGENT_POWER_PROTECT_SCRIPT="$TEST_ROOT/powerProtect.scpt"
export AGENT_CLOSED_LID_MARKER="$TEST_ROOT/closed-lid-verified"
export AGENT_LOCK_DIR="$TEST_ROOT/lock"
AGENT="$PROJECT_ROOT/bin/agent"

fail() { printf 'test_safety: %s\n' "$*" >&2; exit 1; }

: >"$AGENT_POWER_PROTECT_SCRIPT"
printf '%s\n' 'model=TestMac1,1' 'os=99.1' 'build=99A1' 'amphetamine=5.3.2' >"$AGENT_CLOSED_LID_MARKER"

(cd "$TEST_ROOT/a" && "$AGENT" >/dev/null 2>"$TEST_ROOT/battery-warning")
grep -Fq 'configured to end at 30%' "$TEST_ROOT/battery-warning" || fail 'battery start lacked cutoff warning'
(cd "$TEST_ROOT/b" && "$AGENT" >/dev/null)
[ "$(cat "$AGENT_TEST_AMPHETAMINE_STATE")" = true ] || fail 'launch did not enable wake protection'

if (cd "$TEST_ROOT/a" && "$AGENT" sleep >/dev/null 2>&1); then fail 'sleep succeeded with managed sessions'; fi
"$AGENT" sleep --force 2>"$TEST_ROOT/force-warning"
grep -Fq 'WARNING' "$TEST_ROOT/force-warning" || fail 'forced sleep lacked warning'
[ "$(find "$TEST_ROOT/tmux/sessions" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = 2 ] || fail 'forced sleep killed tmux sessions'

"$AGENT" wake >/dev/null
(cd "$TEST_ROOT/a" && "$AGENT" stop >/dev/null)
[ "$(cat "$AGENT_TEST_AMPHETAMINE_STATE")" = true ] || fail 'stopping one project ended shared wake protection'
(cd "$TEST_ROOT/b" && "$AGENT" stop >/dev/null)
[ "$(cat "$AGENT_TEST_AMPHETAMINE_STATE")" = false ] || fail 'stopping last project did not end wake protection'

"$AGENT" wake >/dev/null
export AGENT_TEST_OSASCRIPT_FAILURE=end
if "$AGENT" sleep >/dev/null 2>&1; then fail 'failed AppleScript end was reported as success'; fi
unset AGENT_TEST_OSASCRIPT_FAILURE

export AGENT_TEST_OSASCRIPT_FAILURE=query
if "$AGENT" status >/dev/null 2>&1; then fail 'denied automation was reported as a valid status'; fi
unset AGENT_TEST_OSASCRIPT_FAILURE

"$AGENT" doctor >"$TEST_ROOT/doctor-current"
grep -Fq 'PASS  current closed-lid proof' "$TEST_ROOT/doctor-current" || fail 'current proof did not pass doctor'
printf '%s\n' 'model=StaleMac1,1' >"$AGENT_CLOSED_LID_MARKER"
if "$AGENT" doctor >/dev/null 2>&1; then fail 'stale verification marker passed doctor'; fi

/bin/mv "$AGENT_AMPHETAMINE_APP" "$TEST_ROOT/Amphetamine.missing"
if "$AGENT" wake >/dev/null 2>&1; then fail 'missing app passed wake'; fi
/bin/mv "$TEST_ROOT/Amphetamine.missing" "$AGENT_AMPHETAMINE_APP"

export AGENT_TEST_TMUX_FAILURE=list-sessions
if "$AGENT" sleep >/dev/null 2>&1; then fail 'tmux listing failure was treated as no sessions'; fi
unset AGENT_TEST_TMUX_FAILURE

printf '%s\n' 'test_safety: PASS'
