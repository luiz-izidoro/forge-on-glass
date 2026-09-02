import Foundation
import UIKit
import NaturalLanguage

final class DirectNLViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let label = UILabel()
        label.textColor = UIColor.white
        label.numberOfLines = 0
        let available = NaturalLanguageProbe.portugueseSentenceModelAvailable
        label.text = "NaturalLanguage Swift\nmodel_available=\(available)"
        label.sizeToFit()
        view.addSubview(label)
    }
}
final class DirectNLDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = DirectNLViewController()
        w.makeKeyAndVisible()
        window = w
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(DirectNLDelegate.self))
