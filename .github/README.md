# VTE with a faster mouse wheel and unchanged touchpad scrolling

This is Ubuntu 24.04's `vte2.91` source package (0.76.0-1ubuntu0.1) with one
added patch, [`debian/patches/vte-wheel-events-per-notch.patch`](../debian/patches/vte-wheel-events-per-notch.patch).
VTE is the terminal widget behind GNOME Terminal and several other terminal
emulators. The upstream files are unmodified; the root `README.md` is VTE's own.

## The problem

When a program in the terminal turns on mouse tracking, VTE reports scrolling
to it as wheel button events, one event per whole unit of scroll delta.
Programs that do this include Claude Code in fullscreen mode, tmux with
`mouse on`, and vim with `mouse=a`. GTK reports a mouse wheel notch as a delta
of 1, and a short touchpad movement gives the same delta, so the program
receives identical events from both devices. If it scrolls one line per event,
touchpad scrolling is smooth but a wheel notch moves only one line. If it
scrolls three lines per event, the wheel is fine but the touchpad jumps three
lines at a time.

## What the patch does

VTE can see which device an event came from. With GTK 3, the event's source
device is `GDK_SOURCE_MOUSE` for a wheel and `GDK_SOURCE_TOUCHPAD` for a
touchpad; on Wayland, GTK creates a separate device for each scroll source.
With GTK 4, a wheel event has a scroll direction, while a touchpad event is a
`GDK_SCROLL_SMOOTH` event. Both tests rely on GTK recognising the touchpad.

On X11, GTK recognises a touchpad by a device property that only the libinput
X driver sets, by a touch class, or by the device's name. Under Xwayland,
which runs X11 programs in a Wayland session, all pointer input, touchpads
included, arrives through one device named `xwayland-pointer`, and GTK takes
it for a mouse. A VTE terminal running there, for example one started with
`GDK_BACKEND=x11`, therefore multiplies touchpad scrolling as well: the test
measures 30 events where the stock library sends 10. A touchpad under an X
driver other than libinput, such as synaptics, can be taken for a mouse in the
same way. Set `VTE_WHEEL_EVENTS_PER_NOTCH=1` for such a terminal to turn the
multiplier off. GNOME Terminal in a Wayland session runs as a Wayland client
and tells the devices apart.

While mouse tracking is on, the patch multiplies wheel deltas by
`VTE_WHEEL_EVENTS_PER_NOTCH`, so by default one notch sends three events.
Touchpad deltas still send one event per unit. VTE keeps the fraction of a
unit that earlier scrolling left over; when a wheel notch goes the other way,
the patch drops that fraction first, so the notch still sends three events.
Scrolling without mouse tracking does not change: the scrollback still moves
the same distance, and the arrow keys VTE sends on the alternate screen are
the same.

A program that scrolls one line per event now scrolls three lines per wheel
notch and keeps one-line touchpad resolution. For Claude Code, leave
`CLAUDE_CODE_SCROLL_SPEED` unset; in GNOME Terminal it then scrolls one line
per event. Claude Code also speeds up bursts of wheel events (checked in
version 2.1.322): while events arrive less than 40 ms apart, it adds 0.3 to
its lines-per-event multiplier for each event, up to 6. Because a notch now
sends three events, notches less than 40 ms apart ramp up to 18 lines per
notch, where one event per notch ramps up to 6. If fast flicks overshoot, set
`VTE_WHEEL_EVENTS_PER_NOTCH=2`, or turn the acceleration off with
`"wheelScrollAccelerationEnabled": false` in `~/.claude/settings.json`, which
also turns it off for the touchpad.

For tmux copy mode, which scrolls five lines per event by default, use one
line per event:

```
bind -T copy-mode    WheelUpPane   select-pane \; send-keys -X -N 1 scroll-up
bind -T copy-mode    WheelDownPane select-pane \; send-keys -X -N 1 scroll-down
bind -T copy-mode-vi WheelUpPane   select-pane \; send-keys -X -N 1 scroll-up
bind -T copy-mode-vi WheelDownPane select-pane \; send-keys -X -N 1 scroll-down
```

Programs that already scroll several lines per event scroll correspondingly
more per notch; vim's default of three lines per event becomes nine per notch.

## Configuration

`VTE_WHEEL_EVENTS_PER_NOTCH` sets the number of events per notch, from 1 to
20. A fraction such as 2.5 alternates between two and three events. The
terminal reads the variable at the first wheel notch it sends to a program
with mouse tracking on, and keeps that value until it exits. For any other
value it prints a warning at that point and uses 3.

