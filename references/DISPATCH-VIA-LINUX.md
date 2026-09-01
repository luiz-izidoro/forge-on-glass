# Solving Dispatch/Foundation via a real Linux — SOLVED (2026-08-18)

> **Uso atual:** esta é a receita de bootstrap/reconstrução do cache, não um
> passo normal de cada projeto. Consulte [`BEST-PRACTICES.md`](BEST-PRACTICES.md)
> para compatibilidade de versões e isolamento de módulos. “Resolvido” aqui
> significa validado para o cache/combinação medidos, não para qualquer SDK ou
> toolchain futuro.

**STATUS: RESOLVED.** `import Foundation` + `import Dispatch` (e Combine,
CoreFoundation, ObjectiveC, Darwin, System, Observation, os, simd, Spatial,
Symbols, Accessibility...) compilam e linkam em Swift puro no iSH, usando
módulos construídos num Linux real (VM) com o MESMO toolchain swift.org 6.3.2.

## O que foi feito

1. **VM Linux** (Ubuntu 26.04, x86_64 — arquitetura do host não importa; o
   output é arm64-apple-ios) com swift.org 6.3.2 + o MESMO SDK 26.5 do iSH
   (upload de 328MB) + o orquestrador `orchestrator_vm.py`.
2. **73 artefatos** em `/opt/ios-toolchain/foundation-build/`: 46 `clang_*.pcm`
   + 27 `swift_*.swiftmodule` (incl. Foundation, Dispatch, UIKit-clang).
3. **Copiados para o iSH** — carregam porque têm a tag exata swift.org 6.3.2.

## Os 6 fixes (receita completa em `references/linux-vm/RECEITA-DISPATCH-LINUX.md`)

1. **Symlinks** `$SW/usr/lib/swift/{dispatch,os,CoreFoundation}` → headers do
   SDK — a CAUSA RAIZ do `DISPATCH_ASSUME_ABI_SINGLE_BEGIN` era o search path
   do clang (`-isystem $SW/usr/lib/swift` ANTES do SDK) resolvendo
   `<dispatch/base.h>` para o base.h LINUX (sem macros de bounds). NUNCA foi
   emulação x86 nem module-build hermético.
2. Pre-steps explícitos: SwiftShims / _SwiftConcurrencyShims / _AvailabilityInternal.
3. `os_object.pcm` explícito (renomeado do comando do os_workgroup), depois de
   _DarwinFoundation1 + ObjectiveC.
4. **CoreFoundation do modulemap do SDK** (o do toolchain é o swift-corelibs
   antigo, sem `kCFCalendarUnitDayOfYear`) + `-fmodule-map-file=ObjectiveC.modulemap`
   (o scan omite; sem ele, objc/NSObject.h textual → conflito de nullability).
   ObjectiveC ANTES do CoreFoundation. Verificar: `strings clang_CoreFoundation.pcm
   | grep -c objc/NSObject.h` == 0.
5. `-DCF_SWIFT_SENDABLE=` + VFS + cache isolado + TODOS os pcm injetados em todo build.
6. Frameworks fora do grafo do scan (Foundation, UIKit, Security...) via clone
   do comando do CoreGraphics + `-F $SDK/System/Library/SubFrameworks`.

## No iSH (paths obrigatórios para os pcm carregarem)

```sh
mkdir -p ${ISB_SYSROOT:-/opt/isb/sysroot}
ln -sfn /opt/ios-toolchain/iPhoneOS26.5.sdk ${ISB_SYSROOT:-/opt/isb/sysroot}/iPhoneOS26.5.sdk
ln -sfn /opt/swift6.3 ${ISB_SYSROOT:-/opt/isb/sysroot}/swift-6.3.2
# os mesmos symlinks de headers do toolchain (tamanho dos headers é validado!):
ln -sfn /opt/ios-toolchain/iPhoneOS26.5.sdk/usr/include/dispatch /opt/swift6.3/usr/lib/swift/dispatch
ln -sfn /opt/ios-toolchain/iPhoneOS26.5.sdk/usr/include/os /opt/swift6.3/usr/lib/swift/os
ln -sfn /opt/ios-toolchain/iPhoneOS26.5.sdk/System/Library/Frameworks/CoreFoundation.framework/Headers /opt/swift6.3/usr/lib/swift/CoreFoundation
mkdir -p /opt/swift6.3/usr/lib/swift/CoreFoundation/Modules   # (via symlink: .../Headers/Modules)
cp $SDK/System/Library/Frameworks/CoreFoundation.framework/Modules/module.modulemap \
   $SDK/System/Library/Frameworks/CoreFoundation.framework/Headers/Modules/module.modulemap
rm -rf /root/.cache/clang
```

## Compilar app Swift puro com Foundation (script pronto)

```sh
scripts/build-pure-foundation.sh <App> <main.swift>
# → Mach-O arm64 iOS 26.0 com Foundation+Dispatch, 186+ símbolos Swift
```

## Bloqueados (bug do swift.org 6.3.2, interface-compile mode)

swift:DataDetection, swift:CoreTransferable, swift:SwiftUICore, swift:UIKit —
tipos reexportados do clang Foundation (`Foundation.NSAttributedString` etc.)
não resolvem em contextos aninhados. Workarounds parciais (unqualify/swap de
ordem) resolveram Accessibility, Symbols, Foundation, Dispatch. Para UIKit
puro, usar o híbrido (ObjC UIKit + Swift Foundation) ou os clang pcms.
