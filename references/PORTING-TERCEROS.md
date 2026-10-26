# Porting third-party apps — complete guide (2026-08-19)

> **Required entry point:** read [`BEST-PRACTICES.md`](BEST-PRACTICES.md) before
> porting. This document contains adaptation details; the normative guide
> defines evidence, isolation, diagnostic order, and what not to promise.

This document consolidates ALL the lessons from porting open source projects from
GitHub to IPA with the iSH toolchain. Two real validated cases:

| App | Source | Dependencies | Result |
|---|---|---|---|
| Game2048 | unixzii/SwiftUI-2048 (732⭐) | none (pure SwiftUI) | IPA ✅ 87KB |
| Minesweeper | RogyMD/TCAminesweeper (137⭐) | TCA 0.39.1 + 6 SPM packages | see HANDOFF |

## Recommended flow (1 command)

```sh
git clone <repo> /tmp/projeto
python3 scripts/port-third-party.py /tmp/projeto AppName com.x.y.bundle
# available flags (see below)
```

The script does it on its own: collection → pre-adaptation (entry + imports) →
import stripping → anti-instability merge → reactive build loop with automatic
fixes → validation → `<App>-port.md` report.

## The flags

```sh
--extra DIR            # more source directories (e.g. SPM dependencies)
--resources DIR        # bundle resources (ROMs, JSONs, images)
--strip-imports "A B"  # removes `import A`/`import B` (unified modules)
--exclude "X.swift"    # excludes files from the build (basename)
--no-kit               # does NOT include PureSwiftKit.swift in the build
--merge-mode dep|subdir  # how to group the file concatenation
--debug                # overlay, get-task-allow and StikDebug attach
--stikdebug-bundle-id ID # host bundle ID for return in LiveContainer
```

## Debugging during porting

To debug the ported app in LiveContainer, use the three layers described in
[`DEBUG-LIVECONTAINER-STIKDEBUG.md`](DEBUG-LIVECONTAINER-STIKDEBUG.md): visual
trace for callbacks/UI; attach/script to confirm the PID and the debugserver;
and a persistent session with event breakpoints for continuous monitoring.
Example:

```sh
python3 scripts/port-third-party.py /tmp/projeto AppName com.x.y.bundle \
  --debug --stikdebug-bundle-id com.kdt.livecontainer.A4658DGR7V
```

Do not interpret `debug stop/continue #1` as a crash: it means that `c` is
waiting for a stop. `universal.js` is JIT-specific and is not a universal
logger. For flow bugs, prefer a trace inside the app with events such as
`didPick`, resource loading, and `frame: ok lit=N`.



Xcode downloads packages; we clone and unify EVERYTHING into a single module:

1. Identify the version: `grep -A5 'XCRemoteSwiftPackageReference' *.xcodeproj/project.pbxproj`
   (e.g. TCA 0.39.1 = `kind = exactVersion`).
2. Clone the dependency tree at the right version (each package's Package.swift
   lists its own deps — combine-schedulers → xctest-dynamic-overlay, etc.).
3. `--extra` each `Sources/<Target>/` + `--strip-imports` with ALL the unified
   modules (including the `@_exported import`s — the strip removes them).
4. The app's internal targets (e.g. `TCAminesweeperCommon`, `GameCore`) also go
   into the strip.

### Actual TCA 0.39.1 tree (measured)
```
ComposableArchitecture 0.39.1
├── CombineSchedulers 0.7.4 ──→ XCTestDynamicOverlay 0.4.1
├── CasePaths 0.10.1
├── CustomDump 0.8.0
├── IdentifiedCollections 0.5.0 ──→ swift-collections 1.0.4 (OrderedCollections)
└── XCTestDynamicOverlay 0.4.1
```
All pre-macro (0.x) = compilable pure Swift. TCA 1.x uses macros → NOT portable.

## Special cases and their solutions

