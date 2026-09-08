#!/bin/sh

AGENT_OSASCRIPT=${AGENT_OSASCRIPT:-/usr/bin/osascript}
AGENT_AMPHETAMINE_APP=${AGENT_AMPHETAMINE_APP:-/Applications/Amphetamine.app}

amphetamine_error() {
    printf 'agent: %s\n' "$*" >&2
    return 1
}

amphetamine_require() {
    [ -d "$AGENT_AMPHETAMINE_APP" ] || \
        amphetamine_error "Amphetamine is not installed at $AGENT_AMPHETAMINE_APP"
    [ -x "$AGENT_OSASCRIPT" ] || \
        amphetamine_error "osascript is unavailable at $AGENT_OSASCRIPT"
}

amphetamine_tell() {
    "$AGENT_OSASCRIPT" -e "tell application \"Amphetamine\" to $1"
}

amphetamine_get_active() {
    amphetamine_require || return 1
    result=$(amphetamine_tell 'session is active') || {
        amphetamine_error "Amphetamine automation failed; allow terminal automation access and retry"
        return 1
    }
    case "$result" in
        true|false) printf '%s\n' "$result" ;;
        *) amphetamine_error "Amphetamine returned an unexpected session state: $result" ;;
    esac
}

amphetamine_state() {
    result=$(amphetamine_get_active) || return 1
    [ "$result" = "true" ] && printf '%s\n' active || printf '%s\n' inactive
}

amphetamine_start() {
    amphetamine_require || return 1
    active=$(amphetamine_get_active) || return 1
    if [ "$active" = "true" ]; then
        printf '%s\n' 'Amphetamine is already active.'
        return 0
    fi
    amphetamine_tell 'start new session' >/dev/null || {
        amphetamine_error "could not start Amphetamine; check Automation permissions"
        return 1
    }
    [ "$(amphetamine_get_active)" = "true" ] || \
        amphetamine_error "Amphetamine did not report an active session after start"
}

amphetamine_end() {
    amphetamine_require || return 1
    active=$(amphetamine_get_active) || return 1
    if [ "$active" = "false" ]; then
        printf '%s\n' 'Amphetamine is already inactive.'
        return 0
    fi
    amphetamine_tell 'end session' >/dev/null || {
        amphetamine_error "could not end Amphetamine; check Automation permissions"
        return 1
    }
    active=$(amphetamine_get_active) || return 1
    if [ "$active" = "true" ]; then
        amphetamine_error "Amphetamine still reports an active session after end"
        return 1
    fi
}
