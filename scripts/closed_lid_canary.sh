#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
SCRIPT_PATH="$SCRIPT_DIR/closed_lid_canary.sh"
RUNTIME_DIR="$PROJECT_ROOT/.verification/runtime"
MARKER="$PROJECT_ROOT/.verification/closed-lid-verified"
COUNT_FILE="$RUNTIME_DIR/counter.count"
START_FILE="$RUNTIME_DIR/start.epoch"
META_FILE="$RUNTIME_DIR/meta"
WAKE_FILE="$RUNTIME_DIR/wake-started-here"
CANARY_SESSION="agent-helper-canary-$(/usr/bin/id -u)"
MIN_ELAPSED=120
MIN_TICKS=90

fail() {
    printf 'closed_lid_canary: %s\n' "$*" >&2
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

model_identifier() {
    /usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | \
        /usr/bin/awk -F ': ' '/Model Identifier/ {print $2; exit}'
}

app_version() {
    /usr/bin/mdls -raw -name kMDItemVersion /Applications/Amphetamine.app
}

power_source() {
    /usr/bin/pmset -g batt | /usr/bin/sed -n "1s/.*'\([^']*\)'.*/\1/p"
}

write_identity() {
    printf 'model=%s\nos=%s\nbuild=%s\namphetamine=%s\n' \
        "$(model_identifier)" \
        "$(/usr/bin/sw_vers -productVersion)" \
        "$(/usr/bin/sw_vers -buildVersion)" \
        "$(app_version)"
}

write_metadata() {
    write_identity
    printf 'power_source=%s\n' "$(power_source)"
}

tmux_has_canary() {
    /opt/homebrew/bin/tmux has-session -t "$CANARY_SESSION" 2>/dev/null
}

tmux_owns_canary() {
    [ "$(/opt/homebrew/bin/tmux show-option -qv -t "$CANARY_SESSION" @agent_helper_canary 2>/dev/null || true)" = "1" ]
}

shell_quote() {
    escaped=$(printf '%s' "$1" | /usr/bin/sed "s/'/'\\\\''/g")
    printf "'%s'" "$escaped"
}

counter() {
    target=$1
    ticks=0
    while :; do
        ticks=$((ticks + 1))
        printf '%s\n' "$ticks" >"$target"
        /bin/sleep 1
    done
}

cleanup() {
    cleanup_status=0
    if tmux_has_canary; then
        if tmux_owns_canary; then
            /opt/homebrew/bin/tmux kill-session -t "$CANARY_SESSION" || cleanup_status=1
        else
            printf 'closed_lid_canary: refusing to kill unowned tmux session %s\n' "$CANARY_SESSION" >&2
            cleanup_status=1
        fi
    fi

    if [ -f "$WAKE_FILE" ]; then
        amphetamine 'if (session is active) then end session' >/dev/null 2>&1 || cleanup_status=1
        if ! wait_for_sleep_disabled 0; then
            printf '%s\n' 'closed_lid_canary: normal sleep was not restored (SleepDisabled is not 0)' >&2
            cleanup_status=1
        else
            /bin/rm -f "$WAKE_FILE"
        fi
    fi

    /bin/rm -f "$COUNT_FILE" "$START_FILE" "$META_FILE"
    return "$cleanup_status"
}

prepare() {
    [ -d /Applications/Amphetamine.app ] || fail "Amphetamine is not installed"
    [ -x /opt/homebrew/bin/tmux ] || fail "tmux is missing"
    [ ! -f "$START_FILE" ] || fail "a canary is already prepared; run cleanup first"
    ! tmux_has_canary || fail "tmux session $CANARY_SESSION already exists"
    [ "$(amphetamine 'session is active')" = "false" ] || \
        fail "an Amphetamine session is already active; end it before preparing the canary"
    /bin/mkdir -p "$RUNTIME_DIR"

    amphetamine 'start new session' >/dev/null
    : >"$WAKE_FILE"
    [ "$(amphetamine 'session is active')" = "true" ] || fail "Amphetamine is not active"
    [ "$(amphetamine 'closed display mode enabled')" = "true" ] || fail "closed-display mode is disabled"
    if ! wait_for_sleep_disabled 1; then
        cleanup || true
        fail "Power Protect did not set SleepDisabled=1; restart the Amphetamine session"
    fi

    /bin/date +%s >"$START_FILE"
    write_metadata >"$META_FILE"
    : >"$COUNT_FILE"
    counter_command="exec $(shell_quote "$SCRIPT_PATH") _counter $(shell_quote "$COUNT_FILE")"
    /opt/homebrew/bin/tmux new-session -d -s "$CANARY_SESSION" -c "$PROJECT_ROOT" "$counter_command"
    /opt/homebrew/bin/tmux set-option -q -t "$CANARY_SESSION" @agent_helper_canary 1
    /bin/sleep 2
    tmux_has_canary || { cleanup || true; fail "tmux canary did not stay alive"; }
    tmux_owns_canary || { cleanup || true; fail "tmux canary ownership marker is missing"; }
    ticks=$(cat "$COUNT_FILE")
    [ "${ticks:-0}" -ge 2 ] || { cleanup || true; fail "counter did not begin advancing"; }

    printf '%s\n' "Canary prepared in tmux session $CANARY_SESSION."
    printf '%s\n' "Before closing the lid, run a separate preflight:"
    printf '%s\n' "  sh scripts/closed_lid_canary.sh preflight"
}

preflight() {
    [ -f "$START_FILE" ] || fail "no prepared canary; run prepare first"
    tmux_has_canary || fail "tmux canary is not running"
    tmux_owns_canary || fail "tmux canary ownership marker is missing"
    before=$(cat "$COUNT_FILE")
    /bin/sleep 4
    after=$(cat "$COUNT_FILE")
    [ "$after" -ge $((before + 3)) ] || \
        fail "counter did not survive its launching shell (${before} -> ${after})"
    [ "$(amphetamine 'session is active')" = "true" ] || fail "Amphetamine is not active"
    [ "$(sleep_disabled)" = "1" ] || fail "Power Protect is not active"
    printf 'Open-lid preflight: PASS (%s -> %s ticks, SleepDisabled=1)\n' "$before" "$after"
    printf '%s\n' "Now close the lid for at least 120 seconds, reopen it, and run verify."
}

verify_saved_marker() {
    [ -f "$MARKER" ] || fail "no prepared canary or saved proof; run prepare first"
    current=$(write_identity)
    while IFS= read -r line; do
        /usr/bin/grep -Fqx "$line" "$MARKER" || fail "saved proof is stale for this machine or app version"
    done <<EOF
$current
EOF
    printf 'Closed-lid canary marker is current: PASS\n'
}

verify() {
    if [ ! -f "$START_FILE" ]; then
        verify_saved_marker
        return 0
    fi
    [ -f "$COUNT_FILE" ] || fail "counter output is missing"
    [ -f "$META_FILE" ] || fail "canary metadata is missing"
    if ! tmux_has_canary || ! tmux_owns_canary; then
        cleanup || true
        fail "owned tmux canary did not survive"
    fi

    start=$(cat "$START_FILE")
    now=$(/bin/date +%s)
    elapsed=$((now - start))
    ticks=$(cat "$COUNT_FILE")
    case "$ticks" in
        ''|*[!0-9]*) fail "counter output is invalid" ;;
    esac

    [ "$elapsed" -ge "$MIN_ELAPSED" ] || \
        fail "only ${elapsed}s elapsed; keep the lid closed for at least ${MIN_ELAPSED}s"
    if [ "$ticks" -lt "$MIN_TICKS" ]; then
        cleanup || fail "counter failed and cleanup could not restore normal sleep"
        fail "counter advanced only ${ticks} ticks during ${elapsed}s; the Mac likely slept"
    fi
    if [ "$(amphetamine 'session is active')" != "true" ] || [ "$(sleep_disabled)" != "1" ]; then
        cleanup || fail "protection failed and cleanup could not restore normal sleep"
        fail "Amphetamine or Power Protect ended during the canary"
    fi

    {
        cat "$META_FILE"
        printf 'verified_at=%s\nelapsed_seconds=%s\nticks=%s\n' \
            "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$elapsed" "$ticks"
    } >"$MARKER"
    cleanup || fail "proof passed but cleanup could not restore normal sleep"
    printf 'Closed-lid canary: PASS (%ss elapsed, %s active ticks)\n' "$elapsed" "$ticks"
    printf 'Normal sleep restored: PASS (SleepDisabled=0)\n'
}

case "${1:-}" in
    prepare) prepare ;;
    preflight) preflight ;;
    verify) verify ;;
    cleanup) cleanup ;;
    _counter) counter "${2:?counter file required}" ;;
    *)
        printf 'Usage: %s {prepare|preflight|verify|cleanup}\n' "$0" >&2
        exit 2
        ;;
esac
