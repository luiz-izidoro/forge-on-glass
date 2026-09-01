#!/usr/bin/env python3
"""fix_loop.py — resolve iterativamente os erros de um .swiftinterface.

Compila, le o PRIMEIRO erro, aplica a correcao conhecida, repete. Cada regra
implementa um dos mecanismos ja bissectados (ESTADO-E-NEXT-STEPS.md §2).
Grava tudo em fixlog.json para reproducao posterior.

Uso: python3 fix_loop.py <ModuleName> [max_iters]
"""
import os, re, sys, json, subprocess

os.chdir(os.path.expanduser('~/swift-ios-build'))
SCAN = '/tmp/fscan_swiftui.json'
src = open('orchestrator_vm633.py').read().split('# --- PRE-STEP ---')[0]
src = src.replace('"/tmp/fscan.json"', repr(SCAN)).replace("'/tmp/fscan.json'", repr(SCAN))
g = {'__name__': '__main__'}
exec(compile(src, 'orch', 'exec'), g)
SDK, OUT = g['SDK'], g['OUT']
index, have, outpath = g['index'], g['have'], g['outpath']
fix, common_extra, run_build = g['fix'], g['common_extra'], g['run_build']
BIG = os.path.expanduser('~/bigtmp/impmc'); os.makedirs(BIG, exist_ok=True)

NAME = sys.argv[1] if len(sys.argv) > 1 else 'SwiftUI'
MAX = int(sys.argv[2]) if len(sys.argv) > 2 else 40

IFACE = {
    'SwiftUI': f'{SDK}/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface',
}[NAME]

# tipos do Foundation que sao reexportados do clang e nao resolvem: mapa para
# o nome clang direto (mecanismo #1)
CLANG_NAMES = {
    'UndoManager': 'NSUndoManager',
    'Progress': 'NSProgress',
    'TimeInterval': 'NSTimeInterval',
    'Decimal': 'NSDecimalNumber',
    'PersonNameComponents': 'NSPersonNameComponents',
    'DateInterval': 'NSDateInterval',
    'URLRequest': 'NSURLRequest',
    'Notification': 'NSNotification',
    'AttributedString': 'NSAttributedString',
}


def build():
    out = outpath('swift', NAME)
    if os.path.exists(out):
        os.remove(out)
    args = fix(index[('swift', NAME)]['details']['swift']['commandLine'])
    args = [a for a in args if not a.startswith('-swift-module-file=XPC=')]
    args += ['-Onone']
    so = outpath('swift', 'SwiftOnoneSupport')
    if os.path.exists(so):
        args += [f'-swift-module-file=SwiftOnoneSupport={so}']
    args += ['-enable-cross-import-overlays']
    for fw in ('Foundation', 'CoreFoundation', 'UIKit', 'CoreGraphics', 'CoreText',
               'CoreData', 'CoreImage', 'Metal', 'CoreVideo', 'IOSurface', 'ImageIO'):
        mm = f'{SDK}/System/Library/Frameworks/{fw}.framework/Modules/module.modulemap'
        if os.path.exists(mm):
            args += ['-Xcc', f'-fmodule-map-file={mm}']
    args += common_extra()
    args = [a.replace('/tmp/impmc', BIG) for a in args]
    ok = run_build('swift', NAME, args, wd=5400)
    err = ''
    try:
        err = open(f'{OUT}/swift_{NAME}.err', 'rb').read().decode('utf8', 'ignore')
    except FileNotFoundError:
        pass
    return ok, err


def first_error(err):
    for l in err.split('\n'):
        if re.search(r':\d+:\d+: error:', l):
            return l
    for l in err.split('\n'):
        if 'error:' in l:
            return l
    return ''


log = []
for it in range(MAX):
    ok, err = build()
    if ok:
        print(f'=== SUCESSO na iteracao {it} ===', flush=True)
        break
    e = first_error(err)
    print(f'[{it}] {e[:190]}', flush=True)

    lines = open(IFACE).read().split('\n')
    applied = None

    m = re.search(r"cannot find type '(\w+)' in scope", e)
    if m and m.group(1) in CLANG_NAMES:
        t, repl = m.group(1), CLANG_NAMES[m.group(1)]
        new = re.sub(r'(?<![A-Za-z._])' + t + r'\b', repl, '\n'.join(lines))
        open(IFACE, 'w').write(new)
        applied = f'#1 {t} -> {repl} (global)'

    # mecanismo #8: o interface usa `Modulo.Tipo` mas nao tem `import Modulo`.
    # O erro sai como "cannot find type 'Modulo' in scope" (le o prefixo como tipo).
    if applied is None:
        m = re.search(r"cannot find type '(\w+)' in scope", e)
        if m and (os.path.exists(outpath('swift', m.group(1))) or os.path.exists(outpath('clang', m.group(1)))):
            mod = m.group(1)
            body = '\n'.join(lines)
            anchor = 'import Swift\n'
            if f'import {mod}\n' not in body and anchor in body:
                body = body.replace(anchor, f'import {mod}\n' + anchor, 1)
                open(IFACE, 'w').write(body)
                applied = f'#8 adicionado import {mod}'

    if applied is None:
        m = re.search(r"no type named '(\w+)' in module '(\w+)'", e)
        if m and m.group(1) in CLANG_NAMES:
            t, repl = m.group(1), CLANG_NAMES[t] if False else CLANG_NAMES[m.group(1)]
            body = '\n'.join(lines)
            body = body.replace(f'{m.group(2)}.{t}', repl)
            open(IFACE, 'w').write(body)
            applied = f'#1 {m.group(2)}.{t} -> {repl}'

    # mecanismo #2/#3: corpo @inlinable/@_alwaysEmitIntoClient quebrado ->
    # remover o corpo (a implementacao real vive no dylib do device)
    if applied is None:
        m = re.search(r':(\d+):\d+: error:', e)
        if m:
            ln = int(m.group(1)) - 1
            start = ln
            while start >= 0 and not re.search(r'@(_alwaysEmitIntoClient|inlinable)', lines[start]):
                if start < ln - 30:
                    start = -1
                    break
                start -= 1
            if start >= 0:
                depth, end = 0, start
                for i in range(start, min(start + 200, len(lines))):
                    depth += lines[i].count('{') - lines[i].count('}')
                    if depth == 0 and i > start and '{' in ''.join(lines[start:i + 1]):
                        end = i
                        break
                head = lines[start]
                head = re.sub(r'@_alwaysEmitIntoClient\s*', '', head)
                head = re.sub(r'@inlinable\s*', '', head)
                brace = head.find('{')
                if brace > 0:
                    head = head[:brace].rstrip()
                lines[start:end + 1] = [head]
                open(IFACE, 'w').write('\n'.join(lines))
                applied = f'#2 corpo removido linhas {start+1}-{end+1}'

    if applied is None:
        print('    !! sem regra automatica — parar e tratar a mao', flush=True)
        log.append({'iter': it, 'error': e, 'fix': None})
        break
    print(f'    -> {applied}', flush=True)
    log.append({'iter': it, 'error': e, 'fix': applied})

json.dump(log, open(f'/tmp/fixlog_{NAME}.json', 'w'), indent=1)
print(f'log em /tmp/fixlog_{NAME}.json ({len(log)} fixes)', flush=True)
