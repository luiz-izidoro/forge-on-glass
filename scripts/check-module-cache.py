#!/usr/bin/env python3
"""Validate a generated Swift/Clang module cache."""
import sys
from pathlib import Path

cache = Path(sys.argv[1]) if len(sys.argv) > 1 else None
prefix = sys.argv[2] if len(sys.argv) > 2 else "/opt/isb/sysroot"
if not cache or not cache.is_dir():
    raise SystemExit("cache directory missing")
files = list(cache.glob("*.pcm")) + list(cache.glob("*.swiftmodule"))
if not files:
    raise SystemExit("cache has no PCM/swiftmodule files")
required = {"swift_Swift.swiftmodule", "swift_Foundation.swiftmodule",
            "clang_Foundation.pcm", "clang_SwiftShims.pcm"}
missing = sorted(n for n in required if not (cache / n).is_file())
if missing:
    raise SystemExit("cache missing required modules: " + ", ".join(missing))
bad = []
personal = []
invalid = []
neutral = 0
for path in files:
    data = path.read_bytes()
    if b"/home/" in data:
        personal.append(str(path))
    if prefix.encode() in data:
        neutral += 1
    if not data:
        bad.append(str(path))
        continue
    if path.suffix == ".pcm" and not data.startswith(b"\xcf\xfa\xed\xfe"):
        invalid.append(str(path))
    if path.suffix == ".swiftmodule" and len(data) < 16:
        invalid.append(str(path))
print(f"files={len(files)} nonempty={len(files)-len(bad)} neutral_refs={neutral} personal_refs={len(personal)} invalid={len(invalid)}")
if bad:
    print("empty:", *bad, sep="\n")
if personal:
    print("personal paths:", *personal, sep="\n")
if invalid:
    print("invalid module format:", *invalid, sep="\n")
if bad or personal or invalid:
    raise SystemExit(1)
