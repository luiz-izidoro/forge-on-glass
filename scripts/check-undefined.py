#!/usr/bin/env python3
"""check-undefined.py — verifica se TODOS os simbolos indefinidos de um binario
Mach-O existem nos .tbd do SDK.

POR QUE: um simbolo indefinido que o dyld nao consegue ligar mata o processo
NO LAUNCH, antes de qualquer codigo do app rodar. No LiveContainer isso aparece
como TELA PRETA (sem crash log visivel). O link com ld64.lld NAO pega isso
quando o simbolo vem de um .tbd que o lld aceita mas o dyld real recusa.

Uso: python3 check-undefined.py <binario> [sdk]
"""
import re, subprocess, sys, os, glob

SDK = sys.argv[2] if len(sys.argv) > 2 else "/opt/isb/sysroot/iPhoneOS26.5.sdk"


def undefined_symbols(binary):
    out = subprocess.run(["llvm-nm", binary], capture_output=True, text=True).stdout
    syms = set()
    for line in out.split("\n"):
        parts = line.split()
        if len(parts) >= 2 and parts[-2] == "U":
            syms.add(parts[-1])
        elif len(parts) == 2 and parts[0] == "U":
            syms.add(parts[1])
    return syms


def sdk_exports():
    """Todos os simbolos exportados pelos .tbd/.dylib do SDK."""
    exp = set()
    pats = [SDK + "/usr/lib/**/*.tbd", SDK + "/System/Library/Frameworks/**/*.tbd",
            SDK + "/System/Library/PrivateFrameworks/**/*.tbd"]
    files = []
    for p in pats:
        files += glob.glob(p, recursive=True)
    # extrafw (UIKitCore extraido)
    files += glob.glob("/opt/ios-toolchain/extrafw/**/*.tbd", recursive=True)
    print("lendo %d .tbd ..." % len(files), flush=True)
    sym_re = re.compile(r"[A-Za-z_$][A-Za-z0-9_$.]+")
    for f in files:
        try:
            txt = open(f, errors="replace").read()
        except Exception:
            continue
        for m in sym_re.finditer(txt):
            exp.add(m.group(0))
    return exp


def main():
    binary = sys.argv[1]
    und = undefined_symbols(binary)
    print("simbolos indefinidos: %d" % len(und))
    exp = sdk_exports()
    print("simbolos exportados pelo SDK: %d" % len(exp))

    def known(s):
        if s in exp:
            return True
        # nos .tbd as classes ObjC aparecem em `objc-classes:` SEM o prefixo
        # _OBJC_CLASS_$_ / _OBJC_METACLASS_$_
        for pfx in ("_OBJC_CLASS_$_", "_OBJC_METACLASS_$_", "_OBJC_IVAR_$_"):
            if s.startswith(pfx):
                bare = s[len(pfx):].split(".")[0]
                if bare in exp or ("_" + bare) in exp:
                    return True
        # fornecido pelo proprio dyld
        if s in ("dyld_stub_binder", "__mh_execute_header"):
            return True
        return False

    missing = sorted(s for s in und if not known(s))
    print("\n=== FALTANDO NO SDK: %d ===" % len(missing))
    for s in missing[:200]:
        print("  " + s)
    if len(missing) > 200:
        print("  ... e mais %d" % (len(missing) - 200))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
