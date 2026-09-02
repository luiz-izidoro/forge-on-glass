import Foundation
import UIKit

final class EmbeddingsRuntimeViewController: UIViewController {
    private let label = UILabel()
    private var checkButton: UIButton?
    private var dimensionButton: UIButton?
    private var vectorButton: UIButton?
    private func button(_ title: String, _ y: Double, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        var r = CGRect(); r.origin.x = 20; r.origin.y = CGFloat(y)
        r.size.width = 340; r.size.height = 52
        b.frame = r; b.setTitle(title, for: .normal)
        b.addTarget(self, action: action, for: .touchUpInside)
        view.addSubview(b); return b
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGreen
        label.textColor = UIColor.white; label.numberOfLines = 0
        var r = CGRect(); r.origin.x = 20; r.origin.y = 70
        r.size.width = 370; r.size.height = 260; label.frame = r
        label.text = "NLEmbedding bridge\nFase 0: app aberto"
        view.addSubview(label)
        checkButton = button("1. Verificar modelo", 370, #selector(checkModel))
        dimensionButton = button("2. Obter dimensão", 440, #selector(checkDimension))
        vectorButton = button("3. Gerar vetor", 510, #selector(runVector))
    }
    @objc func checkModel() {
        label.text = "NLEmbedding bridge\nFase 1: disponibilidade..."
        let available = NativeEmbeddings.isAvailable
        label.text = "NLEmbedding bridge\navailability=\(available)\nerror=\(NativeEmbeddings.lastError ?? "none")\nFase 1=PASS"
    }
    @objc func checkDimension() {
        label.text = "NLEmbedding bridge\nFase 2: dimensão..."
        let dimension = NativeEmbeddings.dimension
        label.text = "NLEmbedding bridge\ndimension=\(dimension)\nerror=\(NativeEmbeddings.lastError ?? "none")\nFase 2=PASS"
    }
    @objc func runVector() {
        label.text = "NLEmbedding bridge\nFase 3: getVector..."
        let vector = NativeEmbeddings.vector(for: "teste de embedding")
        label.text = vector.map { "NLEmbedding bridge\nvector_count=\($0.count)\nfirst=\($0.first ?? 0)\nFase 3=PASS" }
            ?? "NLEmbedding bridge\nvector=nil\nerror=\(NativeEmbeddings.lastError ?? "unknown")\nFase 3=FAIL"
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    init() { super.init(nibName: nil, bundle: nil) }
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
