// DebugSupport.swift — optional forge-on-glass instrumentation.
// Included only by the builders when they receive --debug.
// StikDebug stays external: this file only provides logs, overlay and the
// URL request to enable JIT in the current process.

import Foundation
import UIKit
import Darwin

public enum ISBDebugRuntime {
    private static var installed = false
    private static var overlay: UIView?
    public static var scriptName: String? = nil
    // Inside LiveContainer, StikDebug must reopen the host container,
    // not the guest app's bundle ID. The builder can override this value
    // at build time with --stikdebug-bundle-id.
    public static var returnBundleID: String? = nil
    public static var debugSessionRequested = false

    public static var isLiveContainer: Bool {
        getenv("LC_HOME_PATH") != nil
    }

    public static var processID: Int32 { getpid() }

    public static func log(_ message: String) {
        let tag = "[forge-on-glass][pid=\(processID)]"
        NSLog("%@ %@", tag, message)
        print("\(tag) \(message)")
    }

    /// Registers the observer before the first didBecomeActive. This makes the
    /// instrumentation independent of the AppDelegate shape (SwiftUI,
    /// UIKit, SceneDelegate or ObjC shell).
    public static func bootstrap() {
        log("debug runtime loaded")
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: OperationQueue.main
        ) { _ in
            installOnKeyWindow()
        }
    }

    /// Called by the builder in didFinishLaunching. The log is synchronous; the
    /// visual installation waits for the UIWindow to exist.
    /// Installs directly into the window created by the SceneDelegate. Avoids
    /// the race where UIApplication.shared.windows is still empty.
    public static func install(on window: UIWindow) {
        installOnWindow(window)
    }

    public static func installOnWindow(_ window: UIWindow) {
        if installed { return }
        installed = true
        let bar = ISBDebugBar(frame: isbBarFrame())
        bar.onTap = { openStikDebug() }
        window.addSubview(bar)
        window.bringSubviewToFront(bar)
        overlay = bar
        log("debug overlay installed; tap DBG to open StikDebug")
    }

    /// Keeps the global lookup for apps without a SceneDelegate.
    public static func installOnKeyWindow() {
        if installed { return }
        let windows = UIApplication.shared.windows
        let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
        guard let window = window else {
            log("debug overlay: no UIWindow found")
            return
        }
        installOnWindow(window)
    }

    /// Compatibility with the name used by the builder.
    public static func installAfterLaunch() { installOnKeyWindow() }


    /// Opens the official StikDebug request for this process's PID.
    /// Opening the URL is not considered success: the app keeps showing
    /// the PID and the user confirms readiness in the console/overlay.
    public static func openStikDebug() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            log("ERROR: missing bundle identifier; could not build URL")
            return
        }
        let targetBundleID = ISBDebugRuntime.returnBundleID ?? bundleID
        var components = URLComponents()
        components.scheme = "stikdebug"
        components.host = "enable-jit"
        var items = [
            URLQueryItem(name: "bundle-id", value: targetBundleID),
            URLQueryItem(name: "pid", value: String(processID))
        ]
        // Persistent low-level script. Keeps the session open like
        // universal.js, but does not try to interpret JIT commands: it just lets
        // the debugserver continue, logs each stop/signal and inspects
        // thread/registers. The user ends it from StikDebug.
        let lowLevelScript = """
        function show(label, value) {
            let text = value === null || value === undefined ? '<nil>' : String(value);
            if (text.length > 768) text = text.substring(0, 768) + '...';
            log(label + ' = ' + text);
        }
        function parseThread(response) {
            if (!response) return null;
            let m = /thread:([0-9a-f]+);/i.exec(response);
            return m ? m[1] : null;
        }
        const pid = get_pid();
        let attached = false;
        let stops = 0;
        log('forge-on-glass persistent low-level attach');
        log('pid = ' + pid);
        try {
            const attach = send_command('vAttach;' + pid.toString(16));
            show('vAttach', attach);
            attached = true;
            show('qSupported', send_command('qSupported'));
            show('qfThreadInfo', send_command('qfThreadInfo'));
            let current = send_command('qC');
            show('qC', current);
            let thread = parseThread(current);
            if (thread) show('Hg', send_command('Hg' + thread));
            while (true) {
                stops++;
                log('debug stop/continue #' + stops);
                const stop = send_command('c');
                show('stop', stop);
                if (!stop) break;
                current = send_command('qC');
                show('qC', current);
                thread = parseThread(current);
                if (thread) show('Hg', send_command('Hg' + thread));
                const registers = send_command('g');
                log('register_packet_length = ' + (registers ? registers.length : 0));
                show('register_packet_prefix', registers ? registers.substring(0, 256) : null);
            }
        } catch (error) {
            log('debug session interrupted: ' + (error && error.message ? error.message : error));
        }
        if (attached) show('detach', send_command('D'));
        log('forge-on-glass persistent low-level session complete');
        """
        if let data = lowLevelScript.data(using: .utf8) {
            let encoded = data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            items.append(URLQueryItem(name: "script-data", value: encoded))
            items.append(URLQueryItem(name: "script-name", value: "forge-on-glass-lowlevel.js"))
        }
        components.queryItems = items
        guard let url = components.url else {
            log("ERROR: invalid StikDebug URL")
            return
        }
        debugSessionRequested = true
        log("requesting StikDebug: \(url.absoluteString)")
        UIApplication.shared.open(url)
    }
}

/// Small, independent bar so it does not interfere with the app's UI.
/// It is created only in --debug builds.
private final class ISBDebugBar: UIView {
    var onTap: (() -> Void)?
    private let title = UILabel(frame: isbTitleFrame())

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.08, green: 0.35, blue: 0.78, alpha: 0.94)
        layer.cornerRadius = 9
        title.text = "DBG • tap: StikDebug"
        title.textColor = UIColor.white
        title.font = UIFont.systemFont(ofSize: 12)
        addSubview(title)
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                     action: Selector(("pressed"))))
    }

    required init?(coder: NSCoder) { return nil }

    @objc private func pressed() { onTap?() }
}

// The bootstrap is called explicitly by the builder before
// UIApplicationMain. This avoids depending on global initialization order.

// ---------------------------------------------------------------------------
// FRAMES ISOLATED AT THE END OF THE FILE — DO NOT MOVE THEM UP.
//
// In this toolchain, if a declaration that uses CoreGraphics
// (CGRect(origin:size:) / CGPoint / CGSize) appears BEFORE a declaration
// that uses Foundation (Bundle, NotificationCenter, OperationQueue) in the SAME
// file, Foundation degrades and disappears from the scope of the entire file:
//
//   error: cannot find 'Bundle' in scope
//   error: cannot find 'NotificationCenter' in scope
//
// Deterministic (3/3) in whole-module mode; it does not occur with -primary-file.
// See references/WARNINGS-FATAIS.md -> "CoreGraphics before Foundation".
// ---------------------------------------------------------------------------

private func isbBarFrame() -> CGRect {
    return CGRect(origin: CGPoint(x: 10, y: 48),
                  size: CGSize(width: 178, height: 38))
}

private func isbTitleFrame() -> CGRect {
    return CGRect(origin: CGPoint(x: 9, y: 0),
                  size: CGSize(width: 160, height: 38))
}
