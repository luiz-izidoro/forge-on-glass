#!/usr/bin/env python3
"""check-protocol-sig.py — mostra a assinatura REAL de um membro de protocolo
(ou de qualquer declaracao) no SDK que ESTE toolchain usa.

POR QUE EXISTE:
Os `.swiftinterface` do SDK foram patchados para compilar com o toolchain
swift.org. Alguns tipos degradaram (ex.: `[LaunchOptionsKey: Any]?` ->
`NSDictionary<NSString, AnyObject>?`). Escrever a assinatura "do jeito da
Apple", de cabeca ou copiando da internet, gera codigo que COMPILA e NAO
FUNCIONA (ver references/WARNINGS-FATAIS.md).

Regra: antes de implementar QUALQUER metodo de delegate/protocolo do sistema,
consulte a assinatura aqui. Nao adivinhe.

Uso:
  python3 check-protocol-sig.py UIApplicationDelegate
  python3 check-protocol-sig.py UIApplicationDelegate didFinishLaunching
  python3 check-protocol-sig.py --grep "func application"
"""
import glob
import os
import re
import sys

SDK = os.environ.get("IOS_SDK", "/opt/isb/sysroot/iPhoneOS26.5.sdk")
FB = "/opt/ios-toolchain/foundation-build633"


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
        # o SDK pode estar noutro prefixo (o de trabalho e' /opt/ios-toolchain)
        for alt in ("/opt/ios-toolchain/iPhoneOS26.5.sdk",):
            for p in pats:
                files += glob.glob(p.replace(SDK, alt))
    # NOTA: os interfaces do SDK sao arm64e (nao arm64). Nao filtre por "arm64"
    # exato — `arm64` e' substring de `arm64e`, mas se um dia houver os dois,
    # preferir arm64e (e' o que existe hoje).
    pref = [f for f in files if "arm64" in os.path.basename(f)]
    return sorted(set(pref or files))


def find_protocol(name, member=None):
    found = find_in_swift_interfaces(name, member)
    if not found:
        found = find_in_objc_headers(name, member)
    return found


def find_in_objc_headers(name, member=None):
    """Protocolos ObjC (UITableViewDataSource, UICollectionViewDelegate, ...)
    nao existem no .swiftinterface: sao importados dos HEADERS via clang.
    A assinatura que o Swift enxerga vem da declaracao ObjC + as anotacoes de
    nullability/generics do header.
    """
    hdrs = []
    for base in (SDK, "/opt/ios-toolchain/iPhoneOS26.5.sdk"):
        hdrs += glob.glob(base + "/System/Library/Frameworks/*/Headers/*.h")
        if hdrs:
            break
    found = False
    for f in hdrs:
        try:
            txt = open(f, errors="replace").read()
        except OSError:
            continue
        # definicao REAL do protocolo (nao forward-declaration
        # `@protocol A, B;`): tem `<Super>` e/ou corpo ate @end
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
        print("PROTOCOLO ObjC em: %s" % os.path.basename(f))
        print("(vem dos HEADERS, nao do .swiftinterface)")
        print("-" * 72)
        for l in sel[:60]:
            if l.strip():
                print(l)
        print("-" * 72)
        print("⚠️  Em Swift, tipos ObjC podem aparecer DEGRADADOS neste toolchain:")
        print("    NSIndexPath  (nao IndexPath)")
        print("    NSDictionary (nao [Key: Value])")
        print("    NSArray      (nao [Element])")
        print("    Se o compilador reclamar de conversao, use o tipo ObjC na")
        print("    ASSINATURA e converta dentro do corpo.")
    return found


def find_in_swift_interfaces(name, member=None):
    found = False
    for f in interface_files():
        try:
            txt = open(f, errors="replace").read()
        except OSError:
            continue
        # bloco do protocolo/extension
        for m in re.finditer(r"^(public )?(protocol|extension|class|struct)\s+" +
                             re.escape(name) + r"\b", txt, re.M):
            start = m.start()
            # acha o bloco balanceado por chaves
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
            print("ARQUIVO: %s" % f.replace(SDK, "$SDK"))
            print("-" * 72)
            for l in sel[:60]:
                print(l)
            if not member and len(sel) > 60:
                print("... (%d linhas no total; passe um <membro> para filtrar)" % len(sel))
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
                    print("... (truncado)")
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
            print("nao encontrado: %s%s" % (name, (" / " + member) if member else ""))
            print("dica: tente --grep '<trecho>'")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
