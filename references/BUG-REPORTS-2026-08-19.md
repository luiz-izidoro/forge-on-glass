# BUG REPORTS — 2026-08-19 (sessão 6, ResumoFit v8 em Swift puro)

> Registro histórico de reproduções. As regras vigentes estão em
> [`BEST-PRACTICES.md`](BEST-PRACTICES.md); use estes casos para regressão,
> não para inferir que um caminho sem runtime está validado.

Reports com logs completos e passo a passo, medidos durante o desenvolvimento
do ResumoFit v8 (app 100% Swift puro, UIKit, SQLite, rodando no LiveContainer).

---

## BUG 1 — "App returned from its main function with code 0" (entry point vazio)

**Severidade: crítica (app não abre). Classe: erro de quem escreve o entry
point, MAS o sintoma é enganoso — diagnóstico abaixo vale para sempre.**

### Sintoma
O IPA abre no LiveContainer e fecha na hora com:
`App returned from its main function with code 0` (exit limpo, SEM crash).

### Causa raiz
O arquivo que vira `main.swift` (renomeado pelo build-pure-ui.sh) continha
APENAS declarações — **faltava a chamada final**:

```swift
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))
```

Com `main.swift` sem top-level code, o Swift gera um `_main` vazio
(`mov w0, #0; ret`) — o app retorna do main com exit 0 e nunca entra no
run loop. **O compilador NÃO avisa.**

### Diagnóstico passo a passo (reproduzível)
```sh
unzip -o App.ipa -d /tmp/x && cd /tmp/x/Payload/App.app
# 1. o binario referencia UIApplicationMain? (U = undefined, resolve no link)
llvm-nm App | grep UIApplicationMain        # vazio = PROBLEMA
#    (um binario saudavel mostra: U _UIApplicationMain)
# 2. desmonte o entry point
llvm-objdump -d App --start-address=0x100004000 | head -10
#    PROBLEMA:  mov w0, #0x0 / ret          (return imediato)
#    SAUDAVEL:  sub sp, sp, #0x40 ... bl UIApplicationMain
# 3. conferir o fonte: grep UIApplicationMain no arquivo que vira main.swift
```

### Fix
Adicionar `UIApplicationMain(...)` no final do arquivo de entrada (o arquivo
que casa com `*Main.swift` no build-pure-ui.sh).

### Verificação pós-fix
`llvm-nm` mostra `U _UIApplicationMain` e o `_main` desmonta igual ao
PureSwiftDemo (sequência completa com `bl UIApplicationMain`).

### Validação do padrão multi-arquivo
`main.swift` (top-level UIApplicationMain + AppDelegate) + N arquivos de
biblioteca **funciona** — testado com MiniTest (2 arquivos): `_main` correto.

---

## BUG 2 — CGContext do overlay não tem move/addLine/setLineDash/addArc

**Severidade: média (gráficos custom). Classe: degradação do overlay no
toolchain (mediu-se que as funções C existem e funcionam).**

### Sintoma
```swift
ctx.move(to: p)                       // ❌ value of type 'CGContext' has no member 'move'
ctx.addLine(to: p)                    // ❌ no member 'addLine'
ctx.setLineDash(phase: 0, lengths: d) // ❌ no member 'setLineDash'
ctx.addArc(center:radius:...)         // ❌ no member 'addArc'
```

### O que FUNCIONA no CGContext (medido)
`setFillColor(_:)`, `fill(_:)`, `setStrokeColor(_:)`, `setLineWidth(_:)`,
`setLineCap(_:)`, `strokePath()`, `beginPath()`, `fillEllipse(in:)`.

### Workaround (funções C — todas OK)
```swift
CGContextMoveToPoint(ctx, x, y)
CGContextAddLineToPoint(ctx, x, y)
var dashes: [CGFloat] = [3, 3]
CGContextSetLineDash(ctx, 0, &dashes, 2)
CGContextSetLineDash(ctx, 0, nil, 0)          // reset
CGContextAddArc(ctx, x, y, r, a0, a1, 0)
```
`UIBezierPath.move(to:)` / `addLine(to:)` / `addArc(withCenter:...)` também
**funcionam** (preferível para curvas).