GNOME Terminal's server is started by the systemd user manager and takes its
environment from there. `systemctl --user set-environment
VTE_WHEEL_EVENTS_PER_NOTCH=2` applies to servers started afterwards, and a file
in `~/.config/environment.d/` applies from the next login.

## Building and installing

Install the build dependencies listed under `Build-Depends` in
`debian/control`. The documentation packages under `Build-Depends-Indep` are
not needed, because `-B` builds only the architecture-specific packages.
`dpkg-buildpackage` writes the packages to the parent directory, so clone into
a directory of its own:

```sh
mkdir vte-build && cd vte-build
git clone https://github.com/ojura/vte2.91-wheel.git
cd vte2.91-wheel
dpkg-buildpackage -us -uc -B -j"$(nproc)"
sudo dpkg -i ../libvte-2.91-0_*.deb ../libvte-2.91-common_*.deb ../gir1.2-vte-2.91_*.deb
```

The `dpkg -i` line installs the GTK 3 library, which GNOME Terminal uses, its
common files, and the introspection data that Python programs embedding VTE
use. Install every package from the build that you already have installed
(`dpkg -l '*vte*'`), for example also `../libvte-2.91-gtk4-0_*.deb` if GTK 4
terminals such as GNOME Console are installed. Both libraries require
`libvte-2.91-common` of exactly the same version.

A running terminal keeps the library it loaded. GNOME Terminal's server loads
the new library the next time it starts: after all of its windows close, or at
the next login. On Ubuntu, `gnome-terminal --disable-factory` opens a window
on a new server right away.

The local versions, `0.76.0-1ubuntu0.1+localN`, sort above Ubuntu's
`0.76.0-1ubuntu0.1`, so apt keeps them until Ubuntu publishes a newer vte2.91.
That update replaces the patched packages; rebase the patch onto the new
source and rebuild. To go back to Ubuntu's packages, name every package you
installed from the build, such as `libvte-2.91-gtk4-0=0.76.0-1ubuntu0.1`, in
addition to these three:

```sh
sudo apt install --allow-downgrades libvte-2.91-0=0.76.0-1ubuntu0.1 \
    libvte-2.91-common=0.76.0-1ubuntu0.1 gir1.2-vte-2.91=0.76.0-1ubuntu0.1
```

A patched package left out of the list requires the patched
`libvte-2.91-common` exactly, so apt offers to remove it, together with every
package that depends on it, instead of downgrading it.

## Testing

```sh
debian/wheel-test/check.sh <stock root> <patched root>
```

Each root is a directory into which the `libvte-2.91-0`, `gir1.2-vte-2.91`,
`libvte-2.91-gtk4-0` and `gir1.2-vte-3.91` packages of one build are unpacked
with `dpkg-deb -x`. After the build above:

```sh
cd ..
mkdir stock-debs
(cd stock-debs && apt download libvte-2.91-0=0.76.0-1ubuntu0.1 \
    gir1.2-vte-2.91=0.76.0-1ubuntu0.1 libvte-2.91-gtk4-0=0.76.0-1ubuntu0.1 \
    gir1.2-vte-3.91=0.76.0-1ubuntu0.1)
for d in stock-debs/*.deb; do dpkg-deb -x "$d" stock; done
for d in libvte-2.91-0_*+local*.deb gir1.2-vte-2.91_*+local*.deb \
         libvte-2.91-gtk4-0_*+local*.deb gir1.2-vte-3.91_*+local*.deb; do
    dpkg-deb -x "$d" patched
done
vte2.91-wheel/debian/wheel-test/check.sh stock patched
```

The script opens GTK 3 and GTK 4 VTE windows with each library in a headless
mutter inside a private D-Bus session, so it does not touch the desktop. It
injects wheel and touchpad scroll events through mutter's RemoteDesktop API
and compares what a program in the terminal receives with the expected
counts. After each group of events it types a marker key into the terminal,
which splits the program's input into groups independently of timing. A
passing run prints only `ok` lines and the directory of its logs, and exits
with status 0. It needs the `mutter`, `python3-gi`, `gir1.2-gtk-3.0`,
`gir1.2-gtk-4.0` and `dpkg-dev` packages.

The test also runs both GTK versions as X11 clients of the Xwayland server
that headless mutter starts on a private display. There it checks the counts
described above, including the multiplied touchpad scrolling, so that a change
in that behaviour shows up. Native Xorg is untested.

## Licence

VTE's library sources, including the three files the patch changes
(`src/vte.cc`, `src/widget.cc`, `src/widget.hh`), are licensed under the GNU
Lesser General Public License, version 3 or later. The patch is under the same
licence. See the `COPYING.*` files for the licences of the rest of the tree.
