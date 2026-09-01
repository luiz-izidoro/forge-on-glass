// AppEntry.swift — TEMPLATE do entry point. COPIE ESTE PADRAO.
//
// ⚠️ A REGRA MAIS CARA DESTE PROJETO (uma sessao inteira perdida, 2026-08-22):
//
// Use `applicationDidFinishLaunching(_:)`.
// NAO use `application(_:didFinishLaunchingWithOptions:)`.
//
// PORQUE: os `.swiftinterface` do SDK foram patchados para compilar com o
// toolchain swift.org, e nesse processo o tipo de `launchOptions` degradou:
//
//     Apple:      [UIApplication.LaunchOptionsKey: Any]?
//     nosso SDK:  NSDictionary<NSString, AnyObject>?
//
// Como o requisito do protocolo e' OPCIONAL (`optional func`, herdado do ObjC),
// escrever a assinatura da Apple NAO da erro. Da apenas:
//
//     warning: instance method 'application(_:didFinishLaunchingWithOptions:)'
//     nearly matches optional requirement ... of protocol 'UIApplicationDelegate'
//
// O metodo vira um metodo COMUM da classe. O UIKit nunca o chama. A janela
// nunca e' criada. O app ABRE, fica VIVO, e mostra TELA PRETA para sempre —
// sem crash, sem log, sem nada que aponte para a causa.
//
// `applicationDidFinishLaunching(_ application: UIApplication)` nao tem
// parametros degradados, casa exatamente, e e' o que todos os apps validados
// em runtime usam (PureSwiftDemo, SwiftUIDemo, ResumoFit, TortureTest,
// Minesweeper).
//
// Se precisar MESMO de launchOptions, consulte a assinatura real primeiro:
//     python3 scripts/check-protocol-sig.py UIApplicationDelegate didFinishLaunching
//
// O arquivo do entry point deve se chamar `main.swift` (ou `*Main.swift`, que
// o build renomeia) e a chamada `UIApplicationMain(...)` DEVE ser a ultima
// linha — sem ela o `_main` sai vazio e o app "returns from main with code 0".

import Foundation
import SwiftUI
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    // ✅ assinatura que CASA com o protocolo do SDK patchado
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)

        // --- UIKit puro:
        // w.rootViewController = MeuViewController()

        // --- SwiftUI (o ciclo de vida fica em UIKit; a UI e' 100% SwiftUI):
        w.rootViewController = UIHostingController(rootView: ContentView())

        w.makeKeyAndVisible()
        window = w
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Funcionando")
                .font(.largeTitle)
            Text("entry point correto")
                .foregroundColor(.secondary)
        }
    }
}

// A CHAMADA ABAIXO E' OBRIGATORIA E DEVE SER A ULTIMA LINHA DO ARQUIVO.
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))
