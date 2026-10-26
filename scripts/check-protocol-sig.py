#!/usr/bin/env python3
"""check-protocol-sig.py — shows the REAL signature of a protocol member
(or any declaration) in the SDK that THIS toolchain uses.

WHY IT EXISTS:
The SDK's `.swiftinterface` files were patched to compile with the swift.org
toolchain. Some types degraded (e.g. `[LaunchOptionsKey: Any]?` ->
`NSDictionary<NSString, AnyObject>?`). Writing the signature "the Apple way",
from memory or copied from the internet, produces code that COMPILES and DOES
NOT WORK (see references/WARNINGS-FATAIS.md).

Rule: before implementing ANY system delegate/protocol method, check the
signature here. Do not guess.

Usage:
  python3 check-protocol-sig.py UIApplicationDelegate
  python3 check-protocol-sig.py UIApplicationDelegate didFinishLaunching
  python3 check-protocol-sig.py --grep "func application"
"""
import glob
import os
import re
import sys

SDK = os.environ.get("ISB_SDK", os.environ.get("IOS_SDK", "/opt/isb/sysroot/iPhoneOS26.5.sdk"))
FB = os.environ.get("ISB_FOUNDATION_BUILD", "/opt/ios-toolchain/foundation-build633-arm64e")
TOOLCHAIN = os.environ.get("ISB_TOOLCHAIN_ROOT", "/opt/ios-toolchain")


def interface_files():
    pats = [
        SDK + "/System/Library/Frameworks/*/Modules/*.swiftmodule/*.swiftinterface",
        SDK + "/System/Library/PrivateFrameworks/*/Modules/*.swiftmodule/*.swiftinterface",
        SDK + "/usr/lib/swift/*.swiftmodule/*.swiftinterface",
    ]
    files = []
    for p in pats:
        files += glob.glob(p)
    if not files:
        # The SDK is resolved by the configured profile; there is no personal fallback.
        for alt in (os.path.join(TOOLCHAIN, "iPhoneOS26.5.sdk"),):
            for p in pats:
                files += glob.glob(p.replace(SDK, alt))
    # NOTE: the SDK interfaces are arm64e (not arm64). Do not filter by exact
    # "arm64" — `arm64` is a substring of `arm64e`, but if both ever exist,
    # prefer arm64e (it is what exists today).
    pref = [f for f in files if "arm64" in os.path.basename(f)]
    return sorted(set(pref or files))


def find_protocol(name, member=None):
    found = find_in_swift_interfaces(name, member)
    if not found:
        found = find_in_objc_headers(name, member)
    return found


def find_in_objc_headers(name, member=None):
    """ObjC protocols (UITableViewDataSource, UICollectionViewDelegate, ...)
    do not exist in .swiftinterface: they are imported from HEADERS via clang.
    The signature Swift sees comes from the ObjC declaration + the header's
    nullability/generics annotations.
    """
    hdrs = []
    for base in (SDK, os.path.join(TOOLCHAIN, "iPhoneOS26.5.sdk")):
        hdrs += glob.glob(base + "/System/Library/Frameworks/*/Headers/*.h")
        if hdrs:
            break
    found = False
    for f in hdrs:
        try:
            txt = open(f, errors="replace").read()
        except OSError:
            continue
        # REAL protocol definition (not forward-declaration
        # `@protocol A, B;`): has `<Super>` and/or body until @end
        m = re.search(r"@protocol\s+" + re.escape(name) +
                      r"\s*(?:<[^>]*>)?\s*\n", txt)
        if not m or re.search(r"@protocol\s+" + re.escape(name) +
                              r"\s*(?:,|;)", txt[m.start():m.start() + 200]):
            m = re.search(r"@protocol\s+" + re.escape(name) +
                          r"\s*<[^>]*>", txt)
        if not m:
            continue
        end = txt.find("@end", m.start())
        if end < 0:
            continue
        block = txt[m.start():end]
        lines = block.split("\n")
        if member:
            sel = [l for l in lines if member.lower() in l.lower()]
            if not sel:
                continue
        else:
            sel = lines
        found = True
        print("=" * 72)
        print("ObjC PROTOCOL in: %s" % os.path.basename(f))
        print("(comes from HEADERS, not from .swiftinterface)")
        print("-" * 72)
        for l in sel[:60]:
            if l.strip():
                print(l)
        print("-" * 72)
        print("⚠️  In Swift, ObjC types may appear DEGRADED in this toolchain:")
        print("    NSIndexPath  (not IndexPath)")
        print("    NSDictionary (not [Key: Value])")
        print("    NSArray      (not [Element])")
        print("    If the compiler complains about conversion, use the ObjC type in")
        print("    the SIGNATURE and convert inside the body.")
    return found


def find_in_swift_interfaces(name, member=None):
    found = False
    for f in interface_files():
        try:
            txt = open(f, errors="replace").read()
        except OSError:
            continue
        # protocol/extension block
        for m in re.finditer(r"^(public )?(protocol|extension|class|struct)\s+" +
                             re.escape(name) + r"\b", txt, re.M):
            start = m.start()
            # find the brace-balanced block
            i = txt.find("{", start)
            if i < 0:
                continue
            depth = 0
            end = i
            for j in range(i, min(len(txt), i + 200000)):
                if txt[j] == "{":
                    depth += 1
                elif txt[j] == "}":
                    depth -= 1
                    if depth == 0:
                        end = j
                        break
            block = txt[start:end + 1]
            lines = [l for l in block.split("\n")]
            if member:
                sel = [l for l in lines if member.lower() in l.lower()]
                if not sel:
                    continue
            else:
                sel = lines
            found = True
            print("=" * 72)
            print("FILE: %s" % f.replace(SDK, "$SDK"))
            print("-" * 72)
            for l in sel[:60]:
                print(l)
            if not member and len(sel) > 60:
                print("... (%d lines total; pass a <member> to filter)" % len(sel))
    return found


def grep_all(pattern):
    rx = re.compile(pattern)
    n = 0
    for f in interface_files():
        try:
            txt = open(f, errors="replace").read()
        except OSError:
            continue
        for i, line in enumerate(txt.split("\n")):
            if rx.search(line):
                print("%s:%d: %s" % (os.path.basename(f), i + 1, line.strip()))
                n += 1
                if n > 200:
                    print("... (truncated)")
                    return True
    return n > 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    if sys.argv[1] == "--grep":
        ok = grep_all(sys.argv[2])
    else:
        name = sys.argv[1]
        member = sys.argv[2] if len(sys.argv) > 2 else None
        ok = find_protocol(name, member)
        if not ok:
            print("not found: %s%s" % (name, (" / " + member) if member else ""))
            print("tip: try --grep '<snippet>'")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
