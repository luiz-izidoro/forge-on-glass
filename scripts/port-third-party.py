#!/usr/bin/env python3
"""port-third-party.py — builda apps iOS de terceiros (SwiftUI/UIKit puros) SEM edicao manual.

Uso:
  port-third-party.py <dir-do-projeto> <AppName> <BundleID>

Fluxo:
  1. Coleta os .swift do target iOS (pula pastas mac/tests/preview, import AppKit).
  2. Adapta automaticamente: entry point (@UIApplicationMain -> main.swift com a
     chamada UIApplicationMain(...)) e reordena os imports na ordem canonica
     (Foundation -> SwiftUI -> UIKit -> CoreText -> Dispatch).
  3. Roda build-pure-ui.sh (com PureSwiftKit sempre incluido) num loop REATIVO:
     cada erro de compilacao conhecido (CGRect members, UIEdgeInsetsMake,
     TimeInterval, imports faltando, init CGRect...) e corrigido na linha exata
     e o build e repetido — ate passar ou sobrarem erros desconhecidos.
  4. Valida o IPA e escreve <AppName>-port.md (relatorio) no workspace.

The adaptation rules are maintained in the current project guide and handoff.
"""

import os
import re
import shutil
import subprocess
import sys

SKILL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD_SH = os.path.join(SKILL, "scripts", "build-pure-ui.sh")
VALIDATE_SH = os.path.join(SKILL, "scripts", "validate-ipa.sh")
KIT = os.path.join(SKILL, "assets", "PureSwiftKit.swift")
WORKSPACE = "/var/minis/workspace"
MAX_ITER = 10

# Import order is defined by references/BEST-PRACTICES.md.
CANON = {"Foundation": 1, "CoreFoundation": 2, "SwiftUI": 3,
         "UIKit": 4, "CoreText": 5, "Dispatch": 6, "Combine": 7, "Darwin": 8}
# NOTA (2026-08-22): Dispatch DEPOIS de UIKit e' obrigatorio. Medido com 4
# ordens diferentes: so `Foundation UIKit Dispatch <Modulo>` resolve o overlay
# Swift do DispatchQueue (conformance a Scheduler, DispatchQueue.main,
# init(label:qos:)). Com Dispatch antes do UIKit o DispatchQueue vira a classe
# ObjC crua e os erros aparecem LONGE da causa ("does not conform to protocol
# 'Scheduler'", "extra argument 'qos' in call").

# Membros de CGRect/CGAffineTransform/CGPoint/CGSize que nao existem no SDK
# exposto pelo toolchain (extensions @_alwaysEmitIntoClient invisiveis).
# Fix: usar os helpers do PureSwiftKit (cg*).
MEMBER_FIX = {
    "CGRect": {
        "width": "cgWidth", "height": "cgHeight",
        "minX": "cgMinX", "midX": "cgMidX", "maxX": "cgMaxX",
        "minY": "cgMinY", "midY": "cgMidY", "maxY": "cgMaxY",
        "insetBy": "cgInsetBy", "offsetBy": "cgOffsetBy",
        "union": "cgUnion", "intersection": "cgIntersection",
        "intersects": "cgIntersects", "contains": "cgContains",
        "zero": "cgRectZero", "null": "cgRectNull", "infinite": "cgRectInfinite",
    },
    "CGAffineTransform": {"identity": "cgAffineIdentity", "zero": "cgAffineIdentity"},
    "CGPoint": {"zero": "cgPointZero"},
    "CGSize": {"zero": "cgSizeZero"},
}

MATH_FUNCS = {"log", "log2", "log10", "pow", "sqrt", "sin", "cos", "tan",
              "floor", "ceil", "round", "abs", "fabs", "exp"}


def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


def log_append(log, entry):
    log.append(entry)
    print("   - " + entry)


# ---------------------------------------------------------------- passo 1: coleta
def skip_dir(d):
    b = os.path.basename(d).lower()
    return any(k in b for k in ("-mac", "macos", "preview content", "tests",
                                "uitest", "benchmark", ".xcodeproj",
                                ".xcworkspace", ".git"))


def collect(src_dir):
    out = []
    for root, dirs, files in os.walk(src_dir):
        dirs[:] = [d for d in dirs if not skip_dir(d)]
        for f in sorted(files):
            if not f.endswith(".swift"):
                continue
            p = os.path.join(root, f)
            s = read(p)
            if re.search(r"^\s*import\s+AppKit\b", s, re.M):
                continue  # mac-only
            out.append(p)
    return out


# ------------------------------------------------------- passo 2: pre-adaptacao
def reorder_imports(s):
    """Reordena o bloco contiguo de imports do topo para a ordem canonica."""
    lines = s.split("\n")
    i = 0
    while i < len(lines):
        t = lines[i].lstrip()
        if t == "" or t.startswith("//") or t.startswith("/*") or t.startswith("*"):
            i += 1
        else:
            break
    j = i
    blk = []
    while j < len(lines) and re.match(r"\s*import\s+\w+", lines[j]):
        blk.append((j, lines[j]))
        j += 1
    if len(blk) < 2:
        return s

    def mod(line):
        m = re.search(r"import\s+(\w+)", line)
        return m.group(1) if m else ""

    new = [t for _, t in sorted(blk, key=lambda x: CANON.get(mod(x[1]), 99))]
    lines[i:j] = new
    return "\n".join(lines)


def ensure_import(s, module):
    """Adiciona `import <module>` no topo (na posicao canonica) se faltar."""
    if re.search(r"^\s*import\s+" + module + r"\b", s, re.M):
        return s, False
    lines = s.split("\n")
    # CASO ESPECIAL Dispatch: precisa vir DEPOIS do Foundation (a ordem
    # Foundation->Dispatch e obrigatoria; Foundation depois de Dispatch faz o
    # DispatchQueue resolver para Foundation.DispatchQueue sem as extensions).
    # O Foundation pode estar dentro de #if (ex: CombineSchedulers) — inserir
    # logo apos a linha do Foundation, com a mesma indentacao.
    if module == "Dispatch":
        for idx, ln in enumerate(lines):
            m = re.match(r"^(\s*)import\s+Foundation\b", ln)
            if m:
                lines.insert(idx + 1, m.group(1) + "import Dispatch")
                return "\n".join(lines), True
    # acha o fim do bloco de imports atual (posicao de insercao)
    i = 0
    while i < len(lines):
        t = lines[i].lstrip()
        if t == "" or t.startswith("//") or t.startswith("/*") or t.startswith("*"):
            i += 1
        else:
            break
    j = i
    while j < len(lines) and re.match(r"\s*import\s+\w+", lines[j]):
        j += 1
    ins = j
    # insere antes do primeiro import com prioridade maior
    while ins > i and CANON.get(mod_name(lines[ins - 1]), 99) > CANON.get(module, 99):
        ins -= 1
    lines.insert(ins, "import " + module)
    return "\n".join(lines), True


def mod_name(line):
    m = re.search(r"import\s+(\w+)", line)
    return m.group(1) if m else ""


