# vte2.91 with faster mouse wheel scrolling

`.github/README.md` describes the patch and how to build, test, install and
configure it. This file adds the conventions for working on the repository.

The upstream files and the root `README.md` stay pristine. Local changes are
quilt patches in `debian/patches`, one commit per patch, followed by a
"Changelog for <version>" commit with the next `+localN` version.

Build in a detached worktree outside `~/src` (`git worktree add --detach
/tmp/vte-build/vte2.91-wheel HEAD`), because `dpkg-buildpackage` writes the
packages to the parent directory. Run `debian/wheel-test/check.sh` on every
new build before installing it.

After an Ubuntu update to vte2.91, import the new source package with
`dpkg-source --skip-patches -x` in a commit of its own, then rebase the patch
onto it.
