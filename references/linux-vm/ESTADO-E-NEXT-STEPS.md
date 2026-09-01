# ESTADO E NEXT STEPS — Missão UIKit/SwiftUI puro (handoff para nova sessão)

> **Documento histórico.** A política vigente está em
> [`../BEST-PRACTICES.md`](../BEST-PRACTICES.md). O ponto de retomada é
> `references/HANDOFF.md`; confirme o estado atual antes de repetir qualquer
> receita ou experimento.

> ⚠️ **DOCUMENTO HISTÓRICO (2026-08-19).** A missão descrita aqui foi
> **CONCLUÍDA**: `import UIKit` e `import SwiftUI` em Swift puro funcionam e
> rodam no device. O ponto de retomada atual é
> [`references/HANDOFF.md`](../HANDOFF.md), não este arquivo.
>
> 🗑️ **Scripts removidos em 2026-08-23.** Os `patch_*.py`, `try_*.py`,
> `test_import_uikit.py` e `probe_bridge_all.py` citados adiante eram
> ferramentas **one-off** de edição dos `.swiftinterface`. Foram substituídos
> pelo patch-set versionado em `/var/minis/shared/darwin-sdk/patchset/`
> (8 diffs, validados byte a byte), aplicável com
> `scripts/apply-patchset.sh`. Não tente executá-los; leia as menções apenas
> como registro histórico do diagnóstico.

> **Data**: 2026-08-19. Todos os caminhos são relativos ao usuário `configured-user` na
> VM `$ISB_REMOTE_HOST` (acesso via ssh) e ao iSH.

---

## 1. RESUMO DO ESTADO (o que já está resolvido)

### ✅ Resolvido (2026-08-18): Dispatch/Foundation em Swift puro
- Causa raiz do `DISPATCH_ASSUME_ABI_SINGLE_BEGIN`: shadowing de headers Linux
  do toolchain (`-isystem $SW/usr/lib/swift` antes do SDK). Fix: symlinks
  `$SW/usr/lib/swift/{dispatch,os,CoreFoundation}` → headers do SDK (VM e iSH).
- 73 módulos construídos na VM com **swift.org 6.3.2** → copiados para
  `/opt/ios-toolchain/foundation-build/` no iSH → `import Foundation` +
  `import Dispatch` compilam/linkam no iSH (validado, 186 símbolos Swift).
- Receita completa: `references/DISPATCH-VIA-LINUX.md` (SOLVED) +
  `references/linux-vm/RECEITA-DISPATCH-LINUX.md`.

### ✅ Resolvido (2026-08-19): SwiftUICore compilado — via Swift 6.3.3 + patches
- **Swift 6.3.3 EXISTE** (download.swift.org, ubuntu2404 + aarch64) e foi adotado
  como toolchain definitivo (o 6.3.3 NÃO corrige o bug dos tipos reexportados,
  mas é a versão mais nova do branch 6.3).
- Na VM: `~/swift-ios-build/swift-6.3.3/` (x86_64) + `orchestrator_vm633.py`
  (orquestrador adaptado: sdk_mmaps, cf_extra, pre-pass3 ptrauth+CDispatch,
  full_rebuild com special-cases, UIUtilities em SubFrameworks).
- **`foundation-build633/` (152 artefatos: 91 clang pcm + 61 swift modules)**:
  TODA a cadeia compilada com 6.3.3, incluindo:
  - swift: Foundation, Dispatch, Combine, CoreFoundation, Darwin, ObjectiveC,
    Observation, System, os, simd, Spatial, Symbols, Accessibility, CoreText,
    DataDetection, CoreTransferable, OSLog, UniformTypeIdentifiers, QuartzCore,
    DeveloperToolsSupport, SwiftOnoneSupport, _Concurrency, _StringProcessing,
    _DarwinFoundation1-3, _Builtin_float, **SwiftUICore (4.092.912 bytes)**.
  - clang: UIKit (22.8MB), Security, CFNetwork, SystemConfiguration, UIUtilities,
    CoreGraphics, CoreText, Foundation, Dispatch, os, os_object, os_workgroup,
    XPC, MachO, simd, Spatial, ObjectiveC, Darwin, _DarwinFoundation1-3,
    _Builtin_*, CDispatch, ptrauth, ptrcheck, sys_types, _AvailabilityInternal.

