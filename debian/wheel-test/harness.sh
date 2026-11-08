#!/bin/bash
# Usage: harness.sh <log> <libdir, or "stock" for the system library> <track|altscreen> [VAR=value...]
# Runs run.sh in a private D-Bus session with a private runtime dir, in-memory
# GSettings and local-only GIO, so nothing touches the desktop session's state.
# The VAR=value arguments go into the environment of every process in the run.
set -u
here=$(dirname "$(readlink -f "$0")")
log=$1 libdir=$2 mode=$3; shift 3
rt=$(mktemp -d "${TMPDIR:-/tmp}/vte-wheel-bus.XXXXXX"); chmod 700 "$rt"
env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
    XDG_RUNTIME_DIR="$rt" GSETTINGS_BACKEND=memory GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 NO_AT_BRIDGE=1 "$@" \
    timeout 90 dbus-run-session -- "$here/run.sh" "$log" "$libdir" "$mode"
rc=$?
rm -rf "$rt"
exit $rc
