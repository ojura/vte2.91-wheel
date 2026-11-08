"""Counts the wheel events (SGR button 64 up, 65 down) and arrow keys that
each PHASE of a capture log received. Prints one line per phase:
<phase> <up> <down> <arrow keys>."""
import ast, re, sys
for path in sys.argv[1:]:
    phase, counts, order = None, {}, []
    for line in open(path):
        if line.startswith(("LIB", "READY")):
            print("# " + line.strip())
        elif line.startswith("PHASE"):
            phase = line.split()[1]; order.append(phase); counts[phase] = [0, 0, 0]
        elif line.startswith("IN") and phase:
            data = ast.literal_eval(line.split(" ", 2)[2])
            counts[phase][0] += len(re.findall(rb"\x1b\[<64;", data))
            counts[phase][1] += len(re.findall(rb"\x1b\[<65;", data))
            counts[phase][2] += data.count(b"\x1bOA") + data.count(b"\x1b[A") + data.count(b"\x1bOB") + data.count(b"\x1b[B")
    for p in order:
        if p != "end":
            up, down, arrows = counts[p]
            print(f"{p} {up} {down} {arrows}")