### ✅ RESOLVIDO (2026-08-19, sessão 2): UIKit compilado — `import UIKit` FUNCIONA
> **ESTE DOCUMENTO FOI SUPERADO PELO `PLANO-2026-08-19.md` (leia-o primeiro).**
> O §3 abaixo (bissect do crash) está CONCLUÍDO — mantido só como histórico.

O "crash do compilador" eram **dois problemas distintos**, ambos mal diagnosticados:
1. **Falso crash**: `note: IO failure on output stream: Disk quota exceeded` — o
   `/tmp` da VM é tmpfs de 1,9 GB e o `-fmodules-cache-path=/tmp/impmc` o encheu.
   Fix: cache em disco real (`~/bigtmp/impmc`).
2. **Crash real (Signal 11 em `emitNativeToForeignThunk`)**: métodos `@objc` em
   **subclasses GENÉRICAS de NSObject** — apenas 3 classes no interface inteiro
   (`UICollectionViewDiffableDataSource`, `UITableViewDiffableDataSource`,
   `UIIndirectScribbleInteraction`). O compilador REJEITA esse padrão quando
   escrito à mão, mas segfalta ao vê-lo vindo do SDK Apple.
   Fix: `patch_uikit_generic_objc.py` (remove `@objc` de 25 membros).
3. O teste com `-Onone` nunca havia rodado: falhava antes com
   `no such module 'SwiftOnoneSupport'` (faltava o `-swift-module-file`).

Resultado: `[swift:UIKit] OK 1032412B 5s`; `import UIKit`+`import Foundation`
→ objeto de 13.576 B; `import SwiftUICore` → 4.136 B. Falta apenas o módulo
`SwiftUI` top-level, o transporte para o iSH e a validação do IPA.

**NOTA OPERACIONAL CRÍTICA**: jobs na VM morrem quando o SSH cai — `nohup` e
`setsid` NÃO bastam. Usar **tmux**:
`tmux new-session -d -s nome "cmd > /tmp/nome.log 2>&1; sleep 7200"`.

---

## 2. OS 8 MECANISMOS DO BUG (bissectados com probes — conhecimento essencial)

O bug central do swift.org (6.3.2 E 6.3.3) no modo `-compile-module-from-interface`
com `-enable-library-evolution`/`-O`/MemberImportVisibility:

1. **Tipos REEXPORTADOS do clang** (`Foundation.NSNumber`, `Foundation.Decimal`,
   `Foundation.Progress`, `Foundation.TimeInterval`, `Foundation.Notification.Name`)
   não resolvem em contextos aninhados (membros de tipos aninhados, parâmetros de
   funcs em extensions) — nem `Foundation.X` ("no type named") nem `X` unqualified
   ("cannot find in scope"). **Fix**: nome clang direto (`NSDecimalNumber`,
   `NSProgress`, `NSTimeInterval`, `NSNumber`) OU stub local no módulo consumidor.
2. **Members de extensões de OUTROS módulos** (`CGRect(x:y:width:height:)`,
   `.zero`, `.identity`, `x`/`y`/`width`/`height`, `maxX`, `isNull`, `offsetBy`,
   `intersection`) não resolvem em CORPOS `@inlinable`/`@_alwaysEmitIntoClient`.
   **Fix**: reescrever com campos reais (`origin.x`, `size.width`) e construção
   `var r = CGRect(); r.origin.x = ...; return r` (o `CGRect()` e os campos são do
   clang e funcionam).
3. **`.init()` em extension com `where Self == X`** → "requires Self constraint"
   ou "takes no arguments". **Fix**: `X()` explícito; se o init do struct não
   resolver (struct de outro módulo), trocar o getter por `{ get }` sem corpo.
