#!/usr/bin/env python3
"""Check a generated module cache without opening its binaries.

Usage: check-module-cache.py CACHE [PREFIX]
The cache is user-provided and must never be committed.
"""
import re, sys
from pathlib import Path
cache=Path(sys.argv[1]) if len(sys.argv)>1 else None
prefix=sys.argv[2] if len(sys.argv)>2 else "/opt/isb/sysroot"
if not cache or not cache.is_dir(): raise SystemExit("cache directory missing")
files=list(cache.glob("*.pcm"))+list(cache.glob("*.swiftmodule"))
if not files: raise SystemExit("cache has no PCM/swiftmodule files")
bad=[]; personal=[]; neutral=0
for p in files:
    data=p.read_bytes()
    if b"/home/" in data: personal.append(str(p))
    if prefix.encode() in data: neutral += 1
    if not data: bad.append(str(p))
print(f"files={len(files)} nonempty={len(files)-len(bad)} neutral_refs={neutral} personal_refs={len(personal)}")
if bad: print("empty:", *bad, sep="\n")
if personal: print("personal paths:", *personal, sep="\n")
if bad or personal: raise SystemExit(1)