def fix_delegate_signature(path, log):
    """Troca `application(_:didFinishLaunchingWithOptions:)` por
    `applicationDidFinishLaunching(_:)`.

    MOTIVO (2026-08-22): no SDK patchado o launchOptions e'
    NSDictionary<NSString, AnyObject>?, nao [LaunchOptionsKey: Any]?. Como o
    requisito do protocolo e' OPCIONAL, a assinatura da Apple compila com
    apenas um WARNING e o UIKit NUNCA chama o metodo -> app abre com TELA
    PRETA. Ver references/WARNINGS-FATAIS.md.
    """
    s = read(path)
    if "didFinishLaunchingWithOptions" not in s:
        return False
    # assinatura (pode estar quebrada em varias linhas)
    pat = re.compile(
        r"func\s+application\s*\(\s*_\s+(\w+)\s*:\s*UIApplication\s*,\s*"
        r"didFinishLaunchingWithOptions\s+(\w+)\s*:\s*[^)]*\)\s*->\s*Bool\s*\{",
        re.S)
    m = pat.search(s)
    if not m:
        return False
    appvar = m.group(1)
    s2 = s[:m.start()] + \
        "func applicationDidFinishLaunching(_ %s: UIApplication) {" % appvar + \
        s[m.end():]
    # remove o `return true` do fim do metodo (agora e' Void)
    s2 = re.sub(r"\n(\s*)return\s+true\s*\n(\s*)\}", r"\n\2}", s2, count=1)
    write(path, s2)
    log_append(log, "entry: application(_:didFinishLaunchingWithOptions:) -> "
                    "applicationDidFinishLaunching(_:) "
                    "(assinatura da Apple nao casa com o SDK patchado = tela preta)")
    return True


def convert_swiftui_app(s, path, log):
    """Converte `@main struct X: App { var body: some Scene { WindowGroup { V() } } }`
    em AppDelegate + UIApplicationMain + UIHostingController.

    POR QUE: o ciclo de vida SwiftUI (`App`/`Scene`) depende de macros e
    metadata que nao sobrevivem ao interface-compile deste toolchain; alem
    disso `@main` + arquivo `main.swift` (top-level) e' erro do compilador.
    A UI continua 100% SwiftUI — so o ciclo de vida vira UIKit.

    Extrai o conteudo do WindowGroup para usar como rootView. Se nao conseguir
    identificar, cai para a primeira `View` do arquivo.
    """
    # 1. nome da struct @main e corpo
    m = re.search(r"@main\s+(?:public\s+)?struct\s+(\w+)\s*:\s*App\b", s)
    if not m:
        # @main em outra coisa (ex.: enum com main()): so remove o atributo
        s2 = re.sub(r"^\s*@main\s*$", "", s, flags=re.M)
        log_append(log, "entry: @main removido (nao era `struct: App`)")
        return reorder_imports(s2)
    app_name = m.group(1)

    # 2. conteudo do WindowGroup { ... } (primeira ocorrencia, balanceado)
    root_expr = None
    wg = re.search(r"WindowGroup\s*(?:\([^)]*\))?\s*\{", s)
    if wg:
        i = s.index("{", wg.start())
        depth = 0
        for j in range(i, len(s)):
            if s[j] == "{":
                depth += 1
            elif s[j] == "}":
                depth -= 1
                if depth == 0:
                    root_expr = s[i + 1:j].strip()
                    break
    if not root_expr:
        vm = re.search(r"struct\s+(\w+)\s*:\s*(?:\w+\s*,\s*)*View\b", s)
        root_expr = (vm.group(1) + "()") if vm else "Text(\"App\")"
        log_append(log, "entry: WindowGroup nao encontrado; rootView = " + root_expr)

    # 3. remove a struct @main inteira (ela nao pode coexistir com top-level code)
    start = s.rindex("@main", 0, m.end())
    i = s.index("{", m.end() - 1)
    depth = 0
    end = i
    for j in range(i, len(s)):
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                end = j + 1
                break
    s2 = s[:start] + s[end:]

    # 4. imports + AppDelegate + UIApplicationMain
    for mod in ("Foundation", "SwiftUI", "UIKit"):
        s2, _ = ensure_import(s2, mod)
    s2 = reorder_imports(s2)

    delegate = '''

// ---------------------------------------------------------------------------
// Entry point convertido automaticamente de `@main struct %s: App`.
// O ciclo de vida SwiftUI (App/Scene) depende de macros que nao sobrevivem ao
// interface-compile deste toolchain. A UI continua 100%% SwiftUI; so o ciclo
// de vida e' UIKit.
//
// ATENCAO: use `applicationDidFinishLaunching(_:)`. A assinatura
// `application(_:didFinishLaunchingWithOptions:)` NAO casa com o
// .swiftinterface patchado (launchOptions e' NSDictionary aqui) -> o Swift so
// avisa, nao gera o thunk ObjC, o UIKit nunca chama o metodo e o app abre com
// TELA PRETA. Ver references/WARNINGS-FATAIS.md
// ---------------------------------------------------------------------------
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_ application: UIApplication) {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = UIHostingController(rootView: %s)
        w.makeKeyAndVisible()
        window = w
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))
''' % (app_name, root_expr)

    log_append(log, "entry: @main struct %s: App -> AppDelegate + UIApplicationMain "
                    "(rootView: %s)" % (app_name, root_expr.replace("\n", " ")[:60]))
    return s2.rstrip() + "\n" + delegate


def adapt_entry(files, log):
    """Acha o entry point e o adapta: @UIApplicationMain -> main.swift com a chamada."""
    # SEMPRE corrigir a assinatura do delegate, em qualquer arquivo
    for p in files:
        try:
            fix_delegate_signature(p, log)
        except Exception:
            pass
    mains = [p for p in files if os.path.basename(p) == "main.swift"]
    if mains:
        log_append(log, "entry: main.swift ja existe (top-level), mantido")
        return mains[0]
    for p in files:
        s = read(p)
        if re.search(r"\bUIApplicationMain\s*\(", s):
            # ja e um entry AppDelegate-style (top-level UIApplicationMain) —
            # o build-pure-ui.sh o reconhece pelo nome *Main.swift
            log_append(log, "entry: UIApplicationMain(...) ja presente no top-level, mantido")
            return p
        if "@UIApplicationMain" in s:
            s2 = re.sub(r"^\s*@UIApplicationMain\s*$", "", s, flags=re.M)
            m = re.search(r"class\s+(\w+)\s*:\s*UIResponder", s2)
            if not m:
                m = re.search(r"class\s+(\w+)\s*:", s2)
            cls = m.group(1) if m else "AppDelegate"
            s2, a1 = ensure_import(s2, "Foundation")
            s2, a2 = ensure_import(s2, "UIKit")
            s2 = reorder_imports(s2)
            s2 = s2.rstrip() + "\n\nUIApplicationMain(CommandLine.argc, " \
                             "CommandLine.unsafeArgv, nil, NSStringFromClass(" \
                             + cls + ".self))\n"
            write(p, s2)
            log_append(log, "entry: @UIApplicationMain removido; chamada "
                            "UIApplicationMain(...) adicionada (classe " + cls + ")")
            nb = os.path.splitext(os.path.basename(p))[0] + "Main.swift"
            np_ = os.path.join(os.path.dirname(p), nb)
            if np_ != p:
                os.rename(p, np_)
                files[files.index(p)] = np_
                log_append(log, "entry: " + os.path.basename(p) + " -> " + nb)
            return np_
        if re.search(r"^\s*@main\b", s, re.M):
            # `@main class X: UIResponder, UIApplicationDelegate` — UIKit
            # classico (com ou sem lifecycle de cena). O @main em classe
            # depende de UIApplicationDelegate.main() (metadata que nao
            # sobrevive ao interface-compile) — mesmo tratamento do
            # @UIApplicationMain: remove o atributo e anexa a chamada
            # UIApplicationMain(...) no top-level do arquivo *Main.swift.
            mcls = re.search(r"class\s+(\w+)\s*:\s*(?:NSObject\s*,\s*)?UIResponder\b", s)
            if mcls:
                cls = mcls.group(1)
                s2 = re.sub(r"^\s*@main\s*$", "", s, flags=re.M)
                s2, a1 = ensure_import(s2, "Foundation")
                s2, a2 = ensure_import(s2, "UIKit")
                s2 = reorder_imports(s2)
                s2 = s2.rstrip() + "\n\nUIApplicationMain(CommandLine.argc, " \
                                 "CommandLine.unsafeArgv, nil, NSStringFromClass(" \
                                 + cls + ".self))\n"
                write(p, s2)
                log_append(log, "entry: @main class %s (UIApplicationDelegate) -> "
                                "UIApplicationMain(...) anexada no top-level" % cls)
                nb = os.path.splitext(os.path.basename(p))[0] + "Main.swift"
                np_ = os.path.join(os.path.dirname(p), nb)
                if np_ != p:
                    os.rename(p, np_)
                    files[files.index(p)] = np_
                return np_
            # `@main struct X: App` (SwiftUI App lifecycle) NAO funciona aqui:
            # depende de macros/metadata que nao sobrevivem ao interface-compile,
            # e o arquivo vira main.swift (top-level) => erro
            #   "'main' attribute cannot be used in a module that contains
            #    top-level code".
            # Convertemos para o padrao validado em runtime:
            #   AppDelegate + UIApplicationMain + UIHostingController.
            s2 = convert_swiftui_app(s, p, log)
            write(p, s2)
            nb = os.path.splitext(os.path.basename(p))[0] + "Main.swift"
            np_ = os.path.join(os.path.dirname(p), nb)
            if np_ != p:
                os.rename(p, np_)
                files[files.index(p)] = np_
            return np_
    log_append(log, "entry: NENHUM entry point reconhecido "
                    "(@UIApplicationMain/@main/main.swift) — o build pode falhar")
    return None


