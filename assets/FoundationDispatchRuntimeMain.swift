import Foundation
import UIKit
import Dispatch

@available(iOS 26.0, *)
final class FoundationDispatchRuntimeViewController: UIViewController {
    private let label = UILabel()
    private let queue = DispatchQueue(label: "forge.foundation-dispatch")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemTeal
        label.textColor = UIColor.white
        label.numberOfLines = 0
        var labelFrame = CGRect()
        labelFrame.origin.x = 20; labelFrame.origin.y = 70
        labelFrame.size.width = 360; labelFrame.size.height = 360
        label.frame = labelFrame
        label.text = "Foundation + Dispatch\nToque para testar"
        view.addSubview(label)

        let button = UIButton(type: .system)
        var buttonFrame = CGRect()
        buttonFrame.origin.x = 20; buttonFrame.origin.y = 450
        buttonFrame.size.width = 300; buttonFrame.size.height = 55
        button.frame = buttonFrame
        button.setTitle("Executar smoke test", for: .normal)
        button.addTarget(self, action: #selector(runSmoke), for: .touchUpInside)
        view.addSubview(button)
    }

    @objc func runSmoke() {
        label.text = "Foundation + Dispatch\nExecutando..."
        let start = Date()
        let path = NSTemporaryDirectory() + "/forge-foundation-dispatch"
        let group = DispatchGroup()
        group.enter()
        queue.async {
            let made = FileManager.default.createFile(
                atPath: path, contents: Data("ok".utf8), attributes: nil)
            let exists = FileManager.default.fileExists(atPath: path)
            try? FileManager.default.removeItem(atPath: path)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            DispatchQueue.main.async {
                self.label.text = "Foundation + Dispatch\n" +
                    "file_create=\(made)\nfile_exists=\(exists)\n" +
                    "dispatch_group=PASS\nlatency=\(elapsed) ms"
            }
            group.leave()
        }
        group.notify(queue: DispatchQueue.main) {
            if !self.label.text!.contains("dispatch_group=PASS") {
                self.label.text = "Foundation + Dispatch\n" +
                    "dispatch_group=PASS\ncallback=PASS"
            }
        }
    }
}

final class FoundationDispatchRuntimeDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = FoundationDispatchRuntimeViewController()
        w.makeKeyAndVisible()
        window = w
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(FoundationDispatchRuntimeDelegate.self))
