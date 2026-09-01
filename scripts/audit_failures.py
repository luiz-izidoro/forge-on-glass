#!/usr/bin/env python3
"""audit_failures.py — classifica CADA falha do probe_api.py pela sua SOLUCAO.

Motivacao: dizer "as 24 falhas sao cobertas pelo shim" e' impreciso. Este script
mede, para cada falha, qual e' o remedio REAL:

  IMPORT   -> nao e' degradacao: some com a ordem canonica de imports
  SHIM     -> resolvida por um helper do PureSwiftKit.swift (testado aqui)
  DUPLICATA-> o mesmo caso aparece 2x no catalogo
  ABERTA   -> sem solucao conhecida

Uso: python3 audit_failures.py
"""
import json, importlib.util, sys, os

spec = importlib.util.spec_from_file_location(
    "pa", "/var/minis/skills/ios-swift-builder/scripts/probe_api.py")
pa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pa)

RESULTS = '/tmp/probe_api_results.json'
if not os.path.exists(RESULTS):
    print('rode antes: python3 scripts/probe_api.py')
    sys.exit(1)

FULL = "Foundation|UIKit|CoreText|Dispatch"

# Para cada falha: (codigo equivalente usando o shim, ou None se for so import)
SHIM_FIX = {
    'CGRect.minX/maxX/midX':      'let r = cgRect(0,0,1,1); _ = r.cgMinX; _ = r.cgMaxX; _ = r.cgMidX',
    'CGRect.insetBy':             'let r = cgRect(0,0,1,1); _ = r.cgInsetBy(dx: 1, dy: 1)',
    'CGRect.offsetBy':            'let r = cgRect(0,0,1,1); _ = r.cgOffsetBy(dx: 1, dy: 1)',
    'CGRect.intersects':          'let r = cgRect(0,0,1,1); _ = r.cgIntersects(cgRect(0,0,1,1))',
    'CGRect.contains':            'let r = cgRect(0,0,1,1); _ = r.cgContains(cgPoint(0,0))',
    'CGRect.union':               'let r = cgRect(0,0,1,1); _ = r.cgUnion(cgRect(0,0,1,1))',
    'CGRect.zero':                '_ = cgRectZero',
    'CGPoint.zero':               '_ = cgPointZero',
    'CGSize.zero':                '_ = cgSizeZero',
    'CGAffineTransform.identity': '_ = cgAffineIdentity',
    'CGRect.width/.height':       'let r = cgRect(0,0,1,1); _ = r.cgWidth; _ = r.cgHeight',
    'CGRect.height/width':        'let r = cgRect(0,0,1,1); _ = r.cgHeight; _ = r.cgWidth',
    'TimeInterval c/ UIKit':      'let t: Seconds = 1; _ = t',
    'UIEdgeInsetsMake':           '_ = edgeInsets(1,2,3,4)',
    'FileManager c/ UIKit':       '_ = FS.exists("/tmp")',
    'FileManager c/ UIKit (instavel)': '_ = FS.listRecursive("/tmp")',
    'enumerator(atPath:)':        '_ = FS.listRecursive("/tmp")',
    'CGContext.move(to:)':        'let c = UIGraphicsGetCurrentContext()!; c.cgMove(to: cgPoint(1,1))',
    'CGContext.addLine(to:)':     'let c = UIGraphicsGetCurrentContext()!; c.cgAddLine(to: cgPoint(1,1))',
    'CGContext.setLineDash':      'let c = UIGraphicsGetCurrentContext()!; c.cgSetLineDash(phase: 0, lengths: [2,2])',
}

# falhas que somem apenas com a ordem canonica de imports (sem shim)
IMPORT_ONLY = {'NSAttributedString.Key', 'DispatchQueue sem import'}

results = json.load(open(RESULTS))
falhas = [x for x in results if not x['ok']]

# marca duplicatas (mesmo nome + mesmo codigo aparecendo 2x)
seen = {}
for f in falhas:
    key = (f['name'], f['code'])
    seen[key] = seen.get(key, 0) + 1

SHIM_SRC = open('/var/minis/skills/ios-swift-builder/assets/PureSwiftKit.swift').read()

print(f'{"CASO":38} {"CLASSE":10} VERIFICACAO')
print('-' * 92)
counts = {'IMPORT': 0, 'SHIM': 0, 'DUPLICATA': 0, 'ABERTA': 0}
done = set()

for f in falhas:
    name = f['name']
    key = (name, f['code'])
    if key in done:
        counts['DUPLICATA'] += 1
        print(f'{name:38} {"DUPLICATA":10} (mesmo caso ja contado)')
        continue
    done.add(key)

    if name in IMPORT_ONLY:
        ok, err = pa.probe(name, FULL, f['code'])
        counts['IMPORT'] += 1
        print(f'{name:38} {"IMPORT":10} ordem canonica -> {"OK" if ok else "AINDA FALHA: " + err[:30]}')
        continue

    fix = SHIM_FIX.get(name)
    if fix:
        # compila o snippet do shim JUNTO com o PureSwiftKit
        src = f'/tmp/audit_case.swift'
        open(src, 'w').write(
            "import Foundation\nimport UIKit\nimport CoreText\nimport Dispatch\n"
            f"func caso() {{ {fix} }}\n")
        import subprocess
        r = subprocess.run(
            ['/var/minis/skills/ios-swift-builder/scripts/probe_file.sh',
             src, '/var/minis/skills/ios-swift-builder/assets/PureSwiftKit.swift'],
            capture_output=True, text=True)
        ok = 'error:' not in r.stdout
        counts['SHIM'] += 1
        detail = 'OK' if ok else r.stdout.split('error:')[1][:40].strip()
        print(f'{name:38} {"SHIM":10} {fix[:34]:36} -> {detail}')
        continue

    counts['ABERTA'] += 1
    print(f'{name:38} {"ABERTA":10} {f["error"][:40]}')

print('-' * 92)
print(f'total de falhas: {len(falhas)}')
for k, v in counts.items():
    print(f'  {k:10} {v}')
