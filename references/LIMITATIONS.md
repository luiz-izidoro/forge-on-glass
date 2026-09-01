# Limitations & Solution Paths

> **Fonte normativa:** [`BEST-PRACTICES.md`](BEST-PRACTICES.md). Este arquivo
> lista limitações e caminhos de solução; números e estados antigos devem ser
> lidos como snapshot e não como autorização para misturar caches ou promover
> um runtime não comprovado.

Each item: the limitation, root cause, what was already tried, and the concrete
path to solve it from a fresh session.

## §0.3. Arm64e/PAC — estado real (2026-08-28)

O perfil arm64e/PAC está **resolvido localmente**. O suporte arm64e do LLVM
PR #188378 foi compilado para Linux/aarch64 e instalado em
`/opt/ios-toolchain/ld64.lld-arm64e` como executável estático. Depois do
bootstrap, o build não usa rede, SSH, SCP ou VM.

Os caminhos aceitos são:

- **LiveContainer / uso diário:** `build-livecontainer.sh`, arm64 unsigned,
  100% local; comprovado abrindo no iOS 26.6 em iPhone17,1.
- **Arm64e/PAC nativo:** `ISB_ARCH=arm64e`, cache local isolado, linker PAC
  local e IPA arm64e com chained fixups. Foundation, FoundationModels,
  NaturalLanguage e embeddings foram compilados/linkados em aceitação.

A guarda canônica é `scripts/acceptance-suite-arm64e.sh`; ela verifica que o
linker é aarch64 e executável no iSH, que o caminho não contém SSH/SCP, e gera
três IPAs novas com SDK 26.5, subtype arm64e exato, `LC_MAIN`, chained fixups,
entry point, FoundationModels, NaturalLanguage e bridge de embeddings. O
linker remoto permanece somente como ferramenta histórica de bootstrap.



> **Este item está RESOLVIDO.** `import UIKit` e `import SwiftUI` compilam em
> Swift puro e têm apps rodando no device. O texto abaixo é o **registro
> histórico** de como o muro caiu — útil para reproduzir o SDK do zero, não
> para saber o que funciona hoje. Estado atual: `references/HANDOFF.md`.

**Symptom (histórico).** `import UIKit`/`import SwiftUI` in a Swift file fails to compile
its Swift-side interface (swift.org 6.3.2/6.3.3 interface-compile bug).

**Progress (2026-08-19, Swift 6.3.3):** the entire Clang module chain builds on
a real Linux (91 pcm) and ALL Swift interfaces compile except UIKit:
Foundation, Dispatch, Combine, CoreFoundation, ObjectiveC, Darwin, System,
Observation, os, simd, Spatial, Symbols, Accessibility, CoreText,
DataDetection, CoreTransferable, OSLog, UniformTypeIdentifiers, QuartzCore,
DeveloperToolsSupport, **SwiftUICore** (4MB).

### Root cause (swift.org interface-compile bug — 8 mechanisms)

Compiling the Swift interfaces fails with `no type named 'X' in module 'Y'` /
`cannot find type 'X' in scope` / member lookups failing inside nested member
contexts: types re-exported from clang modules don't resolve in
`-compile-module-from-interface` mode. Bisected with minimal probes; the 8
mechanisms + fixes are documented in
`references/linux-vm/ESTADO-E-NEXT-STEPS.md` §2 (stubs locais, nomes clang
diretos, reescrita de corpos com campos reais, remoção de
defaults/conformances, `-import-module CoreFoundation`, etc.).

### Remaining: UIKit

All type errors patched. The last blocker is a **compiler crash** (swift.org
6.3.3, `emitCBridgedToNativeValue` in SILGen — a bridging thunk of an @objc
method with a patched non-bridgeable type). Bisect plan:
`references/linux-vm/ESTADO-E-NEXT-STEPS.md` §3. After UIKit, verify
`import SwiftUI` (top-level re-export module).

### os_workgroup — SOLVED with a real VFS overlay (do this)

Root cause: the `os_workgroup` module (in `usr/include/os.modulemap`) does NOT
declare a dependency on the `os_object` module, where `OS_object` (an
`objc_runtime_visible` class) is declared. In an isolated explicit-module build
(`-fno-implicit-modules`), `OS_object` is therefore an unknown type →
`unexpected type name 'OS_object'`.

