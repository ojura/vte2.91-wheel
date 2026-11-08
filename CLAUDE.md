# vte2.91 with faster mouse wheel scrolling

This is Ubuntu's vte2.91 source package with one local patch,
`debian/patches/vte-wheel-events-per-notch.patch`. With mouse tracking on, VTE
sends the application one wheel button event per whole unit of scroll delta. A
mouse wheel notch and a short touchpad movement both give a delta of 1, so
applications such as Claude Code and tmux cannot tell them apart. The patch
multiplies wheel deltas by `VTE_WHEEL_EVENTS_PER_NOTCH` (default 3) while mouse
tracking is on, and leaves touchpad deltas and scrolling without mouse
tracking unchanged.

The upstream files stay pristine; local changes are quilt patches in
`debian/patches`, one commit per patch, then a "Changelog for <version>"
commit with a `+localN` version.

## Build, test and install

Build in a detached worktree outside `~/src`, because `dpkg-buildpackage`
writes the packages to the parent directory:

```sh
git worktree add --detach /tmp/vte-build/vte2.91-wheel HEAD
cd /tmp/vte-build/vte2.91-wheel && dpkg-buildpackage -us -uc -B -j32
```

`-B` builds only the architecture-specific packages; the documentation
packages need build dependencies that are not installed.

Test with `debian/wheel-test/check.sh <stock libdir> <patched libdir>`, where
each libdir holds `libvte-2.91.so.0`, for example `usr/lib/x86_64-linux-gnu`
inside the stock and the new libvte-2.91-0 package unpacked with
`dpkg-deb -x`. It runs both libraries in a headless mutter and must print
only `ok` lines.

Install `libvte-2.91-0`, `libvte-2.91-common` and `gir1.2-vte-2.91` with
`dpkg -i`. A running gnome-terminal-server keeps the library it loaded; the
new one is used by servers started afterwards, for example by
`gnome-terminal --disable-factory` or after all GNOME Terminal windows close.

## After an Ubuntu update

An Ubuntu vte2.91 update replaces the installed packages, and the wheel goes
back to one line per notch. Import the new source package with
`dpkg-source --skip-patches -x`, rebase the patch onto it, add a changelog
entry with the next `+localN` version, then build, test and install as above.