# ------------------------------------------------------- lifecycle de cena
def parse_storyboard_root(story_path):
    """Extrai (classe_do_rootVC, tem_navigationController) do storyboard.

    Storyboards nao compilam sem ibtool — o port precisa recriar a arvore de
    views em codigo. Segue o initialViewController; se for um
    navigationController, segue a segue relationship rootViewController.
    """
    if not story_path or not os.path.exists(story_path):
        return None, False
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(story_path)
    except Exception:
        return None, False
    doc = tree.getroot()
    initial = doc.get("initialViewController")
    if not initial:
        return None, False

    def find_vc(scene_id):
        if not scene_id:
            return None, False
        # `initialViewController` e `segue.destination` apontam para o id do
        # objeto (navigationController/viewController), nao para sceneID.
        # O parser antigo comparava sceneID e nunca encontrava a Navigation
        # Controller — por isso o Load ROM ficava sem navigationController.
        for scene in doc.iter("scene"):
            for obj in scene.iter():
                if obj.get("id") != scene_id:
                    continue
                if obj.tag == "viewController":
                    return obj.get("customClass"), False
                if obj.tag == "navigationController":
                    for segue in obj.iter("segue"):
                        if (segue.get("kind") == "relationship"
                                and segue.get("relationship") == "rootViewController"):
                            cls, _ = find_vc(segue.get("destination"))
                            return cls or "ViewController", True
                    return None, True
        return None, False

    return find_vc(initial)


def convert_scene_delegate(path, story_path, log, debug=False):
    """Converte o willConnectTo de um SceneDelegate para criar a UIWindow em
    codigo (o storyboard que o app esperava nao existe no IPA). A classe do
    root VC e' lida do Main.storyboard; o root original ficava num
    UINavigationController, entao o wrapper e' recriado."""
    s = read(path)
    if "UIWindowSceneDelegate" not in s:
        return False
    root_cls, is_nav = parse_storyboard_root(story_path)
    if not root_cls:
        root_cls = "ViewController"
        log_append(log, "scene: storyboard nao parseado — root VC padrao "
                        "'ViewController'")
    if is_nav:
        root_expr = "UINavigationController(rootViewController: %s())" % root_cls
    else:
        root_expr = "%s()" % root_cls
    pat = re.compile(
        r"func\s+scene\s*\(\s*_\s+\w+\s*:\s*UIScene\s*,\s*"
        r"willConnectTo\s+\w+\s*:\s*UISceneSession\s*,\s*"
        r"options\s+\w+\s*:\s*UIScene\.ConnectionOptions\s*\)\s*\{", re.S)
    m = pat.search(s)
    body = ("    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, "
            "options connectionOptions: UIScene.ConnectionOptions) {\n"
            "        guard let windowScene = scene as? UIWindowScene else { return }\n"
            "        let window = UIWindow(windowScene: windowScene)\n"
            "        window.rootViewController = %s\n"
            "        window.makeKeyAndVisible()\n"
            "        self.window = window\n"
            "    }\n") % root_expr
    if debug:
        body = body.replace("        self.window = window\n", "        self.window = window\n        ISBDebugRuntime.install(on: window)\n")
    if m:
        open_i = s.index("{", m.start())
        depth, i = 1, open_i + 1
        while i < len(s) and depth:
            if s[i] == "{":
                depth += 1
            elif s[i] == "}":
                depth -= 1
            i += 1
        s2 = s[:m.start()] + body + s[i:]
    else:
        if re.search(r"var\s+window\s*:\s*UIWindow\?", s) is None:
            s2 = re.sub(
                r"(class\s+\w+\s*:\s*(?:NSObject\s*,\s*)?UIResponder\s*,\s*UIWindowSceneDelegate\s*\{)",
                r"\1\n\n    var window: UIWindow?", s, count=1)
        else:
            s2 = s
        s2 = s2.rstrip() + "\n\n" + body
    write(path, s2)
    log_append(log, "scene: willConnectTo reescrito p/ criar a janela em codigo "
                    "(root: %s)" % root_expr)
    return True


def post_process_ipa(app, res_dirs, scene_class, log, debug=False):
    """Depois do build: adiciona recursos (--resources) e o UIApplicationSceneManifest
    no Info.plist (app com lifecycle de cena), e recompacta o IPA.

    O build-pure-ui.sh gera um Info.plist fixo sem manifest e sem recursos; o
    manifest e' OBRIGATORIO para o UIKit instanciar o SceneDelegate — sem ele o
    app abre e fica com tela preta (janela nunca criada).
    """
    work = "/tmp/build-" + app
    pay_app = os.path.join(work, "Payload", app + ".app")
    if not os.path.isdir(pay_app):
        log_append(log, "ipa: Payload nao encontrado — post-process ignorado")
        return
    if scene_class:
        info = os.path.join(pay_app, "Info.plist")
        try:
            import plistlib
            with open(info, "rb") as f:
                pl = plistlib.load(f)
            pl["UIApplicationSceneManifest"] = {
                "UIApplicationSupportsMultipleScenes": False,
                "UISceneConfigurations": {
                    "UIWindowSceneSessionRoleApplication": [
                        {"UISceneConfigurationName": "Default Configuration",
                         "UISceneDelegateClassName": scene_class}
                    ]
                }
            }
            with open(info, "wb") as f:
                plistlib.dump(pl, f, sort_keys=False)
            log_append(log, "info: UIApplicationSceneManifest adicionado "
                            "(UISceneDelegateClassName = %s)" % scene_class)
        except Exception as e:
            log_append(log, "info: FALHA ao adicionar scene manifest: %s" % e)
    if res_dirs:
        for d in res_dirs:
            if not os.path.isdir(d):
                log_append(log, "resource: dir nao encontrado: " + d)
                continue
            for root, _, files in os.walk(d):
                for fn in sorted(files):
                    shutil.copy(os.path.join(root, fn),
                                os.path.join(pay_app, fn))
                    log_append(log, "resource: %s -> Payload/%s.app/%s"
                               % (os.path.relpath(os.path.join(root, fn), d),
                                  app, fn))
    # O build-pure-ui assina antes deste pos-processamento. Alterar o
    # Info.plist depois invalida o CodeDirectory; recursos novos tambem devem
    # entrar antes da assinatura final. Reassina sempre, mesmo sem recursos.
    exe = os.path.join(pay_app, app)
    if debug:
        ent = os.path.join(work, "debug-entitlements.plist")
        subprocess.run(["ldid", "-S" + ent, exe], check=True)
        log_append(log, "ipa: bundle reassinado preservando get-task-allow")
    else:
        subprocess.run(["ldid", "-S", exe], check=True)
    log_append(log, "ipa: bundle reassinado apos manifest/recursos")
    ipa = os.path.join(WORKSPACE, app + ".ipa")
    if os.path.exists(ipa):
        os.remove(ipa)
    subprocess.run(["zip", "-qr", ipa, "Payload"], cwd=work, check=True)
    log_append(log, "ipa: recompactado (recursos/manifest)")


