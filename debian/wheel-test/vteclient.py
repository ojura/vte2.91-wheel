"""A fullscreen GTK 3 window holding one VteTerminal that runs capture.py.
Records which libvte file the process mapped, so each run shows whether it
tested the stock or the patched library."""
import sys
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Vte", "2.91")
from gi.repository import GLib, Gtk, Vte

log_path, capture, mode = sys.argv[1], sys.argv[2], sys.argv[3]
win = Gtk.Window()
term = Vte.Terminal()
term.spawn_async(Vte.PtyFlags.DEFAULT, None,
                 ["/usr/bin/python3", "-I", capture, log_path, mode],
                 None, GLib.SpawnFlags.DEFAULT, None, None, -1, None, None, None)
win.add(term)
win.connect("destroy", Gtk.main_quit)
win.show_all()
win.fullscreen()
libs = sorted({line.split()[-1] for line in open("/proc/self/maps") if "libvte-2.91.so" in line})
with open(log_path, "a") as f:
    f.write("LIB " + " ".join(libs) + "\n")
Gtk.main()
