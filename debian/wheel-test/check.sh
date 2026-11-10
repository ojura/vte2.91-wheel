#!/bin/bash
# Usage: check.sh <stock libdir> <patched libdir>
#
# Tests vte-wheel-events-per-notch.patch without touching the desktop: each
# run starts a headless mutter in a private D-Bus session, opens a VTE window
# in it, injects wheel and touchpad scroll events through mutter's
# RemoteDesktop API and counts what the program inside the terminal receives
# (see harness.sh). Each libdir is a directory holding libvte-2.91.so.0, such
# as usr/lib/x86_64-linux-gnu inside a libvte-2.91-0 .deb unpacked with
# dpkg-deb -x.
#
# Expected counts. GTK divides Wayland axis values by 10, so a wheel notch is a
# delta of 1 and the injected touchpad movements are 20 x 0.5 down and 7 x 0.3
# up. With mouse tracking on, VTE sends one wheel event per whole unit of
# accumulated delta and keeps the remainder: the touchpad's upward 2.1 leaves
# -0.1, which is why the smooth wheel phase gets 3 events from the stock
# library (4 x 1 - 0.1), 11 with 3 events per notch (2 + 3 + 3 + 3), 19 with 5
# (4 + 5 + 5 + 5) and 9 with 2.5 (2 + 2 + 3 + 2). With 2.5, wheel notches
# alternate between 2 and 3 events. Without mouse tracking on the alternate
# screen, VTE sends arrow keys, and the patch must leave those counts
# unchanged.
set -u
if [ $# -ne 2 ]; then
    echo "usage: $0 <stock libdir> <patched libdir>" >&2
    exit 2
fi
here=$(dirname "$(readlink -f "$0")")
stock=$(readlink -f "$1")
patched=$(readlink -f "$2")
out=$(mktemp -d "${TMPDIR:-/tmp}/vte-wheel-check.XXXXXX")
failed=0

run() {
    local name=$1 libdir=$2 mode=$3
    shift 3
    if ! "$here/harness.sh" "$out/$name.log" "$libdir" "$mode" "$@" \
            >"$out/$name.out" 2>&1; then
        echo "FAIL $name: the harness exited with an error, see $out/$name.out"
        failed=1
    fi
}

counts() {
    python3 -I "$here/summarize.py" "$out/$1.log" | grep -v '^#'
}

expect_lib() {
    local name=$1 libdir=$2
    if ! prefix="LIB $libdir/libvte-2.91.so" \
            awk 'index($0, ENVIRON["prefix"]) == 1 {found = 1} END {exit !found}' "$out/$name.log"; then
        echo "FAIL $name: expected libvte from $libdir, the log says: $(grep '^LIB' "$out/$name.log")"
        failed=1
    fi
}

expect_counts() {
    local name=$1 expected=$2 got
    got=$(counts "$name")
    if [ "$got" = "$expected" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name"
        diff <(echo "$expected") <(echo "$got") | sed 's/^/     /'
        failed=1
    fi
}

stock_track='wheel-down-4-notches 0 4 0
wheel-up-2-notches 2 0 0
finger-down-20x5 0 10 0
finger-up-7x3 2 0 0
smooth-wheel-down-4x10 0 3 0'

patched_track_3='wheel-down-4-notches 0 12 0
wheel-up-2-notches 6 0 0
finger-down-20x5 0 10 0
finger-up-7x3 2 0 0
smooth-wheel-down-4x10 0 11 0'

patched_track_5='wheel-down-4-notches 0 20 0
wheel-up-2-notches 10 0 0
finger-down-20x5 0 10 0
finger-up-7x3 2 0 0
smooth-wheel-down-4x10 0 19 0'

patched_track_2_5='wheel-down-4-notches 0 10 0
wheel-up-2-notches 5 0 0
finger-down-20x5 0 10 0
finger-up-7x3 2 0 0
smooth-wheel-down-4x10 0 9 0'

run stock-track "$stock" track
run patched-track "$patched" track
run patched-track-5 "$patched" track VTE_WHEEL_EVENTS_PER_NOTCH=5
run patched-track-2.5 "$patched" track VTE_WHEEL_EVENTS_PER_NOTCH=2.5
run patched-track-invalid "$patched" track VTE_WHEEL_EVENTS_PER_NOTCH=abc
run stock-altscreen "$stock" altscreen
run patched-altscreen "$patched" altscreen

for name in stock-track stock-altscreen; do expect_lib $name "$stock"; done
for name in patched-track patched-track-5 patched-track-2.5 patched-track-invalid patched-altscreen; do
    expect_lib $name "$patched"
done

expect_counts stock-track "$stock_track"
expect_counts patched-track "$patched_track_3"
expect_counts patched-track-5 "$patched_track_5"
expect_counts patched-track-2.5 "$patched_track_2_5"
expect_counts patched-track-invalid "$patched_track_3"
if grep -q 'VTE_WHEEL_EVENTS_PER_NOTCH="abc" is not a number from 1 to 20; using 3' \
        "$out/patched-track-invalid.log.client"; then
    echo "ok   patched-track-invalid warning"
else
    echo "FAIL patched-track-invalid: the client log lacks the warning about the invalid value"
    failed=1
fi

alt_stock=$(counts stock-altscreen)
alt_patched=$(counts patched-altscreen)
if [ "$alt_stock" = "$alt_patched" ] && echo "$alt_stock" | awk '$1 ~ /^wheel-/ && $4 > 0 {n++} END {exit !(n == 2)}'; then
    echo "ok   altscreen arrow keys match the stock library"
else
    echo "FAIL altscreen: stock and patched differ, or a wheel phase did not send arrow keys"
    diff <(echo "$alt_stock") <(echo "$alt_patched") | sed 's/^/     /'
    failed=1
fi

echo "logs: $out"
exit $failed
