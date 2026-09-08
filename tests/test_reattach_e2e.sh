#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-reattach.XXXXXX")
TEST_ROOT=$(CDPATH= cd -- "$TEST_ROOT" && pwd -P)
PREFIX="agent-reattach-$$-"
AGENT=$PROJECT_ROOT/bin/agent
NAME=

cleanup() {
    [ -z "$NAME" ] || /opt/homebrew/bin/tmux kill-session -t "$NAME" 2>/dev/null || true
    AGENT_SESSION_PREFIX=$PREFIX AGENT_LOCK_DIR="$TEST_ROOT/cleanup-lock" "$AGENT" sleep >/dev/null 2>&1 || true
    /bin/rm -rf "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

/bin/mkdir -p "$TEST_ROOT/project"
export AGENT_SESSION_PREFIX=$PREFIX
export AGENT_LOCK_DIR="$TEST_ROOT/lock"

attach_and_detach() {
    { /bin/sleep 1; printf '\002d'; /bin/sleep 1; } | \
        TERM=xterm-256color /usr/bin/script -q /dev/null \
        /bin/sh -c 'cd "$1" && exec "$2"' agent-reattach-client \
        "$TEST_ROOT/project" "$AGENT" >/dev/null
}

attach_and_detach
NAME=$(/opt/homebrew/bin/tmux list-sessions -F '#{session_name}' | /usr/bin/awk -v prefix="$PREFIX" 'index($0,prefix)==1 {print; exit}')
[ -n "$NAME" ] || { printf '%s\n' 'test_reattach_e2e: managed session was not created' >&2; exit 1; }
session_id=$(/opt/homebrew/bin/tmux display-message -p -t "$NAME" '#{session_id}')

command="counter=0; echo \\\$$ > '$TEST_ROOT/worker.pid'; while :; do counter=\\\$((counter + 1)); echo \\\$counter > '$TEST_ROOT/counter'; sleep 1; done"
/opt/homebrew/bin/tmux send-keys -t "$NAME" "sh -c \"$command\"" Enter
attempts=0
while [ ! -s "$TEST_ROOT/counter" ] && [ "$attempts" -lt 20 ]; do
    attempts=$((attempts + 1))
    /bin/sleep 0.25
done
if [ ! -s "$TEST_ROOT/counter" ]; then
    printf '%s\n' 'test_reattach_e2e: counter did not start; pane follows' >&2
    /opt/homebrew/bin/tmux capture-pane -p -t "$NAME" >&2 || true
    exit 1
fi
pid_before=$(cat "$TEST_ROOT/worker.pid")
count_before=$(cat "$TEST_ROOT/counter")

attach_and_detach
/bin/sleep 2
session_after=$(/opt/homebrew/bin/tmux display-message -p -t "$NAME" '#{session_id}')
pid_after=$(cat "$TEST_ROOT/worker.pid")
count_after=$(cat "$TEST_ROOT/counter")

[ "$session_id" = "$session_after" ] || { printf '%s\n' 'test_reattach_e2e: agent entered a different tmux session' >&2; exit 1; }
[ "$pid_before" = "$pid_after" ] || { printf '%s\n' 'test_reattach_e2e: worker PID changed' >&2; exit 1; }
[ "$count_after" -gt "$count_before" ] || { printf '%s\n' 'test_reattach_e2e: counter did not survive re-entry' >&2; exit 1; }

(cd "$TEST_ROOT/project" && "$AGENT" stop >/dev/null)
NAME=
printf '%s\n' 'test_reattach_e2e: PASS'
