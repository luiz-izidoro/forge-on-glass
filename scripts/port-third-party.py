#!/usr/bin/env python3
"""port-third-party.py — builds third-party iOS apps (pure SwiftUI/UIKit) WITHOUT manual editing.

Usage:
  port-third-party.py <project-dir> <AppName> <BundleID>

Flow:
  1. Collects the .swift files from the iOS target (skips mac/tests/preview folders, import AppKit).
  2. Adapts automatically: entry point (@UIApplicationMain -> main.swift with the
     UIApplicationMain(...) call) and reorders imports into canonical order
     (Foundation -> SwiftUI -> UIKit -> CoreText -> Dispatch).
  3. Runs build-pure-ui.sh (with PureSwiftKit always included) in a REACTIVE loop:
     each known compilation error (CGRect members, UIEdgeInsetsMake,
     TimeInterval, missing imports, CGRect init...) is fixed at the exact line
     and the build is repeated — until it passes or unknown errors remain.
  4. Validates the IPA and writes <AppName>-port.md (report) in the workspace.

`ISB_PORT_WORK_ROOT` controls the isolated source-copy directory (default
`/tmp`). `ISB_BUILD_WORK` controls the builder's intermediate directory and
`ISB_WORKSPACE` controls the resulting IPA/report directory. These variables
allow a consumer to keep all generated material outside the checkout.
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
WORKSPACE = os.environ.get("ISB_WORKSPACE", "/var/minis/workspace")
MAX_ITER = 10

# Import order is defined by references/BEST-PRACTICES.md.
CANON = {"Foundation": 1, "CoreFoundation": 2, "SwiftUI": 3,
         "UIKit": 4, "CoreText": 5, "Dispatch": 6, "Combine": 7, "Darwin": 8}
# NOTE (2026-08-22): Dispatch AFTER UIKit is mandatory. Measured with 4
# different orders: only `Foundation UIKit Dispatch <Module>` resolves Dispatch's
# Swift overlay of DispatchQueue (Scheduler conformance, DispatchQueue.main,
# init(label:qos:)). With Dispatch before UIKit, DispatchQueue becomes the raw
# ObjC class and errors appear FAR from the cause ("does not conform to protocol
# 'Scheduler'", "extra argument 'qos' in call").

# CGRect/CGAffineTransform/CGPoint/CGSize members that do not exist in the SDK
# exposed by the toolchain (invisible @_alwaysEmitIntoClient extensions).
# Fix: use the PureSwiftKit helpers (cg*).
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


# ---------------------------------------------------------------- step 1: collect
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


# ------------------------------------------------------- step 2: pre-adaptation
def reorder_imports(s):
    """Reorders the contiguous block of imports at the top into canonical order."""
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
    """Adds `import <module>` at the top (canonical position) if missing."""
    if re.search(r"^\s*import\s+" + module + r"\b", s, re.M):
        return s, False
    lines = s.split("\n")
    # SPECIAL CASE Dispatch: must come AFTER Foundation (the order
    # Foundation->Dispatch is mandatory; Foundation after Dispatch makes
    # DispatchQueue resolve to Foundation.DispatchQueue without the extensions).
    # Foundation may be inside #if (e.g. CombineSchedulers) — insert
    # right after the Foundation line, with the same indentation.
    if module == "Dispatch":
        for idx, ln in enumerate(lines):
            m = re.match(r"^(\s*)import\s+Foundation\b", ln)
            if m:
                lines.insert(idx + 1, m.group(1) + "import Dispatch")
                return "\n".join(lines), True
    # find the end of the current import block (insertion position)
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
    # insert before the first import with higher priority
    while ins > i and CANON.get(mod_name(lines[ins - 1]), 99) > CANON.get(module, 99):
        ins -= 1
    lines.insert(ins, "import " + module)
    return "\n".join(lines), True


def mod_name(line):
    m = re.search(r"import\s+(\w+)", line)
    return m.group(1) if m else ""


def fix_delegate_signature(path, log):
    """Replaces `application(_:didFinishLaunchingWithOptions:)` with
    `applicationDidFinishLaunching(_:)`.

    REASON (2026-08-22): in the patched SDK launchOptions is
    NSDictionary<NSString, AnyObject>?, not [LaunchOptionsKey: Any]?. Since the
    protocol requirement is OPTIONAL, Apple's signature compiles with
    only a WARNING and UIKit NEVER calls the method -> app opens with a BLACK
    SCREEN. See references/WARNINGS-FATAIS.md.
    """
    s = read(path)
    if "didFinishLaunchingWithOptions" not in s:
        return False
    # signature (may be broken across multiple lines)
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
    # remove the trailing `return true` from the method (it is now Void)
    s2 = re.sub(r"\n(\s*)return\s+true\s*\n(\s*)\}", r"\n\2}", s2, count=1)
    write(path, s2)
    log_append(log, "entry: application(_:didFinishLaunchingWithOptions:) -> "
                    "applicationDidFinishLaunching(_:) "
                    "(Apple signature does not match the patched SDK = black screen)")
    return True


def convert_swiftui_app(s, path, log):
    """Converts `@main struct X: App { var body: some Scene { WindowGroup { V() } } }`
    into AppDelegate + UIApplicationMain + UIHostingController.

    WHY: the SwiftUI lifecycle (`App`/`Scene`) depends on macros and
    metadata that do not survive this toolchain's interface-compile; besides,
    `@main` + a `main.swift` file (top-level) is a compiler error.
    The UI remains 100% SwiftUI — only the lifecycle becomes UIKit.

    Extracts the WindowGroup content to use as rootView. If it cannot
    identify it, falls back to the first `View` in the file.
    """
    # 1. @main struct name and body
    m = re.search(r"@main\s+(?:public\s+)?struct\s+(\w+)\s*:\s*App\b", s)
    if not m:
        # @main on something else (e.g. enum with main()): just remove the attribute
        s2 = re.sub(r"^\s*@main\s*$", "", s, flags=re.M)
        log_append(log, "entry: @main removed (it was not `struct: App`)")
        return reorder_imports(s2)
    app_name = m.group(1)

    # 2. WindowGroup { ... } content (first occurrence, balanced)
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
        log_append(log, "entry: WindowGroup not found; rootView = " + root_expr)

    # 3. remove the entire @main struct (it cannot coexist with top-level code)
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
// Entry point automatically converted from `@main struct %s: App`.
// The SwiftUI lifecycle (App/Scene) depends on macros that do not survive this
// toolchain's interface-compile. The UI remains 100%% SwiftUI; only the
// lifecycle is UIKit.
//
// WARNING: use `applicationDidFinishLaunching(_:)`. The signature
// `application(_:didFinishLaunchingWithOptions:)` does NOT match the
// patched .swiftinterface (launchOptions is NSDictionary here) -> Swift only
// warns, does not generate the ObjC thunk, UIKit never calls the method and the app opens with
// a BLACK SCREEN. See references/WARNINGS-FATAIS.md
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
    """Finds the entry point and adapts it: @UIApplicationMain -> main.swift with the call."""
    # ALWAYS fix the delegate signature, in any file
    for p in files:
        try:
            fix_delegate_signature(p, log)
        except Exception:
            pass
    mains = [p for p in files if os.path.basename(p) == "main.swift"]
    if mains:
        log_append(log, "entry: main.swift already exists (top-level), kept")
        return mains[0]
    for p in files:
        s = read(p)
        if re.search(r"\bUIApplicationMain\s*\(", s):
            # it is already an AppDelegate-style entry (top-level UIApplicationMain) —
            # build-pure-ui.sh recognizes it by the *Main.swift name
            log_append(log, "entry: UIApplicationMain(...) already present at top-level, kept")
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
            log_append(log, "entry: @UIApplicationMain removed; "
                            "UIApplicationMain(...) call added (class " + cls + ")")
            nb = os.path.splitext(os.path.basename(p))[0] + "Main.swift"
            np_ = os.path.join(os.path.dirname(p), nb)
            if np_ != p:
                os.rename(p, np_)
                files[files.index(p)] = np_
                log_append(log, "entry: " + os.path.basename(p) + " -> " + nb)
            return np_
        if re.search(r"^\s*@main\b", s, re.M):
            # `@main class X: UIResponder, UIApplicationDelegate` — classic UIKit
            # (with or without scene lifecycle). @main on a class
            # depends on UIApplicationDelegate.main() (metadata that does not
            # survive interface-compile) — same treatment as
            # @UIApplicationMain: remove the attribute and append the
            # UIApplicationMain(...) call at the top-level of the *Main.swift file.
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
                                "UIApplicationMain(...) appended at top-level" % cls)
                nb = os.path.splitext(os.path.basename(p))[0] + "Main.swift"
                np_ = os.path.join(os.path.dirname(p), nb)
                if np_ != p:
                    os.rename(p, np_)
                    files[files.index(p)] = np_
                return np_
            # `@main struct X: App` (SwiftUI App lifecycle) does NOT work here:
            # it depends on macros/metadata that do not survive interface-compile,
            # and the file becomes main.swift (top-level) => error
            #   "'main' attribute cannot be used in a module that contains
            #    top-level code".
            # We convert it to the runtime-validated pattern:
            #   AppDelegate + UIApplicationMain + UIHostingController.
            s2 = convert_swiftui_app(s, p, log)
            write(p, s2)
            nb = os.path.splitext(os.path.basename(p))[0] + "Main.swift"
            np_ = os.path.join(os.path.dirname(p), nb)
            if np_ != p:
                os.rename(p, np_)
                files[files.index(p)] = np_
            return np_
    log_append(log, "entry: NO entry point recognized "
                    "(@UIApplicationMain/@main/main.swift) — the build may fail")
    return None


# ------------------------------------------------------- scene lifecycle
def parse_storyboard_root(story_path):
    """Extracts (rootVC_class, has_navigationController) from the storyboard.

    Storyboards do not compile without ibtool — the port must recreate the view
    tree in code. Follows initialViewController; if it is a
    navigationController, follows the rootViewController relationship segue.
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
        # `initialViewController` and `segue.destination` point to the object id
        # (navigationController/viewController), not to sceneID.
        # The old parser compared sceneID and never found the Navigation
        # Controller — that is why Load ROM ended up without navigationController.
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
    """Converts a SceneDelegate's willConnectTo to create the UIWindow in
    code (the storyboard the app expected does not exist in the IPA). The root VC
    class is read from Main.storyboard; the original root was in a
    UINavigationController, so the wrapper is recreated."""
    s = read(path)
    if "UIWindowSceneDelegate" not in s:
        return False
    root_cls, is_nav = parse_storyboard_root(story_path)
    if not root_cls:
        root_cls = "ViewController"
        log_append(log, "scene: storyboard not parsed — default root VC "
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
    log_append(log, "scene: willConnectTo rewritten to create the window in code "
                    "(root: %s)" % root_expr)
    return True


def post_process_ipa(app, res_dirs, scene_class, log, debug=False):
    """After the build: adds resources (--resources) and the UIApplicationSceneManifest
    to Info.plist (app with scene lifecycle), and re-zips the IPA.

    build-pure-ui.sh generates a fixed Info.plist without a manifest and without resources;
    the manifest is MANDATORY for UIKit to instantiate the SceneDelegate — without it the
    app opens and stays with a black screen (window never created).
    """
    work_dir = os.environ.get("ISB_BUILD_WORK", os.path.join("/tmp", "port-" + app))
    pay_app = os.path.join(work_dir, "Payload", app + ".app")
    if not os.path.isdir(pay_app):
        log_append(log, "ipa: Payload not found — post-process skipped")
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
            log_append(log, "info: UIApplicationSceneManifest added "
                            "(UISceneDelegateClassName = %s)" % scene_class)
        except Exception as e:
            log_append(log, "info: FAILED to add scene manifest: %s" % e)
    if res_dirs:
        for d in res_dirs:
            if not os.path.isdir(d):
                log_append(log, "resource: dir not found: " + d)
                continue
            for root, _, files in os.walk(d):
                for fn in sorted(files):
                    shutil.copy(os.path.join(root, fn),
                                os.path.join(pay_app, fn))
                    log_append(log, "resource: %s -> Payload/%s.app/%s"
                               % (os.path.relpath(os.path.join(root, fn), d),
                                  app, fn))
    # build-pure-ui signs before this post-processing. Changing the
    # Info.plist afterwards invalidates the CodeDirectory; new resources must also
    # enter before final signing. Always re-sign, even without resources.
    exe = os.path.join(pay_app, app)
    if debug:
        ent = os.path.join(work, "debug-entitlements.plist")
        subprocess.run(["ldid", "-S" + ent, exe], check=True)
        log_append(log, "ipa: bundle re-signed preserving get-task-allow")
    else:
        subprocess.run(["ldid", "-S", exe], check=True)
    log_append(log, "ipa: bundle re-signed after manifest/resources")
    ipa = os.path.join(WORKSPACE, app + ".ipa")
    if os.path.exists(ipa):
        os.remove(ipa)
    subprocess.run(["zip", "-qr", ipa, "Payload"], cwd=work, check=True)
    log_append(log, "ipa: re-zipped (resources/manifest)")


def write_minimal_kit(srcs, work, log):
    """Generates Shims_MinimalKit.swift with ONLY the PureSwiftKit helpers the app
    uses.

    REASON (2026-08-22, Chip8Emu): the whole kit (~260 lines, ~55 public
    declarations) pushes the module past a threshold where the Foundation overlay
    DEGRADES deterministically for sibling files — e.g.: `Timer` disappears from
    files that import Foundation, even with a clean cache. Removing the kit and
    keeping only the used helpers (here: cgRectZero) fixes it. It is the same class
    of "large module", now with a measured limit.
    """
    kit = read(KIT)
    used = set()
    for f in srcs:
        if os.path.basename(f) == "PureSwiftKit.swift":
            continue
        used |= set(re.findall(r"\bcg[A-Z]\w*", read(f)))
        used |= set(re.findall(r"\bedgeInsets\b", read(f)))
    # only what the kit REALLY defines (cgColor/cgImage/cgPath belong to the SDK)
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
    # extension members (cgWidth, cgMinX...): include the whole extension
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
    out = ("// Shims_MinimalKit.swift — PureSwiftKit helpers generated "
           "automatically\n"
           "// (the whole kit breaks Foundation types in the module — see "
           "PORTING-TERCEROS.md)\n"
           "import Foundation\nimport UIKit\n\n"
           + "\n\n".join(dict.fromkeys(defs)) + "\n")
    p = os.path.join(work, "Shims_MinimalKit.swift")
    write(p, out)
    log_append(log, "kit: PureSwiftKit removed (the declaration threshold broke "
                    "Foundation types in the module) -> local minimal helpers: "
                    + ", ".join(sorted(used)))
    return p


# --------------------------------------------------- step 3: reactive fixes (loop)
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
        # statics: CGRect.zero -> cgRectZero (and a bare .zero on the error line)
        line = re.sub(r"\b" + typename + r"\." + member + r"\b", repl, line)
        line = re.sub(r"(?<![\w.])\.zero\b(?![\w])", repl, line)
    else:
        # member: rect.width -> rect.cgWidth (all occurrences on the line)
        line = re.sub(r"\." + member + r"\b(?![\w])", "." + repl, line)
    return line


# --- reactive fixes: each known error -> transformation in the source file -----
# Modules that own types that "disappear" (ghost errors from swift-frontend on iSH:
# the same build sometimes compiles, sometimes reports missing types). If the import already
# exists in the file, it is a ghost -> retry the build (do not apply a fix).
TYPE_MODULE = {
    "DispatchQueue": "Dispatch", "DispatchTime": "Dispatch",
    "DispatchWorkItem": "Dispatch", "DispatchGroup": "Dispatch",
    "DispatchQoS": "Dispatch", "DispatchSemaphore": "Dispatch",
    "FileManager": "Foundation", "Bundle": "Foundation", "UUID": "Foundation",
    "Locale": "Foundation", "Formatter": "Foundation", "URL": "Foundation",
    "NSLocalizedString": "Foundation", "TimeInterval": "Foundation",
    "NSNumber": "Foundation", "NSString": "Foundation", "NSIndexPath": "Foundation",
    # Foundation value types that disappear when the file only imports UIKit
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
    """True if the 'cannot find X' error occurs in a file that ALREADY imports the module."""
    # WARNING (2026-08-22): INFERENCE errors are not ghosts and have no
    # automatic fix — they are code the iSH type-checker cannot close. See
    # PORTING-TERCEROS.md §11 (rewrite with explicit nominal types).
    m = re.search(r"cannot find(?: type)? '(\w+)' in scope", msg)
    if not m:
        return False
    name = m.group(1)
    # TimeInterval is NOT a ghost: it is the documented degradation (it disappears with UIKit
    # EVEN with Foundation imported) — fix (c) replaces it with Double.
    if name == "TimeInterval":
        return False
    mod = TYPE_MODULE.get(name)
    if not mod:
        return False
    s = read(src)
    return re.search(r"^\s*import\s+" + mod + r"\b", s, re.M) is not None


def fix_known_errors(work_dir, build_out, log):
    """Returns (applied_fix, has_ghost)."""
    fixed = False
    ghost = False
    for m in ERR_RE.finditer(build_out):
        base = os.path.basename(m.group(1))  # full path -> just the name
        ln, col, msg = int(m.group(2)), int(m.group(3)), m.group(4)
        src = find_src(work_dir, base)
        if not src:
            continue

        # ghost error: the type "disappears" but the module import already exists —
        # it is a transient swift-frontend bug (retry fixes it, a fix does not)
        if is_ghost_error(src, msg):
            ghost = True
            continue

        # (a) CGRect/CGAffineTransform/CGPoint/CGSize: nonexistent member
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

        # (b) UIEdgeInsetsMake does not exist -> init with labels
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

        # (c) TimeInterval disappears with UIKit -> Double (typealias). If the
        # Foundation import already exists, importing does not help — replace the type.
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
                    log_append(log, "import Foundation added (TimeInterval)")
                    fixed = True
            continue

        # (d) import CoreText (NSAttributedString.Key)
        if "NSAttributedString" in msg and "Key" in msg and "cannot find" in msg:
            s, a = ensure_import(read(src), "CoreText")
            if a:
                write(src, s)
                log_append(log, "import CoreText added (NSAttributedString.Key)")
                fixed = True
            continue

        # (d2) IndexPath <-> NSIndexPath: in this toolchain the ObjC protocols
        # (UITableViewDataSource, UICollectionViewDataSource, ...) expose
        # NSIndexPath, not IndexPath. Typical errors:
        #   "cannot convert value of type 'IndexPath' to expected argument type 'NSIndexPath'"
        #   "type 'X' does not conform to protocol 'UITableViewDataSource'"
        # Generic fix: use NSIndexPath in the SIGNATURE; convert inside the body.
        # Confirm the real signature with:
        #   python3 scripts/check-protocol-sig.py <Protocol> <member>
        if re.search(r"cannot convert value of type 'IndexPath' to expected "
                     r"argument type 'NSIndexPath'", msg):
            def _to_nsindexpath(l):
                # IDEMPOTENT: do not touch it if already converted (otherwise the reactive
                # loop applies the fix on top of its own fix)
                if "NSIndexPath(item:" in l:
                    return l
                # ⚠️ `\w*[iI]ndexPath` (not `[A-Za-z_]\w*[iI]ndexPath`): the old one
                # required 1 char before 'indexPath' and never matched names of
                # 9 chars like `indexPath` (latent bug, found 2026-08-22).
                return re.sub(
                    r"\b(for|at)\s*:\s*(?!NSIndexPath\b)(\w*[iI]ndexPath)\b",
                    r"\1: NSIndexPath(item: \2.item, section: \2.section)", l)
            fixed |= fix_line(src, ln, _to_nsindexpath, log)
            continue

        # (d2b) degraded RunLoop.Mode.common -> RunLoop.Mode("kCFRunLoopCommonModes")
        # (CADisplayLink.add(to:forMode:)). In the patched SDK the `.common` member
        # of NSRunLoopMode disappears; the rawValue init works (probe 2026-08-22).
        if "NSRunLoopMode" in msg and "has no member 'common'" in msg:
            fixed |= fix_line(src, ln, lambda l: re.sub(
                r"forMode:\s*\.common\b",
                'forMode: RunLoop.Mode("kCFRunLoopCommonModes")', l), log)
            continue

        # (d2c) CGColorRenderingIntent: the C enum prefix-stripping broke —
        # the case becomes `RenderingIntentDefault` (not `.default`/`.defaultIntent`).
        if "CGColorRenderingIntent" in msg and "defaultIntent" in msg:
            fixed |= fix_line(src, ln, lambda l: re.sub(
                r"\.defaultIntent\b", ".renderingIntentDefault", l), log)
            continue

        # (d3) fatal warnings: optional ObjC requirements with IndexPath. The
        # UICollectionViewDelegate exposes NSIndexPath in this SDK; since the
        # requirement is optional, an IndexPath only produces a warning and UIKit does not call
        # the method (same classic AppDelegate failure). Fixes the signatures of
        # collectionView methods, not data source closures.
        if "nearly matches optional requirement" in msg:
            s = read(src)
            # The warning text does not include `IndexPath`; the function line
            # (which we have from path/line) is the source of truth.
            line = s.split("\n")[ln - 1] if 0 < ln <= len(s.split("\n")) else ""
            if "indexPath:" not in line or "IndexPath" not in line:
                continue
            s2 = re.sub(r"(func\s+collectionView\([^\n]*?\bindexPath\s*:\s*)IndexPath\b",
                        r"\1NSIndexPath", s)
            if s2 != s:
                write(src, s2)
                log_append(log, "%s: IndexPath -> NSIndexPath in the "
                                "UICollectionViewDelegate signatures (fatal ObjC thunk warning)"
                           % os.path.basename(src))
                fixed = True
            continue

        # (d3) "does not conform to protocol 'UITableViewDataSource'" etc.
        # In this toolchain UIKit's ObjC protocols expose NSIndexPath (and
        # other raw ObjC types) in the signatures. A method declared with
        # `IndexPath` does NOT satisfy the requirement.
        #
        # ⚠️ SAME CLASS OF BLACK-SCREEN BUG: if the requirement were OPTIONAL,
        # this would not even be an error — just a warning, and the method would never be called.
        # Here it is an error because the protocol has required requirements.
        cm = re.search(r"type '(\w+)' does not conform to protocol '(\w+)'", msg)
        if cm and "IndexPath" in read(src):
            s = read(src)
            # change IndexPath -> NSIndexPath ONLY in the delegate/dataSource
            # method signatures (parameters `indexPath: IndexPath`)
            s2 = re.sub(r"(\b\w*[iI]ndexPath\s*:\s*)IndexPath\b", r"\1NSIndexPath", s)
            # and in the uses `indexPath.row/.item/.section` NSIndexPath has the
            # same members, so the body remains valid.
            if s2 != s:
                write(src, s2)
                log_append(log, "%s: IndexPath -> NSIndexPath in the signatures "
                                "(SDK protocol '%s' uses NSIndexPath). "
                                "Check with check-protocol-sig.py"
                           % (os.path.basename(src), cm.group(2)))
                fixed = True
                continue

        # (e0) the compiler SAYS which module is missing — generic rule, covers
        # "@objc attribute used without importing module 'Foundation'",
        # "... requires importing module 'X'", etc.
        mm = re.search(r"without importing module '(\w+)'", msg) or \
            re.search(r"requires importing module '(\w+)'", msg) or \
            re.search(r"need(?:s)? to import module '(\w+)'", msg)
        if mm:
            s, a = ensure_import(read(src), mm.group(1))
            if a:
                write(src, s)
                log_append(log, "import %s added (the compiler asked for it)" % mm.group(1))
                fixed = True
                continue

        # (e) import Dispatch. Dispatch's Swift overlay disappears when the file
        # imports Foundation/UIKit but not Dispatch — and DispatchQueue becomes the
        # raw ObjC class. The resulting errors do NOT mention "Dispatch":
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
                log_append(log, "import Dispatch added (DispatchQueue/Scheduler)")
                fixed = True
                continue
            # the import is already there: so the ORDER is wrong (Dispatch before UIKit)
            s2 = reorder_imports(read(src))
            if s2 != read(src):
                write(src, s2)
                log_append(log, "imports reordered (Dispatch must come AFTER UIKit)")
                fixed = True
            continue

        # (f) math functions without Foundation (log2, pow, ...)
        fm = re.search(r"cannot find '(\w+)' in scope", msg)
        if fm and fm.group(1) in MATH_FUNCS:
            s, a = ensure_import(read(src), "Foundation")
            if a:
                write(src, s)
                log_append(log, "import Foundation added (math: " + fm.group(1) + ")")
                fixed = True
            continue

        # (h) ambiguous 'sync': TCA and cs define sync on NSRecursiveLock —
        # trailing closures become ambiguous. Fix: rename the CS definition
        # (operation: label) to csSync + labeled calls; the trailing
        # `lock.sync {` then resolve to TCA's sync (the only one left
        # on NSRecursiveLock). TCA's sync on os_unfair_lock_t (Create) is NOT
        # touched (it conflicts with no one).
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
                    log_append(log, "CombineSchedulers sync -> csSync (" + f + ")")
                    fixed = True
            continue

        # (i) 'CasePaths' in scope: compiled in the same module, the module
        # namespace no longer exists — recreate a shim with the static extract
        # (the original `CasePaths.extract(...)` code is untouched)
        if "cannot find 'CasePaths' in scope" in msg:
            shim = os.path.join(work_dir, "Shims_CasePaths.swift")
            if not os.path.exists(shim):
                with open(shim, "w", encoding="utf-8") as f:
                    f.write("// shim: CasePaths namespace for a single module\n"
                            "enum CasePaths {\n"
                            "    static func extract<Root, Value>(\n"
                            "        _ embed: @escaping (Value) -> Root\n"
                            "    ) -> (Root) -> Value? {\n"
                            "        extract(embed)\n"
                            "    }\n"
                            "}\n")
                log_append(log, "shim enum CasePaths.extract created")
                fixed = True
            continue

        # (j) the TaskLocal macro does not exist in the toolchain (no macro plugin) —
        # remove the attribute (the flag becomes an ordinary static var)
        if "macro implementation type" in msg and "TaskLocal" in msg:
            fixed |= fix_line(src, ln,
                              lambda l: re.sub(r"@TaskLocal\s+", "", l),
                              log)
            continue

        # (k) Foundation/UIKit ObjC types disappear (FileManager/UUID/Locale/Bundle/
        # Formatter/NSLocalizedString/TimeInterval/UIFont...) -> import the
        # OWNING MODULE (Foundation or UIKit)
        fm = re.search(r"cannot find(?: type)? '(\w+)' in scope", msg)
        if fm and fm.group(1) in TYPE_MODULE:
            mod = TYPE_MODULE[fm.group(1)]
            s, a = ensure_import(read(src), mod)
            if a:
                write(src, s)
                log_append(log, "import " + mod + " added (" + fm.group(1) + ")")
                fixed = True
            continue

        # (l) Color("assetName") — catalog assets do not exist in the IPA;
        # replace with a neutral gray (adjust manually later if desired)
        if "no exact matches in call to initializer" in msg:
            lines = read(src).split("\n")
            if 1 <= ln <= len(lines) and 'Color("' in lines[ln - 1]:
                fixed |= fix_line(src, ln, lambda l: re.sub(
                    r'Color\("([^"]+)"\)', 'Color(red: 0.5, green: 0.5, blue: 0.5)', l), log)
            continue

        # (g) init CGRect(x:y:width:height:) -> PureSwiftKit's cgRect helper.
        # The error does not mention 'CGRect' in the text ("argument passed to call that
        # takes no arguments") — we trigger on the pattern and the regex decides.
        if ("takes no arguments" in msg or "extra argument" in msg
                or "missing argument" in msg or "no exact matches" in msg):
            fixed |= fix_line(src, ln, lambda l: re.sub(
                r"CGRect\(\s*x\s*:\s*([^,()]+?)\s*,\s*y\s*:\s*([^,()]+?)\s*,\s*"
                r"width\s*:\s*([^,()]+?)\s*,\s*height\s*:\s*([^,()]+?)\s*\)",
                r"cgRect(\1, \2, \3, \4)", l), log)
            continue

    return fixed, ghost


def run_build(app, bundle, srcs, debug=False):
    # Shims_*.swift files created by the fixes are added automatically
    import glob
    work_dir = os.path.dirname(srcs[0]) if srcs else "/tmp/port-" + app
    shims = sorted(glob.glob(os.path.join(work_dir, "Shims_*.swift")))
    cmd = ["sh", BUILD_SH, app, bundle] + srcs + shims
    if debug:
        cmd.append("--debug")
    build_work = os.environ.get("ISB_BUILD_WORK", os.path.join("/tmp", "build-" + app))
    env = os.environ.copy()
    env["ISB_BUILD_WORK"] = build_work
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    out = r.stdout + r.stderr
    errfile = os.path.join(build_work, "swift.err")
    if os.path.exists(errfile):
        try:
            with open(errfile, encoding="utf-8", errors="replace") as f:
                out += "\n" + f.read()
        except OSError:
            pass
    return r.returncode, out


def dep_root(path, src_dir):
    """Merge grouping root: the dependency (e.g.: 'tca', 'app')."""
    p = path.replace("\\", "/")
    if p.startswith(src_dir):
        return "app"
    m = re.search(r"/([^/]+)/Sources/", p)
    if m:
        return m.group(1)
    return os.path.basename(os.path.dirname(path))


def merge_by_dir(srcs, work_dir, log, entry=None):
    """Concatenates the sources by source directory into single files.

    swift-frontend on iSH becomes unstable with many files per compilation
    (~45+): modules load in corrupted form and types disappear. Concatenating
    per module reduces 191 files to ~10 and stabilizes the build. Imports from
    all files move to the top of the concatenated file (in canonical
    order); bodies follow the original order.
    """
    # basename -> source root (recorded on copy): the dependency
    # directory (e.g.: 'tca', 'app', 'OrderedCollections') to group the merge
    if not hasattr(merge_by_dir, "orig_dirs"):
        return srcs  # no mapping: do not merge
    mode = getattr(merge_by_dir, "mode", "dep")
    orig = merge_by_dir.orig_dirs if mode == "dep" else merge_by_dir.orig_subdirs
    groups = {}
    for s in srcs:
        b = os.path.basename(s)
        if b in ("main.swift", "PureSwiftKit.swift"):
            continue  # entry (top-level) and kit stay separate
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
        # unique imports preserving canonical order
        seen, uniq = set(), []
        for im in imports:
            if im not in seen:
                seen.add(im)
                uniq.append(im)
        uniq.sort(key=lambda l: CANON.get(re.search(r"import\s+(\w+)", l).group(1), 99))
        out = os.path.join(work_dir, "merged_%02d_%s.swift" % (i, d.replace("/", "_")[:40]))
        with open(out, "w", encoding="utf-8") as f:
            f.write("// merged: " + d + " (" + str(len(fs)) + " files)\n")
            f.write("\n".join(uniq) + "\n\n")
            f.write("\n\n".join(b for b in bodies if b.strip()))
        merged.append(out)
        log_append(log, "merged %d files from %s -> %s"
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
        print("ERROR: directory not found:", src_dir)
        sys.exit(1)

    log = []
    print(f"==> porting {os.path.basename(src_dir)} -> {app} ({bundle})")
    print("==> step 1: collecting Swift sources (iOS target)")
    files = collect(src_dir)
    for d in extra_dirs:
        if not os.path.isdir(d):
            print("ERROR: --extra dir not found:", d)
            sys.exit(1)
        files += collect(d)
    if not files:
        print("ERROR: no .swift found in", src_dir)
        sys.exit(1)
    if exclude:
        files = [f for f in files if os.path.basename(f) not in exclude]
        print("   --exclude: " + ", ".join(exclude))
    for f in files:
        print("   + " + os.path.relpath(f, src_dir) if f.startswith(src_dir)
              else "   + " + f)

    print("==> step 2: copying to the work area and adapting")
    # work on a COPY — the project's original repo is never edited
    port_root = os.environ.get("ISB_PORT_WORK_ROOT", "/tmp")
    work = os.path.join(port_root, "port-" + app)
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
            log_append(log, "space in name renamed: " + base)
        dest = os.path.join(work, base)
        if base in seen:
            # basename collision (build-pure-ui.sh flattens the paths):
            # prefix with the parent directory name
            base = os.path.basename(os.path.dirname(f)) + "_" + base
            dest = os.path.join(work, base)
            log_append(log, "duplicate basename renamed: " + base)
        seen[base] = f
        merge_by_dir.orig_dirs[base] = dep_root(f, src_dir)
        merge_by_dir.orig_subdirs[base] = os.path.basename(os.path.dirname(f))
        shutil.copy(f, dest)
        srcs.append(dest)

    # PureSwiftKit enters the build (unless --no-kit: the kit imports UIKit and
    # can break with Foundation types in large modules — use --no-kit
    # when the app does not use the kit's cg*/FS helpers)
    if not no_kit:
        kit = os.path.join(work, "PureSwiftKit.swift")
        shutil.copy(KIT, kit)
        srcs.append(kit)
        print("   + PureSwiftKit.swift included (helpers for degradations)")
    else:
        print("   + --no-kit: PureSwiftKit NOT included")

    # strip imports of modules that will be compiled together (1 single module)
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
        print(f"   + imports of {len(strip_mods)} unified modules removed "
              f"in {n_stripped} files")

    # adaptations on the copy
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
            log_append(log, "debug: StikDebug return bundle ID set to "
                            + stikdebug_bundle_id)

    # scene lifecycle: the storyboard does not compile (no ibtool) — willConnectTo
    # must create the window in code. Detects SceneDelegate and stores the class
    # for UIApplicationSceneManifest (Info.plist, step 3.5).
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
                # Some repos keep the Swift target in a subfolder, but the
                # resources/storyboards at the project root. Searching only
                # that root and its parent avoids scanning the entire filesystem.
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
                log_append(log, "scene: storyboard found at " + story)
            convert_scene_delegate(f, story, log, debug=debug)
            if debug:
                log_append(log, "debug: overlay explicitly installed after makeKeyAndVisible")
            scene_class = app + "." + m.group(1)

    # stability: swift-frontend on iSH breaks with ~45+ files per
    # compilation (corrupted modules -> types disappear). Merge per module.
    if merge_mode != "none" and (len(srcs) > 45 or merge_mode == "subdir"):
        merge_by_dir.mode = merge_mode
        srcs = merge_by_dir(srcs, work, log, entry)
        print(f"   + {len(files) + 1} sources merged into {len(srcs)} files "
              f"(mode {merge_mode})")

    print("==> step 3: reactive build loop (max " + str(MAX_ITER) + " iterations)")
    rc = None
    ghost_retries = 0
    kit_used = not no_kit
    for it in range(1, MAX_ITER + 1):
        print(f"   --- iteration {it} ---")
        rc, out = run_build(app, bundle, srcs, debug=debug)
        if rc == 0:
            print("   BUILD OK")
            break
        if rc < 0:
            # killed by signal (iOS OOM / frontend crash): retry
            ghost_retries += 1
            print(f"   compiler killed (rc={rc}, probably OOM), retry "
                  f"{ghost_retries}/8...")
            if ghost_retries >= 8:
                print("   too many OOM retries — aborting")
                sys.exit(1)
            continue
        fixed, ghost = fix_known_errors(work, out, log)
        if fixed:
            print("   fixes applied, rebuilding...")
            continue
        if ghost and ghost_retries < 5:
            # ghost errors (type disappears with the import present): retry the build
            ghost_retries += 1
            print(f"   ghost errors (modules loaded unstably), "
                  f"retry {ghost_retries}/5...")
            continue
        if ghost and kit_used:
            # the ghost PERSISTS after the retries: it is not transient — the
            # PureSwiftKit (declaration threshold) broke Foundation types
            # in the module DETERMINISTICALLY (measured 2026-08-22).
            kit_used = False
            srcs = [f for f in srcs if os.path.basename(f) != "PureSwiftKit.swift"]
            srcs.append(write_minimal_kit(srcs, work, log))
            ghost_retries = 0
            print("   kit removed -> local minimal helpers; rebuilding...")
            continue
        print("   NON-AUTOMATABLE ERRORS:")
        for line in out.splitlines():
            if "error:" in line:
                print("     " + line.strip())
        sys.exit(1)

    if rc != 0:
        sys.exit(1)

    print("==> step 3.5: resources + manifest in the IPA")
    post_process_ipa(app, resources, scene_class, log, debug=debug)

    print("==> step 4: validating IPA")
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
        f.write("- Source: `" + src_dir + "`\n")
        f.write("- IPA: `" + os.path.join(WORKSPACE, app + ".ipa") + "`\n")
        f.write("- Validation: " + ("OK" if ok else "FAILED") + "\n\n")
        f.write("## Automatic adaptations\n\n")
        for e in log:
            f.write("- " + e + "\n")
    print("==> report: " + report)
    if not ok:
        print("!!! validation failed — see " + report)
        sys.exit(1)
    print("==> DONE")


if __name__ == "__main__":
    main()
