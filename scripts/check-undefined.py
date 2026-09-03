#!/usr/bin/env python3
"""Verify that Mach-O undefined symbols exist in the selected SDK."""
import hashlib, os, glob, re, subprocess, sys

SDK = sys.argv[2] if len(sys.argv) > 2 else "/opt/isb/sysroot/iPhoneOS26.5.sdk"


def undefined_symbols(binary):
    out = subprocess.run(["llvm-nm", binary], capture_output=True, text=True).stdout
    syms = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[-2] == "U":
            syms.add(parts[-1])
        elif len(parts) == 2 and parts[0] == "U":
            syms.add(parts[1])
    return syms


def sdk_exports():
    cache_file = os.environ.get("ISB_EXPORTS_CACHE", "/tmp/isb-sdk-exports.txt")
    key = hashlib.sha256((SDK + "\0" + os.environ.get("ISB_TOOLCHAIN_ROOT", "/opt/ios-toolchain")).encode()).hexdigest()[:16]
    keyed = cache_file + "." + key
    if os.path.isfile(keyed):
        try:
            with open(keyed) as f:
                return set(f.read().splitlines())
        except OSError:
            pass
    exp = set()
    pats = [SDK + "/usr/lib/**/*.tbd", SDK + "/System/Library/Frameworks/**/*.tbd",
            SDK + "/System/Library/PrivateFrameworks/**/*.tbd"]
    files = []
    for p in pats:
        files += glob.glob(p, recursive=True)
    toolchain = os.environ.get("ISB_TOOLCHAIN_ROOT", "/opt/ios-toolchain")
    files += glob.glob(os.path.join(toolchain, "extrafw", "**", "*.tbd"), recursive=True)
    print("lendo %d .tbd ..." % len(files), flush=True)
    sym_re = re.compile(r"[A-Za-z_$][A-Za-z0-9_$.]+")
    for path in files:
        try:
            txt = open(path, errors="replace").read()
        except OSError:
            continue
        exp.update(m.group(0) for m in sym_re.finditer(txt))
    try:
        with open(keyed, "w") as f:
            f.write("\n".join(sorted(exp)) + "\n")
    except OSError:
        pass
    return exp


def main():
    if len(sys.argv) < 2:
        print("usage: check-undefined.py <binary> [sdk]")
        return 2
    binary = sys.argv[1]
    und = undefined_symbols(binary)
    print("simbolos indefinidos: %d" % len(und))
    exp = sdk_exports()
    print("simbolos exportados pelo SDK: %d" % len(exp))

    def known(s):
        if s in exp:
            return True
        for pfx in ("_OBJC_CLASS_$_", "_OBJC_METACLASS_$_", "_OBJC_IVAR_$_"):
            if s.startswith(pfx):
                bare = s[len(pfx):].split(".")[0]
                if bare in exp or ("_" + bare) in exp:
                    return True
        return s in ("dyld_stub_binder", "__mh_execute_header")

    missing = sorted(s for s in und if not known(s))
    print("\n=== FALTANDO NO SDK: %d ===" % len(missing))
    for s in missing[:200]:
        print("  " + s)
    if len(missing) > 200:
        print("  ... e mais %d" % (len(missing) - 200))
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
