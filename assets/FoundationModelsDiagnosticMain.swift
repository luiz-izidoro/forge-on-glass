import Foundation
import UIKit

@available(iOS 26.0, *)
final class FoundationModelsDiagnosticViewController: UIViewController {
    var statusLabel: UILabel?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBlue

        let title = UILabel()
        title.textColor = UIColor.white
        title.text = "FoundationModels"
        title.sizeToFit()
        title.frame.origin.x = 24
        title.frame.origin.y = 80
        view.addSubview(title)

        let status = UILabel()
        status.textColor = UIColor.white
        status.numberOfLines = 0
        status.text = "UI carregada. Toque para verificar o modelo."
        status.frame.origin.x = 24
        status.frame.origin.y = 140
        status.frame.size.width = 360
        status.frame.size.height = 100
        view.addSubview(status)
        statusLabel = status

        let button = UIButton(type: .system)
        button.setTitle("Verificar disponibilidade", for: .normal)
        button.setTitleColor(UIColor.white, for: .normal)
        button.frame.origin.x = 24
        button.frame.origin.y = 270
        button.frame.size.width = 300
        button.frame.size.height = 52
        button.addTarget(self, action: #selector(checkAvailability), for: .touchUpInside)
        view.addSubview(button)
    }

    @objc func checkAvailability() {
        statusLabel?.text = "Consultando SystemLanguageModel..."
        let result = SafeFoundationModels.availability
        statusLabel?.text = "FoundationModels: " + result
    }
}

final class FoundationModelsDiagnosticDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = FoundationModelsDiagnosticViewController()
        w.makeKeyAndVisible()
        window = w
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(FoundationModelsDiagnosticDelegate.self))
