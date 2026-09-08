#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-concurrency.XXXXXX")
TEST_ROOT=$(CDPATH= cd -- "$TEST_ROOT" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
/bin/mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/tmux" "$TEST_ROOT/Amphetamine.app" "$TEST_ROOT/project"
/bin/cp "$PROJECT_ROOT/tests/fixtures/fake-tmux" "$TEST_ROOT/bin/tmux"
/bin/cp "$PROJECT_ROOT/tests/fixtures/fake-osascript" "$TEST_ROOT/bin/osascript"
/bin/chmod +x "$TEST_ROOT/bin/tmux" "$TEST_ROOT/bin/osascript"

export AGENT_TMUX="$TEST_ROOT/bin/tmux"
export AGENT_OSASCRIPT="$TEST_ROOT/bin/osascript"
export AGENT_AMPHETAMINE_APP="$TEST_ROOT/Amphetamine.app"
export AGENT_TEST_TMUX_STATE="$TEST_ROOT/tmux"
export AGENT_TEST_AMPHETAMINE_STATE="$TEST_ROOT/amphetamine-state"
export AGENT_PMSET="$TEST_ROOT/bin/missing-pmset"
export AGENT_LOCK_DIR="$TEST_ROOT/lock"
AGENT="$PROJECT_ROOT/bin/agent"

pids=
index=1
while [ "$index" -le 8 ]; do
    (cd "$TEST_ROOT/project" && "$AGENT" >/dev/null) &
    pids="$pids $!"
    index=$((index + 1))
done
for pid in $pids; do
    wait "$pid"
done

count=$(find "$TEST_ROOT/tmux/sessions" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[ "$count" = 1 ] || { printf 'test_concurrency: expected one session, got %s\n' "$count" >&2; exit 1; }
[ ! -d "$AGENT_LOCK_DIR" ] || { printf '%s\n' 'test_concurrency: lock was not released' >&2; exit 1; }

(cd "$TEST_ROOT/project" && "$AGENT" stop >/dev/null)
[ "$(cat "$AGENT_TEST_AMPHETAMINE_STATE")" = false ] || { printf '%s\n' 'test_concurrency: final stop left wake active' >&2; exit 1; }
printf '%s\n' 'test_concurrency: PASS'
