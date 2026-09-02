import Foundation
import UIKit
import Dispatch

final class EmbeddingsRuntimeViewController: UIViewController {
    private let label = UILabel()
    private let button = UIButton(type: .system)
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGreen
        label.textColor = UIColor.white
        label.numberOfLines = 0
        var frame = CGRect()
        frame.origin.x = 20; frame.origin.y = 80
        frame.size.width = 360; frame.size.height = 300
        label.frame = frame
        label.text = "NLEmbedding bridge\nToque para executar"
        view.addSubview(label)
        var buttonFrame = CGRect()
        buttonFrame.origin.x = 20; buttonFrame.origin.y = 420
        buttonFrame.size.width = 320; buttonFrame.size.height = 55
        button.frame = buttonFrame
        button.setTitle("Gerar vetor", for: .normal)
        button.addTarget(self, action: #selector(run), for: .touchUpInside)
        view.addSubview(button)
    }
    @objc func run() {
        label.text = "NLEmbedding bridge\nExecutando..."
        DispatchQueue.global().async {
            let available = NativeEmbeddings.isAvailable
            let vector = NativeEmbeddings.vector(for: "teste de embedding")
            let detail = vector.map { "vector_count=\($0.count)\nfirst=\($0.first ?? 0)" }
                ?? "vector=nil\nerror=\(NativeEmbeddings.lastError ?? "unknown")"
            DispatchQueue.main.async {
                self.label.text = "NLEmbedding bridge\navailable=\(available)\n" + detail
            }
        }
    }
}

final class EmbeddingsRuntimeDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = EmbeddingsRuntimeViewController()
        w.makeKeyAndVisible(); window = w
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(EmbeddingsRuntimeDelegate.self))