### 1. `@main struct X: App` (SwiftUI App) — INCOMPATIBLE
build-pure-ui.sh renames the entry to `main.swift`; `@main` + a `main.swift`
file = error ("main attribute cannot be used in a module that contains
top-level code"). The `@main` App also degrades ObjC Foundation types in the
same module (NSString/FileManager disappear).

**Solution**: convert to AppDelegate + UIApplicationMain + UIHostingController
(the `assets/AppEntry.swift` pattern). Real example (TCAminesweeper):
```swift
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    // ⚠️ applicationDidFinishLaunching(_:) — do NOT use
    // application(_:didFinishLaunchingWithOptions:): Apple's signature does NOT
    // match the patched .swiftinterface, Swift only WARNS, UIKit never
    // calls the method and the app opens with a BLACK SCREEN. See WARNINGS-FATAIS.md
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let store = Store(initialState: MainAppState(), reducer: mainAppReducer,
                          environment: .live)
        window = UIWindow(frame: UIScreen.main.bounds)
        window!.rootViewController = UIHostingController(
            rootView: AppView(store: store.scope(state: { $0.app },
                                                 action: MainAppAction.appAction)))
        window!.makeKeyAndVisible()
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))
```
(`store.scope(state:)` takes a **closure**, not a KeyPath.)
If the root View is inside a custom Scene (WithViewStore + WindowGroup), extract
the WindowGroup content manually (the Scene does not become a View).

### 2. Symbol conflicts between dependencies
E.g. TCA and CustomDump BOTH define `final class Box<Wrapped>`. In the single
module = redeclaration. Solution: exclude the unused file (`--exclude
"Box.swift"` with care — it excludes every file with that basename; moving the
dependency's file out of Sources is more surgical).

### 3. Macros (`@TaskLocal`, `@Reducer`...) — no plugin in the toolchain
Error: "external macro implementation type 'SwiftMacros.TaskLocalMacro' could
not be found". Solution: remove the `@TaskLocal ` attribute on the line; if the
code uses the API generated by the macro (`$x.withValue`), exclude the file
(e.g. TestStore only serves tests — the app does not use it).

### 4. `DispatchQueue` goes missing (Foundation.DispatchQueue)
Errors "SchedulerTimeType is not a member type of class 'Foundation.DispatchQueue'"
or "cannot find 'DispatchQueue'" = the file imports Foundation but NOT Dispatch
(DispatchQueue resolves to the Foundation re-export, without the Scheduler
extensions). Automatic loop fix: `import Dispatch` (canonical position 6).

### 5. PureSwiftKit is NOT always welcome
The kit imports UIKit and uses FileManager/NSString — in large modules it breaks
by itself (Foundation types disappear). Use `--no-kit` when the app does not use
the helpers (`cgRect`, `cgWidth`, `FS`, `edgeInsets`, `cgDequeueCell`). The
Minesweeper uses none of them → `--no-kit` solved the kit's error class.

### 6. "Phantom" errors (types disappear while the import is present)
Symptom: "cannot find 'DispatchQueue'/'FileManager'/'Bundle' in scope" in files
that ALREADY import the module. Cause: swift-frontend (6.3.3 on iSH) loads
modules in a corrupted way on large compilations — deterministic per run, varies
between runs. The port script detects it (import present = phantom) and retries
the build (up to 5×) without applying wrong fixes. The retry does NOT solve it
if the bad state is deterministic for that set — in that case reduce the size
(merge) or the scope.

### 7. Compilation size limit on iSH (measured)
- ~45+ small files: modules get corrupted (phantom) — 43 OK / 44 breaks.
- Giant files (merged from 8000+ lines): OOM (process killed with no message).
- 60 dummy files + kit: OK → the number is NOT the trigger by itself; the heavy
  content (TCA: Combine/reflection) is the factor.
- Empirical balance: ~10-25 files of ~500-2000 lines + `--no-kit`.

### 8. `-swift-module-file`: use 1 arg (original format)
`-swift-module-file=X=path` is the correct format for swift-frontend.
`-swift-module-file X=path` (2 args) = "unknown argument: '-swift-module-file'"
(contrary to what superficial tests suggested — the parse regex did not catch
`<unknown>:0: error:`).

### 9. main.swift FIRST in the file list
The order of the files on the command line affects the resolution of Foundation
ObjC types in files that import UIKit (main first stabilizes it).
build-pure-ui.sh already guarantees this.

### 10. `os.signpost` / exotic imports
`import os.signpost` (TCA ReducerInstrumentation) may fail if the os module does
not expose the submodule — exclude the file if it is not critical.

## The compiler's sudden death (OOM)
The swift-frontend process dies without a message (negative rc) on large
compilations — iOS tightens memory and kills it. The port script treats rc<0 as
a retry. If it dies repeatedly: reduce the merge (`--merge-mode dep` for fewer
files, or subdir for more/smaller ones), or compile the deps as a separate module
(see HANDOFF — multi-module is not implemented yet).

## Quick triage checklist
1. Does the app use `@main App`? → convert the entry (case 1)
2. Does it have SPM deps? → clone the tree + --extra + --strip-imports
3. Macros in the code? → remove/exclude (case 3)
4. Duplicate basenames? → the script renames them; TYPE conflicts → exclude (case 2)
5. Large build? → --no-kit + --merge-mode + phantom retry
6. Real errors remaining? → the reactive loop covers: CGRect members, init CGRect,
   UIEdgeInsetsMake, TimeInterval→Double, ambiguous sync (csSync), CasePaths (shim),
   imports CoreText/Dispatch/Foundation/UIKit/Combine, @TaskLocal, Color("asset").

## TCAminesweeper status — ✅ RUNNING ON DEVICE (2026-08-22)

`Minesweeper.ipa` (1.1 MB) **opens and plays in LiveContainer**. First app with an
SPM dependency tree (TCA 0.39.1 + 6 packages, 27k lines) validated at runtime.

### The TWO causes that blocked this port (independent)

The current builder uses `-primary-file` to isolate files within one module;
reduce large expressions when type checking becomes slow.

**2. AppDelegate signature** (build OK, app with a black screen)
`application(_:didFinishLaunchingWithOptions:)` does not match the patched
`.swiftinterface` → Swift only **warns** → UIKit never calls the method → window
never created → **black screen with the app alive**.
Fix: `applicationDidFinishLaunching(_:)`.
Details: **`WARNINGS-FATAIS.md`** ← read it before writing any entry point.

### Validated recipe
```sh
# SINGLE module + -primary-file  (the path proven at runtime)
python3 scripts/build-parallel.py --module <App> --src <dir> --out /tmp/obj --jobs 3
# then link with the build-pure-ui.sh flags
```

- **Multi-file:** keep a single arm64e module and use `-primary-file`.
  The old separate-modules experiment was removed and is not supported.

Minesweeper sources: `/var/minis/workspace/minesweeper-port/`
(`single-src/` = what runs; `dep-src/`+`app-src/` = multi-module experiment).

The inference investigation was archived; use `-primary-file`, reduce the case,
and make the types explicit when a build gets slow.

Recipe:

## 12. Import order: `Dispatch` AFTER `UIKit`

Updated canonical order (measured, not assumed):
```
Foundation → SwiftUI → UIKit → CoreText → Dispatch → Combine → <YourModule>
```
With `Dispatch` before `UIKit`, Dispatch's Swift overlay does not load and
`DispatchQueue` becomes the raw ObjC class — the errors show up far from the
cause ("does not conform to protocol 'Scheduler'", "has no member 'main'").

## 13. `#available` breaks the LINK (not the compilation)

```
ld64.lld: error: undefined symbol: ___isPlatformVersionAtLeast
```
The final link includes `PlatformVersionShim.swift` when the project uses `#available`.
