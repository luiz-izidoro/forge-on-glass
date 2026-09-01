#!/usr/bin/env python3
"""build_swiftui.py — constroi os modulos que faltam para `import SwiftUI`.

Reaproveita TODA a logica do orchestrator_vm633.py (funcoes fix/build/run_build),
mas com o scan novo (/tmp/fscan_swiftui.json, 92 modulos) e build incremental:
so constroi o que ainda nao existe em foundation-build633.

LICOES JA EMBUTIDAS (2026-08-19):
 - module cache NUNCA em /tmp (tmpfs 1,9GB) -> ~/bigtmp
 - -Onone + -swift-module-file=SwiftOnoneSupport nos modulos swift
 - -enable-cross-import-overlays (xtool issue #152: SwiftUI+MapKit)
 - patch de @objc em subclasses genericas aplicado ANTES (patch_uikit_generic_objc.py)
"""
import os, sys, json, subprocess, time

os.chdir(os.path.expanduser('~/swift-ios-build'))
SCAN = '/tmp/fscan_swiftui.json'

src = open('orchestrator_vm633.py').read().split('# --- PRE-STEP ---')[0]
src = src.replace('"/tmp/fscan.json"', repr(SCAN)).replace("'/tmp/fscan.json'", repr(SCAN))
g = {'__name__': '__main__'}
exec(compile(src, 'orch_head', 'exec'), g)

SF, SDK, OUT = g['SF'], g['SDK'], g['OUT']
index, deps = g['index'], g['deps']
have, outpath, fix = g['have'], g['outpath'], g['fix']
common_extra, run_build = g['common_extra'], g['run_build']

BIG = os.path.expanduser('~/bigtmp/impmc')
os.makedirs(BIG, exist_ok=True)


def build_one(typ, name, wd=5400):
    if have(typ, name):
        return True
    ent = index.get((typ, name))
    if not ent:
        print(f'[{typ}:{name}] SKIP (nao esta no scan)', flush=True)
        return True
    cmd = ent['details'][typ].get('commandLine')
    if not cmd:
        print(f'[{typ}:{name}] SKIP (sem commandLine)', flush=True)
        return True
    args = fix(cmd)
    if typ == 'swift':
        # LICAO 2026-08-19: o overlay Swift do XPC cria "circular dependency
        # between modules 'os' and 'XPC'" (os e XPC vieram de scans diferentes e
        # cada um lista o outro). Os consumidores so precisam do clang XPC.pcm.
        args = [a for a in args if not a.startswith('-swift-module-file=XPC=')]
        # LICAO 2026-08-19: os -import-module criam "circular dependency between
        # modules 'os' and 'XPC'/'CoreText'" nos modulos NOVOS (CoreData, SwiftUI).
        # Eles so eram necessarios para os modulos da leva anterior, que ja estao
        # construidos. Por isso: aplicar SOMENTE a uma allowlist.
        NEEDS_IMPORTS = {'Accessibility', 'CoreText', 'SwiftUICore', 'UIKit',
                         'DataDetection', 'CoreTransferable', 'Symbols', 'QuartzCore',
                         'DeveloperToolsSupport', 'OSLog', 'UniformTypeIdentifiers'}
        if name in NEEDS_IMPORTS:
            for m in ('Security', 'CFNetwork', 'SystemConfiguration', 'UIUtilities'):
                if have('clang', m):
                    args += ['-import-module', m]
            for m in ('CoreFoundation', 'QuartzCore', 'CoreGraphics', 'CoreText', 'os', 'Dispatch'):
                if have('clang', m):
                    args += ['-import-module', m]
        args += ['-Onone']
        so = outpath('swift', 'SwiftOnoneSupport')
        if os.path.exists(so):
            args += [f'-swift-module-file=SwiftOnoneSupport={so}']
        # xtool issue #152: cross-import overlays (_MapKit_SwiftUI etc)
        args += ['-enable-cross-import-overlays']
        for fw in ('Foundation', 'CoreFoundation', 'UIKit', 'CoreGraphics', 'CoreText',
                   'CDispatch', 'ptrauth', 'Security', 'CFNetwork', 'SystemConfiguration',
                   'CoreData', 'CoreImage', 'Metal', 'CoreVideo', 'IOSurface', 'ImageIO'):
            mm = f'{SDK}/System/Library/Frameworks/{fw}.framework/Modules/module.modulemap'
            if os.path.exists(mm):
                args += ['-Xcc', f'-fmodule-map-file={mm}']
    args += common_extra()
    args = [a.replace('/tmp/impmc', BIG) for a in args]
    return run_build(typ, name, args, wd)


# --- ordem topologica a partir dos alvos ---
visited, order = set(), []


def visit(node):
    if node in visited:
        return
    visited.add(node)
    for d in deps.get(node, []):
        visit(d)
    order.append(node)


targets = [('swift', 'SwiftUI')]
if len(sys.argv) > 1:
    targets = [tuple(a.split(':')) for a in sys.argv[1:]]
for t in targets:
    visit(t)

todo = [(t, n) for (t, n) in order if not have(t, n) and n != 'fscan_swiftui']
print(f'=== {len(todo)} modulos a construir ===', flush=True)
print([f'{t}:{n}' for t, n in todo], flush=True)

failed = []
for typ, name in todo:
    if not build_one(typ, name):
        failed.append(f'{typ}:{name}')

print('=== FIM ===', flush=True)
print('FAILED:', failed if failed else 'nenhum', flush=True)
print('SwiftUI ok?', have('swift', 'SwiftUI'), flush=True)