Fix (files live in `/opt/ios-toolchain/vfs/`):
1. Copy `os.modulemap` and add `header "os/object.h"` INSIDE the
   `os_workgroup` module block (so os_object's decls are in the same TU).
2. Write a VFS overlay JSON that maps the ORIGINAL SDK modulemap path to the
   patched copy (keeps header search context correct):
   ```json
   { "version":0, "case-sensitive":true, "roots":[
     { "type":"file",
       "name":"<SDK>/usr/include/os.modulemap",
       "external-contents":"/opt/ios-toolchain/vfs/os.modulemap" } ] }
   ```
3. Add `-Xcc -ivfsoverlay -Xcc /opt/ios-toolchain/vfs/overlay.yaml` to EVERY
   module build command. → `os_workgroup.pcm` compiles (102 KB, verified).

Things that did NOT work for os_workgroup (don't waste time): `-fmodule-file`,
`-fprebuilt-module-path`, `-fmodules-local-submodule-visibility`,
`-DOS_OBJECT_USE_OBJC=0`, pre-building `os_object.pcm`, `clang -cc1 -emit-module`
directly (fails on Apple `__int64_t` builtins — Alpine clang has its own).

**Progress: Dispatch/Foundation SOLVED via real Linux (2026-08-18).** The
`DISPATCH_ASSUME_ABI_SINGLE_BEGIN` wall was NOT the iSH emulation — the clang
search path resolved `<dispatch/base.h>` to the Linux toolchain's copy
(`-isystem $SW/usr/lib/swift` precedes the SDK). Fixed with symlinks + a real
Linux build (full recipe + orchestrator in `references/linux-vm/` and
`references/DISPATCH-VIA-LINUX.md`). 73 modules now build & load on iSH:
Foundation, Dispatch, UIKit (clang side), Security, CoreGraphics, os, etc.

**Remaining:** the Swift-side interfaces of DataDetection, CoreTransferable,
SwiftUICore and UIKit still fail to compile from `.swiftinterface` (swift.org
6.3.2 bug: re-exported clang types like `Foundation.NSAttributedString` don't
resolve in nested member contexts; partial workarounds — unqualify + member
reorder — fixed Accessibility/Symbols). UIKit pure-Swift stays hybrid until
this is patched in the toolchain.

### Deep root cause (verified this round — do NOT re-try these on iSH)
- The Dispatch Clang module build is **hermetic**: `-include <prefix.h>` is NOT
  applied (tested with `#error` in the prefix → never fired), and `-D`/VFS-header
  injection don't reach it either. Only the **modulemap** VFS overlay works
  (positional arg), which is why os_workgroup was fixable but Dispatch isn't.
- `base.h` guards its macros with `#ifndef __DISPATCH_INDIRECT__ #error`; each
  header compiled as an isolated TU loses base.h's `#else` (no-bounds) macros, so
  `workloop.h` sees `DISPATCH_ASSUME_ABI_SINGLE_BEGIN` undefined.
- Plain `clang19 -E` preprocesses `dispatch.h` cleanly (macros persist in 1 TU)
  BUT fails on Apple `__int64_t`/`TargetConditionals.h` (no Darwin builtin setup,
  no `__is_target_os`). swift-frontend's clang 21 has the Darwin setup but the
  hermetic module isolation. Neither single tool does both on iSH.
- swift-frontend clang 21 exposes `-fexperimental-bounds-safety-attributes`, but
  enabling it only causes PCM late-parse mismatches; it doesn't make
  `__has_feature(bounds_attributes)` true. `-fno-modules` breaks SwiftShims.

### Older note (fully superseded by the VFS fix above)
Copy the SDK, edit `os/object.h` so `OS_object`
   becomes a plain typedef when a custom macro is set, and build against the
   patched copy. Fragile but local; last resort.
4. **Ship hybrid instead (works today).** Swift logic + ObjC UIKit — see SKILL.md
   and assets/. This is the recommended default until §1.1 lands.

## §2. Frameworks limited in pure Swift

**Import requirements:** the active cache for a profile must match the selected
Swift compiler and target triple. The legacy `foundation-build/` cache belongs
to its recorded toolchain; `foundation-build633-arm64e/` is a separate arm64e
cache. Do not interpret the presence of one as proof that the other profile is
ready. `check-env.sh` is authoritative.

**✅ RESOLVIDO (2026-08-19):** `import UIKit` e `import SwiftUI` **funcionam em
Swift puro** e têm apps validados no device. O crash do SILGen foi contornado
pelo patch-set do SDK (`/var/minis/shared/darwin-sdk/patchset/`). Use
`scripts/build-pure-ui.sh`. Os **clang** modules (UIKit.pcm, …) continuam
disponíveis para o caminho híbrido em ObjC.

⚠️ Ressalva ativa: no modo **whole-module**, um arquivo que usa CoreGraphics
pode fazer tipos do Foundation sumirem de outros arquivos → use o padrão
`--primary-file`. Ver `references/WARNINGS-FATAIS.md`.

## §3. Ad-hoc signature only (install requires more)

**Now.** `ldid -S` produces a valid CodeDirectory + CDHash, so the IPA is
well-formed, but it is not signed with an Apple certificate.

**To install on a device:**
- Easiest: hand the IPA to **AltStore / SideStore / Sideloadly** — they re-sign
  with the user's Apple ID (7-day free cert) at install time. No changes needed.
- Jailbroken device: `ldid`-signed ad-hoc installs directly (or via TrollStore,
  which accepts ad-hoc/`get-task-allow` IPAs permanently on supported iOS).
- Proper cert flow on-device: obtain a `developer.mobileprovision` +
  signing identity, then `ldid -S<entitlements> -K<cert.p12>` (ldid supports
  PKCS#12). Embed the profile as `embedded.mobileprovision` in the .app. This is
  the only path for entitlements like push/iCloud.

## §4. Startup race + slow first compile

**Race.** ~15-25% of swift-frontend calls die silently. **Always retry** (all
provided scripts do). Detection: empty stderr + missing output = race → retry;
`error:` in stderr = real → stop.

**Slow stdlib.** First-time stdlib compile ≈ 17 min (core) / ~20 min total. It
is cached afterward; app builds are ~2s. If modules exist, never recompile.
Back them up (scripts do) to `/var/minis/shared/darwin-sdk/swift-modules-full`.

## §5. Mac needed once (SDK bundle)

The open SDK + binary-compatible setup came from a Mac-generated
`darwin.artifactbundle` (via kabiroberai/swift-sdk-darwin `./build.sh auto
aarch64`, or xtool `sdk install`). See references/BOOTSTRAP.md and
/var/minis/shared/darwin-sdk/PROCEDIMENTO-MAC.md. Once the SDK + toolchain exist
on-device, no Mac is needed to build apps.

## §6. Debug no device via LiveContainer + StikDebug

O iSH não oferece `ptrace`, simulator ou Instruments, mas LiveContainer +
StikDebug permitem debug no próprio device. O debug documentado tem três
camadas:

1. trace visual no app para eventos UIKit e renderização;
2. attach/script para PID, threads, `qSupported`, `qC` e registradores;
3. sessão persistente `vAttach → c → parada → g → c`, com breakpoints de evento
   para impedir que o monitor fique eternamente aguardando sem sinais.

Use `--debug` e, dentro do LiveContainer, passe o bundle ID do host em
`--stikdebug-bundle-id` (por exemplo `com.kdt.livecontainer.A4658DGR7V`). O
bundle do convidado e o host são diferentes. `universal.js` é específico para
JIT/BRK e não deve ser tratado como logger genérico. O console do StikDebug
mostra o script/debugserver; `print`/`NSLog` do app exigem trace visual ou
syslog. A IPA preserva `get-task-allow`, mas o instalador pode removê-lo;
valide novamente com `check-debug-ipa.py`.

Guia completo: `references/DEBUG-LIVECONTAINER-STIKDEBUG.md`.

## §7. Disk & performance

Toolchain footprint: ~3.3 GB (swift6.3) + ~330 MB (SDK) + ~170 MB (glibc) +
~180 MB (modules). Keep ≥2 GB free for builds. Large compiles are RAM/CPU heavy
under emulation; close other work.
