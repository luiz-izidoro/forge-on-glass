#!/usr/bin/env python3
"""probe_api.py — testa, UMA A UMA, se uma API compila em Swift puro no iSH.

Serve para MAPEAR a superficie real das degradacoes: em vez de escrever um app
gigante e ficar cego a cada erro, cada snippet e' compilado isoladamente e o
resultado (OK / erro exato) vai para uma tabela.

Uso: python3 probe_api.py            # roda o catalogo embutido
     python3 probe_api.py <arquivo>  # roda um catalogo custom (formato abaixo)

Formato do catalogo (TSV): nome<TAB>imports<TAB>codigo
"""
import os, sys, glob, subprocess, json

SW = '/opt/swift6.3.3'
SF = f'{SW}/usr/bin/swift-frontend'
SDK = '/opt/isb/sysroot/iPhoneOS26.5.sdk'
OUT = '/opt/ios-toolchain/foundation-build633'
VFS = '/opt/isb/sysroot/vfs/overlay.yaml'
BIG = '/var/tmp/isb-cache/probe'
os.makedirs(BIG, exist_ok=True)

# (nome, imports, corpo) — o corpo roda dentro de `func f() { ... }`
CATALOG = [
    # --- CGRect / CoreGraphics (corpos @inlinable reescritos nos patches) ---
    ("CGRect.origin/size",        "Foundation|UIKit", 'var r = CGRect(); r.origin.x = 1; _ = r.size.width'),
    ("CGRect.minX/maxX/midX",     "Foundation|UIKit", 'let r = CGRect(); _ = r.minX; _ = r.maxX; _ = r.midX'),
    ("CGRect.insetBy",            "Foundation|UIKit", 'let r = CGRect(); _ = r.insetBy(dx: 1, dy: 1)'),
    ("CGRect.offsetBy",           "Foundation|UIKit", 'let r = CGRect(); _ = r.offsetBy(dx: 1, dy: 1)'),
    ("CGRect.intersects",         "Foundation|UIKit", 'let r = CGRect(); _ = r.intersects(CGRect())'),
    ("CGRect.contains",           "Foundation|UIKit", 'let r = CGRect(); _ = r.contains(CGPoint())'),
    ("CGRect.union",              "Foundation|UIKit", 'let r = CGRect(); _ = r.union(CGRect())'),
    ("CGRect.zero",               "Foundation|UIKit", '_ = CGRect.zero'),
    ("CGPoint.zero",              "Foundation|UIKit", '_ = CGPoint.zero'),
    ("CGSize.zero",               "Foundation|UIKit", '_ = CGSize.zero'),
    ("CGSize(width:height:)",     "Foundation|UIKit", '_ = CGSize(width: 1, height: 2)'),
    ("CGPoint(x:y:)",             "Foundation|UIKit", '_ = CGPoint(x: 1, y: 2)'),
    ("CGAffineTransform.identity","Foundation|UIKit", '_ = CGAffineTransform.identity'),
    ("CGFloat aritmetica",        "Foundation|UIKit", 'let a: CGFloat = 1.5; _ = a * 2 + 1'),

    # --- Foundation nucleo ---
    ("Date/TimeInterval",         "Foundation",       'let d = Date(); _ = d.addingTimeInterval(60)'),
    ("JSONSerialization",         "Foundation",       '_ = try? JSONSerialization.data(withJSONObject: ["a": 1])'),
    ("JSONEncoder/Codable",       "Foundation",       'struct S: Codable { let a: Int }; _ = try? JSONEncoder().encode(S(a: 1))'),
    ("URL/URLComponents",         "Foundation",       'let u = URL(string: "https://a.b/c?d=1"); _ = URLComponents(string: "https://a.b")'),
    ("DateFormatter",             "Foundation",       'let f = DateFormatter(); f.dateFormat = "yyyy"; _ = f.string(from: Date())'),
    ("NumberFormatter",           "Foundation",       'let f = NumberFormatter(); _ = f.string(from: NSNumber(value: 1))'),
    ("NotificationCenter (Fnd)",  "Foundation",       '_ = NotificationCenter.default'),
    ("NotificationCenter (UIKit)","Foundation|UIKit", '_ = NotificationCenter.default'),
    ("Notification.Name",         "Foundation|UIKit", '_ = Notification.Name("x")'),
    ("NSLock",                    "Foundation",       'let l = NSLock(); l.lock(); l.unlock()'),
    ("FileManager",               "Foundation",       '_ = FileManager.default.temporaryDirectory'),
    ("UserDefaults",              "Foundation",       '_ = UserDefaults.standard'),
    ("NSAttributedString",        "Foundation|UIKit", '_ = NSAttributedString(string: "a", attributes: [.foregroundColor: UIColor.red])'),
    ("NSAttributedString.Key",    "Foundation|UIKit", '_ = NSAttributedString.Key.foregroundColor'),
    ("String as NSString",        "Foundation",       'let s = "a" as NSString; _ = s.length'),
    ("IndexPath",                 "Foundation|UIKit", '_ = IndexPath(item: 0, section: 0)'),

    # --- Dispatch / concorrencia ---
    ("DispatchQueue.main",        "Foundation|Dispatch", '_ = DispatchQueue.main'),
    ("DispatchQueue.global",      "Foundation|Dispatch", '_ = DispatchQueue.global()'),
    ("DispatchQueue(label:)",     "Foundation|Dispatch", '_ = DispatchQueue(label: "x")'),
    ("DispatchGroup",             "Foundation|Dispatch", 'let g = DispatchGroup(); g.enter(); g.leave()'),
    ("DispatchSemaphore",         "Foundation|Dispatch", '_ = DispatchSemaphore(value: 0)'),
    ("DispatchQueue sem import",  "Foundation|UIKit",    '_ = DispatchQueue.main'),

    # --- UIKit comum ---
    ("UIView/UIColor",            "Foundation|UIKit", 'let v = UIView(); v.backgroundColor = UIColor.red'),
    ("UILabel.text (String)",     "Foundation|UIKit", 'let l = UILabel(); l.text = "abc"'),
    ("UIButton.setTitle",         "Foundation|UIKit", 'UIButton(type: .system).setTitle("a", for: .normal)'),
    ("UIFont",                    "Foundation|UIKit", '_ = UIFont.systemFont(ofSize: 12)'),
    ("CALayer",                   "Foundation|UIKit", 'let v = UIView(); v.layer.cornerRadius = 2'),
    ("UIStackView",               "Foundation|UIKit", 'let s = UIStackView(arrangedSubviews: [UIView()]); s.axis = .vertical'),
    ("NSLayoutConstraint/anchors","Foundation|UIKit", 'let a = UIView(); let b = UIView(); _ = a.centerXAnchor.constraint(equalTo: b.centerXAnchor)'),
    ("UIGestureRecognizer",       "Foundation|UIKit", 'UIView().addGestureRecognizer(UITapGestureRecognizer())'),
    ("UIBezierPath",              "Foundation|UIKit", '_ = UIBezierPath(roundedRect: CGRect(), cornerRadius: 2)'),
    ("UIScrollView",              "Foundation|UIKit", 'let s = UIScrollView(); s.contentOffset = CGPoint()'),
    ("UITableView",               "Foundation|UIKit", '_ = UITableView(frame: CGRect(), style: .plain)'),
    ("UIImage/UIImageView",       "Foundation|UIKit", '_ = UIImageView(image: UIImage())'),
    ("UIViewController ciclo",    "Foundation|UIKit", 'class V: UIViewController { override func viewDidLoad() { super.viewDidLoad() } }; _ = V()'),
    ("UIAlertController",         "Foundation|UIKit", '_ = UIAlertController(title: "a", message: "b", preferredStyle: .alert)'),

    # --- as 3 classes genericas que perderam @objc ---
    ("DiffableDataSource tipo",   "Foundation|UIKit", 'typealias DS = UICollectionViewDiffableDataSource<Int, Int>; _ = DS.self'),
    ("NSDiffableDataSourceSnapshot","Foundation|UIKit", 'var s = NSDiffableDataSourceSnapshot<Int, Int>(); s.appendSections([0]); s.appendItems([1])'),
    ("UITableViewDiffableDataSource","Foundation|UIKit", 'typealias DS = UITableViewDiffableDataSource<Int, Int>; _ = DS.self'),

    # --- Swift stdlib ---
    ("Generics",                  "Foundation",       'func m<T: Comparable>(_ x: [T]) -> T? { x.max() }; _ = m([1,2])'),
    ("KeyPath",                   "Foundation",       'struct S { let a = 1 }; _ = S()[keyPath: \\S.a]'),
    ("Result/throws",             "Foundation",       'enum E: Error { case e }; _ = Result { throw E.e }'),
    ("async/await decl",          "Foundation",       'func g() async -> Int { 1 }; _ = g'),
    ("Task",                      "Foundation",       '_ = Task { 1 }'),
    ("existencial any",           "Foundation",       'let x: [any CustomStringConvertible] = [1, "a"]; _ = x.count'),

    # --- degradacoes catalogadas nos BUG-REPORTS (sessao 6-7) ---
    ("TimeInterval (Foundation)",  "Foundation",       'let t: TimeInterval = 1; _ = t'),
    ("CGRect.width/.height",       "Foundation|UIKit", 'let r = CGRect(); _ = r.width; _ = r.height'),
    ("CGRectGetWidth (C)",         "Foundation|UIKit", '_ = CGRectGetWidth(CGRect()); _ = CGRectGetHeight(CGRect())'),
    ("UIEdgeInsets(top:...)",      "Foundation|UIKit", '_ = UIEdgeInsets(top:1,left:2,bottom:3,right:4)'),
    ("FileManager c/ UIKit",       "Foundation|UIKit", '_ = FileManager.default.fileExists(atPath: "/tmp")'),
    ("enumerator(atPath:)",        "Foundation|UIKit", '_ = FileManager.default.enumerator(atPath: "/tmp")'),
    ("NSSearchPathForDirectories", "Foundation|UIKit", '_ = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)'),
    # --- SwiftUI ---
    ("SwiftUI Text/VStack",       "Foundation|SwiftUI", 'struct V: View { var body: some View { VStack { Text("a") } } }; _ = V.self'),
    ("SwiftUI modifiers",         "Foundation|SwiftUI", 'struct V: View { var body: some View { Text("a").padding().foregroundColor(.red) } }; _ = V.self'),
    ("SwiftUI @State",            "Foundation|SwiftUI", 'struct V: View { @State var n = 0; var body: some View { Text("\\(n)") } }; _ = V.self'),
    ("SwiftUI List/ForEach",      "Foundation|SwiftUI", 'struct V: View { var body: some View { ForEach(0..<3, id: \\.self) { i in Text("\\(i)") } } }; _ = V.self'),
    ("SwiftUI Button",            "Foundation|SwiftUI", 'struct V: View { var body: some View { Button("t") {} } }; _ = V.self'),
    ("UIHostingController",       "Foundation|SwiftUI|UIKit", 'struct V: View { var body: some View { Text("a") } }; _ = UIHostingController(rootView: V())'),

    # --- sessao 2026-08-19 (ResumoFit v8, Swift puro) ---
    # CGContext do overlay: NÃO tem move/addLine/setLineDash/addArc (mediu-se
    # que o overlay do toolchain nao expoe esses; as funcoes C funcionam).
    ("CGContext.move(to:)",       "Foundation|UIKit", 'let c = UIGraphicsGetCurrentContext()!; c.move(to: CGPoint(x: 1, y: 1))'),
    ("CGContext.addLine(to:)",    "Foundation|UIKit", 'let c = UIGraphicsGetCurrentContext()!; c.addLine(to: CGPoint(x: 1, y: 1))'),
    ("CGContext.setLineDash",     "Foundation|UIKit", 'let c = UIGraphicsGetCurrentContext()!; c.setLineDash(phase: 0, lengths: [2, 2])'),
    ("CGContext C funcs",         "Foundation|UIKit", 'let c = UIGraphicsGetCurrentContext()!; CGContextMoveToPoint(c, 1, 1); CGContextAddLineToPoint(c, 2, 2); var d: [CGFloat] = [2, 2]; CGContextSetLineDash(c, 0, &d, 2); CGContextAddArc(c, 1, 1, 2, 0, 1, 0)'),
    ("UIBezierPath.addArc",       "Foundation|UIKit", 'let p = UIBezierPath(); p.addArc(withCenter: CGPoint(x: 1, y: 1), radius: 1, startAngle: 0, endAngle: 1, clockwise: true); _ = p'),
    ("TimeInterval",              "Foundation",       'let t: TimeInterval = 1; _ = t'),
    ("TimeInterval c/ UIKit",     "Foundation|UIKit", 'let t: TimeInterval = 1; _ = t'),
    ("FileManager.enumerator(at:)", "Foundation",     'let fm = FileManager.default; let d = URL(fileURLWithPath: "/tmp"); _ = fm.enumerator(at: d, includingPropertiesForKeys: nil, options: [])'),
    ("FileManager.enumerator(at:) skipsHidden", "Foundation", 'let fm = FileManager.default; let d = URL(fileURLWithPath: "/tmp"); _ = fm.enumerator(at: d, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])'),
    ("FileManager.enumerator(atPath:)", "Foundation", 'let fm = FileManager.default; _ = fm.enumerator(atPath: "/tmp")'),
    # FileManager COM UIKit no escopo: instavel — o interface do Accessibility
    # reexporta NSFileManager de forma diferente ("different definitions in
    # different modules"). No probe global falha; dentro de classes compila;
    # a overload URL-based do enumerator SOME sempre. Ver BUG 4 em
    # references/BUG-REPORTS-2026-08-19.md
    ("FileManager c/ UIKit (instavel)", "Foundation|UIKit", 'let fm = FileManager.default; _ = fm.enumerator(atPath: "/tmp")'),
    ("CGRect.height/width",       "Foundation|UIKit", 'var r = CGRect(); _ = r.height; _ = r.width'),
    ("CGRect C funcs",            "Foundation|UIKit", 'var r = CGRect(); let h = CGRectGetHeight(r); let w = CGRectGetWidth(r); _ = (h, w)'),
    ("UIEdgeInsetsMake",          "Foundation|UIKit", 'let e = UIEdgeInsetsMake(1, 2, 3, 4); _ = e.top'),
    ("UIEdgeInsets init",         "Foundation|UIKit", 'let e = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4); _ = e.top'),
    ("UITabBarAppearance",        "Foundation|UIKit", 'let a = UITabBarAppearance(); a.configureWithOpaqueBackground(); a.backgroundColor = UIColor.red; _ = a'),
    ("UIImage(systemName:)",      "Foundation|UIKit", '_ = UIImage(systemName: "sun.max")'),
    ("UIProgressView",            "Foundation|UIKit", 'let p = UIProgressView(); p.progress = 0.5; _ = p'),
    ("UIActivityIndicatorView",   "Foundation|UIKit", 'let a = UIActivityIndicatorView(style: .large); a.startAnimating(); _ = a'),
    ("UITabBarItem com imagem",   "Foundation|UIKit", 'let i = UITabBarItem(title: "x", image: UIImage(systemName: "sun.max"), tag: 0); _ = i'),
    ("UIDocumentPicker",          "Foundation|UIKit", 'let p = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open); _ = p'),
    ("String(format:)",           "Foundation",       'let s = String(format: "%.1f", 1.5); _ = s'),
    ("Data.range(of:)",           "Foundation",       'let d = Data("abc".utf8); _ = d.range(of: Data("b".utf8))'),
    ("NSStringFromClass/NSClassFromString", "Foundation|UIKit", '_ = NSStringFromClass(UIViewController.self); _ = NSClassFromString("ResumoFit.AppDelegate")'),
    ("CommandLine.argc/unsafeArgv", "Foundation",     'let a = CommandLine.argc; _ = a; _ = CommandLine.unsafeArgv'),
    ("UIScreen.main.bounds",      "Foundation|UIKit", 'let r = UIScreen.main.bounds; _ = r.size.width'),
    ("FileManager.attributesOfItem", "Foundation",    'let a = try? FileManager.default.attributesOfItem(atPath: "/etc/hosts"); _ = a?[.size]'),
    ("startAccessingSecurityScopedResource", "Foundation", 'let u = URL(fileURLWithPath: "/tmp"); _ = u.startAccessingSecurityScopedResource()'),
    ("withCString roundtrip",     "Foundation",       'let s = "abc"; let r = s.withCString { String(cString: $0) }; _ = r'),
]


