# iOS Swift Builder — build iOS apps with Swift, on-device, no Mac at build time

> **Fonte normativa para novos trabalhos:** [`references/BEST-PRACTICES.md`](references/BEST-PRACTICES.md). Ela define a ordem de validação, níveis de evidência, perfis, limites do LiveContainer e o que evitar. Os demais documentos preservam detalhes técnicos ou histórico.

Compile modern **Swift** into a signed native **iOS `.ipa`**, 100% inside
**iSH** (Alpine Linux on iPhone/iPad). No Mac needed to *build* — only once, up
front, to obtain the iOS SDK (which you're licensed to use because you have
Xcode / a device).

> **Unofficial. Not affiliated with or endorsed by Apple.** You are responsible
> for complying with the Apple SDK/Xcode license, the Swift toolchain license,
> and glibc's terms. This repo ships only original scripts, docs, and sample
> sources — no Apple/Swift/glibc material. See [Licensing](#licensing).

Proven working: Swift 6.3.3 → Mach-O arm64e.v1/PAC (iOS 26.5 SDK) →
linked with UIKit/Foundation → IPA estruturally valid → LiveContainer/device
validation path. **Pure-Swift `import UIKit` and `import SwiftUI` work on-device**
(since 2026-08-19) — no Objective-C needed. `import Foundation` + `import
Dispatch` also work in pure Swift. The arm64 cache is retained only as an
explicit rollback profile.

---

## Isto funciona para mim?

| Requisito | Necessário |
|---|---|
| iPhone/iPad com iSH | sim |
| iOS 26.x (testado: 26.6) | sim |
| Acesso a um Mac com Xcode 26, **uma vez** | sim — para obter o SDK |
| LiveContainer (ou device com JIT) | para executar as IPAs |
| ~6 GB livres | sim |

**Não testado:** outras versões de iOS/SDK, outros devices e iSH em iPad. A
matriz completa, incluindo o host exato das validações, está em
[`references/VERSION-MATRIX.md`](references/VERSION-MATRIX.md).

## Native arm64e profile (canonical)

The project now treats native arm64e.v1/PAC as the single operational profile.
All new IPAs and the canonical acceptance alias use arm64e. The old arm64 cache and scripts remain only as an explicit local rollback path
for emergency reproduction:

```sh
ISB_ARCH=arm64 sh scripts/build-pure-ui.sh LegacyApp com.example.legacy \
  assets/PureSwiftDemo.swift --primary-file --unsigned
```

Arm64e S2 is fully covered by the matrix in
`scripts/acceptance-suite-arm64e.sh`. S3/S4 still require opening the fresh
IPAs in the target LiveContainer/device and exercising each labeled flow.



## Arm64e acceptance matrix (S2 local)

The canonical `scripts/acceptance-suite.sh` generates and validates fresh
arm64e.v1/PAC IPAs for UIKit/SwiftUI, Foundation/Dispatch, the full TortureTest
(including Diffable UIKit), debug/StikDebug, Swift+ObjC hybrid, CoreML/Vision/
Accelerate, FoundationModels availability and generation, NaturalLanguage, and
NLEmbedding via ObjC bridge. Every IPA is checked for the exact arm64e slice,
chained fixups, entry point, undefined symbols and IPA structure; FoundationModels
also requires weak-link.

S2 is not S3/S4: open the IPAs in the target LiveContainer/device and exercise
each labeled flow before claiming runtime compatibility.


  Combine, Observation, Foundation, Dispatch, …) and the **UI in
  Objective-C/UIKit**, linked together (hybrid — works today).
- **Pure-Swift console apps** with `import Foundation` / `import Dispatch` —
  no ObjC needed (one command).
- **Pure-Swift UIKit and SwiftUI** — full apps, no ObjC, validated on-device.
- One command produces a structurally-valid, ad-hoc-signed `.ipa`.
- Runs entirely on the phone (iSH). The first stdlib compile is slow (~20 min,
  once); app builds are ~2 s afterward.

## Capabilities — what works / what doesn't

### ✅ Works today (validated)