def write_minimal_kit(srcs, work, log):
    """Gera Shims_MinimalKit.swift com SO os helpers do PureSwiftKit que o app
    usa.

    MOTIVO (2026-08-22, Chip8Emu): o kit inteiro (~260 linhas, ~55 declaracoes
    publicas) empurra o modulo alem de um limiar em que o overlay Foundation
    DEGRADA deterministicamente para arquivos irmaos — ex.: `Timer` some de
    arquivos que importam Foundation, mesmo com cache limpo. Remover o kit e
    manter so os helpers usados (aqui: cgRectZero) resolve. E a mesma classe
    do "modulo grande", agora com limite medido.
    """
    kit = read(KIT)
    used = set()
    for f in srcs:
        if os.path.basename(f) == "PureSwiftKit.swift":
            continue
        used |= set(re.findall(r"\bcg[A-Z]\w*", read(f)))
        used |= set(re.findall(r"\bedgeInsets\b", read(f)))
    # so o que o kit REALMENTE define (cgColor/cgImage/cgPath sao do SDK)
    defs = []
    for name in sorted(used):
        m = re.search(r"^public (?:let|func) " + name + r"\b.*$", kit, re.M)
        if not m:
            continue
        if "func " in m.group(0):
            start = m.start()
            open_i = kit.index("{", start)
            depth, i = 1, open_i + 1
            while i < len(kit) and depth:
                if kit[i] == "{":
                    depth += 1
                elif kit[i] == "}":
                    depth -= 1
                i += 1
            defs.append(kit[start:i])
        else:
            defs.append(m.group(0))
    # membros de extension (cgWidth, cgMinX...): inclui a extension inteira
    for m in re.finditer(r"^extension (\w+) \{", kit, re.M):
        start = m.start()
        open_i = kit.index("{", start)
        depth, i = 1, open_i + 1
        while i < len(kit) and depth:
            if kit[i] == "{":
                depth += 1
            elif kit[i] == "}":
                depth -= 1
            i += 1
        block = kit[start:i]
        if set(re.findall(r"\bcg[A-Z]\w*", block)) & used:
            defs.append(block)
    out = ("// Shims_MinimalKit.swift — helpers do PureSwiftKit gerados "
           "automaticamente\n"
           "// (o kit inteiro quebra tipos Foundation no modulo — ver "
           "PORTING-TERCEROS.md)\n"
           "import Foundation\nimport UIKit\n\n"
           + "\n\n".join(dict.fromkeys(defs)) + "\n")
    p = os.path.join(work, "Shims_MinimalKit.swift")
    write(p, out)
    log_append(log, "kit: PureSwiftKit removido (limiar de declaracoes quebrou "
                    "tipos Foundation no modulo) -> helpers minimos locais: "
                    + ", ".join(sorted(used)))
    return p


# ------------------------------------------------- passo 3: fixes reativos (loop)
ERR_RE = re.compile(r"([^\s:]+\.swift):(\d+):(\d+):\s*(?:error|warning):\s*(.*)")


def find_src(work_dir, base):
    hits = []
    for root, dirs, files in os.walk(work_dir):
        if base in files:
            hits.append(os.path.join(root, base))
    return hits[0] if hits else None


def fix_line(path, lineno, func, log):
    s = read(path)
    lines = s.split("\n")
    if 1 <= lineno <= len(lines):
        old = lines[lineno - 1]
        new = func(old)
        if new != old:
            lines[lineno - 1] = new
            write(path, "\n".join(lines))
            log_append(log, f"{os.path.basename(path)}:{lineno}: {old.strip()!r} -> {new.strip()!r}")
            return True
    return False


def member_fix_for(typename, member):
    m = MEMBER_FIX.get(typename)
    if not m or member not in m:
        return None
    return m[member]


def apply_member_fix(line, typename, member):
    repl = member_fix_for(typename, member)
    if not repl:
        return line
    if member in ("zero", "null", "infinite", "identity"):
        # estaticos: CGRect.zero -> cgRectZero (e .zero solto na linha do erro)
        line = re.sub(r"\b" + typename + r"\." + member + r"\b", repl, line)
        line = re.sub(r"(?<![\w.])\.zero\b(?![\w])", repl, line)
    else:
        # membro: rect.width -> rect.cgWidth (todas as ocorrencias na linha)
        line = re.sub(r"\." + member + r"\b(?![\w])", "." + repl, line)
    return line


# --- fixes reativos: cada erro conhecido -> transformacao no arquivo fonte -----
# Módulos donos de tipos que "somem" (erros fantasma do swift-frontend no iSH:
# o mesmo build ora compila, ora reporta tipos ausentes). Se o import já existe
# no arquivo, é fantasma -> retry do build (não aplicar fix).
TYPE_MODULE = {
    "DispatchQueue": "Dispatch", "DispatchTime": "Dispatch",
    "DispatchWorkItem": "Dispatch", "DispatchGroup": "Dispatch",
    "DispatchQoS": "Dispatch", "DispatchSemaphore": "Dispatch",
    "FileManager": "Foundation", "Bundle": "Foundation", "UUID": "Foundation",
    "Locale": "Foundation", "Formatter": "Foundation", "URL": "Foundation",
    "NSLocalizedString": "Foundation", "TimeInterval": "Foundation",
    "NSNumber": "Foundation", "NSString": "Foundation", "NSIndexPath": "Foundation",
    # tipos-valor do Foundation que somem quando o arquivo so importa UIKit
    "IndexPath": "Foundation", "IndexSet": "Foundation", "Data": "Foundation",
    "Date": "Foundation", "DateFormatter": "Foundation", "Calendar": "Foundation",
    "NumberFormatter": "Foundation", "UserDefaults": "Foundation",
    "NotificationCenter": "Foundation", "Notification": "Foundation",
    "JSONDecoder": "Foundation", "JSONEncoder": "Foundation",
    "JSONSerialization": "Foundation", "URLSession": "Foundation",
    "URLRequest": "Foundation", "URLComponents": "Foundation",
    "NSObject": "Foundation", "NSLock": "Foundation", "NSRecursiveLock": "Foundation",
    "NSCoder": "Foundation",
    "Thread": "Foundation", "RunLoop": "Foundation", "Timer": "Foundation",
    "Process": "Foundation", "Progress": "Foundation", "Measurement": "Foundation",
    "UIFont": "UIKit", "UIColor": "UIKit",
    "ObservableObject": "Combine", "Publisher": "Combine", "Cancellable": "Combine",
    "AnyCancellable": "Combine", "PassthroughSubject": "Combine",
    "CurrentValueSubject": "Combine", "AnyPublisher": "Combine",
    "NSAttributedString": "CoreText",
}


