# Solving Dispatch/Foundation via a real Linux — SOLVED (2026-08-18)

> **Uso atual:** esta é a receita de bootstrap/reconstrução do cache, não um
> passo normal de cada projeto. Consulte [`BEST-PRACTICES.md`](BEST-PRACTICES.md)
> para compatibilidade de versões e isolamento de módulos. “Resolvido” aqui
> significa validado para o cache/combinação medidos, não para qualquer SDK ou
> toolchain futuro.

**STATUS: RESOLVED for the active profile.** `import Foundation` + `import
Dispatch` (e Combine, CoreFoundation, ObjectiveC, Darwin, System, Observation,
os, simd, Spatial, Symbols, Accessibility...) compile and link in pure Swift on
iSH using the neutral Swift 6.3.3 profile. The original VM bootstrap used Swift
6.3.2; that is historical evidence only.

## O que foi feito

1. **VM Linux histórica** (Ubuntu 26.04, x86_64 — arquitetura do host não
   importa; o output é arm64-apple-ios) com Swift 6.3.2 + o MESMO SDK 26.5 do
iSH (upload de 328MB) + o orquestrador `orchestrator_vm.py`. O cache ativo foi
posteriormente reconstruído/promovido com Swift 6.3.3.
2. **Cache ativo 6.3.3** — o caminho Foundation/Dispatch foi revalidado
   localmente e produz S2 estrutural; a execução em device deste caminho
   específico ainda está pendente.
3. **73 artefatos históricos** em `/opt/ios-toolchain/foundation-build/` foram
   substituídos como rota principal por `foundation-build633`.

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
# → Mach-O arm64 iOS 26.0 com Foundation+Dispatch (S2 estrutural local)
```

## Estado atual

O caminho acima usa o perfil neutro Swift 6.3.3 e foi revalidado no iSH.
A execução no device/LiveContainer deste caminho específico ainda não foi
confirmada nesta rodada; não confundir S2 estrutural com S3/S4.

## Bloqueios históricos do desbloqueio Swift

DataDetection, CoreTransferable, SwiftUICore e UIKit foram bloqueios do
primeiro ciclo de geração de interfaces. O perfil ativo 6.3.3 contém os
módulos necessários para os builds pure-Swift validados; eventuais falhas em
APIs individuais continuam cobertas por `PureSwiftKit` ou devem ser reduzidas
com `probe_api.py`.