import Foundation
import UIKit

final class FoundationModelsSafeViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBlue
        let label = UILabel()
        label.textColor = UIColor.white
        label.numberOfLines = 0
        label.text = "FoundationModels: aguardando disponibilidade"
        label.sizeToFit()
        view.addSubview(label)
    }
}
final class FoundationModelsSafeDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = FoundationModelsSafeViewController()
        w.makeKeyAndVisible()
        window = w
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(FoundationModelsSafeDelegate.self))