| Capability | How |
|---|---|
| **Pure-Swift `import UIKit`** | `scripts/build-pure-ui.sh` — validated on-device (LiveContainer) since 2026-08-19 |
| **Pure-Swift `import SwiftUI`** | same script; `SwiftUIDemo` runs on-device |
| Pure-Swift `import Foundation`, `import Dispatch` | `scripts/build-pure-foundation.sh` — neutral 6.3.3 module profile; local S2 build validated |
| Pure-Swift `Combine`, `CoreFoundation`, `ObjectiveC`, `Darwin`, `System`, `Observation`, `os`, `simd`, `Spatial`, `Symbols`, `Accessibility`, `CoreText`, `DataDetection`, `CoreTransferable`, `OSLog`, `_Concurrency`, `_StringProcessing` | same prebuilt module set |
| **Apps with SPM dependency trees** | single module + `-primary-file` (`scripts/build-parallel.py` + `scripts/link-ipa.sh`) — validated with TCA 0.39.1 + 6 packages, 27k lines, running on-device |
| **Porting third-party GitHub projects** | `scripts/port-third-party.py` — reactive build loop with automatic fixes |
| Swift logic + **ObjC UIKit UI** (hybrid) | `scripts/build-ipa.sh` — the original architecture, still supported |
| Full IPA packaging + ad-hoc signing | `build-pure-ui.sh` / `link-ipa.sh` → `validate-ipa.sh` |
| **Acceptance / release test** | `scripts/acceptance-suite.sh` — canonical arm64e.v1/PAC IPA matrix, structural guards, weak-link negative test and debug validation |
| Clang modules for **UIKit, Security, CFNetwork, CoreGraphics, CoreText, QuartzCore, OSLog, XPC, MachO, UIUtilities** etc. | prebuilt `.pcm` set (usable from ObjC) |

### ⚠️ Known caveats

| Caveat | Detail |
|---|---|
| **Perfil legado arm64** | cache parcialmente herdado; não é o perfil operacional. Pode ser selecionado explicitamente com `ISB_ARCH=arm64` |
| **CoreGraphics degrades Foundation in whole-module** | a file using `CGRect` can make `Bundle`/`NotificationCenter` vanish from *other* files → `--primary-file` is the default since 2026-08-23. See `references/WARNINGS-FATAIS.md` |
| **Delegate signatures must be checked, not guessed** | the patched SDK exposes `NSDictionary`/`NSIndexPath` where Apple documents Swift types; a mismatch is only a *warning* and yields a black screen. Guards: `check-warnings.py` + `check-entry.py` |
| Patched `.swiftinterface` | some CoreGraphics conveniences are invisible → `assets/PureSwiftKit.swift` |

### ❌ Not working / out of scope

| Capability | Why |
|---|---|
| `scripts/build-multimodule.sh` (deps as a separate module) | 🔴 **deprecated 2026-08-23 — it breaks.** A separate module degrades `String`↔`NSString` bridging in the app module (`l.text = "literal"` → *cannot assign String to NSString*); the same file without the import compiles fine. This caused the black screen in every app it produced. Use a single module + `-primary-file` |
| Real-code-sign installs | ad-hoc only; re-sign with AltStore/SideStore/Sideloadly or use a jailbroken/TrollStore device |
| Storyboards / XIB | no `ibtool` on iSH — the UI must be built in code (the porter recreates simple storyboards) |
| Swift macros (TCA 1.x, `@TaskLocal`) | no macro plugin support → strip the attribute or exclude the file |
| Building the Foundation chain *inside* iSH | the module build must run on a real Linux (VM/Docker) once; iSH only **loads** the prebuilt modules |

## What you must bring (external, one-time)

Nothing here is redistributed — you fetch/derive it yourself:

| Piece | Where from | Notes |
|---|---|---|
| **iSH** | App Store | Alpine Linux userland on iOS. |
| **Swift Linux toolchain** | download.swift.org (`ubuntu24.04-aarch64`) | **6.3.3 recommended** (6.3.2 also works for the hybrid path). Must match the SDK. |
| **iOS 26.5 SDK** | your Xcode, or an open SDK repo (e.g. theos/sdks, xybp888/iOS-SDKs) | headers + `.tbd`. You need a valid license (you have Xcode/a device). |
| **glibc loader + libs (aarch64)** | Ubuntu 24.04 `arm64` debs (libc6, gcc-14, util-linux, ncurses) | lets the glibc Swift toolchain run on musl. |
| **ldid** | build from `ProcursusTeam/ldid` | ad-hoc code signing. |
| **clang19 + lld + zip** | `apk add clang19 lld zip` | compiler, Mach-O linker, packaging. |
| *(optional)* **a real Linux box (VM/Docker)** | any Ubuntu 24.04+ (x86_64 or arm64) | one-time: builds the Foundation/UIKit module set that iSH then loads. |
| *(optional)* **Darwin SDK bundle** | a Mac w/ Xcode 26 + `kabiroberai/swift-sdk-darwin` | only if you want a version-matched SDK + Linux LLVM toolset. |

