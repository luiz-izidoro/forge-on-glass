# Dispatch/Foundation via Linux real — RECEITA FINAL (2026-08-18)

> Receita de bootstrap/reconstrução, não passo de cada build. Antes de usar,
> leia [`../BEST-PRACTICES.md`](../BEST-PRACTICES.md), valide o cache atual e
> não misture toolchain, SDK ou tripla.

Este documento registra o procedimento COMPLETO e verificado que destravou
`import Foundation` / `import Dispatch` em Swift puro para iOS, construindo os
módulos num Linux real (VM) e carregando-os no iSH.

## Resultado

73 artefatos em `foundation-build/`:
- 46 `clang_*.pcm` (módulos Clang: Dispatch, Foundation, CoreFoundation, UIKit,
  Security, CFNetwork, SystemConfiguration, CoreGraphics, CoreText, os_workgroup,
  os_object, os, XPC, MachO, simd, Spatial, ObjectiveC, Darwin, _DarwinFoundation1-3,
  _Builtin_*, CDispatch, ptrauth, ptrcheck, sys_types, _AvailabilityInternal, ...)
- 27 `swift_*.swiftmodule` (Swift: Swift, _Concurrency, _StringProcessing,
  SwiftOnoneSupport, Foundation, Dispatch, Combine, CoreFoundation, Darwin,
  ObjectiveC, Observation, System, _DarwinFoundation1-3, _Builtin_float,
  simd, Spatial, Symbols, Accessibility, os, ...)

**Bloqueados (bug do swift.org 6.3.2 em modo interface-compile):**
swift:DataDetection, swift:CoreTransferable, swift:SwiftUICore, swift:UIKit
(os módulos CLANG deles existem e funcionam; só o lado Swift dos interfaces
falha com "no type named X in module 'Foundation'" em contextos aninhados).

## Os 6 fixes que destravaram tudo (em ordem de importância)

1. **Symlinks dos headers do toolchain para o SDK** (o shadowing era a raiz do
   erro `DISPATCH_ASSUME_ABI_SINGLE_BEGIN` — NUNCA foi emulação x86!):
   ```bash
   SW=~/swift-ios-build/swift-6.3.2; SDK=~/swift-ios-build/iPhoneOS26.5.sdk
   mv $SW/usr/lib/swift/dispatch $SW/usr/lib/swift/dispatch.linux.bak
   ln -sfn $SDK/usr/include/dispatch $SW/usr/lib/swift/dispatch
   mv $SW/usr/lib/swift/os $SW/usr/lib/swift/os.linux.bak
   ln -sfn $SDK/usr/include/os $SW/usr/lib/swift/os
   mv $SW/usr/lib/swift/CoreFoundation $SW/usr/lib/swift/CoreFoundation.linux.bak
   ln -sfn $SDK/System/Library/Frameworks/CoreFoundation.framework/Headers $SW/usr/lib/swift/CoreFoundation
   cp $SW/usr/lib/swift/dispatch.linux.bak/module.modulemap $SW/usr/lib/swift/dispatch/module.modulemap
   ```
   O search path do clang era: `-isystem $SW/usr/lib/swift` (PRIMEIRO) →
   `-isystem $SW/usr/lib/swift/clang/include` → `-internal-externc-isystem $SDK/usr/include`
   (ÚLTIMO). Ou seja, `<dispatch/base.h>` resolvia para o base.h LINUX (sem os
   macros de bounds) → workloop.h:30 "unknown type name". Os symlinks igualam
   os dois mundos.

2. **Pre-steps explícitos**: SwiftShims.pcm, _SwiftConcurrencyShims.pcm e
   _AvailabilityInternal.pcm (via `-emit-pcm` do modulemap shims/DarwinFoundation1)
   com `-fno-implicit-modules` + injeção de todos os pcm existentes (nada de
   builds implícitos poluindo caches — o `_AvailabilityInternal` implícito no
   `~/.cache/clang` causava "defined in both").

3. **os_object.pcm explícito** (o módulo os_workgroup do scan é renomeado para
   os_object via `-module-name os_object` no mesmo comando). Necessário porque
   o `dispatch.h` (SDK) inclui `<os/object.h>` que mapeia para o módulo
   os_object — sem o pcm, "module 'os_object' is needed but has not been
   provided". Tem que ser construído DEPOIS de _DarwinFoundation1 + ObjectiveC.

