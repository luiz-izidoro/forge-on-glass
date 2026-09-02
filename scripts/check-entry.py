#!/usr/bin/env python3
"""check-entry.py — verifica, NO BINARIO JA LINKADO, que o app vai realmente
iniciar. Analise estatica de runtime, nao de fonte.

POR QUE (2026-08-22): duas falhas distintas produzem um app que compila 100%
limpo e nao funciona:

  1. `_main` VAZIO  -> falta a chamada `UIApplicationMain(...)` no fim do
     entry point. Sintoma: "App returned from its main function with code 0".

  2. DELEGATE NUNCA CHAMADO -> o metodo `application(_:didFinishLaunching...)`
     nao casa com o `.swiftinterface` patchado (launchOptions e' NSDictionary
     aqui). O requisito e' OPCIONAL, entao o Swift so AVISA — e as vezes NEM
     ISSO, dependendo do contexto de compilacao. O UIKit nunca chama o metodo,
     a janela nunca e' criada. Sintoma: app ABRE, fica VIVO, TELA PRETA.

Este script NAO depende do warning (que e' inconstante): ele olha o que ficou
no binario — o metodo do delegate esta registrado no runtime ObjC com o
seletor certo?

Uso: python3 check-entry.py <binario | app.ipa>
rc=0 tudo certo; rc=1 problema que impede o app de iniciar.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

# Seletores que o UIKit chama para dar boot no app. Pelo menos UM precisa estar
# implementado pela classe do delegate.
LAUNCH_SELECTORS = [
    "applicationDidFinishLaunching:",
    "application:didFinishLaunchingWithOptions:",
]


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def has_swift_entry_section(binary):
    """Detecta Swift puro por metadado que sobrevive a llvm-strip -x.

    `__swift5_typeref` também aparece em um híbrido Swift+ObjC, portanto não
    basta para selecionar o caminho estrito. O entry section é emitido pelo
    entry point Swift de UIApplicationMain e permanece no Mach-O strippado.
    """
    try:
        out = subprocess.run(
            ["llvm-objdump", "--macho", "--section-headers", binary],
            capture_output=True, text=True, check=False).stdout
    except OSError:
        return False
    return bool(re.search(r"\b__swift5_entry\b", out))


def objc_launch_methods(binary):
    """Retorna seletores presentes nas tabelas ObjC das classes do binário.

    Strings em `__objc_methname` não bastam: UIKit também traz os mesmos
    nomes. A tabela `class_ro_t -> baseMethods -> method_t` só contém métodos
    que realmente receberam exposição ObjC (inclusive thunks Swift), e
    sobrevive ao `llvm-strip -x`.
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
    """Bytes do binario. Necessario porque simbolos de classe ObjC
    (_OBJC_CLASS_$_X) e seletores vivem em secoes de dados que o `llvm-nm`
    nem sempre lista — sobretudo em binarios 100% ObjC (build hibrido)."""
    try:
        with open(binary, "rb") as f:
            return f.read()
    except OSError:
        return b""


