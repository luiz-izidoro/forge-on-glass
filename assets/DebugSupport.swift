// DebugSupport.swift — instrumentacao opcional do ios-swift-builder.
// Incluido apenas pelos builders quando recebem --debug.
// StikDebug permanece externo: este arquivo so fornece logs, overlay e o
// pedido URL para habilitar JIT no processo atual.

import Foundation
import UIKit
import Darwin

public enum ISBDebugRuntime {
    private static var installed = false
    private static var overlay: UIView?
    public static var scriptName: String? = nil
    // Dentro do LiveContainer, o StikDebug deve reabrir o container host,
    // nao o bundle ID do app convidado. O builder pode substituir este valor
    // no build com --stikdebug-bundle-id.
    public static var returnBundleID: String? = nil
    public static var debugSessionRequested = false

    public static var isLiveContainer: Bool {
        getenv("LC_HOME_PATH") != nil
    }

    public static var processID: Int32 { getpid() }

    public static func log(_ message: String) {
        let tag = "[ios-swift-builder][pid=\(processID)]"
        NSLog("%@ %@", tag, message)
        print("\(tag) \(message)")
    }

    /// Registra o observador antes do primeiro didBecomeActive. Isso torna a
    /// instrumentacao independente do formato do AppDelegate (SwiftUI,
    /// UIKit, SceneDelegate ou shell ObjC).
    public static func bootstrap() {
        log("debug runtime carregado")
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: OperationQueue.main
        ) { _ in
            installOnKeyWindow()
        }
    }

    /// Chamada pelo builder no didFinishLaunching. O log e sincronico; a
    /// instalacao visual espera a UIWindow existir.
    /// Instala diretamente na janela criada pelo SceneDelegate. Evita a
    /// corrida em que UIApplication.shared.windows ainda esta vazio.
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
        log("debug overlay instalado; toque DBG para abrir StikDebug")
    }

    /// Mantem a busca global para apps sem SceneDelegate.
    public static func installOnKeyWindow() {
        if installed { return }
        let windows = UIApplication.shared.windows
        let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
        guard let window = window else {
            log("debug overlay: nenhuma UIWindow encontrada")
            return
        }
        installOnWindow(window)
    }

    /// Compatibilidade com o nome usado pelo builder.
    public static func installAfterLaunch() { installOnKeyWindow() }


    /// Abre o pedido oficial do StikDebug para o PID deste processo.
    /// A abertura da URL nao e considerada sucesso: o app continua exibindo
    /// o PID e o usuario confirma o readiness no console/overlay.
    public static func openStikDebug() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            log("ERRO: bundle identifier ausente; nao foi possivel montar URL")
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
        // Script persistente de baixo nivel. Mantem a sessao aberta como o
        // universal.js, mas nao tenta interpretar comandos JIT: apenas deixa
        // o debugserver continuar, registra cada parada/sinal e inspeciona
        // thread/registradores. O usuario encerra pelo StikDebug.
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
        log('ios-swift-builder persistent low-level attach');
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
        log('ios-swift-builder persistent low-level session complete');
        """
        if let data = lowLevelScript.data(using: .utf8) {
            let encoded = data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            items.append(URLQueryItem(name: "script-data", value: encoded))
            items.append(URLQueryItem(name: "script-name", value: "ios-swift-builder-lowlevel.js"))
        }
        components.queryItems = items
        guard let url = components.url else {
            log("ERRO: URL do StikDebug invalida")
            return
        }
        debugSessionRequested = true
        log("solicitando StikDebug: \(url.absoluteString)")
        UIApplication.shared.open(url)
    }
}

/// Barra pequena e independente para nao interferir na UI do app.
/// Ela e criada somente em builds --debug.
private final class ISBDebugBar: UIView {
    var onTap: (() -> Void)?
    private let title = UILabel(frame: isbTitleFrame())

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.08, green: 0.35, blue: 0.78, alpha: 0.94)
        layer.cornerRadius = 9
        title.text = "DBG • toque: StikDebug"
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

// O bootstrap e' chamado explicitamente pelo builder antes de
// UIApplicationMain. Isso evita depender da ordem de inicializacao global.

// ---------------------------------------------------------------------------
// FRAMES ISOLADOS NO FIM DO ARQUIVO — NAO MOVER PARA CIMA.
//
// Neste toolchain, se uma declaracao que usa CoreGraphics
// (CGRect(origin:size:) / CGPoint / CGSize) aparece ANTES de uma declaracao
// que usa Foundation (Bundle, NotificationCenter, OperationQueue) no MESMO
// arquivo, o Foundation degrada e some do escopo do arquivo inteiro:
//
//   error: cannot find 'Bundle' in scope
//   error: cannot find 'NotificationCenter' in scope
//
// Determinstico (3/3) em modo whole-module; nao ocorre com -primary-file.
// Ver references/WARNINGS-FATAIS.md -> "CoreGraphics antes de Foundation".
// ---------------------------------------------------------------------------

private func isbBarFrame() -> CGRect {
    return CGRect(origin: CGPoint(x: 10, y: 48),
                  size: CGSize(width: 178, height: 38))
}

private func isbTitleFrame() -> CGRect {
    return CGRect(origin: CGPoint(x: 9, y: 0),
                  size: CGSize(width: 160, height: 38))
}