4. **CoreFoundation do modulemap do SDK** (não o do toolchain Linux):
   - o comando do scan apontava para `$SW/usr/lib/swift/CoreFoundation/module.modulemap`
     (CF do swift-corelibs-foundation, SEM `kCFCalendarUnitDayOfYear` etc.)
   - swap para `$SDK/System/Library/Frameworks/CoreFoundation.framework/Modules/module.modulemap`
   - + `-Xcc -internal-iframework $SDK/System/Library/Frameworks`
   - + `-Xcc -fmodule-map-file=$SDK/usr/include/ObjectiveC.modulemap` (o scan
     OMITE — sem ele, objc/NSObject.h é incluído TEXTUALMENTE no CF → conflito
     de nullability "NSObject has different definitions in different modules"
     (Class vs Class _Nullable — os apinotes do módulo ObjectiveC)
   - **ordem**: ObjectiveC DEVE ser construído ANTES do CoreFoundation
   - verificação pós-build: `strings clang_CoreFoundation.pcm | grep -c objc/NSObject.h`
     deve ser 0 (senão rebuild — o pass 5 do orquestrador faz isso)

5. **Injeção universal de flags** em TODO build de módulo:
   `-Xcc -ivfsoverlay $VFS -Xcc -DCF_SWIFT_SENDABLE=` (fix do CFCGTypes.h —
   macro do módulo CF não vaza para o CoreGraphics) + `-fmodules-cache-path`
   isolado + TODOS os pcm existentes como `-Xcc -fmodule-file=NAME=<pcm>`.

6. **Frameworks fora do grafo do scan** (Foundation, Accessibility, UIKit,
   Security, CFNetwork, SystemConfiguration, CoreTransferable, Symbols,
   DataDetection, OSLog, QuartzCore, UniformTypeIdentifiers): build implícito
   clonando o comando do CoreGraphics (swap de modulemap/name, drop de
   `-fno-implicit-modules`) + `-F $SDK/System/Library/SubFrameworks`
   (UIUtilities.framework vive lá — UIKitDefines.h:10 precisa).

## Patches nos interfaces (bug do compilador swift.org em interface-compile mode)

O swift.org 6.3.2 falha ao resolver tipos reexportados do módulo clang
Foundation (`Foundation.NSAttributedString` etc.) dentro de membros aninhados
em interfaces. Workarounds aplicados nos SDK interfaces (VM):

- `Accessibility.swiftinterface`: 2 swaps de ordem (init attributedTitle antes
  do init title) + 4× `Foundation.NSNumber` → `NSNumber` + 15 unqualify
  (`Foundation.NS*` → `NS*`) — resolveu (swift_Accessibility OK).
- `DataDetection.swiftinterface`: 1 swap de membros (Decimal first) + 1 unqualify
  — AINDA FALHA ("cannot find type 'Decimal' in scope" — Decimal é clang-side).
- `CoreTransferable.swiftinterface`: 1 unqualify (`Foundation.Progress` → `Progress`)
  — AINDA FALHA (mesmo motivo).
- `UIKit.swiftinterface`: 42 unqualify — depende de DataDetection/CoreTransferable.
- `Foundation.h` (umbrella): bloco de re-importação alfabética de 124 headers
  existentes logo após o `#include <CoreFoundation/CoreFoundation.h>` (os
  headers usam tipos de headers incluídos DEPOIS na ordem original — NSBundle.h
  usa NSAttributedString antes de NSAttributedString.h; o SDK reduzido tem só
  131 de ~200 headers, e os imports originais de headers ausentes são de
  plataformas macOS-only). Patch em `Foundation.h.bak` → patched.

## Orquestrador

`orchestrator_vm.py` (na VM, ~15 min para o build completo):
- pre-steps → pass 1 (scan stack topológico, CF com special-case) → pass 2
  (os_object) → pass 3 (frameworks) → pass 4 (retry) → pass 5 (verifica CF
  limpo; se sujo, rebuild completo determinístico — ObjectiveC antes de CF).

## Como usar no iSH

Copiar `foundation-build/` para `/opt/ios-toolchain/foundation-build/` no iSH.
Compilar app Swift puro:

```
swift-frontend -c -target arm64-apple-ios26.0 -sdk $SDK -resource-dir $SW/usr/lib/swift \
  -I /opt/ios-toolchain/foundation-build \
  -swift-module-file=Swift=.../swift_Swift.swiftmodule \
  -swift-module-file=Foundation=.../swift_Foundation.swiftmodule \
  ... (todos os -swift-module-file) \
  -Xcc -fmodule-file=SwiftShims=... -Xcc -fmodule-file=_SwiftConcurrencyShims=... \
  -Xcc -fmodule-file=Foundation=.../clang_Foundation.pcm (e os demais) \
  -Xcc -ivfsoverlay /opt/ios-toolchain/vfs/overlay.yaml \
  main.swift -o main.o
```
Ver teste validado: `t_reexport.py` (import Foundation + Foundation.NSString
typecheck rc=0). Linkar com clang + lld + UIKit/Foundation frameworks.