4. **Refs totalmente qualificadas ao PRÓPRIO módulo** em `case` de enum aninhado
   (`DataDetection.DataDetector.Match...`) → "no type named 'DataDetector' in
   module 'DataDetection'". **Fix**: remover o prefixo do módulo (e nos cases
   usar o nome curto do tipo).
5. **Defaults com members de tipos clang** (`= .zero`, `= CGRect(x:...)`,
   `= .identity`) → o member não resolve no default. **Fix**: remover o default.
   (Defaults com enums do PRÓPRIO módulo, ex `.continuous`, funcionam — não remover!)
6. **`@_originallyDefinedIn` sem `@available` no membro** → erro ao mover blocos.
   **Fix**: adicionar `@available` ou remover o atributo.
7. **Tipos AUSENTES do SDK** (o SDK 26.5 do bundle é INCONSISTENTE: Foundation sem
   `AttributedString.LineHeight`/`AdaptiveImageGlyph`/`CoreTextAttributes` — eles
   vivem no CoreText como extensions; `URLThumbnailDictionaryItem`,
   `UIMenuSystem.Configuration` faltam no UIKit). **Fix**: stubs locais no módulo
   consumidor (`extension AttributedString { struct LineHeight {...} }` etc.).
   CUIDADO com **ambiguidade**: stub local + tipo clang renamed com o mesmo nome
   (ex: `NSAdaptiveImageGlyph` → `AdaptiveImageGlyph` colide com o stub) → usar o
   nome clang (`NSAdaptiveImageGlyph`) nas referências ou remover o membro.
8. **`-import-module CoreFoundation`** (só, sem os outros) resolve
   `CoreFoundation.CGPoint` em scope (Accessibility/CoreText). UIUtilities idem
   para `UIUtilities.UIAxis`.

---

## 3. O QUE FALTA — passo a passo

### 3.1 Bissectar o crash do UIKit (VM) — ~1-2h
Sintoma: `swift-frontend 6.3.3` CRASHA (segfault, "Please submit a bug report")
ao compilar `UIKit.swiftmodule/arm64e-apple-ios.swiftinterface` (patchado), após
~10 min de compilação. Stack: `swift::Lowering::SILGenFunction::emitNativeToForeignThunk`
→ `emitCBridgedToNativeValue` (SILGenBridging.cpp). Ou seja: **um método @objc
com um tipo patchado não-bridgeable** (provável stub struct em assinatura @objc,
ou typealias String onde o bridge espera outra coisa).

Passos:
1. Na VM: `cd ~/swift-ios-build` — ver o último log `build633cp.log` (tinha
   `-Onone` adicionado ao build de swift modules; o usuário cancelou durante o
   teste — VERIFICAR se com `-Onone` o crash some; o crash era no SILGen que roda
   mesmo sem -O, mas testar).
2. Se `-Onone` não resolver: o crash é num thunk de bridging. Candidatos:
   - `UIMenuSystem.Configuration` (struct stub) em `setBuildConfiguration(_:)`
     (linha ~3302) — remover o método ou trocar o tipo por `Any`.
   - `URLThumbnailDictionaryItem` (struct stub) em `thumbnailDictionary`
     (linha ~1999) — é propriedade (não @objc direto), provavelmente ok.
   - `Notification.Name`/`NSAttributedString.Key` (typealias String) em métodos
     @objc — String bridgea ok, provavelmente ok.
   - Métodos `objectiveCValue`/`value(for:)` dos enums de atributos (removidos
     4 do AdaptiveImageGlyphAttribute — verificar se há OUTROS enums com esses
     métodos e tipos stubs — procurar no interface: `grep -n "objectiveCValue\|value(for:"`).
   - Qualquer membro com `NSAdaptiveImageGlyph` restante.
   Bissect rápido: remover blocos suspeitos e recompilar (cada ciclo ~10 min;
   o compile do UIKit demora ~8-10 min).
