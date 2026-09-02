import Foundation
import UIKit

final class EmbeddingsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let label = UILabel()
        label.textColor = UIColor.white
        label.numberOfLines = 0
        let available = NativeEmbeddings.isAvailable
        let vectorCount = NativeEmbeddings.vector(for: "teste arm64e")?.count ?? 0
        label.text = "NLEmbedding bridge\navailable=\(available)\nvector_count=\(vectorCount)"
        label.sizeToFit()
        view.addSubview(label)
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
