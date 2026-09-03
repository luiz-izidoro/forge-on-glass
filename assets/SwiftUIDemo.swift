// SwiftUIDemo — app iOS 100% Swift usando SwiftUI, compilado no iSH.
//
// Consulte references/HANDOFF.md antes de editar.
//   1. ORDEM DOS IMPORTS: `Foundation` ANTES de `SwiftUI`/`UIKit`.
//   2. CGRect(x:y:width:height:) nao resolve -> construa por campos.
//
// NOTA: o ciclo de vida usa UIKit (UIApplicationMain + UIHostingController)
// porque o `@main struct App: App` do SwiftUI depende de macros/atributos que
// nao sobrevivem ao interface-compile. A UI em si e' 100% SwiftUI.
import Foundation
import SwiftUI
import UIKit

struct ContentView: View {
    let items = Array(1...6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swift puro no iPhone")
                .font(.title)
                .foregroundColor(.white)

            Text("SwiftUI compilado dentro do iSH, sem Mac no build.")
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
