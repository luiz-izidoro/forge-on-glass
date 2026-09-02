# Swift puro com UIKit/SwiftUI — o que funciona e o que degrada

> **Guia técnico subordinado à política:** consulte [`BEST-PRACTICES.md`](BEST-PRACTICES.md) para o fluxo atual. Os números abaixo são medições históricas e devem ser reexecutados quando SDK, toolchain ou cache mudar.

> Medido em 2026-08-19 (iSH + VM, swift.org 6.3.3, SDK iOS 26.5,
> `foundation-build633`). **Estes números vêm de compilações reais**, não de
> estimativa.

## ⚠️ Regra nº 0 — a ORDEM DOS IMPORTS

Esta é a regra mais importante desta página. A ordem canônica, medida:

```swift
import Foundation   // SEMPRE primeiro
import SwiftUI      // se usar SwiftUI
import UIKit
import CoreText     // necessário para NSAttributedString.Key resolver
import Dispatch     // SEMPRE depois de UIKit
```

O que quebra com a ordem errada:

| Ordem | Sintoma |
|---|---|
| `UIKit` antes de `Foundation` | `cannot assign value of type 'String' to type 'NSString'` |
| `Dispatch` antes de `UIKit` | `type 'DispatchQueue' has no member 'global'/'main'` |
| sem `CoreText` | `type 'NSAttributedString' has no member 'Key'` |

## Status

| Import | Compila? | Objeto gerado |
|---|---|---|
| `import SwiftUI` | ✅ | 18.288 B (iSH) |
| `import SwiftUICore` | ✅ | 4.136 B |
| `import UIKit` + `import Foundation` | ✅ | 22.080 B |
| `import Foundation` / `Dispatch` / etc. | ✅ | — |

**Superfície de API medida (reexecutado em 2026-09-01):** o catálogo contém
101 probes e mediu **86/101 compilam** com o perfil neutro 6.3.3. As 15 falhas
restantes são principalmente conveniências Swift ausentes ou APIs C marcadas
`unavailable` pelo SDK patchado; o `PureSwiftKit` fornece os wrappers testados
para esses casos. A compilação dos helpers é coberta por
`scripts/verify-pureswiftkit.sh`. Rode `probe_api.py` novamente após alterar o
SDK, o toolchain ou os módulos.

As falhas do probe usam imports mínimos de propósito para documentar a ordem
canônica e os workarounds; não representam necessariamente uma falha do
caminho `build-pure-ui.sh` com `PureSwiftKit.swift`.
## 🔑 Link: o framework UIKitCore é obrigatório

`UIKit.tbd` é um arquivo **multi-documento** (8 docs: UIKit + 7 private
frameworks). Os símbolos Swift das classes **genéricas**
(`UICollectionViewDiffableDataSource`, `UITableViewDiffableDataSource`,
`NSDiffableDataSourceSnapshot`) são exportados pelo documento do **UIKitCore** —
e o `ld64.lld` **não percorre documentos reexportados**. Sem isso:

```
ld64.lld: error: undefined symbol: _$s5UIKit34UICollectionViewDiffableDataSourceCMn
```

Pior: o `PrivateFrameworks/UIKitCore.framework/UIKitCore.tbd` que vem no SDK
está **incompleto** (não tem os símbolos Swift) — apontar para ele não resolve.

**Fix (já automatizado no `build-pure-ui.sh`):**
```sh
scripts/extract-uikitcore-tbd.sh          # gera /opt/ios-toolchain/extrafw/...
# no link:  -F/opt/ios-toolchain/extrafw -framework UIKitCore
```

## Ressalvas do UIKit (IMPORTANTES — leia antes de escrever código)

As duas limitações abaixo **também ocorrem na VM** (foram reproduzidas lá).
Não são um problema do iSH: são consequência do modo `-compile-module-from-interface`.

## 🔧 A solução única: `assets/PureSwiftKit.swift`

Todos os workarounds das degradações estão consolidados num arquivo só.
Adicione-o ao build e a maioria dos problemas abaixo desaparece:

```sh
build-pure-ui.sh MeuApp com.x.y "Views.swift PureSwiftKit.swift main.swift"
```

Cobre: geometria CGRect (BUG 5), CGContext move/addLine/arc/dash (BUG 2),
`Seconds` no lugar de TimeInterval (BUG 3), helpers de FileManager por path
(BUG 4), `edgeInsets()` (BUG 6), `cgDequeueCell()` (BUG 7).
Validado compilando um app real com todos os helpers.

### 1. Membros de conveniência de CGRect NÃO existem — use `PureSwiftKit.swift`

