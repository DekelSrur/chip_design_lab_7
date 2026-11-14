#!/usr/bin/env python3
"""Generate the sine LUT for rom.sv (Lab 7 DDS).

One full period, DEPTH entries, unsigned WIDTH-bit values.
Raised-cosine shape: starts at 0 (LED dark), peaks at DEPTH/2, back to 0.
    value[i] = round( MAX * (1 - cos(2*pi*i/DEPTH)) / 2 )

Usage:  python scripts/gen_sine.py            -> writes src/sine_lut.mem
"""
import math
from pathlib import Path

DEPTH = 512          # = 2**9, matches the 9-bit init_phase
WIDTH = 8            # values 0..255
MAX   = 2**WIDTH - 1

out = Path(__file__).resolve().parent.parent / "src" / "sine_lut.mem"

with open(out, "w") as f:
    for i in range(DEPTH):
        v = round(MAX * (1 - math.cos(2 * math.pi * i / DEPTH)) / 2)
        f.write(f"{v:02X}\n")

print(f"wrote {DEPTH} entries x {WIDTH} bits -> {out}")
