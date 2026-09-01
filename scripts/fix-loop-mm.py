#!/usr/bin/env python3
"""fix-loop-mm.py — loop de build reativo para o modo MULTI-MODULO.

##########################################################################
## DEPRECADO (2026-08-23) — serve apenas ao build-multimodule.sh, que   ##
## foi descontinuado por PRODUZIR APPS QUEBRADOS (um modulo importado   ##
## degrada o bridging String<->NSString no modulo do app).             ##
##                                                                      ##
## Nao use em codigo novo. O loop reativo do caminho atual esta em      ##
## scripts/port-third-party.py.                                         ##
## Ver: references/TYPECHECKER-E-MULTIMODULO.md secao 0.1               ##
##########################################################################

Compila um alvo (script sh que grava <alvo>.err), le TODOS os erros do disco,
aplica fixes automaticos e repete. Reaproveita as regras validadas do
port-third-party.py, adaptadas ao contexto multi-modulo.

Uso: python3 fix-loop-mm.py <build.sh> <step: dep|app> <err_file> <src_dir> [max_iter]
"""
import os, re, subprocess, sys, glob

# ordem canonica de imports (PURE-SWIFT-UI-STATUS.md §4.0)
ORDER = ["Foundation", "SwiftUI", "UIKit", "CoreText", "Dispatch", "Combine",
         "Darwin", "os", "ComposableArchitecture"]

# tipo -> modulo dono
TYPE_MODULE = {
    "NSRecursiveLock": "Foundation", "NSLock": "Foundation", "NSCondition": "Foundation",
    "Date": "Foundation", "URL": "Foundation", "Data": "Foundation", "UUID": "Foundation",
    "Bundle": "Foundation", "FileManager": "Foundation", "UserDefaults": "Foundation",
    "NSObject": "Foundation", "NotificationCenter": "Foundation", "RunLoop": "Foundation",
    "Thread": "Foundation", "JSONEncoder": "Foundation", "JSONDecoder": "Foundation",
    "DispatchQueue": "Dispatch", "DispatchTime": "Dispatch", "DispatchTimeInterval": "Dispatch",
    "DispatchWorkItem": "Dispatch", "DispatchGroup": "Dispatch",
    "AnyCancellable": "Combine", "PassthroughSubject": "Combine", "CurrentValueSubject": "Combine",
    "Publisher": "Combine", "Published": "Combine", "ObservableObject": "Combine",
    "AnyPublisher": "Combine", "Cancellable": "Combine", "Scheduler": "Combine",
    "SchedulerTimeIntervalConvertible": "Combine", "Subscribers": "Combine",
    "Subscription": "Combine", "Subject": "Combine", "Just": "Combine", "Empty": "Combine",
    "UIView": "UIKit", "UIViewController": "UIKit", "UIColor": "UIKit", "UIFont": "UIKit",
    "UIApplication": "UIKit", "UIWindow": "UIKit", "UIScreen": "UIKit", "UIAlertController": "UIKit",
    "UITextField": "UIKit", "UIImage": "UIKit",
    "View": "SwiftUI", "Binding": "SwiftUI", "Color": "SwiftUI", "Text": "SwiftUI",
    "ViewModifier": "SwiftUI", "Animation": "SwiftUI", "Font": "SwiftUI",
    "NSAttributedString": "CoreText",
}


def read_errors(err_file):
    if not os.path.exists(err_file):
        return []
    txt = open(err_file, errors="replace").read()
    out = []
    for m in re.finditer(r"^(/[^\s:]+\.swift):(\d+):(\d+): error: (.+)$", txt, re.M):
        out.append({"file": m.group(1), "line": int(m.group(2)),
                    "col": int(m.group(3)), "msg": m.group(4).strip()})
    return out


def imports_of(lines):
    return {l.strip()[7:].strip() for l in lines[:80] if l.strip().startswith("import ")}


def ensure_import(path, mod):
    """Insere `import mod` respeitando a ordem canonica. True se mudou."""
    lines = open(path, errors="replace").read().split("\n")
    if mod in imports_of(lines):
        return False
    rank = ORDER.index(mod) if mod in ORDER else len(ORDER)
    idx_ins = None
    last_imp = None
    for i, l in enumerate(lines[:80]):
        s = l.strip()
        if s.startswith("import "):
            last_imp = i
            m = s[7:].strip()
            r = ORDER.index(m) if m in ORDER else len(ORDER)
            if r > rank and idx_ins is None:
                idx_ins = i
    if idx_ins is None:
        if last_imp is not None:
            idx_ins = last_imp + 1
        else:
            idx_ins = 0
            while idx_ins < len(lines) and (lines[idx_ins].startswith("//")
                                            or lines[idx_ins].strip() == ""):
                idx_ins += 1
    lines.insert(idx_ins, "import " + mod)
    open(path, "w").write("\n".join(lines))
    return True


