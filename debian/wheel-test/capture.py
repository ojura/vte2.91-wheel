"""Runs inside the VTE under test and appends every chunk read from the
terminal to the log, with a monotonic timestamp.

Modes: "track" turns on SGR mouse tracking (modes 1000 and 1006), so wheel
events arrive as escape sequences. "altscreen" switches to the alternate
screen without mouse tracking, so VTE turns the wheel into arrow keys."""
import os, sys, termios, time, tty

log = open(sys.argv[1], "a", buffering=1)
mode = sys.argv[2] if len(sys.argv) > 2 else "track"
old = termios.tcgetattr(0)
tty.setraw(0)
if mode == "track":
    os.write(1, b"\x1b[?1000h\x1b[?1006h")
elif mode == "altscreen":
    os.write(1, b"\x1b[?1049h")
os.write(1, b"capture ready\r\n")
log.write(f"READY {mode}\n")
try:
    while True:
        data = os.read(0, 4096)
        if not data:
            break
        log.write(f"IN {time.monotonic():.6f} {data!r}\n")
finally:
    termios.tcsetattr(0, termios.TCSADRAIN, old)
