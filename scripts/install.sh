#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
SOURCE=$PROJECT_ROOT/bin/agent
DESTINATION=$HOME/.local/bin/agent

fail() {
    printf 'install: %s\n' "$*" >&2
    exit 1
}

resolved_link() {
    link=$1
    target=$(readlink "$link") || return 1
    case "$target" in
        /*) ;;
        *) target=$(dirname -- "$link")/$target ;;
    esac
    directory=$(CDPATH= cd -- "$(dirname -- "$target")" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s\n' "$directory" "$(basename -- "$target")"
}

is_ours() {
    [ -L "$DESTINATION" ] && [ "$(resolved_link "$DESTINATION" 2>/dev/null || true)" = "$SOURCE" ]
}

check() {
    is_ours || fail "$DESTINATION is not a symlink to $SOURCE"
    [ -x "$SOURCE" ] || fail "$SOURCE is not executable"
    printf 'Agent Helper installation: PASS (%s -> %s)\n' "$DESTINATION" "$SOURCE"
}

install_agent() {
    [ -x "$SOURCE" ] || fail "$SOURCE is not executable"
    /bin/mkdir -p "$(dirname -- "$DESTINATION")"
    if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
        is_ours || fail "refusing to overwrite existing path: $DESTINATION"
        printf 'Agent Helper is already installed at %s.\n' "$DESTINATION"
        return 0
    fi
    /bin/ln -s "$SOURCE" "$DESTINATION"
    printf 'Installed Agent Helper at %s.\n' "$DESTINATION"
}

uninstall_agent() {
    if [ ! -e "$DESTINATION" ] && [ ! -L "$DESTINATION" ]; then
        printf 'Agent Helper is already uninstalled.\n'
        return 0
    fi
    is_ours || fail "refusing to remove path not owned by this project: $DESTINATION"
    /bin/rm "$DESTINATION"
    printf 'Removed %s. Sessions and Amphetamine settings were left unchanged.\n' "$DESTINATION"
}

case "${1:-}" in
    '') install_agent ;;
    --check) check ;;
    --uninstall) uninstall_agent ;;
    *) printf 'Usage: %s [--check|--uninstall]\n' "$0" >&2; exit 2 ;;
esac
