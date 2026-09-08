#!/bin/sh

AGENT_PMSET=${AGENT_PMSET:-/usr/bin/pmset}
AGENT_UNAME=${AGENT_UNAME:-/usr/bin/uname}
AGENT_SW_VERS=${AGENT_SW_VERS:-/usr/bin/sw_vers}
AGENT_SYSTEM_PROFILER=${AGENT_SYSTEM_PROFILER:-/usr/sbin/system_profiler}
AGENT_MDLS=${AGENT_MDLS:-/usr/bin/mdls}
AGENT_POWER_PROTECT_SCRIPT=${AGENT_POWER_PROTECT_SCRIPT:-$HOME/Library/Application Scripts/com.if.Amphetamine/powerProtect.scpt}
AGENT_CLOSED_LID_MARKER=${AGENT_CLOSED_LID_MARKER:-$PROJECT_ROOT/.verification/closed-lid-verified}

doctor_power_source() {
    "$AGENT_PMSET" -g batt 2>/dev/null | /usr/bin/sed -n "1s/.*'\([^']*\)'.*/\1/p"
}

doctor_battery_percent() {
    "$AGENT_PMSET" -g batt 2>/dev/null | \
        /usr/bin/sed -n 's/.*[[:space:]]\([0-9][0-9]*\)%;.*/\1/p' | /usr/bin/head -n 1
}

doctor_sleep_disabled() {
    "$AGENT_PMSET" -g 2>/dev/null | /usr/bin/awk '/SleepDisabled/ {print $2; exit}'
}

doctor_model() {
    "$AGENT_SYSTEM_PROFILER" SPHardwareDataType 2>/dev/null | \
        /usr/bin/awk -F ': ' '/Model Identifier/ {print $2; exit}'
}

doctor_app_version() {
    "$AGENT_MDLS" -raw -name kMDItemVersion "$AGENT_AMPHETAMINE_APP" 2>/dev/null
}

doctor_expected_identity() {
    printf 'model=%s\nos=%s\nbuild=%s\namphetamine=%s\n' \
        "$(doctor_model)" \
        "$("$AGENT_SW_VERS" -productVersion 2>/dev/null)" \
        "$("$AGENT_SW_VERS" -buildVersion 2>/dev/null)" \
        "$(doctor_app_version)"
}

doctor_marker_is_current() {
    [ -f "$AGENT_CLOSED_LID_MARKER" ] || return 1
    doctor_expected_identity | while IFS= read -r line; do
        /usr/bin/grep -Fqx "$line" "$AGENT_CLOSED_LID_MARKER" || exit 1
    done
}

doctor_automation_check() {
    amphetamine_get_active >/dev/null
}

doctor_check() {
    label=$1
    shift
    if "$@"; then
        printf 'PASS  %s\n' "$label"
    else
        printf 'FAIL  %s\n' "$label"
        DOCTOR_FAILURES=$((DOCTOR_FAILURES + 1))
    fi
}

doctor_install_check() {
    expected=$HOME/.local/bin/agent
    if [ -L "$expected" ] && [ "$(resolve_script "$expected")" = "$SCRIPT_PATH" ]; then
        printf 'PASS  install path (%s)\n' "$expected"
    else
        printf 'WARN  install path (run scripts/install.sh)\n'
    fi
}

doctor_run() {
    DOCTOR_FAILURES=0
    doctor_check 'tmux executable' sessions_require_tmux
    doctor_check 'Amphetamine app' test -d "$AGENT_AMPHETAMINE_APP"
    doctor_check 'AppleScript automation' doctor_automation_check
    if [ "$("$AGENT_UNAME" -m 2>/dev/null)" = arm64 ]; then
        doctor_check 'Amphetamine Power Protect' test -f "$AGENT_POWER_PROTECT_SCRIPT"
    fi
    doctor_check 'current closed-lid proof' doctor_marker_is_current
    doctor_install_check
    source=$(doctor_power_source)
    battery=$(doctor_battery_percent)
    printf 'INFO  power source: %s; battery: %s%%; configured cutoff: 30%%\n' \
        "${source:-unknown}" "${battery:-unknown}"
    [ "$DOCTOR_FAILURES" -eq 0 ]
}