Os membros `minX`/`midX`/`maxX`/`insetBy`/`offsetBy`/`union`/`intersects`/
`contains`/`.zero`/`.identity` vivem numa `extension CoreFoundation.CGRect` do
CoreGraphics, todos `@_alwaysEmitIntoClient` → invisíveis para consumidores
(mecanismo #2). **Nenhum import resolve** (testei CoreGraphics, CoreFoundation,
QuartzCore, Spatial e submódulos).

**A boa notícia:** as funções C equivalentes funcionam todas. O arquivo
`assets/PureSwiftKit.swift` já embrulha tudo:

```swift
// ❌ NÃO funciona
let v = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 80))
let m = r.minX; let i = r.insetBy(dx: 5, dy: 5); let z = CGRect.zero

// ✅ Com PureSwiftKit.swift no build
let v = UIView(frame: cgRect(0, 0, 200, 80))
let m = r.cgMinX; let i = r.cgInsetBy(dx: 5, dy: 5); let z = cgRectZero
```

**Funcionam sem helper:** `CGSize(width:height:)`, `CGPoint(x:y:)`,
`r.origin.x`, `r.size.width`, aritmética de `CGFloat`.

Compile passando os dois arquivos:
```sh
build-pure-ui.sh MeuApp com.x.y "MinhaView.swift PureSwiftKit.swift main.swift"
```

### 1b. Vários arquivos: o entry point precisa se chamar `main.swift`
Regra do Swift: código top-level (`UIApplicationMain`) só é permitido num
arquivo chamado `main.swift`. O `build-pure-ui.sh` cuida disso — ele copia os
fontes e renomeia o arquivo de entrada (detecta `main.swift` ou `*Main.swift`).

### 2. ⚠️ A ORDEM DOS IMPORTS IMPORTA — `Foundation` antes de `UIKit`

**Esta é a descoberta mais importante desta página** (2026-08-19, sessão 4).
O que parecia "bridging String↔NSString quebrado pelo UIKit" era, na verdade,
**ordem de import**:

```swift
// ✅ CERTO — tudo funciona normalmente
import Foundation
import UIKit

label.text = "abc"                    // ✅
button.setTitle("abc", for: .normal)  // ✅

// ❌ ERRADO — as APIs String do UIKit passam a exigir NSString
import UIKit
import Foundation

label.text = "abc"   // error: cannot assign value of type 'String' to type 'NSString'
```

**Regra: `import Foundation` sempre na PRIMEIRA linha de imports.** Com isso,
NENHUM workaround de NSString é necessário — o `PureSwiftDemo.swift` usa
`label.text = "..."` normalmente.

#### Caso residual: o nome curto `NSString`
Mesmo com a ordem certa, escrever o nome curto `NSString` pode ficar ambíguo
(há o tipo do Clang e o do overlay Foundation no escopo):

```swift
let s: NSString = "x"              // ❌ pode falhar
let s: Foundation.NSString = "x"   // ✅ qualifique
```
Na prática isso quase nunca aparece: use `String`.

Módulos em que a ambiguidade do nome curto foi medida: `UIKit`, `SwiftUI`,
`QuartzCore`, `Symbols`, `Accessibility`, `DataDetection`, `CoreTransferable`,
`OSLog`, `FileProvider`, `UniformTypeIdentifiers`.

## Degradações introduzidas pelos patches nos interfaces

Para compilar os interfaces foi preciso modificá-los. O custo:

| O quê | Efeito prático |
|---|---|
| `@objc` removido de 25 membros de 3 classes genéricas (`UICollectionViewDiffableDataSource`, `UITableViewDiffableDataSource`, `UIIndirectScribbleInteraction`) | essas classes **não** podem ser usadas como data source via ObjC runtime; em Swift puro funcionam |
| `Notification.Name` → `typealias String` | perde type-safety; `NotificationCenter` com `.Name` fica "stringly typed" |
| `NSAttributedString.Key` → `typealias String` | idem |
| `UIMenuSystem.Configuration` → struct vazio | API inutilizável |
| `URLThumbnailDictionaryItem` → struct stub | idem |
| conformances `NotificationCenter.MainActorMessage`/`AsyncMessage` removidas (71 + 144) | API de mensagens tipadas do iOS 26 indisponível |
| corpos `@inlinable`/`@_alwaysEmitIntoClient` removidos | sem inlining; **a implementação real existe no dylib do device** — só não é inlinada |
| defaults de parâmetros removidos (`= .zero`, `= CGRect(...)`) | é preciso passar o argumento explicitamente |
| `Metal.makeLibrary(data:)` → decl sem corpo | funciona, sem inlining |
| `CGContext` sem `move(to:)`/`addLine(to:)`/`setLineDash`/`addArc` | usar funções C (`CGContextMoveToPoint`, `CGContextAddLineToPoint`, `CGContextSetLineDash`, `CGContextAddArc`) ou `UIBezierPath` (move/addLine/addArc funcionam) |
| `TimeInterval` some com `import UIKit` | com Foundation-only resolve; use `Double` |
| `FileManager` instável com UIKit (conflito `Accessibility.AXFoundation`) | dentro de classes compila; `enumerator(at:includingPropertiesForKeys:options:)` (URL-based) **sempre some** → usar `enumerator(atPath:)`; se "different definitions", mover FileManager p/ arquivo só-Foundation |
| `CGRect.height`/`.width` também não existem | usar `cgHeight`/`cgWidth` do PureSwiftKit ou `CGRectGetHeight/GetWidth` |
| `UIEdgeInsetsMake` não existe | usar `UIEdgeInsets(top:left:bottom:right:)` |