def load_catalog(path):
    out = []
    for line in open(path):
        line = line.rstrip('\n')
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) >= 3:
            out.append((parts[0], parts[1], parts[2]))
    return out


def module_flags():
    flags = []
    for p in sorted(glob.glob(f'{OUT}/swift_*.swiftmodule')):
        n = os.path.basename(p)[len('swift_'):-len('.swiftmodule')]
        if n == 'XPC':
            continue
        flags += [f'-swift-module-file={n}={p}']
    for p in sorted(glob.glob(f'{OUT}/clang_*.pcm')):
        n = os.path.basename(p)[len('clang_'):-len('.pcm')]
        flags += ['-Xcc', f'-fmodule-file={n}={p}']
    return flags


MODFLAGS = module_flags()


def probe(name, imports, code):
    src = '/tmp/probe_api.swift'
    imp = '\n'.join(f'import {m}' for m in imports.split('|'))
    open(src, 'w').write(f'{imp}\npublic func f() {{\n  {code}\n}}\n')
    args = [SF, '-frontend', '-typecheck', '-target', 'arm64-apple-ios26.0',
            '-sdk', SDK, '-enable-objc-interop', '-swift-version', '5',
            '-disable-implicit-swift-modules', '-Xcc', '-fno-implicit-modules',
            '-Xcc', '-fno-implicit-module-maps',
            '-Xcc', '-ivfsoverlay', '-Xcc', VFS,
            '-module-name', 'Probe', src] + MODFLAGS + \
           ['-Xcc', f'-fmodules-cache-path={BIG}', '-Xcc', '-DCF_SWIFT_SENDABLE=']
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode == 0:
        return True, ''
    err = next((l.split('error:', 1)[1].strip()
                for l in p.stderr.split('\n') if 'error:' in l), 'erro desconhecido')
    return False, err


if __name__ == '__main__':
    catalog = load_catalog(sys.argv[1]) if len(sys.argv) > 1 else CATALOG
    results = []
    ok = 0
    for name, imports, code in catalog:
        good, err = probe(name, imports, code)
        ok += 1 if good else 0
        mark = 'OK  ' if good else 'FALHA'
        print(f'{mark} {name:32} {err[:90]}', flush=True)
        results.append({'name': name, 'imports': imports, 'code': code,
                        'ok': good, 'error': err})
    print(f'\n=== {ok}/{len(catalog)} compilam ===')
    json.dump(results, open('/tmp/probe_api_results.json', 'w'), indent=1)
    print('resultados: /tmp/probe_api_results.json')
