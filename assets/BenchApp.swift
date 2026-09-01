import Foundation
import UIKit

protocol BenchOperation {
    func run(_ n: Int) -> Int
}
struct Arithmetic: BenchOperation {
    func run(_ n: Int) -> Int {
        var x = 0
        for i in 0..<n { x = (x &* 1664525 &+ i) ^ (x >> 3) }
        return x
    }
}
struct GenericCollection: BenchOperation {
    func run(_ n: Int) -> Int {
        let values = Array(0..<n)
        return values.map { $0 &* 3 }.filter { $0 % 2 == 0 }.reduce(0, &+)
    }
}
struct StringWork: BenchOperation {
    func run(_ n: Int) -> Int {
        var result = ""
        for i in 0..<max(1, n / 100) { result += "item-\(i);" }
        return result.utf8.count
    }
}

func bench(_ name: String, _ operation: BenchOperation, _ n: Int) -> String {
    let start = Date().timeIntervalSince1970
    let value = operation.run(n)
    let elapsed = (Date().timeIntervalSince1970 - start) * 1000.0
    return "\(name): \(String(format: "%.2f", elapsed)) ms (checksum \(value))"
}

final class BenchViewController: UIViewController {
    let output = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground
        let title = UILabel()
        title.text = "forge-on-glass benchmark"
        title.font = UIFont.boldSystemFont(ofSize: 26)
        title.frame = rect(20, 70, 370, 40)
        view.addSubview(title)
        output.textColor = UIColor.label
        output.numberOfLines = 0
        output.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        output.frame = rect(20, 130, 370, 250)
        output.text = "Toque para executar cargas locais.\nO resultado depende do device."
        view.addSubview(output)
        let button = UIButton(type: .system)
        button.frame = rect(20, 410, 300, 52)
        button.setTitle("Executar benchmark", for: .normal)
        button.addTarget(self, action: #selector(runBenchmark), for: .touchUpInside)
        view.addSubview(button)
    }
    @objc func runBenchmark() {
        let n = 10000
        output.text = [
            "mode=\(ProcessInfo.processInfo.environment["ISB_OPT"] ?? "device-build")",
            bench("arithmetic", Arithmetic(), n * 10),
            bench("generic-collection", GenericCollection(), n),
            bench("strings", StringWork(), n * 10),
            "Repeat after installing the none/O IPAs."
        ].joined(separator: "\n")
    }
}

func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    var r = CGRect()
    r.origin.x = CGFloat(x); r.origin.y = CGFloat(y)
    r.size.width = CGFloat(w); r.size.height = CGFloat(h)
    return r
}

final class BenchAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = BenchViewController()
        w.makeKeyAndVisible(); window = w
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(BenchAppDelegate.self))