def fix_errors(errors, log):
    """Aplica fixes. Retorna (n_fixes, unresolved)."""
    n = 0
    unresolved = []
    done = set()
    for e in errors:
        f, msg = e["file"], e["msg"]
        if not os.path.exists(f):
            unresolved.append(e); continue
        key = (f, e["line"], msg)
        if key in done:
            continue
        done.add(key)

        # (a) cannot find 'X' / cannot find type 'X' in scope -> import do dono
        m = re.match(r"cannot find(?: type)? '([\w.]+)' in scope", msg)
        if m:
            t = m.group(1).split(".")[0]
            mod = TYPE_MODULE.get(t)
            if mod and ensure_import(f, mod):
                log.append(f"import {mod} -> {os.path.basename(f)} (por '{t}')")
                n += 1; continue
            unresolved.append(e); continue

        # (b) 'X' is not a member type of / has no member 'Y' com DispatchQueue
        if "is not a member type of class 'Foundation.DispatchQueue'" in msg or \
           ("value of type 'DispatchQueue'" in msg and "has no member" in msg):
            if ensure_import(f, "Dispatch"):
                log.append(f"import Dispatch -> {os.path.basename(f)}")
                n += 1; continue

        # (c) NSRecursiveLock/NSLock sem member (extension noutro arquivo do MESMO modulo
        #     e' visivel; se nao for, e' falta de Foundation)
        m = re.match(r"value of type '(\w+)' has no member '(\w+)'", msg)
        if m and m.group(1) in TYPE_MODULE:
            if ensure_import(f, TYPE_MODULE[m.group(1)]):
                log.append(f"import {TYPE_MODULE[m.group(1)]} -> {os.path.basename(f)}")
                n += 1; continue

        # (d) description/String vs NSString: Foundation ausente ou fora de ordem
        if ("cannot override a property with type 'NSString'" in msg
                or "ambiguous use of 'description'" in msg
                or "'String' to 'NSString'" in msg):
            if ensure_import(f, "Foundation"):
                log.append(f"import Foundation (NSString) -> {os.path.basename(f)}")
                n += 1; continue

        # (e) TimeInterval com Foundation presente -> Double
        if re.search(r"cannot find type 'TimeInterval'", msg):
            lines = open(f, errors="replace").read().split("\n")
            i = e["line"] - 1
            if 0 <= i < len(lines) and "TimeInterval" in lines[i]:
                lines[i] = lines[i].replace("TimeInterval", "Double")
                open(f, "w").write("\n".join(lines))
                log.append(f"TimeInterval->Double {os.path.basename(f)}:{e['line']}")
                n += 1; continue

        unresolved.append(e)
    return n, unresolved


def main():
    if len(sys.argv) < 5:
        print(__doc__); sys.exit(2)
    build, step, err_file, src_dir = sys.argv[1:5]
    maxit = int(sys.argv[5]) if len(sys.argv) > 5 else 12
    log = []
    for it in range(1, maxit + 1):
        print(f"=== iteracao {it} ===", flush=True)
        rc = subprocess.call(["sh", build, step])
        if rc == 0:
            print("BUILD OK")
            for l in log: print("  fix:", l)
            return 0
        errors = read_errors(err_file)
        if not errors:
            print(f"rc={rc} sem erros no .err (OOM/race) -> retry")
            continue
        print(f"  {len(errors)} erros")
        n, unresolved = fix_errors(errors, log)
        print(f"  {n} fixes aplicados, {len(unresolved)} sem regra")
        if n == 0:
            print("SEM PROGRESSO. Erros restantes:")
            seen = set()
            for e in unresolved[:25]:
                k = e["msg"][:90]
                if k in seen: continue
                seen.add(k)
                print(f"  {os.path.basename(e['file'])}:{e['line']}: {e['msg'][:150]}")
            return 1
    print("max iteracoes")
    return 1


if __name__ == "__main__":
    sys.exit(main())