Everything above is installed/derived by the scripts on your device — see
[`references/BOOTSTRAP.md`](references/BOOTSTRAP.md) for exact URLs and commands.

## Quick start (once the toolchain exists on-device)

```sh
# 1. verify the toolchain is intact (checks BOTH profiles: pure-Swift and hybrid)
sh scripts/check-env.sh

# 2a. pure-Swift UIKit/SwiftUI app -> .ipa   <- the main path
sh scripts/build-pure-ui.sh MyApp com.example.myapp assets/PureSwiftDemo.swift

# 2b. same, with on-device debug (LiveContainer + StikDebug)
sh scripts/build-pure-ui.sh MyApp com.example.myapp main.swift --debug
python3 scripts/check-debug-ipa.py /var/minis/workspace/MyApp.ipa

# 2c. port a third-party GitHub project (one command)
python3 scripts/port-third-party.py /tmp/project MyApp com.example.myapp

# 2d. hybrid app (Swift logic + ObjC UIKit UI) — original architecture
sh scripts/build-ipa.sh SwiftApp com.example.swiftapp \
   assets/AppLogic.swift assets/AppShell.m

# 3. inspect the result
sh scripts/validate-ipa.sh /var/minis/workspace/MyApp.ipa

# 4. after changing any build script, run the regression suite
sh scripts/regression-suite.sh

# 5. acceptance test for the complete local LiveContainer path
sh scripts/acceptance-suite.sh
```

## From zero (fresh device)

See [`REPRODUCE-FROM-ZERO.md`](REPRODUCE-FROM-ZERO.md) for the complete public
recipe, including `bootstrap.sh`, explicit artifact SHA-256 checks, the Linux
module-cache step, incremental builds, AI diagnostics, and the S0–S4 evidence
contract. For the target-specific Linux graph and Docker mounts, see
[`references/LINUX-MODULE-CACHE.md`](references/LINUX-MODULE-CACHE.md).


Follow [`references/BOOTSTRAP.md`](references/BOOTSTRAP.md) top to bottom:

0. `apk add clang19 lld zip xz zstd binutils patchelf git python3 wget` + build `ldid`.
1. Assemble the **glibc loader** from Ubuntu arm64 debs → `/opt/xtool-glibc/lib`.
2. Download **Swift** → `/opt/swift6.3` (6.3.2) or `/opt/swift6.3.3` (6.3.3),
   `patchelf` it to the glibc loader.
3. Get the **iOS 26.5 SDK** → `/opt/ios-toolchain/iPhoneOS26.5.sdk`.
4. Build the **iOS Swift stdlib** once: `sh scripts/compile-stdlib.sh` (~20 min).
5. *(to unlock Foundation/Dispatch and the UI frameworks in pure Swift)* build
   the module set on a real Linux: `references/linux-vm/RECEITA-DISPATCH-LINUX.md`
   + `orchestrator_vm.py` (6.3.2) or `orchestrator_vm633.py` (6.3.3) → copy
   `foundation-build/` to `/opt/ios-toolchain/foundation-build/`.
6. `sh scripts/check-env.sh` → **READY**, then build apps.

## How it works

- **Hybrid apps**: `AppLogic.swift` (pure Swift, `@_cdecl` exports) +
  `AppShell.m` (UIKit UI in ObjC) → one Mach-O linking UIKit + `libswiftCore`.
- **Pure-Swift Foundation/Dispatch**: the Clang module chain is built *once* on
  a real Linux with the same swift.org toolchain (binary modules carry the
  compiler tag, so iSH loads them without rebuilding). The original
  `DISPATCH_ASSUME_ABI_SINGLE_BEGIN` wall was a header search-path shadowing
  issue — see `references/DISPATCH-VIA-LINUX.md`.
- **Pure-Swift SwiftUI/UIKit:** o SDK patchado e os módulos validados permitem
  compilar apps puros; as ressalvas de sintaxe, `-primary-file` e runtime estão
  em `references/PURE-SWIFT-UI-STATUS.md` e `references/BEST-PRACTICES.md`.

## Repository layout

