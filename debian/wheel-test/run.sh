#!/bin/bash
# Usage (inside dbus-run-session): run.sh <log> <libdir, or "stock" for the system library> <track|altscreen> <3|4>
# Starts a headless mutter with a private Wayland display and runtime dir,
# opens the GTK 3 or GTK 4 VTE test window in it, injects scroll events, then
# stops both.
set -u
log=$1; libdir=$2; mode=$3; gtk=$4
here=$(dirname "$(readlink -f "$0")")
rt=$(mktemp -d "${TMPDIR:-/tmp}/vte-wheel-xdg.XXXXXX"); chmod 700 "$rt"
export XDG_RUNTIME_DIR=$rt
unset DISPLAY WAYLAND_DISPLAY
: > "$log"
mutter --headless --wayland --no-x11 --wayland-display=wl-wheeltest --virtual-monitor 800x600 > "$log.mutter" 2>&1 &
mpid=$!
for _ in $(seq 100); do [ -S "$rt/wl-wheeltest" ] && break; sleep 0.1; done
[ -S "$rt/wl-wheeltest" ] || { echo "mutter did not start"; cat "$log.mutter"; kill $mpid; exit 1; }
if [ "$libdir" = stock ]; then ld=; else ld=$libdir; fi
env WAYLAND_DISPLAY=wl-wheeltest GDK_BACKEND=wayland LD_LIBRARY_PATH="$ld" \
    python3 -I "$here/vteclient.py" "$log" "$here/capture.py" "$mode" "$gtk" > "$log.client" 2>&1 &
cpid=$!
for _ in $(seq 100); do grep -q '^READY' "$log" 2>/dev/null && break; sleep 0.1; done
grep -q '^READY' "$log" || { echo "client did not start"; cat "$log.client"; kill $cpid $mpid; exit 1; }
sleep 0.5
python3 -I "$here/inject.py" "$log"
rc=$?
kill $cpid; wait $cpid 2>/dev/null
kill $mpid; wait $mpid 2>/dev/null
rm -rf "$rt"
exit $rc