---

## BUG 3 — TimeInterval fora de escopo quando UIKit está importado

**Severidade: baixa (use Double). Classe: degradação do interface-compile.**

### Sintoma
```swift
import Foundation
import UIKit
func fadeIn(_ v: UIView, delay: TimeInterval = 0) {}  // ❌ cannot find type 'TimeInterval'
```
Sem UIKit (`import Foundation` apenas): `TimeInterval` compila ✅.

### Workaround
Usar `Double` (typealias idêntico). Probes: `TimeInterval` (Foundation) OK;
`TimeInterval c/ UIKit` FALHA (medido no probe_api.py).

---

## BUG 4 — FileManager instável com UIKit no escopo (conflito Accessibility)

**Severidade: média. Classe: conflito de módulos do SDK (Accessibility reexporta
NSFileManager de forma diferente).**

### Sintoma (dois rostos, dependendo do contexto)
1. Erro de tipo:
```
'NSFileManager' has different definitions in different modules;
definition in module 'Foundation.NSFileManager' is here
note: definition in module 'Accessibility.AXFoundation' is here
```
2. Ou: a overload URL-based do enumerator SOME da overload set:
```swift
fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
// ❌ extra arguments at positions #1, #2, #3 in call
// note: 'enumerator(atPath:)' declared here
```

### Comportamento medido
- `FileManager` DENTRO de uma classe (property `let fm = FileManager.default`
  + métodos): **compila** (caso do SyncManager do ResumoFit — app buildou).
- `FileManager` numa função global (`func f() { let fm = ... }`):
  **não compila** no probe (determinístico, 3/3 runs).
- `enumerator(at:includingPropertiesForKeys:options:)` (URL-based): **sempre
  some** com UIKit (mesmo dentro de classe).
- Só com Foundation (sem UIKit): tudo funciona ✅.

### Workaround
- Use `fm.enumerator(atPath: path)` (versão String — confiável).
- Se o erro "different definitions" aparecer, mova o código de FileManager
  para um arquivo com `import Foundation` APENAS (sem UIKit).

---

## BUG 5 — CGRect.height/.width não existem (mesma família de minX)

**Severidade: média. Classe: degradação do interface (extensão
@_alwaysEmitIntoClient removida — mesma família de minX/midX/insetBy).**

### Sintoma
```swift
var f = v.frame
f.origin.y = y
let h = f.height        // ❌ value of type 'CGRect' has no member 'height'
```

### Workaround (PureSwiftKit.swift)
```swift
let h = f.cgHeight      // CGRectGetHeight(self)
let w = f.cgWidth       // CGRectGetWidth(self)
// funções C diretas também OK: CGRectGetHeight(r), CGRectGetWidth(r)
```

---

## BUG 6 — UIEdgeInsetsMake não existe ("replaced by init")

**Severidade: baixa. Classe: overlay do UIKit.**

### Sintoma
```swift
let e = UIEdgeInsetsMake(1, 2, 3, 4)   // ❌ 'UIEdgeInsetsMake' has been replaced by 'UIEdgeInsets.init(top:left:bottom:right:)'
```

### Workaround
```swift
let e = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)   // ✅ funciona
```

---

## BÔNUS — SQLite sem módulo Clang (padrão SQLiteShim)

O `foundation-build633` NÃO tem `clang_SQLite3.pcm` → `import SQLite3` não
funciona com `-fno-implicit-modules`. Solução usada no ResumoFit v8 (linka
`-lsqlite3` — adicionado na cópia do build.sh no projeto):

