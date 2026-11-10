#!/bin/bash
# Usage: check.sh <stock root> <patched root>
#
# Tests vte-wheel-events-per-notch.patch without touching the desktop: each
# run starts a headless mutter in a private D-Bus session, opens a GTK 3 or
# GTK 4 VTE window in it, injects wheel and touchpad scroll events through
# mutter's RemoteDesktop API and counts what the program inside the terminal
# receives (see harness.sh and inject.py). Each root is a directory into which
# the libvte-2.91-0, gir1.2-vte-2.91, libvte-2.91-gtk4-0 and gir1.2-vte-3.91
# packages of one build are unpacked with dpkg-deb -x.
#
# Expected counts. A wheel notch reaches VTE as a delta of 1 with GTK 3 and
# GTK 4. GTK 3 divides Wayland touchpad values by 10, and GTK 4 passes them on
# in pixels, which stock VTE turns into one event per pixel. Mutter rounds the
# injected values to 1/256 of its axis unit, so each upward touchpad step is
# 3.0078125 pixels instead of 3, and the seven steps leave VTE's accumulator
# at -0.105 with GTK 3 and -0.055 with GTK 4. With mouse tracking on, VTE
# sends one wheel event per whole unit of accumulated delta and keeps the
# remainder, so the smooth wheel phase that follows gets 3 events from the
# stock library (0 + 1 + 1 + 1), 11 with 3 events per notch (2 + 3 + 3 + 3),
# 19 with 5 (4 + 5 + 5 + 5) and 9 with 2.5 (2 + 2 + 3 + 2). With 2.5, wheel
# notches alternate between 2 and 3 events. Without mouse tracking on the
# alternate screen, VTE sends arrow keys, and the patch must leave those
# counts unchanged.
set -u
if [ $# -ne 2 ]; then
    echo "usage: $0 <stock root> <patched root>" >&2
    exit 2
fi
here=$(dirname "$(readlink -f "$0")")
multiarch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
stock=$(readlink -f "$1")/usr/lib/$multiarch
patched=$(readlink -f "$2")/usr/lib/$multiarch
missing=0
for libdir in "$stock" "$patched"; do
    for f in libvte-2.91.so.0 libvte-2.91-gtk4.so.0 girepository-1.0/Vte-2.91.typelib girepository-1.0/Vte-3.91.typelib; do
        if [ ! -e "$libdir/$f" ]; then
            echo "missing $libdir/$f" >&2
            missing=1
        fi
    done
done
if [ $missing = 1 ]; then
    echo "unpack libvte-2.91-0, gir1.2-vte-2.91, libvte-2.91-gtk4-0 and gir1.2-vte-3.91 into each root" >&2
    exit 2
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/vte-wheel-check.XXXXXX")
failed=0

# run <name> <libdir> <track|altscreen> <3|4> [VAR=value...]
run() {
    local name=$1 libdir=$2 mode=$3 gtk=$4
    shift 4
    if ! "$here/harness.sh" "$out/$name.log" "$libdir" "$mode" "$gtk" \
            GI_TYPELIB_PATH="$libdir/girepository-1.0" "$@" >"$out/$name.out" 2>&1; then
        echo "FAIL $name: the harness exited with an error, see $out/$name.out"
        failed=1
    fi
}

counts() {
    python3 -I "$here/summarize.py" "$out/$1.log" | grep -v '^#'
}

# expect_lib <name> <libdir> <3|4>
expect_lib() {
    local name=$1 libdir=$2 file
    if [ "$3" = 4 ]; then file=libvte-2.91-gtk4.so; else file=libvte-2.91.so; fi
    if ! prefix="LIB $libdir/$file" \
            awk 'index($0, ENVIRON["prefix"]) == 1 {found = 1} END {exit !found}' "$out/$name.log"; then
        echo "FAIL $name: expected $file from $libdir, the log says: $(grep '^LIB' "$out/$name.log")"
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

expect_same_altscreen() {
    local gtk=$1 alt_stock alt_patched
    alt_stock=$(counts stock-gtk$gtk-altscreen)
    alt_patched=$(counts patched-gtk$gtk-altscreen)
    if [ "$alt_stock" = "$alt_patched" ] &&
            echo "$alt_stock" | awk '$1 ~ /^wheel-/ && $4 > 0 {n++} END {exit !(n == 2)}'; then
        echo "ok   gtk$gtk altscreen arrow keys match the stock library"
    else
        echo "FAIL gtk$gtk altscreen: stock and patched differ, or a wheel phase did not send arrow keys"
        diff <(echo "$alt_stock") <(echo "$alt_patched") | sed 's/^/     /'
        failed=1
    fi
}

gtk3_stock='wheel-down-4-notches 0 4 0
wheel-up-2-notches 2 0 0
finger-down-20x5 0 10 0
finger-up-7x3 2 0 0
smooth-wheel-down-4x10 0 3 0'

gtk3_patched_3='wheel-down-4-notches 0 12 0
wheel-up-2-notches 6 0 0
finger-down-20x5 0 10 0
finger-up-7x3 2 0 0
smooth-wheel-down-4x10 0 11 0'

gtk3_patched_5='wheel-down-4-notches 0 20 0
wheel-up-2-notches 10 0 0
finger-down-20x5 0 10 0
finger-up-7x3 2 0 0
smooth-wheel-down-4x10 0 19 0'

gtk3_patched_2_5='wheel-down-4-notches 0 10 0
wheel-up-2-notches 5 0 0
finger-down-20x5 0 10 0
finger-up-7x3 2 0 0
smooth-wheel-down-4x10 0 9 0'

gtk4_stock='wheel-down-4-notches 0 4 0
wheel-up-2-notches 2 0 0
finger-down-20x5 0 100 0
finger-up-7x3 21 0 0
smooth-wheel-down-4x10 0 3 0'

gtk4_patched_3='wheel-down-4-notches 0 12 0
wheel-up-2-notches 6 0 0
finger-down-20x5 0 100 0
finger-up-7x3 21 0 0
smooth-wheel-down-4x10 0 11 0'

run stock-gtk3-track "$stock" track 3
run patched-gtk3-track "$patched" track 3
run patched-gtk3-track-5 "$patched" track 3 VTE_WHEEL_EVENTS_PER_NOTCH=5
run patched-gtk3-track-2.5 "$patched" track 3 VTE_WHEEL_EVENTS_PER_NOTCH=2.5
run patched-gtk3-track-invalid "$patched" track 3 VTE_WHEEL_EVENTS_PER_NOTCH=abc
run stock-gtk3-altscreen "$stock" altscreen 3
run patched-gtk3-altscreen "$patched" altscreen 3
run stock-gtk4-track "$stock" track 4
run patched-gtk4-track "$patched" track 4
run stock-gtk4-altscreen "$stock" altscreen 4
run patched-gtk4-altscreen "$patched" altscreen 4

for gtk in 3 4; do
    for name in stock-gtk$gtk-track stock-gtk$gtk-altscreen; do expect_lib $name "$stock" $gtk; done
    for name in patched-gtk$gtk-track patched-gtk$gtk-altscreen; do expect_lib $name "$patched" $gtk; done
done
for name in patched-gtk3-track-5 patched-gtk3-track-2.5 patched-gtk3-track-invalid; do
    expect_lib $name "$patched" 3
done

expect_counts stock-gtk3-track "$gtk3_stock"
expect_counts patched-gtk3-track "$gtk3_patched_3"
expect_counts patched-gtk3-track-5 "$gtk3_patched_5"
expect_counts patched-gtk3-track-2.5 "$gtk3_patched_2_5"
expect_counts patched-gtk3-track-invalid "$gtk3_patched_3"
if grep -q 'VTE_WHEEL_EVENTS_PER_NOTCH="abc" is not a number from 1 to 20; using 3' \
        "$out/patched-gtk3-track-invalid.log.client"; then
    echo "ok   patched-gtk3-track-invalid warning"
else
    echo "FAIL patched-gtk3-track-invalid: the client log lacks the warning about the invalid value"
    failed=1
fi
expect_same_altscreen 3
expect_counts stock-gtk4-track "$gtk4_stock"
expect_counts patched-gtk4-track "$gtk4_patched_3"
expect_same_altscreen 4

echo "logs: $out"
exit $failed