3. Quando compilar: `swift_UIKit.swiftmodule` (~10-20MB) será criado em
   `foundation-build633/`.

### 3.2 Copiar para o iSH — ~10 min
1. Na VM: `tar cf /tmp/fb633.tar foundation-build633` (~160MB).
2. No iSH: `scp $ISB_REMOTE_USER@$ISB_REMOTE_HOST:/tmp/fb633.tar /tmp/ && tar xf /tmp/fb633.tar -C /tmp && rm -rf /opt/ios-toolchain/foundation-build633 && mv /tmp/foundation-build633 /opt/ios-toolchain/foundation-build633`.
3. Instalar o toolchain 6.3.3 no iSH (JÁ FEITO — verificar):
   - `/opt/swift6.3.3` extraído, patchelf'd (glibc loader), `--version` OK.
   - Symlinks: `${ISB_SYSROOT:-/opt/isb/sysroot}/{iPhoneOS26.5.sdk,swift-6.3.2}` →
     paths reais (para o 6.3.3, criar também `swift-6.3.3` → `/opt/swift6.3.3`).
   - Symlinks de headers: `/opt/swift6.3.3/usr/lib/swift/{dispatch,os,CoreFoundation}`
     → SDK (JÁ FEITO — verificar).
   - `$SDK/.../CoreFoundation.framework/Headers/Modules/module.modulemap` (JÁ FEITO).
   - `rm -rf /root/.cache/clang`.

### 3.3 Validar no iSH — ~30 min
1. Atualizar `scripts/build-pure-foundation.sh` para usar o 6.3.3 e o
   foundation-build633 (ou criar `build-pure-uikit.sh`).
2. Testes:
   - `import UIKit; let v = UIView()` (compilar+linkar, Mach-O arm64).
   - `import SwiftUI; let t = Text("oi")` (via SwiftUICore).
   - `import SwiftUICore` direto.
3. Ajustar o script de link: adicionar `-lswiftSwiftUICore`/`-lswiftUIKit`
   (os .tbd existem em $SDK/usr/lib/swift/), `-framework UIKit -framework SwiftUI`.

### 3.4 Documentação pós-validação
- Atualizar README/SKILL/LIMITATIONS: UIKit/SwiftUI ✅ (ou parcial — ver o que
  compila de fato; os stubs degradam algumas APIs — documentar as limitações
  dos stubs: `Notification.Name` é String, `UIMenuSystem.Configuration` é vazio,
  conformances `*Message` removidas, corpos `@inlinable` ausentes (o runtime do
  device tem a implementação), defaults removidos em algumas APIs).
- Atualizar os planos em `references/linux-vm/PLANOS-UIKIT-SWIFT.md`.

---

## 4. PATCHES APLICADOS NOS INTERFACES (SDK da VM — para reproduzir)

Os interfaces do SDK na VM foram patchados IN PLACE. O SDK ORIGINAL (sem
patches) está no iSH em `/opt/ios-toolchain/iPhoneOS26.5.sdk/`. Para reproduzir
o build num ambiente limpo, aplicar os seguintes patches (scripts em
`references/linux-vm/patch_*.py` + os comandos abaixo):

### Foundation.h (umbrella) — já patchado desde 2026-08-18
Bloco de re-importação alfabética de 124 headers existentes logo após
`#include <CoreFoundation/CoreFoundation.h>` + `#import <Foundation/NSError.h>`.
(O SDK reduzido tem só 131 de ~200 headers; a ordem original quebra: NSBundle.h
usa NSAttributedString antes de NSAttributedString.h.)

### Accessibility.swiftinterface (compila SEM patches no 6.3.3? — testar!)
No 6.3.2 precisou de: swaps de ordem (init attributedTitle antes de title),
unqualify de `Foundation.NS*` → `NS*`. No 6.3.3 com `-import-module CoreFoundation`
compilou com os patches. Testar se o ORIGINAL compila direto no 6.3.3.

