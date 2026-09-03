---
name: ios-swift-builder
version: 0.2.0
description: >-
  Build native iOS IPA apps with Swift inside iSH using arm64e.v1/PAC. Use for
  UIKit, SwiftUI, Foundation, Dispatch, CoreML, Vision, Accelerate,
  NaturalLanguage, FoundationModels, LiveContainer, StikDebug, IPA validation,
  third-party Swift ports and toolchain troubleshooting.
---

# iOS Swift Builder

Use this skill to build and validate native iOS IPAs on-device in iSH. The
repository contains only original scripts, documentation and sample sources.
Apple SDKs, Swift/glibc runtimes, generated modules, patchsets, credentials and
IPAs are user-provided and must remain outside Git.

> Unofficial; not affiliated with Apple. Respect Apple/Xcode, Swift, glibc and
> third-party licenses.

## Before any task

Read:

1. `references/BEST-PRACTICES.md` — normative policy and S0–S4 evidence;
2. `references/HANDOFF.md` — current state and next actions;
3. `references/PROJECT-GOVERNANCE.md` — privacy, copyright and Git;
4. `references/PROJECT-GUIDE.md` — internal/external project workflow;
5. the relevant bootstrap, porting, debug or AI reference.

Dated reports are archival evidence only; rerun current checks before relying
on them.

## Canonical profile

Release and operational builds use native **arm64e.v1/PAC**:

```text
Swift 6.3.3 · iOS SDK 26.5 · arm64e-apple-ios26.5
module cache: /opt/ios-toolchain/foundation-build633-arm64e
PAC linker: /opt/ios-toolchain/ld64.lld-arm64e
```

All defaults use arm64e/PAC. Do not mix caches, objects or IPAs.

## Preconditions and build

```sh
sh scripts/check-env.sh
python3 scripts/check-module-cache.py /opt/ios-toolchain/foundation-build633-arm64e
sh scripts/build-pure-ui.sh MyApp com.example.myapp main.swift
sh scripts/validate-ipa.sh /var/minis/workspace/MyApp.ipa
```

Use a unique `ISB_OUTPUT` for custom output. With multiple Swift files, use one
module and the default `-primary-file` mode. The entry file must be `main.swift`
or end in `Main.swift`.

The patched SDK requires this delegate signature:

```swift
func applicationDidFinishLaunching(_ application: UIApplication) { ... }
```

Check system protocol signatures before implementing them:

```sh
python3 scripts/check-protocol-sig.py UIApplicationDelegate didFinishLaunching
```

Canonical import order:

```swift
import Foundation
import SwiftUI       // if used
import UIKit
import CoreText      // if needed
import Dispatch      // after UIKit
import Combine       // if used
```

Use `assets/PureSwiftKit.swift` for known patched-SDK gaps and validate it with
`sh scripts/verify-pureswiftkit.sh`.

## Supported paths

```sh
# Foundation/Dispatch
sh scripts/build-pure-foundation.sh FoundationApp main.swift

# Swift + Objective-C/UIKit
sh scripts/build-ipa.sh App com.example.app assets/AppLogic.swift assets/AppShell.m

# FoundationModels, weak-linked
sh scripts/build-pure-ui.sh AIApp com.example.ai main.swift \
  assets/FoundationModelsProbe.swift --weak-framework FoundationModels

# NaturalLanguage/NLEmbedding bridge
sh scripts/build-pure-ui.sh EmbedApp com.example.embed main.swift \
  assets/NativeEmbeddings.swift --extra-objc assets/NativeNLBridge.m \
  --extra-framework NaturalLanguage

# debug
sh scripts/build-pure-ui.sh App com.example.app main.swift --debug
python3 scripts/check-debug-ipa.py /var/minis/workspace/App.ipa
```

For third-party projects, clone outside this repository and use
`scripts/port-third-party.py`. Pin dependencies, preserve their licenses and
source commit, use one module plus `-primary-file`, and never use the deprecated
separate-module builder for production. See `references/PROJECT-GUIDE.md` and
`references/PORTING-TERCEROS.md`.

## Acceptance and evidence

```sh
sh scripts/regression-suite.sh --quick
sh scripts/verify-docs.sh
sh scripts/check-newcomer.sh
sh scripts/verify-release.sh
sh scripts/acceptance-suite.sh
```

The canonical acceptance matrix covers UI, Foundation/Dispatch, Diffable UIKit,
PureSwiftKit, debug/StikDebug, Swift+ObjC hybrid, CoreML/Vision/Accelerate,
NaturalLanguage, NLEmbedding and FoundationModels. It checks PAC subtype,
chained fixups, entry point, undefined symbols, weak-link and IPA structure.

- S0: hypothesis/plan;
- S1: source compiled;
- S2: fresh IPA passed structural guards;
- S3: fresh IPA opened on a real device/LiveContainer;
- S4: relevant flow passed on that device.

Never promote S2 to S3/S4 from static inspection. Record date, commit, profile,
SDK, device/iOS, host and result.

## Debugging

Start with synchronous visual trace. Then use `--debug` and StikDebug. The guest
and LiveContainer host bundle IDs differ. A waiting `c` or `Handling signal 1`
is not automatically a crash. Read `references/DEBUG-LIVECONTAINER-STIKDEBUG.md`.

## Governance and cleanup

Before a commit:

```sh
sh scripts/verify-release.sh
sh scripts/regression-suite.sh --quick
python3 scripts/check-repo-clean.py
```

For a clean release tree:

```sh
VERIFY_RELEASE_CLEAN=1 sh scripts/verify-release.sh
```

Never commit SDKs, headers, modulemaps, `.tbd`, `.swiftinterface`,
`.swiftmodule`, `.pcm`, IPAs, objects, toolchains, patchsets with SDK context,
credentials, certificates, provisioning profiles, private keys, personal paths,
public server addresses or user exports.

Safe cleanup targets are Python bytecode, stale `/tmp` workdirs, failed builds,
old generated IPAs and scan caches. Preserve the active SDK, neutral sysroot,
arm64e cache, PAC linker and Swift frontend until a replacement is validated.
Current continuation is always `references/HANDOFF.md`.
