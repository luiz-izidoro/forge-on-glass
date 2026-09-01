import Foundation
import UIKit
import FoundationModels

@available(iOS 26.0, *)
final class FoundationModelsRuntimeViewController: UIViewController {
    private let label = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemIndigo
        label.textColor = UIColor.white
        label.numberOfLines = 0
        label.frame = CGRect(x: 20, y: 70, width: 360, height: 360)
        label.text = "Toque para testar respond(to:)"
        view.addSubview(label)
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 20, y: 450, width: 300, height: 55)
        button.setTitle("Gerar resposta", for: .normal)
        button.addTarget(self, action: #selector(generate), for: .touchUpInside)
        view.addSubview(button)
    }
    @objc func generate() {
        label.text = "availability=\(SystemLanguageModel.default.availability)\nGerando..."
        let start = Date()
        Task { @MainActor in
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: "Responda apenas: OK")
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                label.text = "availability=available\nlatency=\(ms) ms\nresponse=\(response.content)"
            } catch {
                label.text = "generation unavailable/error:\n\(error)"
            }
        }
    }
}
final class FoundationModelsRuntimeDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = FoundationModelsRuntimeViewController()
        w.makeKeyAndVisible(); window = w
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(FoundationModelsRuntimeDelegate.self))
