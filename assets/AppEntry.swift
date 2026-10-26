// AppEntry.swift — entry point TEMPLATE. COPY THIS PATTERN.
//
// ⚠️ THE MOST EXPENSIVE RULE OF THIS PROJECT (an entire session lost, 2026-08-22):
//
// Use `applicationDidFinishLaunching(_:)`.
// Do NOT use `application(_:didFinishLaunchingWithOptions:)`.
//
// WHY: the SDK `.swiftinterface` files were patched to compile with the
// swift.org toolchain, and in that process the type of `launchOptions` degraded:
//
//     Apple:      [UIApplication.LaunchOptionsKey: Any]?
//     our SDK:    NSDictionary<NSString, AnyObject>?
//
// Since the protocol requirement is OPTIONAL (`optional func`, inherited from
// ObjC), writing Apple's signature does NOT produce an error. It only gives:
//
//     warning: instance method 'application(_:didFinishLaunchingWithOptions:)'
//     nearly matches optional requirement ... of protocol 'UIApplicationDelegate'
//
// The method becomes a PLAIN method of the class. UIKit never calls it. The
// window is never created. The app LAUNCHES, stays ALIVE, and shows a BLACK
// SCREEN forever — no crash, no log, nothing that points to the cause.
//
// `applicationDidFinishLaunching(_ application: UIApplication)` has no
// degraded parameters, matches exactly, and is what all the runtime-validated
// apps use (PureSwiftDemo, SwiftUIDemo, ResumoFit, TortureTest,
// Minesweeper).
//
// If you REALLY need launchOptions, check the real signature first:
//     python3 scripts/check-protocol-sig.py UIApplicationDelegate didFinishLaunching
//
// The entry point file must be named `main.swift` (or `*Main.swift`, which the
// build renames) and the `UIApplicationMain(...)` call MUST be the last
// line — without it `_main` comes out empty and the app "returns from main with code 0".

import Foundation
import SwiftUI
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    // ✅ signature that MATCHES the patched SDK protocol
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)

        // --- Pure UIKit:
        // w.rootViewController = MeuViewController()

        // --- SwiftUI (lifecycle stays in UIKit; the UI is 100% SwiftUI):
        w.rootViewController = UIHostingController(rootView: ContentView())

        w.makeKeyAndVisible()
        window = w
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Working")
                .font(.largeTitle)
            Text("correct entry point")
                .foregroundColor(.secondary)
        }
    }
}

// THE CALL BELOW IS MANDATORY AND MUST BE THE LAST LINE OF THE FILE.
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))
