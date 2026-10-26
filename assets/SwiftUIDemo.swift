// SwiftUIDemo — 100% Swift iOS app using SwiftUI, compiled on iSH.
//
// See references/HANDOFF.md before editing.
//   1. IMPORT ORDER: `Foundation` BEFORE `SwiftUI`/`UIKit`.
//   2. CGRect(x:y:width:height:) does not resolve -> build it field by field.
//
// NOTE: the lifecycle uses UIKit (UIApplicationMain + UIHostingController)
// because SwiftUI's `@main struct App: App` depends on macros/attributes that
// do not survive interface-compile. The UI itself is 100% SwiftUI.
import Foundation
import SwiftUI
import UIKit

struct ContentView: View {
    let items = Array(1...6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pure Swift on iPhone")
                .font(.title)
                .foregroundColor(.white)

            Text("SwiftUI compiled inside iSH, no Mac in the build.")
                .font(.subheadline)
                .foregroundColor(.gray)

            Divider()

            ForEach(items, id: \.self) { n in
                HStack {
                    Text("item \(n)")
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(n * n)")
                        .foregroundColor(.green)
                }
            }

            Spacer()
        }
        .padding(24)
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = UIHostingController(rootView: ContentView())
        w.makeKeyAndVisible()
        window = w
    }
}

UIApplicationMain(CommandLine.argc,
                  CommandLine.unsafeArgv,
                  nil,
                  NSStringFromClass(AppDelegate.self))
