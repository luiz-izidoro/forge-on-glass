#!/usr/bin/env python3
"""check-entry.py — verifies, IN THE ALREADY LINKED BINARY, that the app will
really start. Static runtime analysis, not source analysis.

WHY (2026-08-22): two distinct failures produce an app that compiles 100%
clean and does not work:

  1. EMPTY `_main`  -> missing the `UIApplicationMain(...)` call at the end of
     the entry point. Symptom: "App returned from its main function with code 0".

  2. DELEGATE NEVER CALLED -> the method `application(_:didFinishLaunching...)`
     does not match the patched `.swiftinterface` (launchOptions is NSDictionary
     here). The requirement is OPTIONAL, so Swift only WARNS — and sometimes NOT
     EVEN THAT, depending on the compilation context. UIKit never calls the method,
     the window is never created. Symptom: app OPENS, stays ALIVE, BLACK SCREEN.

This script does NOT depend on the warning (which is inconsistent): it looks at
what ended up in the binary — is the delegate method registered in the ObjC
runtime with the right selector?

Usage: python3 check-entry.py <binary | app.ipa>
rc=0 all good; rc=1 a problem that prevents the app from starting.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

# Selectors that UIKit calls to boot the app. At least ONE must be
# implemented by the delegate class.
LAUNCH_SELECTORS = [
    "applicationDidFinishLaunching:",
    "application:didFinishLaunchingWithOptions:",
]


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def has_swift_entry_section(binary):
    """Detects pure Swift by metadata that survives llvm-strip -x.

    `__swift5_typeref` also appears in a Swift+ObjC hybrid, so it is not
    enough to select the strict path. The entry section is emitted by Swift's
    UIApplicationMain entry point and remains in the stripped Mach-O.
    """
    try:
        out = subprocess.run(
            ["llvm-objdump", "--macho", "--section-headers", binary],
            capture_output=True, text=True, check=False).stdout
    except OSError:
        return False
    return bool(re.search(r"\b__swift5_entry\b", out))


def objc_launch_methods(binary):
    """Returns selectors present in the ObjC tables of the binary's classes.

    Strings in `__objc_methname` are not enough: UIKit brings the same names
    too. The `class_ro_t -> baseMethods -> method_t` table only contains methods
    that actually received ObjC exposure (including Swift thunks), and
    survives `llvm-strip -x`.
    """
    try:
        data = open(binary, "rb").read()
        magic, = __import__("struct").unpack_from("<I", data)
        if magic != 0xfeedfacf:
            return set()
        import struct
        _magic, _cpu, _sub, _filetype, ncmds, _sizeofcmds, _flags, _reserved = struct.unpack_from("<IiiIIIII", data, 0)
        sections = []
        p = 32
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", data, p)
            if cmd == 0x19 and cmdsize >= 72:
                nsects = struct.unpack_from("<I", data, p + 64)[0]
                for i in range(nsects):
                    q = p + 72 + i * 80
                    if q + 80 > len(data):
                        continue
                    name = data[q:q+16].split(b"\0", 1)[0]
                    addr, size = struct.unpack_from("<QQ", data, q + 32)
                    off = struct.unpack_from("<I", data, q + 48)[0]
                    sections.append((addr, size, off, name))
            p += cmdsize

        def ptr_off(addr, align=False):
            # Metadata pointers may carry PAC/flags in low bits. Class and
            # class_ro pointers are aligned; selector pointers may be byte
            # offsets into __objc_methname and must retain their low bits.
            candidates = []
            if align:
                # Do not fall through to the unaligned candidate: a PAC
                # pointer such as ...0xf02 must resolve to the aligned
                # class_ro_t at ...0xf00, not into its middle.
                candidates.append(addr & 0x0000FFFFFFFFFFF0)
            else:
                candidates += [addr & 0x000000FFFFFFFFFF,
                               addr & 0x0000FFFFFFFFFFFF,
                               addr & 0x00000000FFFFFFFF]
            for candidate in candidates:
                for base, size, off, _name in sections:
                    # Mach-O metadata in this toolchain may store either the
                    # full VM address or its low 32-bit offset after stripping.
                    for section_base in (base, base & 0xffffffff):
                        if section_base <= candidate < section_base + size:
                            return off + candidate - section_base
            return None

        def u64(addr):
            off = ptr_off(addr)
            return struct.unpack_from("<Q", data, off)[0] if off is not None and off + 8 <= len(data) else None

        names = set()
        class_sec = next((s for s in sections if s[3] == b"__objc_classlist"), None)
        if not class_sec:
            return names
        base, size, off, _ = class_sec
        for i in range(0, size - (size % 8), 8):
            cls = struct.unpack_from("<Q", data, off + i)[0]
            cls_off = ptr_off(cls, align=True)
            if cls_off is None or cls_off + 40 > len(data):
                continue
            ro = struct.unpack_from("<Q", data, cls_off + 32)[0]
            ro_off = ptr_off(ro, align=True)
            if ro_off is None or ro_off + 36 > len(data):
                continue
            methods = struct.unpack_from("<Q", data, ro_off + 32)[0]
            moff = ptr_off(methods)
            if moff is None or moff + 8 > len(data):
                continue
            entsize_flags, count = struct.unpack_from("<II", data, moff)
            entsize = entsize_flags & 0xFFFF
            if entsize < 24 or count > 10000:
                continue
            for j in range(count):
                e = moff + 8 + j * entsize
                if e + 8 > len(data):
                    break
                name = struct.unpack_from("<Q", data, e)[0]
                noff = ptr_off(name) if name else None
                if noff is not None:
                    names.add(data[noff:data.find(b"\0", noff)].decode("utf-8", "ignore"))
        # The selector string itself is not proof: UIKit contributes it too.
        # Only accept selectors found by the class method-list parser above.
        return names
    except (OSError, ValueError, IndexError, struct.error):
        return set()


def raw(binary):
    """Binary bytes. Needed because ObjC class symbols
    (_OBJC_CLASS_$_X) and selectors live in data sections that `llvm-nm`
    does not always list — especially in 100% ObjC binaries (hybrid build)."""
    try:
        with open(binary, "rb") as f:
            return f.read()
    except OSError:
        return b""


def is_objc_app(binary):
    """Detects the HYBRID build (UI in Objective-C, logic in Swift).

    In these binaries the AppDelegate is a real ObjC class: there is no
    mangled Swift symbol or `To` thunk — the method IS native ObjC. Applying
    the pure-Swift path rules here produces a FALSE POSITIVE.
    """
    d = raw(binary)
    tem_selector = (b"applicationDidFinishLaunching:" in d or
                    b"application:didFinishLaunchingWithOptions:" in d)
    nm = run(["llvm-nm", binary])
    tem_swift_delegate = bool(re.search(
        r"_\$s\S*(?:applicationDidFinishLaunching|didFinishLaunchingWithOptions)",
        nm))
    return tem_selector and not tem_swift_delegate


def extract(path):
    """Accepts .ipa or binary. Returns (binary_path, tempdir_or_None)."""
    if not path.endswith(".ipa"):
        return path, None
    td = tempfile.mkdtemp(prefix="checkentry")
    with zipfile.ZipFile(path) as z:
        z.extractall(td)
    for root, _dirs, files in os.walk(os.path.join(td, "Payload")):
        for f in files:
            p = os.path.join(root, f)
            if f.endswith(".plist"):
                continue
            head = open(p, "rb").read(4)
            if head[:4] in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
                return p, td
    shutil.rmtree(td, ignore_errors=True)
    return None, None


def check_main(binary):
    """_main must call UIApplicationMain."""
    nm = run(["llvm-nm", binary])
    if re.search(r"^\s*U\s+_UIApplicationMain\s*$", nm, re.M) or \
       " U _UIApplicationMain" in nm:
        return True, "_main references UIApplicationMain"
    return False, ("_main does NOT call UIApplicationMain -> the app exits immediately "
                   "('returned from main with code 0'). Missing the line "
                   "`UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, "
                   "nil, NSStringFromClass(AppDelegate.self))` AT THE END of the entry point.")


def check_delegate(binary):
    """The delegate method must have an ObjC THUNK (@objc thunk).

    THIS IS THE DECISIVE TEST (discovered 2026-08-22 comparing an app that
    runs with one that shows a black screen):

    When the signature MATCHES the protocol requirement, the compiler emits
    TWO symbols for the method:
        ..._$s<App>11AppDelegateC11application_29didFinish...F     <- Swift function
        ..._$s<App>11AppDelegateC11application_29didFinish...FTo   <- ObjC THUNK  ✅
    The `To` suffix ("to ObjC") is the thunk that registers the method in the ObjC runtime.
    It is through it that UIKit calls your delegate.

    When the signature DOES NOT match (launchOptions with a different type from
    the patched .swiftinterface), the compiler emits ONLY the Swift function, WITHOUT the
    `To` thunk. The method exists in the binary, but ObjC never sees it
    -> UIKit never calls it -> window never created -> BLACK SCREEN.

    Note: searching for the SELECTOR NAME in __objc_methname does NOT work — the string
    appears either way (it comes from UIKit itself). What discriminates is the
    thunk in YOUR class.
    """
    nm = run(["llvm-nm", binary])

    # Swift symbols of the launch method, in the APP's OWN class.
    # ATTENTION to name mangling: the class name may appear compressed
    # (e.g. `_$s7TodoApp0B8DelegateC29applicationDidFinishLaunching...`), so
    # do NOT look for the substring "AppDelegate" — look for the METHOD NAME.
    swift_fns = re.findall(
        r"^\S+\s+[tTsSdD]\s+(_\$s\S*(?:applicationDidFinishLaunching|"
        r"didFinishLaunchingWithOptions)\S*)$", nm, re.M)

    swift_binary = has_swift_entry_section(binary)
    objc_methods = objc_launch_methods(binary)

    # A pure Swift binary may lose the `_$s...To` symbols after `llvm-strip -x`,
    # but the ObjC method table still registers the thunk and the selector.
    # In that case, the __swift5_entry section keeps the positive Swift
    # identification and the table is the proof of exposure to UIKit.
    if swift_binary:
        launch_methods = set(LAUNCH_SELECTORS) & objc_methods
        if not swift_fns and launch_methods:
            return True, ("stripped pure SWIFT app: launch selector remains "
                          "in the ObjC table -> UIKit can call the delegate")
        if not swift_fns and not launch_methods:
            return False, ("pure SWIFT app identified by __swift5_entry, but "
                           "no launch method is in the ObjC table. "
                           "The delegate will not be called.")

    # --- HYBRID path (UI in ObjC): the delegate is a native ObjC class.
    if not swift_binary and is_objc_app(binary):
        d = raw(binary)
        if b"applicationDidFinishLaunching:" in d or \
           b"application:didFinishLaunchingWithOptions:" in d:
            return True, ("HYBRID app (ObjC): launch method present as a "
                          "native ObjC selector -> UIKit can call the delegate")
        return False, ("no launch method found in the ObjC shell. "
                       "Implement `-(void)applicationDidFinishLaunching:` "
                       "in AppShell.m's AppDelegate")

    # Swift symbols of the launch method, in the APP's OWN class.
    # ATTENTION to name mangling: the class name may appear compressed
    # (e.g. `_$s7TodoApp0B8DelegateC29applicationDidFinishLaunching...`), so
    # do NOT look for the substring "AppDelegate" — look for the METHOD NAME, which
    # mangling preserves literally (preceded by its length).
    swift_fns = re.findall(
        r"^\S+\s+[tTsSdD]\s+(_\$s\S*(?:applicationDidFinishLaunching|"
        r"didFinishLaunchingWithOptions)\S*)$", nm, re.M)
    if not swift_fns:
        return False, ("no launch method implemented in the app. "
                       "Implement `applicationDidFinishLaunching(_ application: "
                       "UIApplication)` in AppDelegate.")

    # the ObjC thunk ends in `To`. (`Tq` = method descriptor, not usable.)
    thunks = [s for s in swift_fns if s.endswith("To")]
    if thunks:
        return True, ("launch method exposed to ObjC (`To` thunk present) "
                      "-> UIKit can call the delegate")

    base = swift_fns[0]
    hint = ""
    if "didFinishLaunchingWithOptions" in base:
        hint = ("\n           The signature `application(_:didFinishLaunchingWithOptions:)` "
                "does NOT match the\n           patched .swiftinterface (launchOptions "
                "is NSDictionary here).\n           REPLACE it with: "
                "`func applicationDidFinishLaunching(_ application: UIApplication)`"
                "\n           See assets/AppEntry.swift and references/WARNINGS-FATAIS.md")
    return False, ("the launch method exists in Swift but has NO ObjC thunk "
                   "(`...To`).\n           UIKit will NEVER call it -> the window "
                   "is never created -> APP OPENS WITH A BLACK SCREEN." + hint)


def check_delegate_class(binary):
    """The delegate class must exist and inherit from UIResponder."""
    nm = run(["llvm-nm", binary])
    d = raw(binary)
    # The symbol may be only in the data section (not listed by llvm-nm),
    # which is the typical case for the 100% ObjC binary from the hybrid build.
    has_resp = ("_OBJC_METACLASS_$_UIResponder" in nm
                or "_OBJC_CLASS_$_UIResponder" in nm
                or b"_OBJC_CLASS_$_UIResponder" in d
                or b"_OBJC_METACLASS_$_UIResponder" in d)
    if not has_resp:
        return False, ("the binary does not reference UIResponder — AppDelegate "
                       "probably does not inherit from UIResponder (required "
                       "for UIApplicationMain to find it).")
    return True, "AppDelegate inherits from UIResponder"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    binary, td = extract(sys.argv[1])
    if not binary:
        print("could not find the binary in %s" % sys.argv[1])
        return 2

    print("binary: %s" % binary)
    ok = True
    for fn in (check_main, check_delegate_class, check_delegate):
        good, msg = fn(binary)
        print(("  [OK]   " if good else "  [FAIL] ") + msg)
        ok = ok and good

    if td:
        shutil.rmtree(td, ignore_errors=True)

    if ok:
        print("\ncheck-entry: the app has a valid entry point and delegate.")
        return 0
    print("\ncheck-entry: THIS APP WILL NOT START CORRECTLY.")
    print("See references/WARNINGS-FATAIS.md and assets/AppEntry.swift")
    return 1


if __name__ == "__main__":
    sys.exit(main())
