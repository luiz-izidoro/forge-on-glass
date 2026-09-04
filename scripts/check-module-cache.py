#!/usr/bin/env python3
"""Validate the canonical arm64e Swift/Clang module cache.

The cache is opaque compiler output, so this guard checks stable file-format
magic, required modules, absence of personal paths and arm64e/iOS 26.5
identity markers where the format exposes them.
"""
import sys
from pathlib import Path

SWIFT_MAGIC = b"\xe2\x9c\xa8\x0e"
PCM_MAGIC = b"\xcf\xfa\xed\xfe"
REQUIRED = {
    "swift_Swift.swiftmodule", "swift_Foundation.swiftmodule",
    "clang_Foundation.pcm", "clang_SwiftShims.pcm",
}

cache = Path(sys.argv[1]) if len(sys.argv) > 1 else None
prefix = sys.argv[2] if len(sys.argv) > 2 else "/opt/isb/sysroot"
if not cache or not cache.is_dir():
    raise SystemExit("cache directory missing")
files = sorted(cache.glob("*.pcm")) + sorted(cache.glob("*.swiftmodule"))
if not files:
    raise SystemExit("cache has no PCM/swiftmodule files")
missing = sorted(n for n in REQUIRED if not (cache / n).is_file())
bad = []
personal = []
neutral = 0
identity = 0
for path in files:
    data = path.read_bytes()
    if b"/home/" in data:
        personal.append(str(path))
    if prefix.encode() in data:
        neutral += 1
    if path.suffix == ".pcm":
        valid = data.startswith(PCM_MAGIC)
    else:
        valid = data.startswith(SWIFT_MAGIC) and len(data) >= 16
    if not valid:
        bad.append(str(path))
    if b"arm64e-apple-ios26.5" in data:
        identity += 1
print(f"files={len(files)} nonempty={sum(bool(p.stat().st_size) for p in files)} "
      f"neutral_refs={neutral} personal_refs={len(personal)} invalid={len(bad)} "
      f"arm64e_ios26.5_refs={identity}")
if missing:
    print("missing required modules:", *missing, sep="\n")
if bad:
    print("invalid module format:", *bad, sep="\n")
if personal:
    print("personal paths:", *personal, sep="\n")
if missing or bad or personal:
    raise SystemExit(1)
# Swift module files expose the target triple in this toolchain. Requiring it
# prevents an arm64/other-SDK cache from being silently consumed as arm64e.
swift_files = [p for p in files if p.suffix == ".swiftmodule"]
if not any(b"arm64e-apple-ios26.5" in p.read_bytes() for p in swift_files):
    raise SystemExit("cache has no arm64e-apple-ios26.5 Swift module identity")
if identity == 0:
    raise SystemExit("cache has no arm64e/iOS 26.5 identity markers")
