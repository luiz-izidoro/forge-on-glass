// TortureTest — exercises AT RUNTIME the areas that were degraded by the patches
// to the .swiftinterface files. Goal: find out what actually breaks on device.
//
// Each block runs inside a `check(...)` that captures the result and paints the
// line green (passed) or red (failed). The app must NOT crash: if something
// is broken, we want to SEE it on screen, not lose the process.
//
// IMPORTANT: `import Foundation` before `import UIKit`.
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
        results.append(TestResult(name: name, ok: false, detail: "returned nil"))
    }
}

// ---------------------------------------------------------------- the tests --

/// 1. @inlinable bodies of CGRect (mechanism #2 — they were REWRITTEN by the patches).
func testCGRectBodies() {
    check("CGRect: basic fields") {
        let r = cgRect(10, 20, 100, 50)
        return "x=\(r.origin.x) w=\(r.size.width)"
    }
    check("CGRect: minX/maxX/midX (extension)") {
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

/// 2. NotificationCenter — `Notification.Name` became `typealias String` (stub!)
///    and the *Message conformances were REMOVED (71+144).
func testNotifications() {
    check("NotificationCenter: post/observe") {
        // uses a constant from the SDK itself: avoids the ping-pong between
        // Notification.Name (stub=String) and NSNotification.Name
        let center = NotificationCenter.default
        var got = "did not receive"
        let token = center.addObserver(forName: UIApplication.significantTimeChangeNotification,
                                       object: nil, queue: nil) { _ in
            got = "received"
        }
        center.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        center.removeObserver(token)
        return got
    }
    check("Notification.Name: real type (stub = String)") {
        let n = Notification.Name("x")
        return "type=\(type(of: n))"
    }
    check("UIApplication notification names (SDK constants)") {
        let n = UIApplication.didBecomeActiveNotification
        return "\(n)"
    }
}

/// 3. AttributedString / NSAttributedString.Key — `Key` became `typealias String`.
func testAttributedStrings() {
    check("NSAttributedString: create with attributes") {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.red,
            .font: UIFont.systemFont(ofSize: 14),
        ]
        let s = NSAttributedString(string: "test", attributes: attrs)
        return "len=\(s.length)"
    }
    check("NSMutableAttributedString: addAttribute") {
        let m = NSMutableAttributedString(string: "abcdef")
        m.addAttribute(.foregroundColor, value: UIColor.blue,
                       range: NSRange(location: 0, length: 3))
        return "len=\(m.length)"
    }
    check("NSAttributedString.Key: real type") {
        let k = NSAttributedString.Key.foregroundColor
        return "type=\(type(of: k))"
    }
    check("UILabel.attributedText") {
        let l = UILabel()
        l.attributedText = NSAttributedString(string: "attr")
        return l.attributedText?.string ?? "nil"
    }
}

/// 4. The 3 GENERIC classes that lost @objc (25 members).
///    Here the risk is real: without the @objc thunks, UIKit may not be able
///    to call the data source methods through the ObjC runtime.
func testDiffableDataSource() {
    check("UICollectionViewDiffableDataSource: instantiate") {
        var layout = UICollectionViewFlowLayout()
        layout.itemSize = cgSize(50, 50)
        let cv = UICollectionView(frame: cgRect(0, 0, 100, 100),
                                  collectionViewLayout: layout)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "c")
        // The closure receives NSIndexPath (not IndexPath). Rebuilding the
        // NSIndexPath with (item:section:) fixes it — dequeue requires a
        // REGISTERED cell; a raw UICollectionViewCell() makes UIKit throw
        // "returned a cell without a reuseIdentifier".
        let ds = UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) {
            (cv, ip, _) -> UICollectionViewCell? in
            return cv.dequeueReusableCell(
                withReuseIdentifier: "c",
                for: NSIndexPath(item: ip.item, section: ip.section) as IndexPath)
        }
        return "created: \(type(of: ds))"
    }
    check("DiffableDataSource: apply snapshot") {
        var layout = UICollectionViewFlowLayout()
        layout.itemSize = cgSize(50, 50)
        let cv = UICollectionView(frame: cgRect(0, 0, 100, 100),
                                  collectionViewLayout: layout)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "c")
        // The closure receives NSIndexPath (not IndexPath). Rebuilding the
        // NSIndexPath with (item:section:) fixes it — dequeue requires a
        // REGISTERED cell; a raw UICollectionViewCell() makes UIKit throw
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
        // if the removed @objc thunks mattered, UIKit would fail here
        return "sections=\(ds.snapshot().numberOfSections) items=\(ds.snapshot().numberOfItems)"
    }
    check("UICollectionView.dataSource responded to the ObjC runtime") {
        var layout = UICollectionViewFlowLayout()
        let cv = UICollectionView(frame: cgRect(0, 0, 100, 100),
                                  collectionViewLayout: layout)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "c")
        // The closure receives NSIndexPath (not IndexPath). Rebuilding the
        // NSIndexPath with (item:section:) fixes it — dequeue requires a
        // REGISTERED cell; a raw UICollectionViewCell() makes UIKit throw
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

