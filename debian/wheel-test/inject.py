"""Injects scroll events through mutter's RemoteDesktop API on the private
session bus.

Before each group of events it writes a PHASE line with the group's name to
the log, and after the group it types the marker key "z" into the terminal.
VTE writes keys and wheel events to the program in the order it receives
them, so the markers split the program's input into one part per group, no
matter how late VTE delivers the events (see summarize.py). At the end it
waits until every marker has reached the log."""
import ast, sys, time
from gi.repository import Gio, GLib

log_path = sys.argv[1]
NAME = "org.gnome.Mutter.RemoteDesktop"
FINISH, SOURCE_WHEEL, SOURCE_FINGER = 1, 2, 4
BTN_LEFT = 0x110
KEYSYM_Z, MARKER = 0x7A, b"z"
MARKER_DEADLINE_S = 30
SETUP_ATTEMPTS = 10

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
rd = Gio.DBusProxy.new_sync(bus, 0, None, NAME, "/org/gnome/Mutter/RemoteDesktop", NAME)
session_path = rd.call_sync("CreateSession", None, 0, -1, None).unpack()[0]
s = Gio.DBusProxy.new_sync(bus, 0, None, NAME, session_path, NAME + ".Session")
s.call_sync("Start", None, 0, -1, None)
markers_sent = 0


def call(method, sig, *args):
    s.call_sync(method, GLib.Variant(sig, args), 0, -1, None)


def begin(name):
    with open(log_path, "a") as f:
        f.write(f"PHASE {name}\n")


def type_marker():
    call("NotifyKeyboardKeysym", "(ub)", KEYSYM_Z, True)
    call("NotifyKeyboardKeysym", "(ub)", KEYSYM_Z, False)


def end():
    global markers_sent
    type_marker()
    markers_sent += 1


def markers_received():
    count = 0
    for line in open(log_path):
        if line.startswith("IN "):
            count += ast.literal_eval(line.split(" ", 2)[2]).count(MARKER)
    return count


def wait_for_markers(count, timeout_s):
    deadline = time.monotonic() + timeout_s
    while markers_received() < count:
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.05)
    return True


def end_setup():
    """Ends the setup phase once a marker has reached the program. The window
    takes keyboard focus a moment after the click, and a key typed before
    that is lost, so the marker is typed again until one arrives."""
    global markers_sent
    for _ in range(SETUP_ATTEMPTS):
        type_marker()
        if wait_for_markers(1, 1.0):
            markers_sent = 1
            return
    print(f"inject.py: none of {SETUP_ATTEMPTS} marker keys reached the program", file=sys.stderr)
    call("Stop", "()")
    sys.exit(1)


# The virtual pointer needs a moment after Start. Motion events give the VTE
# surface pointer focus, and a click gives the window keyboard focus, which
# the marker keys need. The click reaches the program in the setup phase,
# which summarize.py does not report.
time.sleep(0.5)
begin("setup")
for _ in range(5):
    call("NotifyPointerMotionRelative", "(dd)", 20.0, 15.0)
    time.sleep(0.05)
call("NotifyPointerButton", "(ib)", BTN_LEFT, True)
call("NotifyPointerButton", "(ib)", BTN_LEFT, False)
end_setup()

begin("wheel-down-4-notches")
for _ in range(4):
    call("NotifyPointerAxisDiscrete", "(ui)", 0, 1)
    time.sleep(0.15)
end()

begin("wheel-up-2-notches")
for _ in range(2):
    call("NotifyPointerAxisDiscrete", "(ui)", 0, -1)
    time.sleep(0.15)
end()

begin("finger-down-20x5")
for _ in range(20):
    call("NotifyPointerAxis", "(ddu)", 0.0, 5.0, SOURCE_FINGER)
    time.sleep(0.01)
call("NotifyPointerAxis", "(ddu)", 0.0, 0.0, SOURCE_FINGER | FINISH)
end()

begin("finger-up-7x3")
for _ in range(7):
    call("NotifyPointerAxis", "(ddu)", 0.0, -3.0, SOURCE_FINGER)
    time.sleep(0.01)
call("NotifyPointerAxis", "(ddu)", 0.0, 0.0, SOURCE_FINGER | FINISH)
end()

begin("smooth-wheel-down-4x10")
for _ in range(4):
    call("NotifyPointerAxis", "(ddu)", 0.0, 10.0, SOURCE_WHEEL)
    time.sleep(0.15)
end()

# Wait for the program to receive every marker. The deadline only ends a run
# in which the markers never arrive, for example when the window did not get
# keyboard focus.
wait_for_markers(markers_sent, MARKER_DEADLINE_S)
call("Stop", "()")
received = markers_received()
if received != markers_sent:
    print(f"inject.py: sent {markers_sent} marker keys, the program received {received}", file=sys.stderr)
    sys.exit(1)