def is_ghost_error(src, msg):
    """True se o erro 'cannot find X' ocorre num arquivo que JA importa o modulo."""
    # ATENCAO (2026-08-22): erros de INFERENCIA nao sao fantasmas nem tem fix
    # automatico — sao codigo que o type-checker do iSH nao fecha. Ver
    # PORTING-TERCEROS.md §11 (reescrever com tipos nominais explicitos).
    m = re.search(r"cannot find(?: type)? '(\w+)' in scope", msg)
    if not m:
        return False
    name = m.group(1)
    # TimeInterval NAO e fantasma: e a degradacao documentada (some com UIKit
    # MESMO com Foundation importado) — o fix (c) substitui por Double.
    if name == "TimeInterval":
        return False
    mod = TYPE_MODULE.get(name)
    if not mod:
        return False
    s = read(src)
    return re.search(r"^\s*import\s+" + mod + r"\b", s, re.M) is not None


def fix_known_errors(work_dir, build_out, log):
    """Retorna (aplicou_fix, tem_fantasma)."""
    fixed = False
    ghost = False
    for m in ERR_RE.finditer(build_out):
        base = os.path.basename(m.group(1))  # path completo -> so o nome
        ln, col, msg = int(m.group(2)), int(m.group(3)), m.group(4)
        src = find_src(work_dir, base)
        if not src:
            continue

        # erro fantasma: o tipo "some" mas o import do modulo ja existe —
        # e um bug transiente do swift-frontend (retry resolve, fix nao)
        if is_ghost_error(src, msg):
            ghost = True
            continue

        # (a) CGRect/CGAffineTransform/CGPoint/CGSize: membro inexistente
        tm = re.match(r"value of type '(\w+)' has no member '(\w+)'", msg)
        if tm and tm.group(1) in MEMBER_FIX:
            typename, member = tm.group(1), tm.group(2)
            if member_fix_for(typename, member):
                fixed |= fix_line(src, ln,
                                  lambda l: apply_member_fix(l, typename, member),
                                  log)
                continue
        tm = re.match(r"type '(\w+)' has no member '(\w+)'", msg)
        if tm and tm.group(1) in MEMBER_FIX:
            typename, member = tm.group(1), tm.group(2)
            if member_fix_for(typename, member):
                fixed |= fix_line(src, ln,
                                  lambda l: apply_member_fix(l, typename, member),
                                  log)
                continue

        # (b) UIEdgeInsetsMake nao existe -> init com labels
        if "UIEdgeInsetsMake" in msg:
            s = read(src)
            s2 = re.sub(r"UIEdgeInsetsMake\(\s*([^,()]+?)\s*,\s*([^,()]+?)\s*,\s*"
                        r"([^,()]+?)\s*,\s*([^,()]+?)\s*\)",
                        r"UIEdgeInsets(top: \1, left: \2, bottom: \3, right: \4)", s)
            if s2 != s:
                write(src, s2)
                log_append(log, "UIEdgeInsetsMake -> UIEdgeInsets(top:left:bottom:right:)")
                fixed = True
            continue

        # (c) TimeInterval some com UIKit -> Double (typealias). Se o import
        # Foundation ja existe, o import nao resolve — substituir o tipo.
        if re.search(r"cannot find(?: type)? 'TimeInterval' in scope", msg):
            s = read(src)
            if re.search(r"^\s*import\s+Foundation\b", s, re.M):
                fixed |= fix_line(src, ln,
                                  lambda l: re.sub(r"\bTimeInterval\b", "Double", l),
                                  log)
            else:
                s, a = ensure_import(s, "Foundation")
                if a:
                    write(src, s)
                    log_append(log, "import Foundation adicionado (TimeInterval)")
                    fixed = True
            continue

        # (d) import CoreText (NSAttributedString.Key)
        if "NSAttributedString" in msg and "Key" in msg and "cannot find" in msg:
            s, a = ensure_import(read(src), "CoreText")
            if a:
                write(src, s)
                log_append(log, "import CoreText adicionado (NSAttributedString.Key)")
                fixed = True
            continue

        # (d2) IndexPath <-> NSIndexPath: neste toolchain os protocolos ObjC
        # (UITableViewDataSource, UICollectionViewDataSource, ...) expoem
        # NSIndexPath, nao IndexPath. Erros tipicos:
        #   "cannot convert value of type 'IndexPath' to expected argument type 'NSIndexPath'"
        #   "type 'X' does not conform to protocol 'UITableViewDataSource'"
        # Fix generico: na ASSINATURA use NSIndexPath; no corpo, converta.
        # Confirme a assinatura real com:
        #   python3 scripts/check-protocol-sig.py <Protocolo> <membro>
        if re.search(r"cannot convert value of type 'IndexPath' to expected "
                     r"argument type 'NSIndexPath'", msg):
            def _to_nsindexpath(l):
                # IDEMPOTENTE: nao mexe se ja converteu (senao o loop reativo
                # aplica o fix em cima do proprio fix)
                if "NSIndexPath(item:" in l:
                    return l
                # ⚠️ `\w*[iI]ndexPath` (nao `[A-Za-z_]\w*[iI]ndexPath`): o antigo
                # exigia 1 char antes de 'indexPath' e nunca casava nomes de
                # 9 chars como `indexPath` (bug latente, achado 2026-08-22).
                return re.sub(
                    r"\b(for|at)\s*:\s*(?!NSIndexPath\b)(\w*[iI]ndexPath)\b",
                    r"\1: NSIndexPath(item: \2.item, section: \2.section)", l)
            fixed |= fix_line(src, ln, _to_nsindexpath, log)
            continue

        # (d2b) RunLoop.Mode.common degradado -> RunLoop.Mode("kCFRunLoopCommonModes")
        # (CADisplayLink.add(to:forMode:)). No SDK patchado o membro `.common`
        # de NSRunLoopMode some; o init por rawValue funciona (probe 2026-08-22).
        if "NSRunLoopMode" in msg and "has no member 'common'" in msg:
            fixed |= fix_line(src, ln, lambda l: re.sub(
                r"forMode:\s*\.common\b",
                'forMode: RunLoop.Mode("kCFRunLoopCommonModes")', l), log)
            continue

        # (d2c) CGColorRenderingIntent: o prefix-stripping do C enum quebrou —
        # o case vira `RenderingIntentDefault` (nao `.default`/`.defaultIntent`).
        if "CGColorRenderingIntent" in msg and "defaultIntent" in msg:
            fixed |= fix_line(src, ln, lambda l: re.sub(
                r"\.defaultIntent\b", ".renderingIntentDefault", l), log)
            continue

        # (d3) warnings fatais: requisitos opcionais ObjC com IndexPath. O
        # UICollectionViewDelegate expoe NSIndexPath neste SDK; como o requisito
        # e' opcional, um IndexPath apenas gera warning e o UIKit nao chama o
        # metodo (mesma falha classica do AppDelegate). Corrige as assinaturas
        # de metodos collectionView, nao closures de data source.
        if "nearly matches optional requirement" in msg:
            s = read(src)
            # O texto da warning nao inclui `IndexPath`; a linha da funcao
            # (que temos pelo path/linha) e' a fonte de verdade.
            line = s.split("\n")[ln - 1] if 0 < ln <= len(s.split("\n")) else ""
            if "indexPath:" not in line or "IndexPath" not in line:
                continue
            s2 = re.sub(r"(func\s+collectionView\([^\n]*?\bindexPath\s*:\s*)IndexPath\b",
                        r"\1NSIndexPath", s)
            if s2 != s:
                write(src, s2)
                log_append(log, "%s: IndexPath -> NSIndexPath nas assinaturas "
                                "UICollectionViewDelegate (warning fatal de thunk ObjC)"
                           % os.path.basename(src))
                fixed = True
            continue

        # (d3) "does not conform to protocol 'UITableViewDataSource'" etc.
        # Neste toolchain os protocolos ObjC do UIKit expoem NSIndexPath (e
        # outros tipos ObjC crus) nas assinaturas. Um metodo declarado com
        # `IndexPath` NAO satisfaz o requisito.
        #
        # ⚠️ MESMA CLASSE DE BUG DA TELA PRETA: se o requisito fosse OPCIONAL,
        # isto nem seria erro — so um warning, e o metodo nunca seria chamado.
        # Aqui e' erro porque o protocolo tem requisitos obrigatorios.
        cm = re.search(r"type '(\w+)' does not conform to protocol '(\w+)'", msg)
        if cm and "IndexPath" in read(src):
            s = read(src)
            # troca IndexPath -> NSIndexPath SO nas assinaturas de metodos de
            # delegate/dataSource (parametros `indexPath: IndexPath`)
            s2 = re.sub(r"(\b\w*[iI]ndexPath\s*:\s*)IndexPath\b", r"\1NSIndexPath", s)
            # e nos usos `indexPath.row/.item/.section` o NSIndexPath tem os
            # mesmos membros, entao o corpo continua valido.
            if s2 != s:
                write(src, s2)
                log_append(log, "%s: IndexPath -> NSIndexPath nas assinaturas "
                                "(protocolo '%s' do SDK usa NSIndexPath). "
                                "Confira com check-protocol-sig.py"
                           % (os.path.basename(src), cm.group(2)))
                fixed = True
                continue

        # (e0) o compilador DIZ qual modulo falta — regra generica, cobre
        # "@objc attribute used without importing module 'Foundation'",
        # "... requires importing module 'X'", etc.
        mm = re.search(r"without importing module '(\w+)'", msg) or \
            re.search(r"requires importing module '(\w+)'", msg) or \
            re.search(r"need(?:s)? to import module '(\w+)'", msg)
        if mm:
            s, a = ensure_import(read(src), mm.group(1))
            if a:
                write(src, s)
                log_append(log, "import %s adicionado (o compilador pediu)" % mm.group(1))
                fixed = True
                continue

        # (e) import Dispatch. O overlay Swift do Dispatch some quando o arquivo
        # importa Foundation/UIKit mas nao Dispatch — e o DispatchQueue vira a
        # classe ObjC crua. Os erros resultantes NAO mencionam "Dispatch":
        #   "type 'DispatchQueue' has no member 'main'"
        #   "value of type 'DispatchQueue' has no member 'async'"
        #   "does not conform to protocol 'Scheduler'"
        #   "extra argument 'qos' in call" / "missing arguments for parameters 'attr'"
        # See references/BEST-PRACTICES.md for the type-checking guidance.
        if (re.search(r"cannot find(?: type)? 'DispatchQueue' in scope", msg)
                or "Foundation.DispatchQueue" in msg
                or "does not conform to protocol 'Scheduler'" in msg
                or re.search(r"type 'DispatchQueue' has no member", msg)
                or re.search(r"value of type 'DispatchQueue' has no member", msg)
                or re.search(r"'Dispatch(Time|Queue|WorkItem|Group|QoS)\w*' has no member", msg)
                or ("SchedulerTimeType" in msg and "not a member" in msg)):
            s, a = ensure_import(read(src), "Dispatch")
            if a:
                write(src, s)
                log_append(log, "import Dispatch adicionado (DispatchQueue/Scheduler)")
                fixed = True
                continue
            # ja tem o import: entao a ORDEM esta errada (Dispatch antes de UIKit)
            s2 = reorder_imports(read(src))
            if s2 != read(src):
                write(src, s2)
                log_append(log, "imports reordenados (Dispatch precisa vir DEPOIS de UIKit)")
                fixed = True
            continue

        # (f) funcoes de math sem Foundation (log2, pow, ...)
        fm = re.search(r"cannot find '(\w+)' in scope", msg)
        if fm and fm.group(1) in MATH_FUNCS:
            s, a = ensure_import(read(src), "Foundation")
            if a:
                write(src, s)
                log_append(log, "import Foundation adicionado (math: " + fm.group(1) + ")")
                fixed = True
            continue

        # (h) 'sync' ambiguo: TCA e cs definem sync no NSRecursiveLock —
        # trailing closures ficam ambiguos. Fix: renomear a definicao do CS
        # (rotulo operation:) para csSync + chamadas com rotulo; os trailing
        # `lock.sync {` passam a resolver para o sync do TCA (unico restante
        # no NSRecursiveLock). O sync do TCA em os_unfair_lock_t (Create) NAO
        # e tocado (nao conflita com ninguem).
        if "ambiguous use of 'sync'" in msg:
            for f in sorted(os.listdir(work_dir)):
                if not f.endswith(".swift"):
                    continue
                p = os.path.join(work_dir, f)
                s = read(p)
                s2 = re.sub(r"func sync(<[^>]*>)?\(operation:", r"func csSync\1(operation:", s)
                s2 = re.sub(r"\.sync\(operation:", ".csSync(operation:", s2)
                if s2 != s:
                    write(p, s2)
                    log_append(log, "sync do CombineSchedulers -> csSync (" + f + ")")
                    fixed = True
            continue

        # (i) 'CasePaths' em scope: compilado no mesmo modulo, o namespace do
        # modulo nao existe mais — recriar um shim com o static extract
        # (o codigo original `CasePaths.extract(...)` continua intacto)
        if "cannot find 'CasePaths' in scope" in msg:
            shim = os.path.join(work_dir, "Shims_CasePaths.swift")
            if not os.path.exists(shim):
                with open(shim, "w", encoding="utf-8") as f:
                    f.write("// shim: namespace CasePaths para modulo unico\n"
                            "enum CasePaths {\n"
                            "    static func extract<Root, Value>(\n"
                            "        _ embed: @escaping (Value) -> Root\n"
                            "    ) -> (Root) -> Value? {\n"
                            "        extract(embed)\n"
                            "    }\n"
                            "}\n")
                log_append(log, "shim enum CasePaths.extract criado")
                fixed = True
            continue

        # (j) macro TaskLocal nao existe no toolchain (sem plugin de macros) —
        # remover o atributo (o flag vira uma var estatica comum)
        if "macro implementation type" in msg and "TaskLocal" in msg:
            fixed |= fix_line(src, ln,
                              lambda l: re.sub(r"@TaskLocal\s+", "", l),
                              log)
            continue

        # (k) tipos Foundation/UIKit ObjC somem (FileManager/UUID/Locale/Bundle/
        # Formatter/NSLocalizedString/TimeInterval/UIFont...) -> import do
        # MODULO DONO (Foundation ou UIKit)
        fm = re.search(r"cannot find(?: type)? '(\w+)' in scope", msg)
        if fm and fm.group(1) in TYPE_MODULE:
            mod = TYPE_MODULE[fm.group(1)]
            s, a = ensure_import(read(src), mod)
            if a:
                write(src, s)
                log_append(log, "import " + mod + " adicionado (" + fm.group(1) + ")")
                fixed = True
            continue

        # (l) Color("assetName") — assets do catalog nao existem no IPA;
        # substituir por um cinza neutro (ajuste manual depois se quiser)
        if "no exact matches in call to initializer" in msg:
            lines = read(src).split("\n")
            if 1 <= ln <= len(lines) and 'Color("' in lines[ln - 1]:
                fixed |= fix_line(src, ln, lambda l: re.sub(
                    r'Color\("([^"]+)"\)', 'Color(red: 0.5, green: 0.5, blue: 0.5)', l), log)
            continue

        # (g) init CGRect(x:y:width:height:) -> helper cgRect do PureSwiftKit.
        # O erro nao menciona 'CGRect' no texto ("argument passed to call that
        # takes no arguments") — disparamos pelo padrao e a regex decide.
        if ("takes no arguments" in msg or "extra argument" in msg
                or "missing argument" in msg or "no exact matches" in msg):
            fixed |= fix_line(src, ln, lambda l: re.sub(
                r"CGRect\(\s*x\s*:\s*([^,()]+?)\s*,\s*y\s*:\s*([^,()]+?)\s*,\s*"
                r"width\s*:\s*([^,()]+?)\s*,\s*height\s*:\s*([^,()]+?)\s*\)",
                r"cgRect(\1, \2, \3, \4)", l), log)
            continue

    return fixed, ghost


