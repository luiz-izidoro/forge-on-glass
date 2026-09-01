# Planos para destravar UIKit/SwiftUI puro em Swift (no iSH)

> **Registro histórico de alternativas.** A política vigente está em
> [`../BEST-PRACTICES.md`](../BEST-PRACTICES.md). Não trate um plano ou
> workaround antigo como caminho de produção sem nova aceitação.

Estado: 2026-08-19. O muro: `import UIKit` / `import SwiftUI` em Swift puro.
Sintoma: swift.org 6.3.2/6.3.3 falha ao compilar os `.swiftinterface` do SDK
("no type named X in module Y" em contextos aninhados). Causa raiz bissectada:
8 mecanismos documentados em `ESTADO-E-NEXT-STEPS.md` §2.

## Plano A — Patches nos interfaces (workaround, EM USO — está funcionando)

Técnica validada: stubs locais, nomes clang diretos (NSProgress, NSTimeInterval,
NSDecimalNumber), reescrita de corpos com campos reais, remoção de
defaults/conformances, `-import-module CoreFoundation`. Destravou TODOS os
módulos, incluindo **SwiftUICore (4MB)**.
- Prós: funciona com o toolchain disponível; contras: degrada levemente a API
  (stubs, conformances removidas, corpos @inlinable ausentes — o runtime do
  device tem a implementação).
- Status: SwiftUICore ✅; UIKit no último passo (crash do compilador — §3 do
  ESTADO-E-NEXT-STEPS).

## Plano B — Upgrade toolchain (feito: 6.3.3)

O 6.3.3 (release de manutenção do branch 6.3, que recebeu o fix do _GUID
#86327) foi adotado. NÃO corrige o bug dos tipos reexportados, mas é a versão
mais nova. Custo: rebuild completo (feito — foundation-build633).

## Plano C — Módulos binários do Mac (descartado)

Os .swiftmodule binários do Xcode têm tag Apple — não carregam no swift.org
(version-lock).

## Plano D — import UIKit via módulo clang (fallback validado parcialmente)

`import UIKit` em Swift puro resolvendo para o **clang UIKit.pcm** (sem o
swiftinterface): UIViewController/UIView/UIColor/UIView(frame:) funcionam em
typecheck; quebra com `import Foundation` no mesmo arquivo (bridge
String/NSString ausente). Se o Plano A não fechar o UIKit, este é o fallback
(API "crua" ObjC, sem refinamentos Swift).

## Plano E — Snapshot do main/6.4 (se necessário)

Se o crash do SILGen do UIKit não for contornável no 6.3.3, testar um snapshot
DEVELOPMENT do 6.4 na VM (mesmo custo: rebuild total + toolchain novo no iSH).

## Plano F — Fork do compilador (descartado)

Buildar um swift compiler patched: inviável (VM x86_64 não produz binário
aarch64 para o iSH).

## Plano G — Interface minimal gerado do clang module

Gerar um swiftmodule "UIKit" a partir do clang UIKit (equivalente ao Plano D
com artefato estável). Se o Plano D funcionar bem, este é o refinamento.

## Recomendação de execução

1. Terminar o bissect do crash do UIKit (ESTADO-E-NEXT-STEPS.md §3) — se
   fechar, copiar foundation-build633 para o iSH e validar `import UIKit`/
   `import SwiftUI`.
2. Se o crash for intratável: Plano D (fallback) + documentar.
3. Migrar o iSH para 6.3.3 (toolchain + stdlib + módulos) — o 6.3.2 fica como
   backup.
