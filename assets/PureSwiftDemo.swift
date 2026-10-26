// PureSwiftDemo — 100% Swift iOS app (not a single line of Objective-C).
// Proves that `import UIKit` + `import Foundation` work in pure Swift
// compiled entirely inside iSH (iPhone), with no Mac in the build.
//
// See references/HANDOFF.md before editing.
//   1. CGRect(x:y:width:height:) is @_transparent and does NOT resolve -> use rect()
//   2. IMPORT ORDER MATTERS: `import Foundation` BEFORE `import UIKit`.
//      Reversed, UIKit's String APIs start requiring NSString.
import Foundation
import UIKit

/// CGRect built field by field (the CoreGraphics @_transparent init does not resolve).
func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    var r = CGRect()
    r.origin.x = CGFloat(x)
    r.origin.y = CGFloat(y)
    r.size.width = CGFloat(w)
    r.size.height = CGFloat(h)
    return r
}

final class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black

        let card = UIView(frame: rect(24, 120, 320, 240))
        card.backgroundColor = UIColor.darkGray
        card.layer.cornerRadius = 18
        view.addSubview(card)

        let title = UILabel(frame: rect(20, 20, 280, 40))
        title.textColor = UIColor.white
        title.font = UIFont.boldSystemFont(ofSize: 22)
        title.text = "Pure Swift on iPhone"
        card.addSubview(title)

        // real Swift logic: generics, closures, map/filter/reduce
        let nums = Array(1...10)
        let evens = nums.filter { $0 % 2 == 0 }
        let total = evens.reduce(0, +)
        let joined = evens.map { String($0) }.joined(separator: ", ")

        let body = UILabel(frame: rect(20, 76, 280, 70))
        body.numberOfLines = 3
        body.textColor = UIColor.lightGray
        body.text = "evens: \(joined)\nsum: \(total)"
        card.addSubview(body)

        let stamp = UILabel(frame: rect(20, 160, 280, 24))
        stamp.textColor = UIColor.systemGreen
        stamp.font = UIFont.systemFont(ofSize: 13)
        stamp.text = "compiled on iSH · \(Int(Date().timeIntervalSince1970))"
        card.addSubview(stamp)

        let btn = UIButton(type: .system)
        btn.frame = rect(20, 190, 280, 34)
        btn.setTitle("Tap here", for: .normal)
        card.addSubview(btn)
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

UIApplicationMain(CommandLine.argc,
                  CommandLine.unsafeArgv,
                  nil,
                  NSStringFromClass(AppDelegate.self))
