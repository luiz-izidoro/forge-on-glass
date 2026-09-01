#!/usr/bin/env python3
# rebuild_uikit.py — retenta o swift_UIKit com -Onone + SwiftOnoneSupport explicito.
import sys, os
sys.argv = ['orchestrator_vm633.py']
os.chdir(os.path.expanduser('~/swift-ios-build'))
src = open('orchestrator_vm633.py').read()
# corta o script na definicao de build() -- reaproveita tudo ate o final do PASS,
# mas queremos SO as funcoes. Estrategia: importar via exec ate a marca de PRE-STEP.
head = src.split('# --- PRE-STEP ---')[0]
g = {'__name__': '__main__'}
exec(compile(head, 'orch_head', 'exec'), g)

OUT = g['OUT']; SF = g['SF']; index = g['index']; fix = g['fix']
have = g['have']; common_extra = g['common_extra']; run_build = g['run_build']
outpath = g['outpath']; SDK = g['SDK']

name = 'UIKit'; typ = 'swift'
cmd = index[(typ, name)]['details'][typ]['commandLine']
args = fix(cmd)
for m in ('Security', 'CFNetwork', 'SystemConfiguration', 'UIUtilities'):
    if have('clang', m):
        args += ["-import-module", m]
for m in ('CoreFoundation', 'QuartzCore', 'CoreGraphics', 'CoreText', 'os', 'Dispatch'):
    if have('clang', m):
        args += ["-import-module", m]

MODE = sys.argv[1] if len(sys.argv) > 1 else 'onone'
if MODE == 'onone':
    args += ["-Onone"]
    so = outpath('swift', 'SwiftOnoneSupport')
    if os.path.exists(so):
        args += [f"-swift-module-file=SwiftOnoneSupport={so}"]

for fw in ('Foundation', 'CoreFoundation', 'UIKit', 'CoreGraphics', 'CoreText',
           'CDispatch', 'ptrauth', 'Security', 'CFNetwork', 'SystemConfiguration'):
    mm = f"{SDK}/System/Library/Frameworks/{fw}.framework/Modules/module.modulemap"
    if os.path.exists(mm):
        args += ["-Xcc", f"-fmodule-map-file={mm}"]
args += common_extra()

# FIX: /tmp is a 1.9GB tmpfs on this VM -> the clang module cache filled it and
# the compiler died with "IO failure on output stream: Disk quota exceeded"
# (misdiagnosed as a SILGen crash). Move the cache to real disk.
BIGTMP = os.path.expanduser('~/bigtmp/impmc')
os.makedirs(BIGTMP, exist_ok=True)
args = [BIGTMP if a == '/tmp/impmc' else
        (a.replace('/tmp/impmc', BIGTMP) if '/tmp/impmc' in a else a)
        for a in args]

out = outpath(typ, name)
if os.path.exists(out):
    os.remove(out)
open('/tmp/uikit_cmd.txt', 'w').write(' '.join([SF] + args + ['-o', out]))
print('MODE=', MODE, flush=True)
ok = run_build(typ, name, args, wd=5400)
print('RESULT', ok, flush=True)
