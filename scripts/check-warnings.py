#!/usr/bin/env python3
"""check-warnings.py — promove a ERRO os warnings do compilador que, neste
toolchain, significam "seu codigo NAO vai rodar".

MOTIVACAO (custou uma sessao inteira em 2026-08-22):
O SDK usado aqui tem `.swiftinterface` PATCHADOS. Isso muda assinaturas de
alguns membros de protocolo (ex.: `launchOptions` virou
`NSDictionary<NSString, AnyObject>?` em vez de `[LaunchOptionsKey: Any]?`).

Quando o requisito do protocolo e' OPCIONAL (`optional func`, comum em
delegates ObjC), uma assinatura que nao casa **nao e' erro**: o Swift emite
apenas
    warning: instance method 'X' nearly matches optional requirement 'X'
e trata seu metodo como um metodo comum da classe. O UIKit NUNCA o chama.

Resultado no device: o app ABRE, o processo fica VIVO, e a tela fica PRETA
para sempre — sem crash, sem log, sem sintoma que aponte para a causa.

Este script le o stderr do swift-frontend e falha o build nesses casos.

Uso:
  python3 check-warnings.py <arquivo.err> [mais.err ...]
  python3 check-warnings.py --dir <dir com *.err>

Saida: rc=0 se limpo; rc=1 e relatorio se houver warning fatal.
"""
import glob
import os
import re
import sys

# (regex do warning, explicacao, como corrigir)
FATAL_WARNINGS = [
    (
        r"nearly matches optional requirement '([^']+)' of protocol '([^']+)'",
        "O metodo NAO satisfaz o requisito do protocolo (assinatura diferente da "
        "declarada no .swiftinterface patchado). Como o requisito e' OPCIONAL, o "
        "compilador so avisa — e o framework NUNCA chama o seu metodo. "
        "Sintoma no device: app abre e fica com TELA PRETA.",
        "Use a assinatura EXATA do interface do SDK. Para UIApplicationDelegate, "
        "prefira `applicationDidFinishLaunching(_ application: UIApplication)` "
        "(casa exatamente) em vez de "
        "`application(_:didFinishLaunchingWithOptions:)`. "
        "Confira com: python3 scripts/check-protocol-sig.py <Protocolo> <membro>",
    ),
    (
        r"instance method '([^']+)' nearly matches (?:optional )?requirement",
        "Idem: assinatura divergente de um requisito de protocolo.",
        "Ajuste a assinatura para a declarada no SDK.",
    ),
    (
        r"non-void function should return a value",
        "Fluxo sem retorno — pode indicar corpo degradado.",
        "Revise o corpo da funcao.",
    ),
    (
        r"result of call to '([^']+)' is unused",
        "Chamada cujo resultado foi descartado; em entry points "
        "(ex.: UIApplicationMain) isso pode indicar entry mal formado.",
        "Confirme que o valor nao era necessario.",
    ),
]

# warnings que sao RUIDO conhecido e nao devem falhar o build
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
    """Retorna lista de (linha_do_warning, contexto, explicacao, fix)."""
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
        # o compilador repete o warning nas linhas de "caret" (| `- warning:)
        if re.match(r"^\s*[\d\s]*\|", line):
            continue
        if any(re.search(p, line) for p in IGNORE):
            continue
        for pat, why, fix in FATAL_WARNINGS:
            m = re.search(pat, line)
            if m:
                # deduplica por (arquivo:linha, mensagem)
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
        print("ARQUIVO DE LOG: %s" % f)
        for line, ctx, why, fix in hits:
            print("-" * 72)
            print("WARNING FATAL: %s" % line)
            print("\nPOR QUE E' FATAL:\n  %s" % why)
            print("\nCOMO CORRIGIR:\n  %s" % fix)
            print("\nCONTEXTO:")
            for l in ctx.split("\n"):
                print("  " + l)

    if total:
        print("=" * 72)
        print("%d warning(s) FATAL(is). O build produziria um app que NAO funciona." % total)
        print("Leia references/WARNINGS-FATAIS.md")
        return 1
    print("check-warnings: nenhum warning fatal (%d log(s) analisado(s))" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