```swift
typealias SQLiteDestructor = @convention(c) (UnsafeMutableRawPointer?) -> Void
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: SQLiteDestructor.self)

@_silgen_name("sqlite3_open")
func sqlite3_open(_ f: UnsafePointer<CChar>?, _ db: UnsafeMutablePointer<OpaquePointer?>?) -> Int32
// ... prepare_v2 / step / finalize / bind_text / bind_double / bind_int64 /
//     column_count / column_name / column_text / column_double / errmsg

// Strings SEMPRE via withCString (String nao converte direto para CChar*):
path.withCString { sqlite3_open($0, &db) }
sql.withCString { sqlite3_exec(db, $0, nil, nil, nil) }
```

Funciona ponta a ponta: CREATE/INSERT/query com binds, `PRAGMA journal_mode=WAL`.
Prova: ResumoFit v8 rodou com banco SQLite no device.

## Runtime PROVADO (LiveContainer) — todos os bugs endereçados

| App | Resultado |
|---|---|
| **PureSwiftDemo.ipa** | ✅ UIKit puro, UIApplicationMain, labels/buttons |
| **SwiftUIDemo.ipa** | ✅ SwiftUI puro (VStack/ForEach/Text/modifiers) |
| **ResumoFit.ipa v8.1** | ✅ app completo: SQLite, picker, gráficos, GCD, 4 abas |
| **TortureTest.ipa** | ✅ **37/37 testes passaram** |

O TortureTest exercitou justamente as áreas destes bug reports e **todas
passaram em runtime**, incluindo a de maior risco:
`UICollectionView.dataSource respondeu ao ObjC runtime: numberOfItems via UIKit = 2`
— o UIKit conversa normalmente com as classes genéricas mesmo após a remoção do
`@objc` de 25 membros.

## ✅ Todos os workarounds consolidados em `assets/PureSwiftKit.swift`

Em vez de reimplementar caso a caso, adicione o arquivo ao build:

```sh
build-pure-ui.sh MeuApp com.x.y "Views.swift PureSwiftKit.swift main.swift"
```

| Bug | Helper do PureSwiftKit |
|---|---|
| 2 — CGContext | `ctx.cgMove(to:)`, `cgAddLine(to:)`, `cgAddArc(...)`, `cgSetLineDash(...)` |
| 3 — TimeInterval | `Seconds` (alias de Double) |
| 4 — FileManager | `FS.documentsPath`, `FS.listRecursive(_:suffix:)`, `FS.exists`, `FS.copy`... |
| 5 — CGRect | `cgRect()`, `r.cgMinX`, `r.cgWidth`, `r.cgInsetBy`, `cgRectZero`... |
| 6 — UIEdgeInsets | `edgeInsets(1,2,3,4)` |
| 7 — dequeue | `cv.cgDequeueCell("id", ip)` / `tv.cgDequeueCell("id", ip)` |

**Cobertura verificada:** `scripts/verify-pureswiftkit.sh` compila um app que usa
*todos* os helpers. Se passar, a cobertura está 100%.
(BUG 1 é regra de código — a chamada `UIApplicationMain` no fim do main.swift.)

---

## BUG 7 — `dequeueReusableCell(withReuseIdentifier:for:)` exige `NSIndexPath`

**Contexto:** closure do `UICollectionViewDiffableDataSource`.

O closure entrega `IndexPath`, mas o método de dequeue espera `NSIndexPath`:

```swift
// ❌ error: cannot convert value of type 'IndexPath' to expected argument type 'NSIndexPath'
cv.dequeueReusableCell(withReuseIdentifier: "c", for: ip)

// ✅
cv.dequeueReusableCell(withReuseIdentifier: "c",
                       for: NSIndexPath(item: ip.item, section: ip.section) as IndexPath)
```

**Detalhe importante:** em arquivo ÚNICO o `NSIndexPath(item:section:)` sozinho
compila; em **MULTI-ARQUIVO** o `as IndexPath` explícito passa a ser obrigatório
("'NSIndexPath' is not implicitly convertible to 'IndexPath'"). Ou seja, a
resolução de bridging muda conforme o número de arquivos na mesma invocação.

**Runtime (medido no device):** funciona. O UIKit instancia a classe genérica,
registra como dataSource e chama o closure Swift — ver PURE-SWIFT-UI-STATUS.md.
