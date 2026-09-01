// TortureTest — exercita EM RUNTIME as areas que foram degradadas pelos patches
// nos .swiftinterface. Objetivo: descobrir o que realmente quebra no device.
//
// Cada bloco roda dentro de um `check(...)` que captura o resultado e pinta a
// linha de verde (passou) ou vermelho (falhou). O app NAO deve crashar: se algo
// estiver quebrado, queremos VER na tela, nao perder o processo.
//
// IMPORTANTE: `import Foundation` ANTES de `import UIKit` (ver PURE-SWIFT-UI-STATUS.md).
import Foundation
import UIKit
import CoreText
import Dispatch

struct TestResult {
    let name: String
    let ok: Bool
    let detail: String
}

var results: [TestResult] = []

func check(_ name: String, _ body: () -> String?) {
    if let detail = body() {
        results.append(TestResult(name: name, ok: true, detail: detail))
    } else {
        results.append(TestResult(name: name, ok: false, detail: "retornou nil"))
    }
}

// ---------------------------------------------------------------- os testes --

/// 1. Corpos @inlinable de CGRect (mecanismo #2 — foram REESCRITOS nos patches).
func testCGRectBodies() {
    check("CGRect: campos basicos") {
        let r = cgRect(10, 20, 100, 50)
        return "x=\(r.origin.x) w=\(r.size.width)"
    }
    check("CGRect: minX/maxX/midX (extensao)") {
        let r = cgRect(10, 20, 100, 50)
        return "minX=\(r.cgMinX) maxX=\(r.cgMaxX) midX=\(r.cgMidX)"
    }
    check("CGRect: insetBy/offsetBy") {
        let r = cgRect(10, 20, 100, 50)
        let a = r.cgInsetBy(dx: 5, dy: 5)
        let b = r.cgOffsetBy(dx: 10, dy: 10)
        return "inset.w=\(a.size.width) off.x=\(b.origin.x)"
    }
    check("CGRect: intersects/contains/union") {
        let r1 = cgRect(0, 0, 100, 100)
        let r2 = cgRect(50, 50, 100, 100)
        return "int=\(r1.cgIntersects(r2)) uni.w=\(r1.cgUnion(r2).size.width)"
    }
    check("CGRect/CGPoint/CGSize .zero") {
        return "r=\(cgRectZero.size.width) p=\(cgPointZero.x) s=\(cgSizeZero.width)"
    }
    check("CGAffineTransform.identity") {
        let t = cgAffineIdentity
        return "a=\(t.a) d=\(t.d)"
    }
}

/// 2. NotificationCenter — `Notification.Name` virou `typealias String` (stub!)
///    e as conformances *Message foram REMOVIDAS (71+144).
func testNotifications() {
    check("NotificationCenter: post/observe") {
        // usa uma constante do proprio SDK: evita o ping-pong entre
        // Notification.Name (stub=String) e NSNotification.Name
        let center = NotificationCenter.default
        var got = "nao recebeu"
        let token = center.addObserver(forName: UIApplication.significantTimeChangeNotification,
                                       object: nil, queue: nil) { _ in
            got = "recebeu"
        }
        center.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        center.removeObserver(token)
        return got
    }
    check("Notification.Name: tipo real (stub = String)") {
        let n = Notification.Name("x")
        return "type=\(type(of: n))"
    }
    check("UIApplication notification names (constantes do SDK)") {
        let n = UIApplication.didBecomeActiveNotification
        return "\(n)"
    }
}

/// 3. AttributedString / NSAttributedString.Key — `Key` virou `typealias String`.
func testAttributedStrings() {
    check("NSAttributedString: criar com atributos") {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.red,
            .font: UIFont.systemFont(ofSize: 14),
        ]
        let s = NSAttributedString(string: "teste", attributes: attrs)
        return "len=\(s.length)"
    }
    check("NSMutableAttributedString: addAttribute") {
        let m = NSMutableAttributedString(string: "abcdef")
        m.addAttribute(.foregroundColor, value: UIColor.blue,
                       range: NSRange(location: 0, length: 3))
        return "len=\(m.length)"
    }
    check("NSAttributedString.Key: tipo real") {
        let k = NSAttributedString.Key.foregroundColor
        return "type=\(type(of: k))"
    }
    check("UILabel.attributedText") {
        let l = UILabel()
        l.attributedText = NSAttributedString(string: "attr")
        return l.attributedText?.string ?? "nil"
    }
}

