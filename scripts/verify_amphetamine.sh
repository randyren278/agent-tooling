#!/bin/sh
set -eu

APP="/Applications/Amphetamine.app"
POWER_PROTECT_SCRIPT="$HOME/Library/Application Scripts/com.if.Amphetamine/powerProtect.scpt"
POWER_PROTECT_RULE="/private/etc/sudoers.d/amphetamine_powerProtect"
started_here=0

fail() {
    printf 'verify_amphetamine: %s\n' "$*" >&2
    exit 1
}

amphetamine() {
    /usr/bin/osascript -e "tell application \"Amphetamine\" to $1"
}

sleep_disabled() {
    /usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/ {print $2; exit}'
}

wait_for_sleep_disabled() {
    expected=$1
    attempts=0
    while [ "$attempts" -lt 8 ]; do
        [ "$(sleep_disabled)" = "$expected" ] && return 0
        attempts=$((attempts + 1))
        /bin/sleep 1
    done
    return 1
}

cleanup() {
    if [ "$started_here" -eq 1 ]; then
        amphetamine 'if (session is active) then end session' >/dev/null 2>&1 || true
        if ! wait_for_sleep_disabled 0; then
            printf '%s\n' 'verify_amphetamine: cleanup could not restore SleepDisabled=0' >&2
        fi
    fi
}
trap cleanup EXIT HUP INT TERM

[ -d "$APP" ] || fail "Amphetamine is not installed at $APP"

if [ "$(/usr/bin/uname -m)" = "arm64" ]; then
    [ -f "$POWER_PROTECT_SCRIPT" ] || fail "Power Protect script is missing: $POWER_PROTECT_SCRIPT"
    [ -e "$POWER_PROTECT_RULE" ] || fail "Power Protect sudoers rule is missing: $POWER_PROTECT_RULE"
fi

[ "$(amphetamine 'session is active')" = "false" ] || \
    fail "an Amphetamine session is already active; end it before running this verifier"
[ "$(amphetamine 'display sleep allowed')" = "true" ] || \
    fail "default sessions must allow display sleep"
[ "$(amphetamine 'closed display mode enabled')" = "true" ] || \
    fail "closed-display mode is not enabled"
[ "$(/usr/bin/defaults read com.if.Amphetamine 'End Session On Low Battery')" = "1" ] || \
    fail "low-battery auto-end is disabled"
[ "$(/usr/bin/defaults read com.if.Amphetamine 'Low Battery Percent')" = "30" ] || \
    fail "low-battery threshold is not 30%"

amphetamine 'start new session' >/dev/null
started_here=1
[ "$(amphetamine 'session is active')" = "true" ] || fail "session did not become active"
[ "$(amphetamine 'display sleep allowed')" = "true" ] || fail "active session prevents display sleep"
[ "$(amphetamine 'closed display mode enabled')" = "true" ] || fail "active session lacks closed-display mode"
wait_for_sleep_disabled 1 || fail "Power Protect did not set SleepDisabled=1"

amphetamine 'end session' >/dev/null
[ "$(amphetamine 'session is active')" = "false" ] || fail "session did not end cleanly"
wait_for_sleep_disabled 0 || fail "Power Protect did not restore SleepDisabled=0"
started_here=0

version=$(/usr/bin/mdls -raw -name kMDItemVersion "$APP")
printf 'Amphetamine %s automation, 30%% cutoff, cleanup, and Power Protect: PASS\n' "$version"