def run_build(app, bundle, srcs, debug=False):
    # arquivos Shims_*.swift criados pelos fixes entram automaticamente
    import glob
    work_dir = os.path.dirname(srcs[0]) if srcs else "/tmp/port-" + app
    shims = sorted(glob.glob(os.path.join(work_dir, "Shims_*.swift")))
    cmd = ["sh", BUILD_SH, app, bundle] + srcs + shims
    if debug:
        cmd.append("--debug")
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = r.stdout + r.stderr
    # IMPORTANTE: o build-pure-ui.sh so imprime os 20 primeiros erros
    # (grep | head -20). Para o loop reativo, ler o swift.err COMPLETO do
    # disco — os fixes reais podem estar alem do corte.
    errfile = "/tmp/build-" + app + "/swift.err"
    if os.path.exists(errfile):
        try:
            with open(errfile, encoding="utf-8", errors="replace") as f:
                out += "\n" + f.read()
        except OSError:
            pass
    return r.returncode, out


def dep_root(path, src_dir):
    """Raiz de agrupamento do merge: a dependencia (ex: 'tca', 'app')."""
    p = path.replace("\\", "/")
    if p.startswith(src_dir):
        return "app"
    m = re.search(r"/([^/]+)/Sources/", p)
    if m:
        return m.group(1)
    return os.path.basename(os.path.dirname(path))


