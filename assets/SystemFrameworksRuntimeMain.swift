import Foundation
import UIKit
import CoreML
import Vision
import Accelerate

final class SystemFrameworksRuntimeViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBrown
        let label = UILabel()
        label.textColor = UIColor.white
        label.numberOfLines = 0
        var a: [Float] = [1, 2, 3]
        var b: [Float] = [4, 5, 6]
        var result: [Float] = [0, 0, 0]
        vDSP_vadd(a, 1, b, 1, &result, 1, 3)
        let config = MLModelConfiguration()
        let request = VNDetectFaceRectanglesRequest()
        label.text = "CoreML + Vision + Accelerate\n" +
            "vDSP=\(result.map { Int($0) })\n" +
            "MLConfig=\(type(of: config))\n" +
            "Vision=\(type(of: request))"
        label.sizeToFit()
        view.addSubview(label)
    }
}

final class SystemFrameworksRuntimeDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = SystemFrameworksRuntimeViewController()
        w.makeKeyAndVisible()
        window = w
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(SystemFrameworksRuntimeDelegate.self))
