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
With GTK 4, a wheel event's scroll unit is `GDK_SCROLL_UNIT_WHEEL`.

While mouse tracking is on, the patch multiplies wheel deltas by
`VTE_WHEEL_EVENTS_PER_NOTCH`, so by default one notch sends three events.
Touchpad deltas still send one event per unit. Scrolling without mouse
tracking does not change: the scrollback still moves the same distance, and
the arrow keys VTE sends on the alternate screen are the same.

A program that scrolls one line per event now scrolls three lines per wheel
notch and keeps one-line touchpad resolution. For Claude Code, leave
`CLAUDE_CODE_SCROLL_SPEED` unset; in GNOME Terminal it then scrolls one line
per event. Claude Code still accelerates fast wheel flicks on its own. For tmux copy mode, which
scrolls five lines per event by default, use one line per event:

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
terminal reads the variable once, when it starts. For any other value it
prints a warning and uses 3.

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

Install the packages you already have installed (`dpkg -l '*vte*'`).
`libvte-2.91-0` requires `libvte-2.91-common` of exactly the same version.

A running terminal keeps the library it loaded. GNOME Terminal's server loads
the new library the next time it starts: after all of its windows close, or at
the next login. On Ubuntu, `gnome-terminal --disable-factory` opens a window
on a new server right away.

The local version `0.76.0-1ubuntu0.1+local1` sorts above Ubuntu's
`0.76.0-1ubuntu0.1`, so apt keeps it until Ubuntu publishes a newer vte2.91.
That update replaces the patched packages; rebase the patch onto the new
source and rebuild. To go back to Ubuntu's packages:

```sh
sudo apt install --allow-downgrades libvte-2.91-0=0.76.0-1ubuntu0.1 \
    libvte-2.91-common=0.76.0-1ubuntu0.1 gir1.2-vte-2.91=0.76.0-1ubuntu0.1
```

## Testing

```sh
debian/wheel-test/check.sh <stock libdir> <patched libdir>
```

Each libdir is a directory holding `libvte-2.91.so.0`, for example
`usr/lib/x86_64-linux-gnu` inside the stock and the patched `libvte-2.91-0`
package unpacked with `dpkg-deb -x`. The script runs each library in a
headless mutter inside a private D-Bus session, so it does not touch the
desktop. It injects wheel and touchpad scroll events through mutter's
RemoteDesktop API and compares what a program in the terminal receives with
the expected counts. A passing run prints only `ok` lines. It needs the
`mutter`, `python3-gi`, `gir1.2-gtk-3.0` and `gir1.2-vte-2.91` packages.

## Licence

VTE's library sources, including the three files the patch changes
(`src/vte.cc`, `src/widget.cc`, `src/widget.hh`), are licensed under the GNU
Lesser General Public License, version 3 or later. The patch is under the same
licence. See the `COPYING.*` files for the licences of the rest of the tree.