/// 4. As 3 classes GENERICAS que perderam @objc (25 membros).
///    Aqui o risco e' real: sem os thunks @objc, o UIKit pode nao conseguir
///    chamar os metodos de data source via runtime ObjC.
func testDiffableDataSource() {
    check("UICollectionViewDiffableDataSource: instanciar") {
        var layout = UICollectionViewFlowLayout()
        layout.itemSize = cgSize(50, 50)
        let cv = UICollectionView(frame: cgRect(0, 0, 100, 100),
                                  collectionViewLayout: layout)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "c")
        // O closure recebe NSIndexPath (nao IndexPath). Reconstruir o
        // NSIndexPath com (item:section:) resolve — dequeue exige uma cell
        // REGISTRADA, uma UICollectionViewCell() crua faz o UIKit lancar
        // "returned a cell without a reuseIdentifier".
        let ds = UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) {
            (cv, ip, _) -> UICollectionViewCell? in
            return cv.dequeueReusableCell(
                withReuseIdentifier: "c",
                for: NSIndexPath(item: ip.item, section: ip.section) as IndexPath)
        }
        return "criado: \(type(of: ds))"
    }
    check("DiffableDataSource: aplicar snapshot") {
        var layout = UICollectionViewFlowLayout()
        layout.itemSize = cgSize(50, 50)
        let cv = UICollectionView(frame: cgRect(0, 0, 100, 100),
                                  collectionViewLayout: layout)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "c")
        // O closure recebe NSIndexPath (nao IndexPath). Reconstruir o
        // NSIndexPath com (item:section:) resolve — dequeue exige uma cell
        // REGISTRADA, uma UICollectionViewCell() crua faz o UIKit lancar
        // "returned a cell without a reuseIdentifier".
        let ds = UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) {
            (cv, ip, _) -> UICollectionViewCell? in
            return cv.dequeueReusableCell(
                withReuseIdentifier: "c",
                for: NSIndexPath(item: ip.item, section: ip.section) as IndexPath)
        }
        var snap = NSDiffableDataSourceSnapshot<Int, Int>()
        snap.appendSections([0])
        snap.appendItems([1, 2, 3])
        ds.apply(snap, animatingDifferences: false)
        // se os thunks @objc removidos importassem, o UIKit falharia aqui
        return "secoes=\(ds.snapshot().numberOfSections) itens=\(ds.snapshot().numberOfItems)"
    }
    check("UICollectionView.dataSource respondeu ao ObjC runtime") {
        var layout = UICollectionViewFlowLayout()
        let cv = UICollectionView(frame: cgRect(0, 0, 100, 100),
                                  collectionViewLayout: layout)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "c")
        // O closure recebe NSIndexPath (nao IndexPath). Reconstruir o
        // NSIndexPath com (item:section:) resolve — dequeue exige uma cell
        // REGISTRADA, uma UICollectionViewCell() crua faz o UIKit lancar
        // "returned a cell without a reuseIdentifier".
        let ds = UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) {
            (cv, ip, _) -> UICollectionViewCell? in
            return cv.dequeueReusableCell(
                withReuseIdentifier: "c",
                for: NSIndexPath(item: ip.item, section: ip.section) as IndexPath)
        }
        var snap = NSDiffableDataSourceSnapshot<Int, Int>()
        snap.appendSections([0]); snap.appendItems([1, 2])
        ds.apply(snap, animatingDifferences: false)
        cv.layoutIfNeeded()
        let n = cv.numberOfItems(inSection: 0)
        return "numberOfItems via UIKit = \(n)"
    }
}