def is_objc_app(binary):
    """Detecta o build HIBRIDO (UI em Objective-C, logica em Swift).

    Nesses binarios o AppDelegate e' uma classe ObjC de verdade: nao existe
    simbolo Swift mangled nem thunk `To` — o metodo ja E' ObjC nativo. Aplicar
    as regras do caminho Swift puro aqui gera FALSO POSITIVO.
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
    """Aceita .ipa ou binario. Retorna (caminho_binario, tempdir_ou_None)."""
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
    """_main precisa chamar UIApplicationMain."""
    nm = run(["llvm-nm", binary])
    if re.search(r"^\s*U\s+_UIApplicationMain\s*$", nm, re.M) or \
       " U _UIApplicationMain" in nm:
        return True, "_main referencia UIApplicationMain"
    return False, ("_main NAO chama UIApplicationMain -> o app sai imediatamente "
                   "('returned from main with code 0'). Falta a linha "
                   "`UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, "
                   "nil, NSStringFromClass(AppDelegate.self))` NO FIM do entry point.")


def check_delegate(binary):
    """O metodo do delegate precisa ter THUNK ObjC (@objc thunk).

    ESTE E' O TESTE DECISIVO (descoberto em 2026-08-22 comparando um app que
    roda com um que da tela preta):

    Quando a assinatura CASA com o requisito do protocolo, o compilador emite
    DOIS simbolos para o metodo:
        ..._$s<App>11AppDelegateC11application_29didFinish...F     <- funcao Swift
        ..._$s<App>11AppDelegateC11application_29didFinish...FTo   <- THUNK ObjC  ✅
    O sufixo `To` ("to ObjC") e' o thunk que registra o metodo no runtime ObjC.
    E' por ele que o UIKit chama o seu delegate.

    Quando a assinatura NAO casa (launchOptions com tipo diferente do
    .swiftinterface patchado), o compilador emite APENAS a funcao Swift, SEM o
    thunk `To`. O metodo existe no binario, mas o ObjC nunca o ve
    -> UIKit nunca chama -> janela nunca criada -> TELA PRETA.

    Nota: procurar o NOME DO SELETOR em __objc_methname NAO funciona — a string
    aparece de qualquer jeito (vem do proprio UIKit). O que discrimina e' o
    thunk na SUA classe.
    """
    nm = run(["llvm-nm", binary])

    # Simbolos Swift do metodo de launch, na classe do PROPRIO app.
    # ATENCAO ao name mangling: o nome da classe pode aparecer comprimido
    # (ex.: `_$s7TodoApp0B8DelegateC29applicationDidFinishLaunching...`), entao
    # NAO procure a substring "AppDelegate" — procure o NOME DO METODO.
    swift_fns = re.findall(
        r"^\S+\s+[tTsSdD]\s+(_\$s\S*(?:applicationDidFinishLaunching|"
        r"didFinishLaunchingWithOptions)\S*)$", nm, re.M)

    swift_binary = has_swift_entry_section(binary)
    objc_methods = objc_launch_methods(binary)

    # Um Swift puro pode perder os símbolos `_$s...To` após `llvm-strip -x`,
    # mas a tabela de métodos ObjC continua registrando o thunk e o seletor.
    # Nesse caso, a seção __swift5_entry mantém a identificação positiva de
    # Swift e a tabela é a prova de exposição ao UIKit.
    if swift_binary:
        launch_methods = set(LAUNCH_SELECTORS) & objc_methods
        if not swift_fns and launch_methods:
            return True, ("app SWIFT puro strippado: seletor de launch permanece "
                          "na tabela ObjC -> o UIKit consegue chamar o delegate")
        if not swift_fns and not launch_methods:
            return False, ("app SWIFT puro identificado por __swift5_entry, mas "
                           "nenhum método de launch está na tabela ObjC. "
                           "O delegate não será chamado.")

    # --- caminho HIBRIDO (UI em ObjC): o delegate e' uma classe ObjC nativa.
    if not swift_binary and is_objc_app(binary):
        d = raw(binary)
        if b"applicationDidFinishLaunching:" in d or \
           b"application:didFinishLaunchingWithOptions:" in d:
            return True, ("app HIBRIDO (ObjC): metodo de launch presente como "
                          "seletor ObjC nativo -> o UIKit consegue chamar o delegate")
        return False, ("nenhum metodo de launch encontrado no shell ObjC. "
                       "Implemente `-(void)applicationDidFinishLaunching:` "
                       "no AppDelegate do AppShell.m")

    # Simbolos Swift do metodo de launch, na classe do PROPRIO app.
    # ATENCAO ao name mangling: o nome da classe pode aparecer comprimido
    # (ex.: `_$s7TodoApp0B8DelegateC29applicationDidFinishLaunching...`), entao
    # NAO procure a substring "AppDelegate" — procure o NOME DO METODO, que o
    # mangling preserva literalmente (precedido do seu tamanho).
    swift_fns = re.findall(
        r"^\S+\s+[tTsSdD]\s+(_\$s\S*(?:applicationDidFinishLaunching|"
        r"didFinishLaunchingWithOptions)\S*)$", nm, re.M)
    if not swift_fns:
        return False, ("nenhum metodo de launch implementado no app. "
                       "Implemente `applicationDidFinishLaunching(_ application: "
                       "UIApplication)` no AppDelegate.")

    # o thunk ObjC termina em `To`. (`Tq` = method descriptor, nao serve.)
    thunks = [s for s in swift_fns if s.endswith("To")]
    if thunks:
        return True, ("metodo de launch exposto ao ObjC (thunk `To` presente) "
                      "-> o UIKit consegue chamar o delegate")

    base = swift_fns[0]
    hint = ""
    if "didFinishLaunchingWithOptions" in base:
        hint = ("\n           A assinatura `application(_:didFinishLaunchingWithOptions:)` "
                "NAO casa com o\n           .swiftinterface patchado (launchOptions "
                "e' NSDictionary aqui).\n           TROQUE por: "
                "`func applicationDidFinishLaunching(_ application: UIApplication)`"
                "\n           Ver assets/AppEntry.swift e references/WARNINGS-FATAIS.md")
    return False, ("o metodo de launch existe em Swift mas NAO tem thunk ObjC "
                   "(`...To`).\n           O UIKit NUNCA vai chama-lo -> a janela "
                   "nunca e' criada -> APP ABRE COM TELA PRETA." + hint)


def check_delegate_class(binary):
    """A classe do delegate precisa existir e herdar de UIResponder."""
    nm = run(["llvm-nm", binary])
    d = raw(binary)
    # O simbolo pode estar so na secao de dados (nao listado pelo llvm-nm),
    # que e' o caso tipico do binario 100% ObjC do build hibrido.
    has_resp = ("_OBJC_METACLASS_$_UIResponder" in nm
                or "_OBJC_CLASS_$_UIResponder" in nm
                or b"_OBJC_CLASS_$_UIResponder" in d
                or b"_OBJC_METACLASS_$_UIResponder" in d)
    if not has_resp:
        return False, ("o binario nao referencia UIResponder — o AppDelegate "
                       "provavelmente nao herda de UIResponder (obrigatorio "
                       "para UIApplicationMain encontra-lo).")
    return True, "AppDelegate herda de UIResponder"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    binary, td = extract(sys.argv[1])
    if not binary:
        print("nao achei o binario em %s" % sys.argv[1])
        return 2

    print("binario: %s" % binary)
    ok = True
    for fn in (check_main, check_delegate_class, check_delegate):
        good, msg = fn(binary)
        print(("  [OK]   " if good else "  [FALHA] ") + msg)
        ok = ok and good

    if td:
        shutil.rmtree(td, ignore_errors=True)

    if ok:
        print("\ncheck-entry: o app tem entry point e delegate validos.")
        return 0
    print("\ncheck-entry: ESTE APP NAO VAI INICIAR CORRETAMENTE.")
    print("Ver references/WARNINGS-FATAIS.md e assets/AppEntry.swift")
    return 1


if __name__ == "__main__":
    sys.exit(main())