def merge_by_dir(srcs, work_dir, log, entry=None):
    """Concatena os fontes por diretorio de origem em arquivos unicos.

    O swift-frontend no iSH fica instavel com muitos arquivos por compilacao
    (~45+): os modulos carregam de forma corrompida e tipos somem. Concatenar
    por modulo reduz 191 arquivos para ~10 e estabiliza o build. Imports de
    todos os arquivos sobem para o topo do arquivo concatenado (na ordem
    canonica); corpos seguem na ordem original.
    """
    # basename -> raiz de origem (registrado na copia): o diretorio da
    # dependencia (ex: 'tca', 'app', 'OrderedCollections') para agrupar o merge
    if not hasattr(merge_by_dir, "orig_dirs"):
        return srcs  # sem mapeamento: nao mergear
    mode = getattr(merge_by_dir, "mode", "dep")
    orig = merge_by_dir.orig_dirs if mode == "dep" else merge_by_dir.orig_subdirs
    groups = {}
    for s in srcs:
        b = os.path.basename(s)
        if b in ("main.swift", "PureSwiftKit.swift"):
            continue  # entry (top-level) e kit ficam separados
        if entry and s == entry:
            continue
        d = orig.get(b, "misc")
        groups.setdefault(d, []).append(s)
    if len(groups) <= 1:
        return srcs
    merged = []
    for i, (d, fs) in enumerate(sorted(groups.items())):
        imports, bodies = [], []
        for f in sorted(fs):
            lines = read(f).split("\n")
            j = 0
            while j < len(lines):
                t = lines[j].lstrip()
                if t == "" or t.startswith("//") or t.startswith("/*") or t.startswith("*"):
                    j += 1
                else:
                    break
            k = j
            while k < len(lines) and re.match(r"\s*import\s+\w+", lines[k]):
                imports.append(lines[k].strip())
                k += 1
            bodies.append("\n".join(lines[k:]))
        # imports unicos preservando ordem canonica
        seen, uniq = set(), []
        for im in imports:
            if im not in seen:
                seen.add(im)
                uniq.append(im)
        uniq.sort(key=lambda l: CANON.get(re.search(r"import\s+(\w+)", l).group(1), 99))
        out = os.path.join(work_dir, "merged_%02d_%s.swift" % (i, d.replace("/", "_")[:40]))
        with open(out, "w", encoding="utf-8") as f:
            f.write("// merged: " + d + " (" + str(len(fs)) + " arquivos)\n")
            f.write("\n".join(uniq) + "\n\n")
            f.write("\n\n".join(b for b in bodies if b.strip()))
        merged.append(out)
        log_append(log, "merged %d arquivos de %s -> %s"
                   % (len(fs), d, os.path.basename(out)))
    return merged + [s for s in srcs
                     if os.path.basename(s) in ("main.swift", "PureSwiftKit.swift")
                     or (entry and s == entry)]


