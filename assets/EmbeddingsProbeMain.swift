import Foundation
import UIKit

final class EmbeddingsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGreen
        let label = UILabel()
        label.textColor = UIColor.white
        label.sizeToFit()
        view.addSubview(label)
        _ = NativeEmbeddings.isAvailable
    }
}
final class EmbeddingsDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = EmbeddingsViewController()
        w.makeKeyAndVisible()
        window = w
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(EmbeddingsDelegate.self))
