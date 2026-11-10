#!/bin/bash
# Usage (inside dbus-run-session):
#   run.sh <log> <libdir, or "stock" for the system library> <track|altscreen> <3|4> <wayland|x11>
# Starts a headless mutter with a private Wayland display and runtime dir,
# opens the GTK 3 or GTK 4 VTE test window in it, injects scroll events, then
# stops both. With x11, mutter also serves X displays through Xwayland and the
# window connects to one of them.
set -u
log=$1; libdir=$2; mode=$3; gtk=$4; backend=$5
here=$(dirname "$(readlink -f "$0")")
rt=$(mktemp -d "${TMPDIR:-/tmp}/vte-wheel-xdg.XXXXXX"); chmod 700 "$rt"
export XDG_RUNTIME_DIR=$rt
unset DISPLAY WAYLAND_DISPLAY
: > "$log"
if [ "$backend" = x11 ]; then x11_flag=; else x11_flag=--no-x11; fi
mutter --headless --wayland $x11_flag --wayland-display=wl-wheeltest --virtual-monitor 800x600 > "$log.mutter" 2>&1 &
mpid=$!
for _ in $(seq 100); do [ -S "$rt/wl-wheeltest" ] && break; sleep 0.1; done
[ -S "$rt/wl-wheeltest" ] || { echo "mutter did not start"; cat "$log.mutter"; kill $mpid; exit 1; }

# Mutter reserves its X displays by writing its own process id into
# /tmp/.X<n>-lock, as every X server does, and starts Xwayland when the first
# client connects. Both displays it reserves lead to the same Xwayland, so
# take the lowest. Matching the process id keeps the window off the desktop's
# own displays.
our_x_display() {
    local f n best=
    for f in /tmp/.X*-lock; do
        [ "$(tr -d ' \n' < "$f" 2>/dev/null)" = "$mpid" ] || continue
        n=${f#/tmp/.X}; n=${n%-lock}
        if [ -z "$best" ] || [ "$n" -lt "$best" ]; then best=$n; fi
    done
    echo "$best"
}
display_env=(WAYLAND_DISPLAY=wl-wheeltest GDK_BACKEND=wayland)
if [ "$backend" = x11 ]; then
    xnum=
    for _ in $(seq 100); do xnum=$(our_x_display); [ -n "$xnum" ] && break; sleep 0.1; done
    auths=("$rt"/.mutter-Xwaylandauth.*)
    if [ -z "$xnum" ] || [ ${#auths[@]} -ne 1 ] || [ ! -f "${auths[0]}" ]; then
        echo "mutter did not reserve an X display with an auth file"; cat "$log.mutter"; kill $mpid; exit 1
    fi
    display_env=(DISPLAY=":$xnum" XAUTHORITY="${auths[0]}" GDK_BACKEND=x11)
fi

if [ "$libdir" = stock ]; then ld=; else ld=$libdir; fi
env "${display_env[@]}" LD_LIBRARY_PATH="$ld" \
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