def main():
    # args: <src_dir> <AppName> <BundleID> [--extra DIR ...] [--strip-imports "A B C"] [--exclude "a.swift b.swift"] [--no-kit] [--merge-mode dep|subdir|none] [--debug] [--stikdebug-bundle-id ID]
    argv = sys.argv[1:]
    extra_dirs, strip_mods, exclude, resources = [], [], [], []
    no_kit = False
    merge_mode = "dep"
    debug = False
    stikdebug_bundle_id = None
    pos = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--extra" and i + 1 < len(argv):
            extra_dirs.append(argv[i + 1])
            i += 2
        elif a == "--strip-imports" and i + 1 < len(argv):
            strip_mods += argv[i + 1].split()
            i += 2
        elif a == "--exclude" and i + 1 < len(argv):
            exclude += argv[i + 1].split()
            i += 2
        elif a == "--resources" and i + 1 < len(argv):
            resources.append(argv[i + 1])
            i += 2
        elif a == "--no-kit":
            no_kit = True
            i += 1
        elif a == "--debug":
            debug = True
            i += 1
        elif a == "--stikdebug-bundle-id" and i + 1 < len(argv):
            stikdebug_bundle_id = argv[i + 1]
            i += 2
        elif a == "--merge-mode" and i + 1 < len(argv):
            merge_mode = argv[i + 1]
            i += 2
        else:
            pos.append(a)
            i += 1
    if len(pos) < 3:
        print(__doc__)
        sys.exit(1)
    src_dir, app, bundle = pos[0], pos[1], pos[2]
    if not os.path.isdir(src_dir):
        print("ERRO: diretorio nao encontrado:", src_dir)
        sys.exit(1)

    log = []
    print(f"==> portando {os.path.basename(src_dir)} -> {app} ({bundle})")
    print("==> passo 1: coletando fontes Swift (iOS target)")
    files = collect(src_dir)
    for d in extra_dirs:
        if not os.path.isdir(d):
            print("ERRO: --extra dir nao encontrado:", d)
            sys.exit(1)
        files += collect(d)
    if not files:
        print("ERRO: nenhum .swift encontrado em", src_dir)
        sys.exit(1)
    if exclude:
        files = [f for f in files if os.path.basename(f) not in exclude]
        print("   --exclude: " + ", ".join(exclude))
    for f in files:
        print("   + " + os.path.relpath(f, src_dir) if f.startswith(src_dir)
              else "   + " + f)

    print("==> passo 2: copiando para area de trabalho e adaptando")
    # trabalha numa COPIA — o repo original do projeto nunca e editado
    work = os.path.join("/tmp", "port-" + app)
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    srcs = []
    seen = {}
    merge_by_dir.orig_dirs = {}
    merge_by_dir.orig_subdirs = {}
    for f in files:
        base = os.path.basename(f)
        if " " in base:
            base = base.replace(" ", "_")
            log_append(log, "espaco no nome renomeado: " + base)
        dest = os.path.join(work, base)
        if base in seen:
            # colisao de basename (build-pure-ui.sh achata os paths):
            # prefixa com o nome do diretorio pai
            base = os.path.basename(os.path.dirname(f)) + "_" + base
            dest = os.path.join(work, base)
            log_append(log, "basename duplicado renomeado: " + base)
        seen[base] = f
        merge_by_dir.orig_dirs[base] = dep_root(f, src_dir)
        merge_by_dir.orig_subdirs[base] = os.path.basename(os.path.dirname(f))
        shutil.copy(f, dest)
        srcs.append(dest)

    # PureSwiftKit entra no build (a menos que --no-kit: o kit importa UIKit e
    # pode quebrar com tipos Foundation em modulos grandes — usar --no-kit
    # quando o app nao usa os helpers cg*/FS do kit)
    if not no_kit:
        kit = os.path.join(work, "PureSwiftKit.swift")
        shutil.copy(KIT, kit)
        srcs.append(kit)
        print("   + PureSwiftKit.swift incluido (helpers de degradacoes)")
    else:
        print("   + --no-kit: PureSwiftKit NAO incluido")

    # strip de imports de modulos que serao compilados juntos (1 modulo unico)
    if strip_mods:
        n_stripped = 0
        for f in srcs:
            if os.path.basename(f) == "PureSwiftKit.swift":
                continue
            s = read(f)
            s2 = re.sub(r"(?m)^\s*(?:@_exported\s+)?import\s+(?:"
                        + "|".join(strip_mods) + r")\s*$", "", s)
            if s2 != s:
                write(f, s2)
                n_stripped += 1
        print(f"   + imports de {len(strip_mods)} modulos unificados removidos "
              f"em {n_stripped} arquivos")

    # adaptacoes na copia
    for f in srcs:
        if os.path.basename(f) == "PureSwiftKit.swift":
            continue
        write(f, reorder_imports(read(f)))
    entry = adapt_entry(srcs, log)
    if debug and stikdebug_bundle_id and entry:
        es = read(entry)
        marker = "ISBDebugRuntime.returnBundleID = "
        if marker not in es:
            es = es.replace(
                "UIApplicationMain(CommandLine.argc,",
                "ISBDebugRuntime.returnBundleID = \"%s\"\n\nUIApplicationMain(CommandLine.argc," % stikdebug_bundle_id,
                1)
            write(entry, es)
            log_append(log, "debug: bundle ID de retorno StikDebug configurado como "
                            + stikdebug_bundle_id)

    # lifecycle de cena: o storyboard nao compila (sem ibtool) — o willConnectTo
    # precisa criar a janela em codigo. Detecta SceneDelegate e guarda a classe
    # para o UIApplicationSceneManifest (Info.plist, passo 3.5).
    scene_class = None
    for f in srcs:
        if os.path.basename(f) in ("PureSwiftKit.swift", "main.swift"):
            continue
        s = read(f)
        m = re.search(
            r"class\s+(\w+)\s*:\s*(?:NSObject\s*,\s*)?UIResponder\s*,\s*UIWindowSceneDelegate",
            s)
        if m:
            story_candidates = [
                os.path.join(src_dir, "Base.lproj", "Main.storyboard"),
                os.path.join(os.path.dirname(src_dir), "Base.lproj", "Main.storyboard"),
                os.path.join(src_dir, "Main.storyboard"),
                os.path.join(os.path.dirname(src_dir), "Main.storyboard"),
            ]
            story = next((p for p in story_candidates if os.path.exists(p)), None)
            if story is None:
                # Alguns repos mantem o target Swift numa subpasta, mas os
                # recursos/storyboards na raiz do projeto. Procurar apenas
                # nessa raiz e no pai evita varrer o filesystem inteiro.
                for search_root in (src_dir, os.path.dirname(src_dir)):
                    if not os.path.isdir(search_root):
                        continue
                    for root, _, fns in os.walk(search_root):
                        if "Main.storyboard" in fns:
                            story = os.path.join(root, "Main.storyboard")
                            break
                    if story:
                        break
            if story:
                log_append(log, "scene: storyboard encontrado em " + story)
            convert_scene_delegate(f, story, log, debug=debug)
            if debug:
                log_append(log, "debug: overlay instalado explicitamente apos makeKeyAndVisible")
            scene_class = app + "." + m.group(1)

    # estabilidade: swift-frontend no iSH quebra com ~45+ arquivos por
    # compilacao (modulos corrompidos -> tipos somem). Merge por modulo.
    if merge_mode != "none" and (len(srcs) > 45 or merge_mode == "subdir"):
        merge_by_dir.mode = merge_mode
        srcs = merge_by_dir(srcs, work, log, entry)
        print(f"   + {len(files) + 1} fontes mergeados em {len(srcs)} arquivos "
              f"(modo {merge_mode})")

    print("==> passo 3: loop de build reativo (max " + str(MAX_ITER) + " iteracoes)")
    rc = None
    ghost_retries = 0
    kit_used = not no_kit
    for it in range(1, MAX_ITER + 1):
        print(f"   --- iteracao {it} ---")
        rc, out = run_build(app, bundle, srcs, debug=debug)
        if rc == 0:
            print("   BUILD OK")
            break
        if rc < 0:
            # morto por sinal (OOM do iOS / crash do frontend): retry
            ghost_retries += 1
            print(f"   compilador morto (rc={rc}, provavel OOM), retry "
                  f"{ghost_retries}/8...")
            if ghost_retries >= 8:
                print("   muitos retries de OOM — abortando")
                sys.exit(1)
            continue
        fixed, ghost = fix_known_errors(work, out, log)
        if fixed:
            print("   fixes aplicados, rebuildando...")
            continue
        if ghost and ghost_retries < 5:
            # erros fantasma (tipo some com import presente): retry do build
            ghost_retries += 1
            print(f"   erros fantasma (modulos carregados de forma instavel), "
                  f"retry {ghost_retries}/5...")
            continue
        if ghost and kit_used:
            # o fantasma PERSISTE apos os retries: nao e transiente — o
            # PureSwiftKit (limiar de declaracoes) quebrou tipos Foundation
            # no modulo de forma DETERMINISTICA (medido 2026-08-22).
            kit_used = False
            srcs = [f for f in srcs if os.path.basename(f) != "PureSwiftKit.swift"]
            srcs.append(write_minimal_kit(srcs, work, log))
            ghost_retries = 0
            print("   kit removido -> helpers minimos locais; rebuildando...")
            continue
        print("   ERROS NAO AUTOMATIZAVEIS:")
        for line in out.splitlines():
            if "error:" in line:
                print("     " + line.strip())
        sys.exit(1)

    if rc != 0:
        sys.exit(1)

    print("==> passo 3.5: recursos + manifest no IPA")
    post_process_ipa(app, resources, scene_class, log, debug=debug)

    print("==> passo 4: validando IPA")
    r = subprocess.run(["sh", VALIDATE_SH, os.path.join(WORKSPACE, app + ".ipa")],
                       capture_output=True, text=True)
    out = r.stdout
    ok = "=== OK ===" in out
    for line in out.splitlines():
        if any(k in line for k in ("platform", "sdk", "minos", "Swift symbols",
                                   "CDHash", "=== OK ===")):
            print("   " + line.strip())

    report = os.path.join(WORKSPACE, app + "-port.md")
    with open(report, "w", encoding="utf-8") as f:
        f.write("# Porting report: " + app + "\n\n")
        f.write("- Fonte: `" + src_dir + "`\n")
        f.write("- IPA: `" + os.path.join(WORKSPACE, app + ".ipa") + "`\n")
        f.write("- Validacao: " + ("OK" if ok else "FALHOU") + "\n\n")
        f.write("## Adaptacoes automaticas\n\n")
        for e in log:
            f.write("- " + e + "\n")
    print("==> relatorio: " + report)
    if not ok:
        print("!!! validacao falhou — veja " + report)
        sys.exit(1)
    print("==> PRONTO")


if __name__ == "__main__":
    main()
