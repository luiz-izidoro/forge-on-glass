import Foundation
import UIKit

final class HybridRuntimeViewController: UIViewController {
    private let label = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemPurple
        label.textColor = UIColor.white
        label.numberOfLines = 0
        var labelFrame = CGRect()
        labelFrame.origin.x = 20; labelFrame.origin.y = 80
        labelFrame.size.width = 360; labelFrame.size.height = 300
        label.frame = labelFrame
        label.text = "Swift + ObjC UIKit\nToque para testar"
        view.addSubview(label)
        let button = UIButton(type: .system)
        var buttonFrame = CGRect()
        buttonFrame.origin.x = 20; buttonFrame.origin.y = 420
        buttonFrame.size.width = 300; buttonFrame.size.height = 55
        button.frame = buttonFrame
        button.setTitle("Executar Swift", for: .normal)
        button.addTarget(self, action: #selector(runSwift), for: .touchUpInside)
        view.addSubview(button)
    }
    @objc func runSwift() {
        let value = HybridRuntimeLogic.fibonacci(20)
        label.text = "Swift + ObjC UIKit\nfibonacci(20)=\(value)\ncallback=PASS"
    }
}

final class HybridRuntimeDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = HybridRuntimeViewController()
        w.makeKeyAndVisible()
        window = w
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(HybridRuntimeDelegate.self))
