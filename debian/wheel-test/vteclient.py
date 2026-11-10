"""A fullscreen window holding one VteTerminal that runs capture.py.

Usage: vteclient.py <log> <capture.py> <capture mode> <3|4>
The last argument picks GTK 3 with Vte 2.91 (libvte-2.91.so.0) or GTK 4 with
Vte 3.91 (libvte-2.91-gtk4.so.0). The client records which libvte file the
process mapped, so each run shows which library it tested."""
import sys
import gi

log_path, capture, mode, gtk = sys.argv[1:5]
if gtk == "4":
    gi.require_version("Gtk", "4.0")
    gi.require_version("Vte", "3.91")
else:
    gi.require_version("Gtk", "3.0")
    gi.require_version("Vte", "2.91")
from gi.repository import GLib, Gtk, Vte

loop = GLib.MainLoop()
term = Vte.Terminal()
term.spawn_async(Vte.PtyFlags.DEFAULT, None,
                 ["/usr/bin/python3", "-I", capture, log_path, mode],
                 None, GLib.SpawnFlags.DEFAULT, None, None, -1, None, None, None)
win = Gtk.Window()
if gtk == "4":
    win.set_child(term)
    win.connect("close-request", lambda _win: loop.quit())
    win.fullscreen()
    win.present()
else:
    win.add(term)
    win.connect("destroy", lambda _win: loop.quit())
    win.show_all()
    win.fullscreen()

libs = sorted({line.split()[-1] for line in open("/proc/self/maps") if "/libvte-2.91" in line})
with open(log_path, "a") as f:
    f.write("LIB " + " ".join(libs) + "\n")
loop.run()
