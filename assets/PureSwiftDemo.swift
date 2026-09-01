// PureSwiftDemo — app iOS 100% Swift (nenhuma linha de Objective-C).
// Prova que `import UIKit` + `import Foundation` funcionam em Swift puro
// compilado inteiramente dentro do iSH (iPhone), sem Mac no build.
//
// LEIA ANTES DE EDITAR: references/PURE-SWIFT-UI-STATUS.md
//   1. CGRect(x:y:width:height:) e' @_transparent e NAO resolve -> use rect()
//   2. A ORDEM DOS IMPORTS IMPORTA: `import Foundation` ANTES de `import UIKit`.
//      Invertido, as APIs String do UIKit passam a exigir NSString.
import Foundation
import UIKit

/// CGRect por campos (o init @_transparent do CoreGraphics nao resolve).
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
        title.text = "Swift puro no iPhone"
        card.addSubview(title)

        // logica Swift real: generics, closures, map/filter/reduce
        let nums = Array(1...10)
        let evens = nums.filter { $0 % 2 == 0 }
        let total = evens.reduce(0, +)
        let joined = evens.map { String($0) }.joined(separator: ", ")

        let body = UILabel(frame: rect(20, 76, 280, 70))
        body.numberOfLines = 3
        body.textColor = UIColor.lightGray
        body.text = "pares: \(joined)\nsoma: \(total)"
        card.addSubview(body)

        let stamp = UILabel(frame: rect(20, 160, 280, 24))
        stamp.textColor = UIColor.systemGreen
        stamp.font = UIFont.systemFont(ofSize: 13)
        stamp.text = "compilado no iSH · \(Int(Date().timeIntervalSince1970))"
        card.addSubview(stamp)

        let btn = UIButton(type: .system)
        btn.frame = rect(20, 190, 280, 34)
        btn.setTitle("Toque aqui", for: .normal)
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
