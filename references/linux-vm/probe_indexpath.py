#!/usr/bin/env python3
# probe_indexpath.py — confirma se o segfault do SILGen e' o BRIDGING de
# Foundation.IndexPath num metodo @objc (e nao os stubs patchados do UIKit).
import os, subprocess, sys
os.chdir(os.path.expanduser('~/swift-ios-build'))
src = open('orchestrator_vm633.py').read().split('# --- PRE-STEP ---')[0]
g = {'__name__': '__main__'}
exec(compile(src, 'orch', 'exec'), g)
SF = g['SF']; index = g['index']; fix = g['fix']; have = g['have']
common_extra = g['common_extra']; SDK = g['SDK']; OUT = g['OUT']

IFACE = '/tmp/Probe.swiftinterface'
BODY = sys.argv[1] if len(sys.argv) > 1 else 'indexpath'
cases = {
 'generic': '''
@objc @_inheritsConvenienceInitializers open class GP<S, I> : ObjectiveC.NSObject where S : Swift.Hashable, I : Swift.Hashable {
  @objc open func g(_ cv: ObjectiveC.NSObject, cellForItemAt indexPath: IndexPath) -> ObjectiveC.NSObject { return cv }
  @objc override dynamic public init()
  @objc deinit
}''',

 # metodo @objc recebendo IndexPath (igual ao que crasha no UIKit)
 'indexpath': '''
@objc @_inheritsConvenienceInitializers open class P : ObjectiveC.NSObject {
  @objc open func f(_ p: IndexPath) -> Swift.Int { return 0 }
  @objc override dynamic public init()
  @objc deinit
}''',
 # controle: mesmo metodo mas SEM @objc (sem thunk de bridging)
 'noobjc': '''
open class P2 {
  open func f(_ p: IndexPath) -> Swift.Int { return 0 }
  public init()
}''',
 # controle: @objc com String (bridging conhecido/OK)
 'string': '''
@objc @_inheritsConvenienceInitializers open class P3 : ObjectiveC.NSObject {
  @objc open func f(_ s: Swift.String) -> Swift.Int { return 0 }
  @objc override dynamic public init()
  @objc deinit
}''',
}
header = '''// swift-interface-format-version: 1.0
// swift-compiler-version: Apple Swift version 6.3.2
// swift-module-flags: -target arm64-apple-ios26.0 -enable-objc-interop -enable-library-evolution -swift-version 5 -module-name Probe
import Foundation
import ObjectiveC
import Swift
import _Concurrency
'''
open(IFACE, 'w').write(header + cases[BODY] + '\n')

# reaproveita a linha de comando do UIKit, trocando entrada/module-name/saida
cmd = fix(index[('swift', 'UIKit')]['details']['swift']['commandLine'])
out_args, i = [], 0
while i < len(cmd):
    a = cmd[i]
    if a.endswith('.swiftinterface'):
        out_args.append(IFACE); i += 1; continue
    if a == '-module-name' or a == '-module-abi-name' or a == '-module-link-name' or a == '-user-module-version':
        i += 2; continue
    out_args.append(a); i += 1
args = out_args + ['-module-name', 'Probe']
for m in ('CoreFoundation', 'CoreGraphics', 'os', 'Dispatch'):
    if have('clang', m):
        args += ['-import-module', m]
args += common_extra()
BIG = os.path.expanduser('~/bigtmp/probe'); os.makedirs(BIG, exist_ok=True)
args = [a.replace('/tmp/impmc', BIG) for a in args]
outp = f'/tmp/Probe_{BODY}.swiftmodule'
p = subprocess.run([SF] + args + ['-o', outp], capture_output=True, text=True, env=g['ENV'])
print('CASE', BODY, 'rc=', p.returncode, 'size=', os.path.getsize(outp) if os.path.exists(outp) else 0)
errs = [l for l in p.stderr.split('\n') if 'error:' in l or 'While silgen' in l or 'Signal' in l]
print('\n'.join(errs[:8]))