> Reports completos com logs e passo a passo: `references/BUG-REPORTS-2026-08-19.md`

## O que ainda NÃO foi provado

✅ **Runtime básico PROVADO (2026-08-19):** `PureSwiftDemo.ipa` foi instalado no
**LiveContainer** e abriu e funcionou. Os corpos `@inlinable` removidos e os
stubs **não quebram** o caminho comum — o dylib real do iOS tem as
implementações; o interface-compile só precisa das assinaturas.

✅ **App COMPLETO em Swift puro PROVADO (2026-08-19, sessão 6):**
`ResumoFit.ipa` v8.1 (10 arquivos, UIKit puro, SQLite via `@_silgen_name` +
`libsqlite3`, UIDocumentPickerViewController, gráficos CoreGraphics custom,
GCD, JSONSerialization) **abriu e funcionou no LiveContainer** após a correção
do entry point (ver BUG 1 em `references/BUG-REPORTS-2026-08-19.md`). Sync com
dados reais do Health Auto Export: **a testar**.

## Validação em runtime — 🏆 TUDO PASSOU

| App | Resultado no device (LiveContainer) |
|---|---|
| `PureSwiftDemo.ipa` (UIKit puro) | ✅ abriu e funcionou |
| `SwiftUIDemo.ipa` (SwiftUI puro) | ✅ abriu e funcionou |
| `ResumoFit.ipa` v8.1 (app completo, SQLite) | ✅ abriu e funcionou |
| **`TortureTest.ipa` (37 testes)** | ✅ **37/37 passaram** |

### O placar 37/37 — o que ficou provado

Todas as áreas degradadas pelos patches **funcionam em runtime**:

| Área testada | Resultado medido na tela |
|---|---|
| CGRect via funções C | `minX=10 maxX=110 midX=60`, `inset.w=90`, `uni.w=150`, `.zero`, `identity a=1 d=1` |
| **NotificationCenter** post/observe | **"recebeu"** — o stub `Notification.Name = String` não quebra nada |
| Constantes do SDK | `NSNotificationName(_rawValue: UIApplicationDidBecomeActiveNotification)` |
| NSAttributedString + `.Key` | `len=5`, `type=NSAttributedStringKey`, `UILabel.attributedText` |
| Foundation | Date, JSON, Codable, URL, DateFormatter, NumberFormatter, String↔NSString |
| UIKit | Autolayout, UIStackView, UIColor/UIFont, CALayer, gestures, UIBezierPath |
| GCD | `DispatchQueue.sync v=42`, `DispatchGroup count=5`, NSLock/NSCondition |
| Swift | generics, KeyPath, Result/throws, existencial `any`, regex |
| **DiffableDataSource** (as 3 classes que perderam `@objc`) | instanciar ✅, snapshot `secoes=1 itens=3` ✅, **`numberOfItems via UIKit = 2`** ✅ |

> 🏆 **A última linha é a prova definitiva:** o UIKit consultou a classe genérica
> *através do runtime ObjC* e obteve a resposta certa. Remover o `@objc` dos 25
> membros das 3 classes genéricas **não quebrou a interoperabilidade**.

**Conclusão do projeto:** os patches nos `.swiftinterface` — incluindo as 10.012
linhas do SwiftUICore e a remoção de `@objc` — **não degradam o comportamento no
device**. O dylib real do iOS tem as implementações; o interface-compile só
precisa das assinaturas. A tese está validada de ponta a ponta.

### Detalhe de API (DiffableDataSource)
O closure entrega `IndexPath`, mas `dequeueReusableCell` espera `NSIndexPath`.
Use o helper do `PureSwiftKit.swift`:
```swift
let ds = UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) { cv, ip, _ in
    cv.cgDequeueCell("c", ip)      // resolve a conversão para você
}
```
⚠️ Sutileza medida: escrevendo à mão, a forma correta **muda com o contexto** —
dentro de `extension`/método é `NSIndexPath(item:section:)` **sem** cast; em
closure inline no corpo de uma função exige `as IndexPath`. Use o helper.
