#!/bin/sh

AGENT_LOCK_DIR=${AGENT_LOCK_DIR:-${TMPDIR:-/tmp}/agent-helper-$(/usr/bin/id -u).lock}
AGENT_LOCK_HELD=0

lock_error() {
    printf 'agent: %s\n' "$*" >&2
    return 1
}

lock_acquire() {
    attempts=0
    while ! /bin/mkdir "$AGENT_LOCK_DIR" 2>/dev/null; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 100 ] || {
            lock_error "timed out waiting for another Agent Helper command"
            return 1
        }
        /bin/sleep 0.05
    done
    printf '%s\n' "$$" >"$AGENT_LOCK_DIR/owner"
    AGENT_LOCK_HELD=1
}

lock_release() {
    [ "$AGENT_LOCK_HELD" -eq 1 ] || return 0
    if [ "$(cat "$AGENT_LOCK_DIR/owner" 2>/dev/null || true)" = "$$" ]; then
        /bin/rm -f "$AGENT_LOCK_DIR/owner"
        /bin/rmdir "$AGENT_LOCK_DIR" 2>/dev/null || true
    fi
    AGENT_LOCK_HELD=0
}
