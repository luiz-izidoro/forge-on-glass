#!/usr/bin/env python3
"""Validate that a thin Mach-O has exactly the requested ARM slice."""
import struct
import subprocess
import sys

if len(sys.argv) != 3:
    print("usage: check-slice.py <mach-o> <arm64e>")
    raise SystemExit(2)
binpath, wanted = sys.argv[1:]
if wanted != "arm64e":
    print("architecture discontinued: only arm64e.v1/PAC is supported")
    raise SystemExit(2)

raw = open(binpath, "rb").read(32)
if len(raw) < 12:
    raise SystemExit("short Mach-O")
magic = struct.unpack_from("<I", raw, 0)[0]
if magic != 0xFEEDFACF:
    raise SystemExit("not a thin little-endian 64-bit Mach-O")
cpu, subtype = struct.unpack_from("<ii", raw, 4)
if cpu != 0x0100000C:
    raise SystemExit("not an ARM64 Mach-O")
base = subtype & 0x00FFFFFF
actual = {0: "arm64", 1: "arm64_32", 2: "arm64e"}.get(base, "unknown")
if wanted == "arm64e" and (subtype & 0xFF000000) not in (0x80000000, 0x81000000):
    print("ERROR: invalid arm64e ABI; got 0x%08x" % (subtype & 0xFFFFFFFF))
    raise SystemExit(1)
out = subprocess.run(["file", binpath], capture_output=True, text=True).stdout.strip()
print(out)
if actual != wanted:
    print("ERROR: requested slice is not present:", wanted,
          "(detected:", actual, ")")
    raise SystemExit(1)
print("slice OK:", wanted, "subtype=0x%08x" % (subtype & 0xFFFFFFFF))
