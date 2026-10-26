# FATAL Warnings — when "warning" means "your app won't work"

> **Prevention policy:** [`BEST-PRACTICES.md`](BEST-PRACTICES.md) is the normative
> source for diagnosis and evidence levels. This document details the
> warnings and the automatic guards.

> This document exists because an entire session was lost on 2026-08-22
> chasing a black screen whose cause was **printed in the build log
> from the very first minute**, classified as a *warning*.

## The general rule

This project compiles against **patched** `.swiftinterface` files. In the
overwhelming majority of cases the patches preserve the signatures, but some
types degraded (typically Swift collections became raw ObjC types):

| Apple | Our SDK |
|---|---|
| `[UIApplication.LaunchOptionsKey: Any]?` | `NSDictionary<NSString, AnyObject>?` |
| `[String: Any]` (in several delegates) | `NSDictionary` |

When the protocol member is **optional** — which holds for almost every
delegate inherited from ObjC (`optional func`) — a signature that does not
match **is not an error**. Swift merely warns:

```
warning: instance method 'X' nearly matches optional requirement 'X'
         of protocol 'Y'
note: candidate has non-matching type '...'
```

And then treats your method as **an ordinary method of the class**. The
framework never calls it.

**Consequence: code that compiles 100% cleanly (0 errors) and does not work.**

## The case that cost the session

```swift
// ❌ compiles with a warning; UIKit NEVER calls this
func application(_ a: UIApplication,
                 didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds)   // never executes
    ...
    return true
}

// ✅ matches the SDK protocol exactly
func applicationDidFinishLaunching(_ application: UIApplication) {
    window = UIWindow(frame: UIScreen.main.bounds)
    ...
}
```

### Why the symptom is so misleading

The app **opens**. The process stays **alive**. There is no crash, no log, no
crash report. Just a black screen — because no window was ever created.

This led to a cascade of wrong hypotheses (all discarded through tests):

| Hypothesis | Test that refuted it |
|---|---|
| TCA effects don't emit | `MinLink` (doesn't use TCA) also went black |
| `ViewStore` reactivity is dead | same |
| SwiftUI doesn't render | same |
| `__isPlatformVersionAtLeast` shim | `AvailTest` with the shim launched (blue) |
| Missing symbol for the dyld | `check-undefined.py`: 0 missing in both |
| Multi-module build corrupts metadata | single module also went black |
| `libswift_Concurrency` doesn't load | `T1Conc` (which links it) launched normally |

All these tests were useful — each one eliminated an entire floor of the building.
But none was necessary: reading the warning would have been enough.

## The automatic defense (already integrated)

There are **two** layers, because one alone is not enough.

### ⚠️ Why two: the warning is INCONSISTENT
Measured on 2026-08-22: the **same** code with the wrong signature emits the
warning in one compilation context and **does not emit it** in another (small
apps with few imports compiled without warning — and in those cases the ObjC
thunk is even generated, so the app works). In other words: **absence of a
warning proves nothing**.
That is why the second layer looks at the binary.

### Layer 1 — `scripts/check-warnings.py` (source/log)
Runs on its own in `build-pure-ui.sh` and in `build-parallel.py`; **aborts the build**
and explains the cause.
```sh
python3 scripts/check-warnings.py <file.err>
python3 scripts/check-warnings.py --dir <dir with *.err>
```

### Layer 2 — `scripts/check-entry.py` (linked binary) ⭐ the one that doesn't fail
It doesn't depend on a warning: it checks what ended up in the binary.

**The decisive signal is the ObjC thunk.** When the signature matches the protocol,
the compiler emits TWO symbols:
```
_$s<App>11AppDelegateC11application_29didFinishLaunching...F     <- Swift function
_$s<App>11AppDelegateC11application_29didFinishLaunching...FTo   <- ObjC THUNK ✅
```
The **`To`** suffix ("to ObjC") is what registers the method with the ObjC runtime — it is
through it that UIKit calls your delegate. Without a thunk, the method exists in Swift and
ObjC **never sees it**.

> There is no point in looking for the selector name in `__objc_methname`: the string appears
> in any binary (it comes from UIKit itself). What discriminates is the **thunk in
> your class**.

```sh
python3 scripts/check-entry.py <App.ipa | binary>
```
Checks: (1) `_main` calls `UIApplicationMain`; (2) the delegate inherits from
`UIResponder`; (3) the launch method has an ObjC thunk.

**Validated on the 6 IPAs of this investigation** — it separated exactly those that run
from those that show a black screen:

| IPA | check-entry | device |
|---|---|---|
| Minesweeper (fixed) | 3/3 ✅ | runs |
| AvailTest | 3/3 ✅ | runs |
| Bad3App | 3/3 ✅ | (thunk present) |
| MinLink | 2/3 ❌ | black screen |
| MineDiag | 2/3 ❌ | black screen |
| MinesweeperSM | 2/3 ❌ | black screen |

### Layer 3 — `scripts/check-protocol-sig.py` — consult, don't guess
Shows the **real** signature of any protocol/member in this toolchain's
SDK:
```sh
python3 scripts/check-protocol-sig.py UIApplicationDelegate didFinishLaunching
python3 scripts/check-protocol-sig.py --grep "func application"
```
**Before implementing any system delegate, consult here.** Copying from Apple's
documentation or writing from memory is the direct path to this bug.

