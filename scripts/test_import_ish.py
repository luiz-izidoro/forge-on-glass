#!/usr/bin/env python3
"""test_import_ish.py — valida `import UIKit` / `import SwiftUI` NO iSH.

Versao iSH do test_import_uikit.py da VM. Usa os modulos explicitos de
/opt/ios-toolchain/foundation-build633 (construidos na VM com swift.org 6.3.3).

Uso: python3 test_import_ish.py [uikit|uikit_foundation|swiftui|swiftuicore]
"""
import os, sys, glob, subprocess

SW = '/opt/swift6.3.3'
SF = f'{SW}/usr/bin/swift-frontend'
SDK = '/opt/isb/sysroot/iPhoneOS26.5.sdk'
OUT = '/opt/ios-toolchain/foundation-build633'
VFS = '/opt/isb/sysroot/vfs/overlay.yaml'
BIG = '/var/tmp/isb-cache/user'
os.makedirs(BIG, exist_ok=True)

PROGS = {
    'uikit': '''import UIKit
public final class MyVC: UIViewController {
  public override func viewDidLoad() {
    super.viewDidLoad()
    let v = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
    v.backgroundColor = UIColor.systemBlue
    view.addSubview(v)
  }
}
''',
    'uikit_foundation': '''import UIKit
import Foundation
public func f() -> String {
  let d = Date()
  let items = [1, 2, 3].map { $0 * 2 }
  let v = UIView()
  v.tag = items.count
  let l = UILabel()
  l.text = "iSH pure Swift"
  return "\\(d.timeIntervalSince1970) \\(v.tag) \\(l.text ?? "")"
}
''',
    'swiftui': '''import SwiftUI
public struct MyView: View {
  public init() {}
  public var body: some View {
    VStack {
      Text("Hello from pure Swift on iSH")
        .font(.title)
        .foregroundColor(.blue)
      Button("Tap") { }
    }
  }
}
''',
    'swiftuicore': '''import SwiftUICore
public func g() -> Color { return Color.red }
''',
}

case = sys.argv[1] if len(sys.argv) > 1 else 'swiftui'
src = f'/tmp/user_{case}.swift'
open(src, 'w').write(PROGS[case])

args = [SF, '-frontend', '-c', '-target', 'arm64-apple-ios26.0', '-sdk', SDK,
        '-enable-objc-interop', '-swift-version', '5',
        '-disable-implicit-swift-modules', '-Xcc', '-fno-implicit-modules',
        '-Xcc', '-fno-implicit-module-maps',
        '-Xcc', '-ivfsoverlay', '-Xcc', VFS,
        '-module-name', 'UserApp', src]

# o overlay Swift do XPC cria ciclo os<->XPC / CoreText<->XPC
SKIP = {'XPC'}
for p in sorted(glob.glob(f'{OUT}/swift_*.swiftmodule')):
    n = os.path.basename(p)[len('swift_'):-len('.swiftmodule')]
    if n in SKIP:
        continue
    args += [f'-swift-module-file={n}={p}']
for p in sorted(glob.glob(f'{OUT}/clang_*.pcm')):
    n = os.path.basename(p)[len('clang_'):-len('.pcm')]
    args += ['-Xcc', f'-fmodule-file={n}={p}']
obj = f'/tmp/user_{case}.o'
args += ['-Xcc', f'-fmodules-cache-path={BIG}', '-Xcc', '-DCF_SWIFT_SENDABLE=',
         '-o', obj]

if os.path.exists(obj):
    os.remove(obj)
p = subprocess.run(args, capture_output=True, text=True)
sz = os.path.getsize(obj) if os.path.exists(obj) else 0
print(f'CASE {case} rc={p.returncode} obj={sz}')
for l in p.stderr.split('\n'):
    if 'error:' in l:
        print(' ', l[:200])