### DataDetection.swiftinterface
- `DataDetection.DataDetector.` → `DataDetector.` (33 refs; depois nos cases:
  `DataDetector.Match.SemanticDetails.X` → `X` — 10 cases).
- `public let amount: Decimal` → `public let amount: NSDecimalNumber`.

### CoreTransferable.swiftinterface
- `Progress` → `NSProgress` (1×).
- `CoreTransferable.` → "" (120 refs).

### SwiftUICore.swiftinterface (muitos patches — o interface PRÉ-strip está em
`/tmp/SwiftUICore.before-bodies.swiftinterface` na VM)
- `SwiftUICore.` → "" (6788 refs).
- `Foundation.` → "" (1207 refs) + corrigir `Core`+`CG*` → `CoreGraphics.CG*`
  (o replace quebra `CoreFoundation.CGPoint` → `CoreCGPoint`) + CG* restantes →
  `CoreGraphics.CG*`.
- Remover `@_exported import SwiftUICore` (self-import).
- `TimeInterval` → `NSTimeInterval` (46×).
- Stubs locais: `extension AttributedString { struct LineHeight {...} }` +
  `struct AdaptiveImageGlyph {...}` (OBS: no 6.3.2 o AdaptiveImageGlyph vinha do
  CoreText com import — no 6.3.3 o stub é necessário e o import CoreText foi
  REMOVIDO para evitar ambiguidade); `extension AttributeScopes {
  struct CoreTextAttributes { enum TextAlignmentAttribute : AttributedStringKey
  {...}; enum LineHeightAttribute : AttributedStringKey {...} } }`.
- Bloco ImagePaint: mover `extension ShapeStyle where Self == ImagePaint` para
  DEPOIS do struct ImagePaint; remover defaults `= CGRect(x:...)` e `= 1`;
  `.init(image:...)` → `ImagePaint(image:...)`; adicionar `@available(iOS 13.0,
  macOS 10.15, tvOS 13.0, watchOS 6.0, *)` (por causa do Image).
- Corpos da extensão CGRect reescritos com campos reais (center, isFinite,
  flushNullToZero, offset(by:), scaledBy, hasIntersection, maxXY, minXY,
  init(size:), init(center:size:), init(position:size:anchor:), subscript(axis:),
  subscript(edge:), finalizeLayoutDirection, roundCoordinatesToNearestOrUp).
- `CGBlendMode.xor.rawValue` → `25` (o enum clang não resolve).
- Defaults `.zero`/`.continuous` removidos e RESTAURADOS os `.continuous`
  (16 — enums do próprio módulo funcionam em defaults).
- CUIDADO: replaces em massa de `x`/`y`/`width`/`height` → `origin.x` etc. só em
  corpos da extensão CGRect (nunca em labels de chamadas nem em extensões CGPoint).

### UIKit.swiftinterface (~30 patches — os principais)
- `UIKit.` → "" (763 refs).
- `Foundation.` → "" + corrigir `Core`+`CG*` → `CoreGraphics.CG*` + CG* →
  `CoreGraphics.CG*`.
- Remover `import UIMainMenuSystem`/`import UIMenuSystem` (frameworks ausentes);
  `extension UIMainMenuSystem` → `extension UIMenuSystem`; `UIMainMenuSystem.Configuration`
  → `UIMenuSystem.Configuration`.
- Remover `import CoreText` (causa ambiguidade com stubs do SwiftUICore).
- `TimeInterval` → `NSTimeInterval` (14×).
- `Notification.Name` → stub `extension Foundation.Notification { typealias Name =
  Swift.String }` (72 usos) + REMOVER conformances `: NotificationCenter.MainActorMessage`
  (71) e `: NotificationCenter.AsyncMessage`/`BaseMessage` (o protocolo usa o Name
  do Foundation — conflita com o stub).
- `NSAttributedString.Key` → stub `extension NSAttributedString { typealias Key =
  Swift.String }` (2 usos).
