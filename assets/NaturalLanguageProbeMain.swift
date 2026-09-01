import Foundation
import UIKit
import NaturalLanguage

final class DirectNLViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemOrange
        _ = NaturalLanguageProbe.portugueseSentenceModelAvailable
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
