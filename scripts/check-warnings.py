#!/usr/bin/env python3
"""check-warnings.py — promotes to ERROR the compiler warnings that, in this
toolchain, mean "your code will NOT run".

RATIONALE (it cost an entire session on 2026-08-22):
The SDK used here has PATCHED `.swiftinterface` files. That changes signatures of
some protocol members (e.g.: `launchOptions` became
`NSDictionary<NSString, AnyObject>?` instead of `[LaunchOptionsKey: Any]?`).

When the protocol requirement is OPTIONAL (`optional func`, common in
ObjC delegates), a signature that does not match is **not an error**: Swift emits
only
    warning: instance method 'X' nearly matches optional requirement 'X'
and treats your method as an ordinary method of the class. UIKit NEVER calls it.

Result on device: the app OPENS, the process stays ALIVE, and the screen stays BLACK
forever — no crash, no log, no symptom pointing to the cause.

This script reads swift-frontend's stderr and fails the build in those cases.

Usage:
  python3 check-warnings.py <file.err> [more.err ...]
  python3 check-warnings.py --dir <dir with *.err>

Output: rc=0 if clean; rc=1 and a report if there is a fatal warning.
"""
import glob
import os
import re
import sys

# (warning regex, explanation, how to fix)
FATAL_WARNINGS = [
    (
        r"nearly matches optional requirement '([^']+)' of protocol '([^']+)'",
        "The method does NOT satisfy the protocol requirement (signature different from the "
        "one declared in the patched .swiftinterface). Since the requirement is OPTIONAL, the "
        "compiler only warns — and the framework NEVER calls your method. "
        "Device symptom: the app opens and shows a BLACK SCREEN.",
        "Use the EXACT signature from the SDK interface. For UIApplicationDelegate, "
        "prefer `applicationDidFinishLaunching(_ application: UIApplication)` "
        "(matches exactly) instead of "
        "`application(_:didFinishLaunchingWithOptions:)`. "
        "Check with: python3 scripts/check-protocol-sig.py <Protocol> <member>",
    ),
    (
        r"instance method '([^']+)' nearly matches (?:optional )?requirement",
        "Same: signature diverging from a protocol requirement.",
        "Adjust the signature to the one declared in the SDK.",
    ),
    (
        r"non-void function should return a value",
        "Flow without a return — may indicate a degraded body.",
        "Review the function body.",
    ),
    (
        r"result of call to '([^']+)' is unused",
        "Call whose result was discarded; in entry points "
        "(e.g. UIApplicationMain) this may indicate a malformed entry.",
        "Confirm that the value was not needed.",
    ),
]

# warnings that are known NOISE and must not fail the build
IGNORE = [
    r"was deprecated in iOS",
    r"'retroactive' attribute does not apply",
    r"argument unused during compilation",
    r"auto-linked framework not found",
    r"never used",
    r"was never mutated",
    r"initialization of immutable value",
    r"no calls to throwing functions",
    r"string interpolation produces a debug description",
]


def scan(path):
    """Returns a list of (warning_line, context, explanation, fix)."""
    try:
        txt = open(path, errors="replace").read()
    except OSError:
        return []
    hits = []
    seen = set()
    lines = txt.split("\n")
    for i, line in enumerate(lines):
        if "warning:" not in line:
            continue
        # the compiler repeats the warning on the "caret" lines (| `- warning:)
        if re.match(r"^\s*[\d\s]*\|", line):
            continue
        if any(re.search(p, line) for p in IGNORE):
            continue
        for pat, why, fix in FATAL_WARNINGS:
            m = re.search(pat, line)
            if m:
                # deduplicate by (file:line, message)
                key = re.sub(r"^.*?([^/\s]+\.swift:\d+)", r"\1", line)[:160]
                if key in seen:
                    break
                seen.add(key)
                ctx = "\n".join(lines[i:i + 6])
                hits.append((line.strip(), ctx, why, fix))
                break
    return hits


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    if args[0] == "--dir":
        files = sorted(glob.glob(os.path.join(args[1], "*.err")))
    else:
        files = args

    total = 0
    for f in files:
        hits = scan(f)
        if not hits:
            continue
        total += len(hits)
        print("=" * 72)
        print("LOG FILE: %s" % f)
        for line, ctx, why, fix in hits:
            print("-" * 72)
            print("WARNING FATAL: %s" % line)
            print("\nWHY IT IS FATAL:\n  %s" % why)
            print("\nHOW TO FIX:\n  %s" % fix)
            print("\nCONTEXT:")
            for l in ctx.split("\n"):
                print("  " + l)

    if total:
        print("=" * 72)
        print("%d FATAL warning(s). The build would produce an app that does NOT work." % total)
        print("Read references/WARNINGS-FATAIS.md")
        return 1
    print("check-warnings: no fatal warning (%d log(s) analyzed)" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