### `assets/AppEntry.swift` — entry point template
It already ships with the correct signature and the explanation. Copy from it.

### `port-third-party.py` — fixes it automatically
`fix_delegate_signature()` rewrites `application(_:didFinishLaunchingWithOptions:)`
→ `applicationDidFinishLaunching(_:)` (every third-party app uses Apple's).

## How to investigate a "compiles but doesn't work" (recipe)

1. **Read the build warnings.** `grep -c "nearly matches" *.err`. Don't skip it.
2. **Run `check-warnings.py`** over the logs.
3. If clean, then bisect by layers — and use MINIMAL apps (15 KB, seconds
   to build), never the whole app (10 min per 1 bit of information):
   - is the entry point called? (paint the screen a solid color in `viewDidLoad`)
   - does the window exist? was `rootViewController` set?
   - only then investigate the app's logic
4. **A distinct background color in each test** (blue/green/purple) — "black" is
   ambiguous between "it didn't run" and "it ran and didn't draw".
5. **Synchronous logging**, never via `DispatchQueue.main.async`: if the main thread
   hangs or the view never appears, the async block never runs and you are left
   with no information at all.

## Other warnings worth paying attention to

| Warning | Risk |
|---|---|
| `nearly matches optional requirement` | 🔴 **fatal** — method never called |
| `result of call to '...' is unused` in the entry point | 🟡 may indicate a malformed `UIApplicationMain` |
| `was deprecated in iOS` | 🟢 noise (ignored by the checker) |
| `'retroactive' attribute does not apply` | 🟢 noise |
| `auto-linked framework not found: UIUtilities` | 🟢 known lld noise |

---

# PHANTOM Errors — when the error lies about the cause

Not every problem shows up as a warning. There is a class of **errors** whose
message points to the wrong place. The case below cost the entire `--debug`
feature (it stayed broken and documented as "validated").

## 🔴 CoreGraphics degrades Foundation (whole-module) — 2026-08-23

### Symptom

```
error: cannot find 'Bundle' in scope
error: cannot find 'NotificationCenter' in scope
error: cannot find 'OperationQueue' in scope
error: 'nil' requires a contextual type
```

The file **imports `Foundation`** and the import is in the canonical order. The type
exists. Compiled on its own, the same file passes.

### Cause

In **whole-module** mode, if any file in the module uses **CoreGraphics**
(`CGRect(origin:size:)`, `CGPoint`, `CGSize`), Foundation's ObjC types
can **disappear from OTHER files** in the same module.

The degradation is **cross-file**: the file that reports the error may not have a
single line of CoreGraphics. In the real case, `main.swift` (with 9 uses of CGRect) made
`Bundle` vanish from a 3-line `Helper.swift`.

Reproduced **deterministically** (3/3) with two files:

```swift
// main.swift  — uses CGRect
// Helper.swift:
import Foundation
import UIKit
public enum Helper {
    public static func b() -> String { return Bundle.main.bundleIdentifier ?? "?" }
}
// -> error: cannot find 'Bundle' in scope
```

It also occurs **within a single file**, when the declaration that uses
CoreGraphics comes **before** the one that uses Foundation:

```swift
// ❌ FAILS
enum H {
  static func r() -> CGRect { CGRect(origin: CGPoint(x:1,y:2), size: CGSize(width:3,height:4)) }
  static func b() -> String { Bundle.main.bundleIdentifier ?? "?" }
}
// ✅ OK — same code, reversed order
enum H {
  static func b() -> String { Bundle.main.bundleIdentifier ?? "?" }
  static func r() -> CGRect { CGRect(origin: CGPoint(x:1,y:2), size: CGSize(width:3,height:4)) }
}
```

**Ruled out by testing** (they are not the cause): `public`, `import Darwin`, alphabetical
ordering of the files, a large multi-line string literal, file size,
import order.

### ✅ Solution: `-primary-file`

The same code, **with no changes at all**, compiles in seconds in
file-by-file mode:

| Mode | Result |
|---|---|
| whole-module | ❌ `cannot find 'Bundle' in scope` |
| `-primary-file` (`build-parallel.py`) | ✅ 6 s |

That is why `build-pure-ui.sh` uses **`--primary-file` as the default** since
2026-08-23 (with 2+ files). To force the old mode: `--whole-module`.

> ⚠️ `-primary-file` is not just "for a large app with TCA/heavy generics",
> as the previous documentation suggested. It fixes an **entire class of
> name-resolution degradation** that affects small apps too.

### If you really need whole-module

Order the declarations: everything that uses Foundation **before** everything that uses
CoreGraphics. See `assets/DebugSupport.swift` (functions `isbBarFrame()` /
`isbTitleFrame()` isolated at the end of the file). This mitigates the intra-file case,
but **does not fix the cross-file** one — for that one, only `-primary-file`.

### Guard

`scripts/regression-suite.sh` includes the `cgfoundation` case, which reproduces
exactly this combination in both modes. Run it after changing the build
scripts.
