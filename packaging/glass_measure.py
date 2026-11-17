#!/usr/bin/env python3
"""Tells from the window glass check's pictures whether the desktop showed
through the window (docs/specs/window-glass.md, runGlassCheck in
lib/app/smoke_check.dart).

    glass_measure.py <folder>

The folder holds pictures of the screen under the window, taken by
windows|linux|macos/packaging/glass-check.*, with a magenta window behind
Lumtub: glass-off, glass-frame, glass-whole, glass-clear (no blur),
glass-dark-off and glass-dark-frame (.png), and glass-state.json, what the runner answered.
Each picture is measured for magenta, (R + B) / 2 - G, in two places: the
bottom of the side rail, part of the frame, and the middle of the pages.

Exits 0 when, in each skin, the frame took on the magenta behind it while
the pages stayed as they were without glass, and the whole window took it
on too; 1 otherwise. Only Python's standard library is used.
"""

import json
import struct
import sys
import zlib
from pathlib import Path


def read_png(path):
    """Width, height and rows of (r, g, b) tuples of an 8-bit PNG."""
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    pos = 8
    idat = b""
    width = height = depth = kind = interlace = None
    while pos < len(data):
        length, = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, depth, kind, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
    if depth != 8 or kind not in (2, 6) or interlace:
        raise ValueError(f"{path}: 8-bit RGB or RGBA without interlacing only (depth {depth}, type {kind})")
    channels = 3 if kind == 2 else 4
    stride = width * channels
    raw = zlib.decompress(idat)
    rows = []
    previous = bytearray(stride)
    i = 0
    for _ in range(height):
        kind_of_filter = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = previous[x]
            c = previous[x - channels] if x >= channels else 0
            if kind_of_filter == 1:
                line[x] = (line[x] + a) & 0xFF
            elif kind_of_filter == 2:
                line[x] = (line[x] + b) & 0xFF
            elif kind_of_filter == 3:
                line[x] = (line[x] + (a + b) // 2) & 0xFF
            elif kind_of_filter == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        rows.append([tuple(line[x:x + 3]) for x in range(0, stride, channels)])
        previous = line
    return width, height, rows


def magenta(rows, width, height, box):
    """Mean (R + B) / 2 - G over box, as fractions of the picture."""
    left, top, right, bottom = box
    total = count = 0
    for y in range(int(top * height), int(bottom * height)):
        row = rows[y]
        for x in range(int(left * width), int(right * width), 2):
            r, g, b = row[x]
            total += (r + b) / 2 - g
            count += 1
    return total / max(count, 1)


# The bottom of the side rail, under its items: bare frame. The middle of
# the pages: what the frame surrounds.
FRAME = (0.004, 0.72, 0.045, 0.94)
PAGES = (0.55, 0.5, 0.9, 0.8)


def main(folder):
    folder = Path(folder)
    state = json.loads((folder / "glass-state.json").read_text()) if (folder / "glass-state.json").exists() else {}
    measured = {}
    for name in ["glass-off", "glass-frame", "glass-whole", "glass-clear", "glass-dark-off", "glass-dark-frame"]:
        path = folder / f"{name}.png"
        if not path.exists():
            print(f"{name}: no picture")
            continue
        width, height, rows = read_png(path)
        measured[name] = (magenta(rows, width, height, FRAME), magenta(rows, width, height, PAGES))
        print(f"{name}: {width}x{height}, magenta on the frame {measured[name][0]:.1f}, on the pages {measured[name][1]:.1f}, runner said {state.get(name)}")
        # A coarse map of the picture, for reading in the log.
        for row in range(8):
            print("  " + " ".join(f"{magenta(rows, width, height, (col / 12, row / 8, (col + 1) / 12, (row + 1) / 8)):4.0f}" for col in range(12)))
    ok = True

    def check(what, passed):
        nonlocal ok
        print(f"{'PASS' if passed else 'FAIL'}: {what}")
        ok = ok and passed

    for off, frame, whole in [("glass-off", "glass-frame", "glass-whole"), ("glass-off", "glass-clear", None), ("glass-dark-off", "glass-dark-frame", None)]:
        if off not in measured or frame not in measured:
            check(f"pictures {off} and {frame} taken", False)
            continue
        (frame_off, pages_off), (frame_on, pages_on) = measured[off], measured[frame]
        check(f"{frame}: the desktop shows through the frame ({frame_on - frame_off:+.1f})", frame_on - frame_off >= 12)
        check(f"{frame}: the pages stay solid ({pages_on - pages_off:+.1f})", abs(pages_on - pages_off) <= 6)
        if whole and whole in measured:
            _, pages_whole = measured[whole]
            check(f"{whole}: the desktop shows through the pages too ({pages_whole - pages_off:+.1f})", pages_whole - pages_off >= 6)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
