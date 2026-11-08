"""Injects scroll events through mutter's RemoteDesktop API on the private
session bus, writing a PHASE line to the log before each group."""
import sys, time
from gi.repository import Gio, GLib

log_path = sys.argv[1]
NAME = "org.gnome.Mutter.RemoteDesktop"
FINISH, SOURCE_WHEEL, SOURCE_FINGER = 1, 2, 4

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
rd = Gio.DBusProxy.new_sync(bus, 0, None, NAME, "/org/gnome/Mutter/RemoteDesktop", NAME)
session_path = rd.call_sync("CreateSession", None, 0, -1, None).unpack()[0]
s = Gio.DBusProxy.new_sync(bus, 0, None, NAME, session_path, NAME + ".Session")
s.call_sync("Start", None, 0, -1, None)

def call(method, sig, *args):
    s.call_sync(method, GLib.Variant(sig, args), 0, -1, None)

def phase(name):
    time.sleep(0.6)
    with open(log_path, "a") as f:
        f.write(f"PHASE {name}\n")

# The virtual pointer needs a moment after Start, then motion events
# to give the VTE surface pointer focus.
time.sleep(0.5)
for _ in range(5):
    call("NotifyPointerMotionRelative", "(dd)", 20.0, 15.0)
    time.sleep(0.05)

phase("wheel-down-4-notches")
for _ in range(4):
    call("NotifyPointerAxisDiscrete", "(ui)", 0, 1)
    time.sleep(0.15)

phase("wheel-up-2-notches")
for _ in range(2):
    call("NotifyPointerAxisDiscrete", "(ui)", 0, -1)
    time.sleep(0.15)

phase("finger-down-20x5")
for _ in range(20):
    call("NotifyPointerAxis", "(ddu)", 0.0, 5.0, SOURCE_FINGER)
    time.sleep(0.01)
call("NotifyPointerAxis", "(ddu)", 0.0, 0.0, SOURCE_FINGER | FINISH)

phase("finger-up-7x3")
for _ in range(7):
    call("NotifyPointerAxis", "(ddu)", 0.0, -3.0, SOURCE_FINGER)
    time.sleep(0.01)
call("NotifyPointerAxis", "(ddu)", 0.0, 0.0, SOURCE_FINGER | FINISH)

phase("smooth-wheel-down-4x10")
for _ in range(4):
    call("NotifyPointerAxis", "(ddu)", 0.0, 10.0, SOURCE_WHEEL)
    time.sleep(0.15)

phase("end")
time.sleep(0.6)
call("Stop", "()")