/// 5. General Foundation (Date, JSON, URL, formatters) — the basis of everything.
func testFoundation() {
    check("Date + TimeInterval") {
        let d = Date()
        let later = d.addingTimeInterval(3600)
        return "delta=\(Int(later.timeIntervalSince(d)))s"
    }
    check("JSONSerialization round-trip") {
        let obj: [String: Any] = ["a": 1, "b": "two", "c": [1, 2, 3]]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let back = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return "keys=\(back.keys.count) bytes=\(data.count)"
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

/// 6. "Normal" UIKit — the common path, which we already know works,
///    but expanded to autolayout, gestures and animations.
func testUIKitCommon() {
    check("Autolayout: NSLayoutConstraint") {
        let a = UIView(); let b = UIView()
        a.addSubview(b)
        b.translatesAutoresizingMaskIntoConstraints = false
        let c = b.centerXAnchor.constraint(equalTo: a.centerXAnchor)
        c.isActive = true
        return "constraint active=\(c.isActive)"
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
        return "elements=\(p.isEmpty ? "empty" : "ok") bounds.w=\(p.bounds.size.width)"
    }
}

/// 7. Concurrency — GCD and async/await (_Concurrency was compiled by us).
func testConcurrency() {
    check("DispatchQueue.sync") {
        var v = 0
        v = 42  // DispatchQueue.global() unavailable in multi-file builds (see STATUS)
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

/// 8. Heavy Swift stdlib — generics, protocols, existentials, KeyPaths.
func testSwiftCore() {
    check("Generics + protocols") {
        func maiorDe<T: Comparable>(_ xs: [T]) -> T? { xs.max() }
        return "max=\(maiorDe([3, 9, 2]) ?? 0) str=\(maiorDe(["a", "z"]) ?? "")"
    }
    check("KeyPath") {
        struct S { let a: Int; let b: String }
        let s = S(a: 5, b: "five")
        return "\(s[keyPath: \S.a])/\(s[keyPath: \S.b])"
    }
    check("Result / throws") {
        enum E: Error { case failure }
        func risky(_ ok: Bool) throws -> Int { if ok { return 1 }; throw E.failure }
        let r = Swift.Result { try risky(true) }
        switch r {
        case .success(let v): return "success=\(v)"
        case .failure: return "failure"
        }
    }
    check("Existential (any) + type erasure") {
        let items: [any CustomStringConvertible] = [1, "two", 3.0]
        return items.map { $0.description }.joined(separator: ",")
    }
    check("Regex / String processing") {
        let s = "abc123def"
        let digits = s.filter { $0.isNumber }
        return "digits=\(digits)"
    }
}

// ------------------------------------------------------------------- the screen --

final class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black

        // ORDER MATTERS: the DiffableDataSource tests involve real UIKit
        // and may throw NSException (not catchable in pure Swift) — leave them
        // for LAST so a failure does not hide the previous results.
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
        header.text = "TortureTest\n\(passed)/\(total) passed"
        stack.addArrangedSubview(header)

        for r in results {
            let l = UILabel()
            l.numberOfLines = 0
            l.font = UIFont.systemFont(ofSize: 12)
            l.textColor = r.ok ? UIColor.systemGreen : UIColor.systemRed
            l.text = "\(r.ok ? "OK " : "FAILED ") \(r.name)\n      \(r.detail)"
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