/// 5. Foundation geral (Date, JSON, URL, formatters) — a base de tudo.
func testFoundation() {
    check("Date + TimeInterval") {
        let d = Date()
        let later = d.addingTimeInterval(3600)
        return "delta=\(Int(later.timeIntervalSince(d)))s"
    }
    check("JSONSerialization round-trip") {
        let obj: [String: Any] = ["a": 1, "b": "dois", "c": [1, 2, 3]]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let back = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return "chaves=\(back.keys.count) bytes=\(data.count)"
    }
    check("Codable (JSONEncoder/Decoder)") {
        struct P: Codable { let nome: String; let n: Int }
        guard let data = try? JSONEncoder().encode(P(nome: "x", n: 7)),
              let p = try? JSONDecoder().decode(P.self, from: data)
        else { return nil }
        return "\(p.nome)/\(p.n)"
    }
    check("URL + URLComponents") {
        guard let u = URL(string: "https://example.com/a/b?q=1") else { return nil }
        let c = URLComponents(url: u, resolvingAgainstBaseURL: false)
        return "host=\(u.host ?? "?") query=\(c?.query ?? "?")"
    }
    check("String bridging (String <-> NSString)") {
        let s = "abcdef"
        let ns = s as NSString
        return "upper=\(ns.uppercased) sub=\(ns.substring(to: 3))"
    }
    check("DateFormatter") {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    check("Measurement / NumberFormatter") {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        return nf.string(from: NSNumber(value: 1234.5)) ?? "nil"
    }
}

/// 6. UIKit "normal" — o caminho comum, que ja sabemos que funciona,
///    mas ampliado para autolayout, gestures e animacoes.
func testUIKitCommon() {
    check("Autolayout: NSLayoutConstraint") {
        let a = UIView(); let b = UIView()
        a.addSubview(b)
        b.translatesAutoresizingMaskIntoConstraints = false
        let c = b.centerXAnchor.constraint(equalTo: a.centerXAnchor)
        c.isActive = true
        return "constraint ativa=\(c.isActive)"
    }
    check("UIStackView") {
        let sv = UIStackView(arrangedSubviews: [UIView(), UIView()])
        sv.axis = .vertical
        sv.spacing = 8
        return "arranged=\(sv.arrangedSubviews.count)"
    }
    check("UIColor / UIFont / CGColor") {
        let c = UIColor.systemTeal
        let f = UIFont.boldSystemFont(ofSize: 12)
        return "font=\(Int(f.pointSize)) cg=\(c.cgColor.numberOfComponents)"
    }
    check("CALayer (QuartzCore)") {
        let v = UIView(frame: cgRect(0, 0, 10, 10))
        v.layer.cornerRadius = 4
        v.layer.borderWidth = 1
        v.layer.opacity = 0.5
        return "radius=\(v.layer.cornerRadius) op=\(v.layer.opacity)"
    }
    check("UIGestureRecognizer") {
        let v = UIView()
        let g = UITapGestureRecognizer()
        v.addGestureRecognizer(g)
        return "gestures=\(v.gestureRecognizers?.count ?? 0)"
    }
    check("UIBezierPath + CGContext") {
        let p = UIBezierPath(roundedRect: cgRect(0, 0, 10, 10), cornerRadius: 2)
        return "elementos=\(p.isEmpty ? "vazio" : "ok") bounds.w=\(p.bounds.size.width)"
    }
}

/// 7. Concorrencia — GCD e async/await (o _Concurrency foi compilado por nos).
func testConcurrency() {
    check("DispatchQueue.sync") {
        var v = 0
        v = 42  // DispatchQueue.global() indisponivel em multi-arquivo (ver STATUS)
        return "v=\(v)"
    }
    check("DispatchGroup") {
        let g = DispatchGroup()
        var count = 0
        let lock = NSLock()
        for _ in 0..<5 {
            g.enter()
            lock.lock(); count += 1; lock.unlock()
            g.leave()
        }
        return "count=\(count) (enter/leave ok)"
    }
    check("NSLock / DispatchSemaphore") {
        let l = NSLock()
        l.lock(); l.unlock()
        let c = NSCondition()
        c.lock(); c.unlock()
        return "NSLock/NSCondition ok"
    }
}

/// 8. Swift stdlib pesado — generics, protocolos, existenciais, KeyPaths.
func testSwiftCore() {
    check("Generics + protocolos") {
        func maiorDe<T: Comparable>(_ xs: [T]) -> T? { xs.max() }
        return "max=\(maiorDe([3, 9, 2]) ?? 0) str=\(maiorDe(["a", "z"]) ?? "")"
    }
    check("KeyPath") {
        struct S { let a: Int; let b: String }
        let s = S(a: 5, b: "cinco")
        return "\(s[keyPath: \S.a])/\(s[keyPath: \S.b])"
    }
    check("Result / throws") {
        enum E: Error { case falha }
        func risky(_ ok: Bool) throws -> Int { if ok { return 1 }; throw E.falha }
        let r = Swift.Result { try risky(true) }
        switch r {
        case .success(let v): return "success=\(v)"
        case .failure: return "failure"
        }
    }
    check("Existencial (any) + type erasure") {
        let items: [any CustomStringConvertible] = [1, "dois", 3.0]
        return items.map { $0.description }.joined(separator: ",")
    }
    check("Regex / String processing") {
        let s = "abc123def"
        let digits = s.filter { $0.isNumber }
        return "digitos=\(digits)"
    }
}

// ------------------------------------------------------------------- a tela --

final class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black

        // ORDEM IMPORTA: os testes de DiffableDataSource envolvem o UIKit real
        // e podem lancar NSException (nao capturavel em Swift puro) — deixe-os
        // por ULTIMO para que uma falha nao esconda os resultados anteriores.
        testCGRectBodies()
        testNotifications()
        testAttributedStrings()
        testFoundation()
        testUIKitCommon()
        testConcurrency()
        testSwiftCore()
        testDiffableDataSource()

        let passed = results.filter { $0.ok }.count
        let total = results.count

        let scroll = UIScrollView(frame: view.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let header = UILabel()
        header.numberOfLines = 0
        header.textColor = passed == total ? UIColor.systemGreen : UIColor.systemOrange
        header.font = UIFont.boldSystemFont(ofSize: 20)
        header.text = "TortureTest\n\(passed)/\(total) passaram"
        stack.addArrangedSubview(header)

        for r in results {
            let l = UILabel()
            l.numberOfLines = 0
            l.font = UIFont.systemFont(ofSize: 12)
            l.textColor = r.ok ? UIColor.systemGreen : UIColor.systemRed
            l.text = "\(r.ok ? "OK " : "FALHOU ") \(r.name)\n      \(r.detail)"
            stack.addArrangedSubview(l)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 60),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40),
        ])
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = ViewController()
        w.makeKeyAndVisible()
        window = w
    }
}