```
SKILL.md                     agent-facing index / happy path
README.md                    this file
LICENSE                      MIT — original files only
scripts/
  check-env.sh               verify toolchain, restore modules from backup
  bootstrap.sh               staged zero-to-checkout bootstrap with hashes
  bootstrap-glibc.sh          checksum-gated Ubuntu arm64 glibc assembly
  benchmark-build.sh          local none/O/Osize build and size benchmark
  benchmark-device-build.sh   generate none/O IPAs for device timing
  scan-dependencies.sh       generate a target-specific Linux graph
  check-module-cache.py      validate transferred module caches
  build-arm64-modules.sh     regenerate arm64 PCMs or full modules
  verify-docs.sh              static documentation and repository assertions
  build-ipa.sh               end-to-end build (hybrid or --pure)
  build-pure-foundation.sh   compile+link a pure-Swift Foundation/Dispatch app
  validate-ipa.sh            inspect a built IPA
  apply-vfs-fix.sh           install the os_workgroup VFS overlay
  compile-stdlib.sh          (re)build the iOS Swift stdlib (~20 min)
assets/
  AppLogic.swift             Swift logic template (@_cdecl exports)
  AppShell.m                 ObjC UIKit shell template (iOS 26 UIScene)
references/
  CONTEXT.md                 the journey, decisions, key learnings
  LIMITATIONS.md             every limitation + concrete solution path
  DISPATCH-VIA-LINUX.md      how pure-Swift Foundation/Dispatch was unlocked
  BOOTSTRAP.md               rebuild the whole toolchain from zero (+ Mac step)
  PUBLISHING.md              copyright/licensing analysis for GitHub
  linux-vm/                  VM recipe, orchestrators, patches,
                             PLANOS-UIKIT-SWIFT.md and
                             ESTADO-E-NEXT-STEPS.md (handoff state)
```

## Debug on-device

O debug de device é opt-in e funciona em três camadas: trace visual dentro do
app para fluxos UIKit; attach/script no StikDebug para PID, threads e
registradores; e sessão persistente para monitorar `vAttach → c → parada → g → c`
enquanto o processo roda.

```sh
sh scripts/build-pure-ui.sh MeuApp com.example.meuapp main.swift --debug
python3 scripts/port-third-party.py /tmp/projeto MeuApp com.example.meuapp \
  --debug --stikdebug-bundle-id com.kdt.livecontainer.A4658DGR7V
python3 scripts/check-debug-ipa.py /var/minis/workspace/MeuApp.ipa
```

A IPA recebe `get-task-allow`, esquema `stikdebug`, overlay DBG e
`DebugSupport.swift`. Em LiveContainer, o ID do app convidado e o ID do host
são diferentes; use o ID real do host com `--stikdebug-bundle-id`. Um script
finito pode confirmar attach e retornar; para monitoramento contínuo, o script
precisa permanecer no `c` e receber breakpoints/sinais de evento. `universal.js`
é específico do protocolo JIT e não é logger genérico: em apps comuns pode
aguardar indefinidamente por `BRK`. O console do StikDebug mostra script e
debugserver; `print`/`NSLog` do app exigem trace visual ou syslog apropriado.

Guia operacional completo: [`references/DEBUG-LIVECONTAINER-STIKDEBUG.md`](references/DEBUG-LIVECONTAINER-STIKDEBUG.md).

- **Whole-module name degradation** — a file using CoreGraphics can make
  Foundation types vanish from *other* files. `--primary-file` is the default
  since 2026-08-23 and avoids it (`references/WARNINGS-FATAIS.md`).
- **Ad-hoc signature only** — install via AltStore/SideStore/Sideloadly (they
  re-sign) or a jailbroken/TrollStore device.
- **Startup race** — swift-frontend fails ~15-25% of the time; scripts retry.
- **First stdlib compile is slow** (~20 min, once). iSH `/proc` reports cpu=0
  even while working — trust only the output file, never abort early.
- **Debug on-device via LiveContainer + StikDebug** — use `--debug`; o attach e o console ocorrem no device, nao no iSH.
- **Module set needs a Linux box once** — iSH loads prebuilt modules; rebuilding
  them on-device is not supported.

## Signing & installing

The `.ipa` is ad-hoc signed (`ldid`). To install on a device:
- **AltStore / SideStore / Sideloadly** re-sign with your Apple ID at install — no
  changes needed.
- **TrollStore / jailbroken** devices accept ad-hoc / `get-task-allow` IPAs.
- For real entitlements (push, iCloud): sign with a cert (`ldid -S… -K cert.p12`)
  and embed an `embedded.mobileprovision`. See `references/LIMITATIONS.md` §3.

## Reproducible acceptance plan (2026-08-28)

Run this after changing build scripts, SDK patching, module caches, or linker
selection:

