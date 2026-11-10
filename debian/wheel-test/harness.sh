#!/bin/bash
# Usage: harness.sh <log> <libdir, or "stock" for the system library> <track|altscreen> <3|4> [VAR=value...]
# Runs run.sh in a private D-Bus session with a private runtime dir, in-memory
# GSettings and local-only GIO, so the run leaves the desktop session's state
# as it was. VTE_WHEEL_EVENTS_PER_NOTCH from the caller's environment is
# removed, so each run uses the default unless it passes the variable itself.
# The VAR=value arguments go into the environment of every process in the run.
set -u
here=$(dirname "$(readlink -f "$0")")
log=$1 libdir=$2 mode=$3 gtk=$4; shift 4
rt=$(mktemp -d "${TMPDIR:-/tmp}/vte-wheel-bus.XXXXXX"); chmod 700 "$rt"
env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u VTE_WHEEL_EVENTS_PER_NOTCH \
    XDG_RUNTIME_DIR="$rt" GSETTINGS_BACKEND=memory GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 NO_AT_BRIDGE=1 "$@" \
    timeout 90 dbus-run-session -- "$here/run.sh" "$log" "$libdir" "$mode" "$gtk"
rc=$?
rm -rf "$rt"
exit $rc
