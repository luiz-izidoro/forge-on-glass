#!/usr/bin/env python3
"""rebuild_clean.py — reconstroi modulos SEM os -import-module extras.

CAUSA RAIZ (2026-08-19, sessao 3): os modulos construidos com as flags
`-import-module Foundation/CoreFoundation/...` acabam gravando no .swiftmodule
uma visao de Foundation que QUEBRA o bridging String<->NSString em qualquer
arquivo do usuario que os importe:

    import Foundation
    import Symbols        // ou Accessibility, ou DataDetection
    let s: NSString = "x" // error: cannot convert 'String' to 'NSString'

Sem esses modulos no import, o bridging funciona normalmente.

Uso: python3 rebuild_clean.py Symbols Accessibility DataDetection
"""
import os, sys

os.chdir(os.path.expanduser('~/swift-ios-build'))
SCAN = '/tmp/fscan_swiftui.json'
src = open('orchestrator_vm633.py').read().split('# --- PRE-STEP ---')[0]
src = src.replace('"/tmp/fscan.json"', repr(SCAN)).replace("'/tmp/fscan.json'", repr(SCAN))
g = {'__name__': '__main__'}
exec(compile(src, 'orch', 'exec'), g)
SDK, OUT = g['SDK'], g['OUT']
index, have, outpath = g['index'], g['have'], g['outpath']
fix, common_extra, run_build = g['fix'], g['common_extra'], g['run_build']
BIG = os.path.expanduser('~/bigtmp/impmc')
os.makedirs(BIG, exist_ok=True)

names = sys.argv[1:] or ['Symbols', 'Accessibility', 'DataDetection']
for name in names:
    if ('swift', name) not in index:
        print(f'[{name}] nao esta no scan', flush=True)
        continue
    out = outpath('swift', name)
    if os.path.exists(out):
        os.rename(out, out + '.with-imports')
    args = fix(index[('swift', name)]['details']['swift']['commandLine'])
    args = [a for a in args if not a.startswith('-swift-module-file=XPC=')]
    args += ['-Onone']
    so = outpath('swift', 'SwiftOnoneSupport')
    if os.path.exists(so):
        args += [f'-swift-module-file=SwiftOnoneSupport={so}']
    args += ['-enable-cross-import-overlays']
    # SEM -import-module; apenas os modulemaps (que nao afetam o bridging)
    for fw in ('Foundation', 'CoreFoundation', 'CoreGraphics', 'CoreText', 'UIKit'):
        mm = f'{SDK}/System/Library/Frameworks/{fw}.framework/Modules/module.modulemap'
        if os.path.exists(mm):
            args += ['-Xcc', f'-fmodule-map-file={mm}']
    args += common_extra()
    args = [a.replace('/tmp/impmc', BIG) for a in args]
    ok = run_build('swift', name, args, wd=5400)
    if not ok and os.path.exists(out + '.with-imports'):
        os.rename(out + '.with-imports', out)
        print(f'[{name}] revertido', flush=True)
        err = open(f'{OUT}/swift_{name}.err').read()
        for l in err.split('\n'):
            if 'error:' in l:
                print('   ', l[:180], flush=True)
                break
