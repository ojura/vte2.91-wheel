"""Counts what the program in the terminal received in each phase of a
capture log.

inject.py names each phase in a PHASE line and types the marker key "z" at
the end of it, so the input before the first marker belongs to the first
phase, the input between the first and second markers to the second, and so
on. Prints one line per phase except the setup phase:
<phase> <wheel up> <wheel down> <arrow keys>
where wheel events are SGR mouse button 64 (up) and 65 (down). Prints an
ERROR line and exits with status 1 when the markers do not match the phases."""
import ast, re, sys

MARKER = b"z"
ARROWS = (b"\x1bOA", b"\x1b[A", b"\x1bOB", b"\x1b[B")

names, data = [], b""
for line in open(sys.argv[1]):
    if line.startswith(("LIB ", "READY ")):
        print("# " + line.strip())
    elif line.startswith("PHASE "):
        names.append(line.split()[1])
    elif line.startswith("IN "):
        data += ast.literal_eval(line.split(" ", 2)[2])

parts = data.split(MARKER)
if len(parts) != len(names) + 1 or parts[-1]:
    print(f"ERROR {len(names)} phases, {len(parts) - 1} markers, "
          f"{len(parts[-1])} bytes after the last marker")
    sys.exit(1)

for name, part in zip(names, parts):
    if name == "setup":
        continue
    up = len(re.findall(rb"\x1b\[<64;", part))
    down = len(re.findall(rb"\x1b\[<65;", part))
    arrows = sum(part.count(a) for a in ARROWS)
    print(f"{name} {up} {down} {arrows}")
