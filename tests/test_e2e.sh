#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-e2e.XXXXXX")
TEST_ROOT=$(CDPATH= cd -- "$TEST_ROOT" && pwd -P)
PREFIX="agent-e2e-$$-"
AGENT=$PROJECT_ROOT/bin/agent

cleanup() {
    /opt/homebrew/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null | \
        /usr/bin/awk -v prefix="$PREFIX" 'index($0,prefix)==1 {print}' | \
        while IFS= read -r name; do
            [ -n "$name" ] && /opt/homebrew/bin/tmux kill-session -t "$name" 2>/dev/null || true
        done
    AGENT_SESSION_PREFIX=$PREFIX AGENT_LOCK_DIR="$TEST_ROOT/cleanup-lock" "$AGENT" sleep >/dev/null 2>&1 || true
    /bin/rm -rf "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

/bin/mkdir -p "$TEST_ROOT/one/same project" "$TEST_ROOT/two/same project"
export AGENT_SESSION_PREFIX=$PREFIX
export AGENT_LOCK_DIR="$TEST_ROOT/lock"
export AGENT_NONINTERACTIVE=1

(cd "$TEST_ROOT/one/same project" && "$AGENT" >/dev/null)
(cd "$TEST_ROOT/two/same project" && "$AGENT" >/dev/null)

names=$(/opt/homebrew/bin/tmux list-sessions -F '#{session_name}' | /usr/bin/awk -v prefix="$PREFIX" 'index($0,prefix)==1 {print}')
count=$(printf '%s\n' "$names" | /usr/bin/awk 'NF {count++} END {print count+0}')
[ "$count" -eq 2 ] || { printf 'test_e2e: expected two sessions, got %s\n' "$count" >&2; exit 1; }
first=$(printf '%s\n' "$names" | /usr/bin/sed -n '1p')
second=$(printf '%s\n' "$names" | /usr/bin/sed -n '2p')
[ "$first" != "$second" ] || { printf '%s\n' 'test_e2e: duplicate basenames collided' >&2; exit 1; }

for name in $names; do
    [ "$(/opt/homebrew/bin/tmux show-environment -t "$name" AGENT_HELPER_MANAGED)" = 'AGENT_HELPER_MANAGED=1' ] || exit 1
    command=$(/opt/homebrew/bin/tmux list-panes -t "$name" -F '#{pane_start_command}')
    printf '%s\n' "$command" | /usr/bin/grep -Fq ' -l' || { printf 'test_e2e: %s is not a login shell\n' "$name" >&2; exit 1; }
    ! printf '%s\n' "$command" | /usr/bin/grep -Eq 'claude|codex' || { printf 'test_e2e: %s auto-launched an agent\n' "$name" >&2; exit 1; }
done

(cd "$TEST_ROOT/one/same project" && "$AGENT" stop >/dev/null)
[ "$(/usr/bin/osascript -e 'tell application "Amphetamine" to session is active')" = true ] || { printf '%s\n' 'test_e2e: shared wake ended too early' >&2; exit 1; }
(cd "$TEST_ROOT/two/same project" && "$AGENT" stop >/dev/null)
[ "$(/usr/bin/osascript -e 'tell application "Amphetamine" to session is active')" = false ] || { printf '%s\n' 'test_e2e: final stop left wake active' >&2; exit 1; }

printf '%s\n' 'test_e2e: PASS'
