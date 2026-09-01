#!/usr/bin/env python3
"""bisect_bridge.py — acha o conjunto MINIMO de -import-module que (a) compila o
modulo e (b) NAO quebra o bridging String<->NSString nos consumidores.

CONTEXTO: modulos construidos com `-import-module X` gravam no .swiftmodule uma
visao de Foundation que quebra `let s: NSString = "x"` em qualquer arquivo que
os importe. Mas UIKit/SwiftUICore nao compilam sem algum -import-module.
Este script cruza as duas coisas.

Uso: python3 bisect_bridge.py UIKit
"""
import os, sys, glob, subprocess, itertools

os.chdir(os.path.expanduser('~/swift-ios-build'))
SCAN = '/tmp/fscan_swiftui.json'
src = open('orchestrator_vm633.py').read().split('# --- PRE-STEP ---')[0]
src = src.replace('"/tmp/fscan.json"', repr(SCAN)).replace("'/tmp/fscan.json'", repr(SCAN))
g = {'__name__': '__main__'}
exec(compile(src, 'orch', 'exec'), g)
SF, SDK, OUT, VFS, ENV = g['SF'], g['SDK'], g['OUT'], g['VFS'], g['ENV']
index, have, outpath = g['index'], g['have'], g['outpath']
fix, common_extra, run_build = g['fix'], g['common_extra'], g['run_build']
BIG = os.path.expanduser('~/bigtmp/impmc')
os.makedirs(BIG, exist_ok=True)

NAME = sys.argv[1] if len(sys.argv) > 1 else 'UIKit'

# candidatos, do menos ao mais invasivo
CANDIDATES = [
    [],
    ['UIUtilities'],
    ['CoreFoundation'],
    ['UIUtilities', 'CoreFoundation'],
    ['UIUtilities', 'CoreFoundation', 'CoreGraphics'],
    ['UIUtilities', 'CoreFoundation', 'CoreGraphics', 'QuartzCore'],
    ['Security', 'CFNetwork', 'SystemConfiguration', 'UIUtilities'],
    ['Security', 'CFNetwork', 'SystemConfiguration', 'UIUtilities',
     'CoreFoundation', 'QuartzCore', 'CoreGraphics', 'CoreText', 'os', 'Dispatch'],
]

BRIDGE_SRC = '/tmp/bridge_probe.swift'
open(BRIDGE_SRC, 'w').write(f'''import Foundation
import {NAME}
public func f() {{
  let s: NSString = "xyz"
  print(s.length)
}}
''')


def build(imports):
    out = outpath('swift', NAME)
    if os.path.exists(out):
        os.remove(out)
    args = fix(index[('swift', NAME)]['details']['swift']['commandLine'])
    args = [a for a in args if not a.startswith('-swift-module-file=XPC=')]
    for m in imports:
        if have('clang', m):
            args += ['-import-module', m]
    args += ['-Onone']
    so = outpath('swift', 'SwiftOnoneSupport')
    if os.path.exists(so):
        args += [f'-swift-module-file=SwiftOnoneSupport={so}']
    args += ['-enable-cross-import-overlays']
    for fw in ('Foundation', 'CoreFoundation', 'UIKit', 'CoreGraphics', 'CoreText',
               'CDispatch', 'ptrauth', 'Security', 'CFNetwork', 'SystemConfiguration',
               'CoreData', 'CoreImage', 'Metal', 'CoreVideo', 'IOSurface', 'ImageIO'):
        mm = f'{SDK}/System/Library/Frameworks/{fw}.framework/Modules/module.modulemap'
        if os.path.exists(mm):
            args += ['-Xcc', f'-fmodule-map-file={mm}']
    args += common_extra()
    args = [a.replace('/tmp/impmc', BIG) for a in args]
    return run_build('swift', NAME, args, wd=5400)


def bridge_ok():
    args = [SF, '-frontend', '-c', '-target', 'arm64-apple-ios26.0', '-sdk', SDK,
            '-enable-objc-interop', '-swift-version', '5',
            '-disable-implicit-swift-modules', '-Xcc', '-fno-implicit-modules',
            '-Xcc', '-fno-implicit-module-maps',
            '-Xcc', '-ivfsoverlay', '-Xcc', VFS,
            '-module-name', 'BridgeProbe', BRIDGE_SRC]
    for p in sorted(glob.glob(f'{OUT}/swift_*.swiftmodule')):
        n = os.path.basename(p)[len('swift_'):-len('.swiftmodule')]
        if n == 'XPC':
            continue
        args += [f'-swift-module-file={n}={p}']
    for p in sorted(glob.glob(f'{OUT}/clang_*.pcm')):
        n = os.path.basename(p)[len('clang_'):-len('.pcm')]
        args += ['-Xcc', f'-fmodule-file={n}={p}']
    args += ['-Xcc', f'-fmodules-cache-path={BIG}', '-Xcc', '-DCF_SWIFT_SENDABLE=',
             '-o', '/tmp/bridge_probe.o']
    if os.path.exists('/tmp/bridge_probe.o'):
        os.remove('/tmp/bridge_probe.o')
    p = subprocess.run(args, capture_output=True, text=True, env=ENV)
    return p.returncode == 0, [l for l in p.stderr.split('\n') if 'error:' in l][:2]


for imports in CANDIDATES:
    print(f'\n=== imports={imports} ===', flush=True)
    if not build(imports):
        err = open(f'{OUT}/swift_{NAME}.err').read()
        first = next((l for l in err.split('\n') if 'error:' in l), '')
        print(f'  BUILD FAIL: {first[:160]}', flush=True)
        continue
    ok, errs = bridge_ok()
    print(f'  BUILD OK | bridging: {"OK" if ok else "QUEBRADO"}', flush=True)
    if ok:
        print(f'*** SOLUCAO: {NAME} com imports={imports}', flush=True)
        sys.exit(0)
    for e in errs:
        print(f'    {e[:150]}', flush=True)
print('\n*** nenhuma combinacao resolve os dois', flush=True)