- `URLThumbnailDictionaryItem` → stub struct (1 uso).
- `UIMenuSystem.Configuration` → stub struct (2 usos).
- AdaptiveImageGlyphAttribute: remover conformidades (CodableAttributedStringKey/
  ObjectiveCConvertibleAttributedStringKey), `Value = NSAdaptiveImageGlyph`,
  remover os 4 métodos objectiveCValue/value/encode/decode (candidatos do crash).
- Blocos `extension NotificationCenter.MessageIdentifier where Self ==
  NotificationCenter.BaseMessageIdentifier<X>` (72): `.init()` → `X()` explícito
  e depois getters → `{ get }` sem corpo (78).
- Remover as 2 extensões do AdaptiveImageGlyph/NSAdaptiveImageGlyph (inits de
  conveniência — ambiguidade/erro de membro).

### Foundation.swiftmodule (clang side) e demais — sem patches de interface.

---

## 5. ARQUIVOS E PATHS (não apagar!)

### VM ($ISB_REMOTE_USER@$ISB_REMOTE_HOST, ~/swift-ios-build/)
- `swift-6.3.3/` — toolchain x86_64 (com symlinks dispatch/os/CoreFoundation →
  SDK; `dispatch.linux.bak`, `os.linux.bak`, `CoreFoundation.linux.bak` — os
  originais Linux; `dispatch/module.modulemap` = cópia do Linux para o CDispatch).
- `swift-6.3.2/` — toolchain antigo (não apagar — o foundation-build 6.3.2 no
  iSH depende dos paths; na VM pode apagar para liberar 3.3GB se precisar).
- `iPhoneOS26.5.sdk/` — SDK 26.5 (com interfaces PATCHADOS — é a cópia de
  trabalho; o ORIGINAL está no iSH).
- `foundation-build633/` — **152 artefatos 6.3.3 (NÃO APAGAR)**.
- `foundation-build/` — artefatos 6.3.2 (backup — pode apagar se precisar de
  espaço; o iSH tem a cópia).
- `orchestrator_vm633.py` — orquestrador 6.3.3 (com todos os fixes).
- `orchestrator_vm.py` — orquestrador 6.3.2 (manter como referência).
- `vfs/overlay.yaml` + `os.modulemap` patchado — VFS do os_workgroup.
- `seed.swift`, `scan633.sh`, `run_build.sh`, `run_build2.sh` — scripts auxiliares.
- `SwiftUICore.orig.swiftinterface` — original do SwiftUICore (do iSH).
- `/tmp/fscan.json` — grafo do scan 6.3.3 (USADO pelo orquestrador — não apagar
  enquanto o build não terminar).
- `/tmp/impmc` — cache de módulos implícitos (pode apagar — é regenerado).
- Logs `build*.log` — podem apagar (o build633* recente é o útil).
- `/tmp/mcs` — cache do scan (apagável).