```sh
# fast structural regression, including the known whole-module reproducer
sh scripts/regression-suite.sh --quick

# complete local acceptance path (creates a fresh unsigned IPA)
sh scripts/acceptance-suite.sh
```

The canonical `scripts/acceptance-suite.sh` generates a complete arm64e.v1/PAC
matrix. It checks fresh IPAs for UIKit/SwiftUI, Foundation/Dispatch,
TortureTest/Diffable UIKit, debug/StikDebug, Swift+ObjC hybrid,
CoreML/Vision/Accelerate, FoundationModels availability and generation,
NaturalLanguage, and NLEmbedding via ObjC bridge. Each IPA is checked for the
exact arm64e slice, chained fixups, entry point, undefined symbols and IPA
structure; FoundationModels also requires weak-link.


Acceptance status measured in this session:

- canonical `acceptance-suite.sh` → arm64e.v1/PAC matrix: **PASS**;
- 11 fresh IPAs generated: UI, Foundation/Dispatch, TortureTest, debug,
  hybrid, CoreML/Vision/Accelerate, FoundationModels availability/runtime,
  NaturalLanguage, embeddings and weak-link negative fixture;
- every IPA: exact arm64e slice, chained fixups, entry point and 0 undefined
  symbols: **PASS**;
- runtime S3/S4 still requires opening each fresh IPA in the target
  LiveContainer/device and exercising the labeled flow.



**MIT** for this repo's original files (scripts, docs, sample Swift/ObjC).
Do **not** commit any Apple SDK material, compiled `.swiftmodule`/`.pcm`
(including the `foundation-build/` sets), built `.ipa`, the Swift toolchain,
glibc binaries, or a Mac-generated Darwin bundle — all third-party. The scripts
fetch/derive those on the user's own licensed machine. Full analysis:
[`references/PUBLISHING.md`](references/PUBLISHING.md).

## Credits / prior art

- [`swiftlang/swift`](https://github.com/swiftlang/swift) — the Swift toolchain.
- [`xtool-org/xtool`](https://github.com/xtool-org/xtool) and
  [`kabiroberai/swift-sdk-darwin`](https://github.com/kabiroberai/swift-sdk-darwin)
  — cross-compiling iOS apps from Linux; the VFS/SDK-bundle approach.
- [`ProcursusTeam/ldid`](https://github.com/ProcursusTeam/ldid) — signing.
- [`ish-app/ish`](https://github.com/ish-app/ish) — the Linux shell on iOS.

## Perfil nativo arm64e/PAC (canônico)

O projeto agora usa arm64e.v1/PAC como perfil operacional único. A matriz
canônica gera e valida IPAs novas para UI, Foundation/Dispatch, TortureTest,
debug, híbrido Swift+ObjC, CoreML/Vision/Accelerate, FoundationModels,
NaturalLanguage e embeddings. O cache arm64 e os scripts antigos permanecem
somente como rollback local explícito (`ISB_ARCH=arm64`).
```sh
# embeddings do sistema, inclusive com o perfil arm64 já comprovado
sh scripts/build-pure-ui.sh EmbedApp com.example.embed main.swift \
  --extra-objc assets/NativeNLBridge.m --extra-framework NaturalLanguage

# IA on-device Apple, com cache arm64e e linker PAC local já instalado
ISB_ARCH=arm64e sh scripts/build-pure-ui.sh LocalAI com.example.localai \
  main.swift assets/FoundationModelsProbe.swift

# aceitação completa, sem rede/VM no caminho de build
ISB_ARCH=arm64e sh scripts/acceptance-suite-arm64e.sh
```

`FoundationModels.framework` e `NaturalLanguage.framework` do SDK 26.5 têm
stubs para arm64e. Foundation Models usa o modelo Apple disponível no sistema;
não é um runtime para pesos locais de terceiros. Para modelos locais
embarcados, use Core ML/Vision/Accelerate e passe `--extra-framework` conforme
necessário. Receita do cache arm64e: `scripts/build-arm64e-modules.sh` e
`references/NATIVE-INTELLIGENCE.md`.

**Foundation/Dispatch:** o perfil arm64e tem smoke test local S2 com IPA
visual, incluindo verificação de slice, Mach-O e símbolos indefinidos. O
TortureTest arm64e também cobre Diffable UIKit e PureSwiftKit.

**Runtime:** as IPAs finais estão em `workspace/arm64e-final`. A aceitação
estrutural está concluída; para converter cada capacidade em S3/S4, abra a IPA
correspondente no LiveContainer e toque o fluxo indicado na tela. Não
extrapolar o resultado para outros hosts ou devices.
