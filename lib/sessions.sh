#!/bin/sh

AGENT_TMUX=${AGENT_TMUX:-$(command -v tmux 2>/dev/null || true)}
AGENT_SHASUM=${AGENT_SHASUM:-/usr/bin/shasum}
AGENT_LOGIN_SHELL=${AGENT_LOGIN_SHELL:-${SHELL:-/bin/zsh}}
AGENT_SESSION_PREFIX=${AGENT_SESSION_PREFIX:-agent-}

sessions_error() {
    printf 'agent: %s\n' "$*" >&2
    return 1
}

sessions_require_tmux() {
    [ -n "$AGENT_TMUX" ] && [ -x "$AGENT_TMUX" ] || \
        sessions_error "tmux is required but was not found"
}

canonical_root() {
    (CDPATH= cd -- "${1:-.}" 2>/dev/null && pwd -P) || \
        sessions_error "cannot resolve directory: ${1:-.}"
}

session_slug() {
    basename -- "$1" | /usr/bin/tr '[:upper:]' '[:lower:]' | \
        /usr/bin/sed -e 's/[^a-z0-9_-][^a-z0-9_-]*/-/g' \
            -e 's/^-*//' -e 's/-*$//' -e 's/^$/project/' | \
        /usr/bin/cut -c1-32
}

session_name_for_root() {
    root=$(canonical_root "$1") || return 1
    slug=$(session_slug "$root")
    digest=$(printf '%s' "$root" | "$AGENT_SHASUM" -a 256 | /usr/bin/awk '{print substr($1,1,10)}')
    printf '%s%s-%s\n' "$AGENT_SESSION_PREFIX" "$slug" "$digest"
}

session_exists() {
    "$AGENT_TMUX" has-session -t "$1" 2>/dev/null
}

session_is_managed() {
    [ "$("$AGENT_TMUX" show-environment -t "$1" -v AGENT_HELPER_MANAGED 2>/dev/null || true)" = "1" ]
}

session_root() {
    "$AGENT_TMUX" show-environment -t "$1" -v AGENT_HELPER_ROOT 2>/dev/null
}

session_for_root() {
    root=$(canonical_root "$1") || return 1
    name=$(session_name_for_root "$root") || return 1
    if session_exists "$name" && session_is_managed "$name" && \
        [ "$(session_root "$name")" = "$root" ]; then
        printf '%s\n' "$name"
        return 0
    fi
    return 1
}

sessions_create() {
    root=$(canonical_root "$1") || return 1
    name=$(session_name_for_root "$root") || return 1
    if session_exists "$name"; then
        if ! session_is_managed "$name" || [ "$(session_root "$name")" != "$root" ]; then
            sessions_error "tmux session name collision: $name"
            return 1
        fi
        printf '%s\n' "$name"
        return 0
    fi

    "$AGENT_TMUX" new-session -d -s "$name" -c "$root" "exec $AGENT_LOGIN_SHELL -l" || \
        sessions_error "could not create tmux session $name"
    if ! "$AGENT_TMUX" set-environment -t "$name" AGENT_HELPER_MANAGED 1 || \
        ! "$AGENT_TMUX" set-environment -t "$name" AGENT_HELPER_ROOT "$root"; then
        "$AGENT_TMUX" kill-session -t "$name" >/dev/null 2>&1 || true
        sessions_error "could not record metadata for tmux session $name"
        return 1
    fi
    printf '%s\n' "$name"
}

sessions_attach() {
    "$AGENT_TMUX" attach-session -t "$1"
}

sessions_list_managed() {
    sessions_require_tmux || return 1
    if output=$("$AGENT_TMUX" list-sessions -F '#{session_name}' 2>/dev/null); then
        :
    else
        status=$?
        [ "$status" -eq 1 ] && return 0
        sessions_error "could not list tmux sessions"
        return 1
    fi
    printf '%s\n' "$output" | while IFS= read -r name; do
        [ -n "$name" ] || continue
        session_is_managed "$name" || continue
        root=$(session_root "$name") || continue
        printf '%s\t%s\n' "$name" "$root"
    done
}

sessions_managed_names() {
    sessions_require_tmux || return 1
    if output=$("$AGENT_TMUX" list-sessions -F '#{session_name}' 2>/dev/null); then
        :
    else
        status=$?
        [ "$status" -eq 1 ] && return 0
        sessions_error "could not list tmux sessions"
        return 1
    fi
    printf '%s\n' "$output" | while IFS= read -r name; do
        [ -n "$name" ] && session_is_managed "$name" && printf '%s\n' "$name"
    done
}

sessions_count_managed() {
    names=$(sessions_managed_names) || return 1
    count=$(printf '%s\n' "$names" | /usr/bin/awk 'NF {count++} END {print count+0}')
    printf '%s\n' "$count"
}

session_stop() {
    name=$1
    session_exists "$name" || return 0
    session_is_managed "$name" || {
        sessions_error "refusing to stop unmanaged tmux session $name"
        return 1
    }
    "$AGENT_TMUX" kill-session -t "$name" || \
        sessions_error "could not stop tmux session $name"
}