### iSH
- `/opt/swift6.3` (6.3.2 patchelf'd) — NÃO apagar (build híbrido atual usa).
- `/opt/swift6.3.3` (6.3.3 patchelf'd + symlinks de headers) — NÃO apagar.
- `/opt/ios-toolchain/iPhoneOS26.5.sdk` — SDK ORIGINAL (sem patches) — NÃO apagar.
- `/opt/ios-toolchain/foundation-build/` — módulos 6.3.2 — NÃO apagar.
- `/opt/ios-toolchain/exp63/` — stdlib 6.3.2 — NÃO apagar.
- `/opt/ios-toolchain/vfs/` — VFS overlay — NÃO apagar.
- `${ISB_SYSROOT:-/opt/isb/sysroot}/{iPhoneOS26.5.sdk,swift-6.3.2}` — symlinks
  (exigidos pelos pcm 6.3.2) — NÃO apagar.
- `/var/minis/skills/ios-swift-builder/` — a skill (docs + scripts).
- `/var/minis/workspace/demo-foundation.*` — demo validado (manter).

---

## 6. LIMPEZA REALIZADA (2026-08-19)

### iSH
- `/tmp/swift633-aarch64.tar.gz` (591MB) — apagado (já extraído em /opt/swift6.3.3).
- `/tmp/fb.tar` (130MB) — apagado (já extraído em /opt/ios-toolchain/foundation-build).
- `/tmp/swift-6.3.3-RELEASE-ubuntu24.04-aarch64/` — movido para /opt/swift6.3.3.
- Testes temporários em /tmp (test_foundation.*, tuikit*, probes) — apagados.
- Logs de testes (/tmp/*.log, /tmp/*.txt) — apagados.
- `~/.cache/clang` — limpo (regenerado automaticamente).

### VM
- `swift633.tar.gz` (1021MB) — apagado (já extraído).
- `sdk.tar` (329MB) — apagado (já extraído).
- `fb.tar` — apagado.
- Logs antigos `build*.log` (build.log, build2.log ... build633b.log) — apagados
  (mantido apenas o mais recente).
- `/tmp/mcs`, `/tmp/impmc`, `~/.cache/clang` — limpos (regenerados).
- `/tmp/P_*.swiftinterface`, `/tmp/V_*.swiftinterface`, `/tmp/t_*.py`,
  `/tmp/planoD*.txt`, `/tmp/probe*.txt` etc. — apagados.
- Testes `/tmp/tu*.swift`, `/tmp/t633_*.swift` — apagados.

---

## 7. COMANDOS ÚTEIS PARA RETOMAR

```bash
# VM
ssh $ISB_REMOTE_USER@$ISB_REMOTE_HOST
cd ~/swift-ios-build
# rebuild do UIKit (incremental — pula o que existe):
rm -f foundation-build633/swift_UIKit.swiftmodule
nohup python3 orchestrator_vm633.py > build633_next.log 2>&1 &
tail -f build633_next.log
# ver erro do UIKit:
head -20 foundation-build633/swift_UIKit.err

# iSH (depois do build)
scp $ISB_REMOTE_USER@$ISB_REMOTE_HOST:/tmp/fb633.tar /tmp/ && tar xf /tmp/fb633.tar -C /tmp \
  && rm -rf /opt/ios-toolchain/foundation-build633 \
  && mv /tmp/foundation-build633 /opt/ios-toolchain/foundation-build633
# symlink do 6.3.3 (para os pcm referenciarem):
ln -sfn /opt/swift6.3.3 ${ISB_SYSROOT:-/opt/isb/sysroot}/swift-6.3.3
# compilar app de teste:
# (usar a mesma estrutura do build-pure-foundation.sh com SW=/opt/swift6.3.3
#  e OUT=/opt/ios-toolchain/foundation-build633)
```

## 8. DECISÕES PENDENTES / RISCOS
- O crash do SILGen pode exigir remover MAIS métodos @objc com stubs (o UIKit
  tem centenas de métodos @objc; os stubs de struct (Configuration,
  URLThumbnailDictionaryItem) em assinaturas @objc são os suspeitos).
- Os stubs degradam a API (Notification.Name=String, conformances removidas,
  corpos @inlinable ausentes). Documentar como limitações conhecidas.
- SwiftUI (o framework de alto nível) NÃO é um módulo separado do SDK — o
  SwiftUI.swiftmodule do SDK é um re-export do SwiftUICore (verificar: o SDK tem
  SwiftUI.framework com interface que importa SwiftUICore? — se sim, compilar o
  SwiftUI.swiftmodule também; se não, `import SwiftUI` resolve via SwiftUICore
  com -module-abi-name SwiftUI).
- O iSH precisa dos módulos 6.3.3 (os .swiftmodule 6.3.2 NÃO carregam no 6.3.3 e
  vice-versa — version-lock). Decidir: migrar TUDO para 6.3.3 (toolchain +
  stdlib + foundation-build) ou manter os dois (6.3.2 para híbrido, 6.3.3 para
  pure-Swift UIKit/SwiftUI). Recomendação: migrar para 6.3.3 (o 6.3.2 fica como
  backup).
