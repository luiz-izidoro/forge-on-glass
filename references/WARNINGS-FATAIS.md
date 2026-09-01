# Warnings FATAIS — quando "warning" significa "seu app não vai funcionar"

> **Política de prevenção:** [`BEST-PRACTICES.md`](BEST-PRACTICES.md) é a fonte
> normativa para diagnóstico e níveis de evidência. Este documento detalha os
> warnings e as guardas automáticas.

> Este documento existe porque uma sessão inteira foi perdida em 2026-08-22
> perseguindo uma tela preta cuja causa estava **impressa no log do build
> desde o primeiro minuto**, classificada como *warning*.

## A regra geral

Este projeto compila contra `.swiftinterface` **patchados**. Os patches
preservam as assinaturas na esmagadora maioria dos casos, mas alguns tipos
degradaram (tipicamente coleções Swift viraram tipos ObjC crus):

| Apple | Nosso SDK |
|---|---|
| `[UIApplication.LaunchOptionsKey: Any]?` | `NSDictionary<NSString, AnyObject>?` |
| `[String: Any]` (em vários delegates) | `NSDictionary` |

Quando o membro de protocolo é **opcional** — o que vale para quase todo
delegate herdado do ObjC (`optional func`) — uma assinatura que não casa
**não é erro**. O Swift apenas avisa:

```
warning: instance method 'X' nearly matches optional requirement 'X'
         of protocol 'Y'
note: candidate has non-matching type '...'
```

E então trata o seu método como **um método comum da classe**. O framework
nunca o chama.

**Consequência: código que compila 100% limpo (0 erros) e não funciona.**

## O caso que custou a sessão

```swift
// ❌ compila com warning; o UIKit NUNCA chama isto
func application(_ a: UIApplication,
                 didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds)   // nunca executa
    ...
    return true
}

// ✅ casa exatamente com o protocolo do SDK
func applicationDidFinishLaunching(_ application: UIApplication) {
    window = UIWindow(frame: UIScreen.main.bounds)
    ...
}
```

### Por que o sintoma engana tanto

O app **abre**. O processo fica **vivo**. Não há crash, não há log, não há
crash report. Só uma tela preta — porque nenhuma janela foi criada.

Isso levou a hipóteses erradas em cascata (todas descartadas com testes):

| Hipótese | Teste que a refutou |
|---|---|
| Effects do TCA não emitem | `MinLink` (não usa TCA) também ficou preto |
| Reatividade do `ViewStore` morta | idem |
| SwiftUI não renderiza | idem |
| Shim `__isPlatformVersionAtLeast` | `AvailTest` com o shim abriu (azul) |
| Símbolo faltando p/ o dyld | `check-undefined.py`: 0 faltando nos dois |
| Build multi-módulo corrompe metadata | módulo único também ficou preto |
| `libswift_Concurrency` não carrega | `T1Conc` (que a linka) abriu normalmente |

Todos esses testes foram úteis — cada um eliminou um andar inteiro do prédio.
Mas nenhum era necessário: bastava ler o warning.

## A defesa automática (já integrada)

São **duas** camadas, porque uma só não basta.

### ⚠️ Por que duas: o warning é INCONSTANTE
Medido em 2026-08-22: o **mesmo** código com a assinatura errada emite o
warning em um contexto de compilação e **não emite** em outro (apps pequenos
com poucos imports compilaram sem avisar — e nesses casos o thunk ObjC até é
gerado, então o app funciona). Ou seja: **ausência de warning não prova nada**.
Por isso a segunda camada olha o binário.

### Camada 1 — `scripts/check-warnings.py` (fonte/log)
Roda sozinho no `build-pure-ui.sh` e no `build-parallel.py`; **aborta o build**
e explica a causa.
```sh
python3 scripts/check-warnings.py <arquivo.err>
python3 scripts/check-warnings.py --dir <dir com *.err>
```

### Camada 2 — `scripts/check-entry.py` (binário linkado) ⭐ a que não falha
Não depende de warning: verifica o que ficou no binário.

**O sinal decisivo é o thunk ObjC.** Quando a assinatura casa com o protocolo,
o compilador emite DOIS símbolos:
```
_$s<App>11AppDelegateC11application_29didFinishLaunching...F     <- função Swift
_$s<App>11AppDelegateC11application_29didFinishLaunching...FTo   <- THUNK ObjC ✅
```
O sufixo **`To`** ("to ObjC") é o que registra o método no runtime ObjC — é por
ele que o UIKit chama seu delegate. Sem thunk, o método existe em Swift e o
ObjC **nunca o vê**.

> Não adianta procurar o nome do seletor em `__objc_methname`: a string aparece
> em qualquer binário (vem do próprio UIKit). O que discrimina é o **thunk na
> sua classe**.

```sh
python3 scripts/check-entry.py <App.ipa | binário>
```
Verifica: (1) `_main` chama `UIApplicationMain`; (2) o delegate herda de
`UIResponder`; (3) o método de launch tem thunk ObjC.

**Validado nos 6 IPAs desta investigação** — separou exatamente os que rodam
dos que dão tela preta:

| IPA | check-entry | device |
|---|---|---|
| Minesweeper (corrigido) | 3/3 ✅ | roda |
| AvailTest | 3/3 ✅ | roda |
| Bad3App | 3/3 ✅ | (thunk presente) |
| MinLink | 2/3 ❌ | tela preta |
| MineDiag | 2/3 ❌ | tela preta |
| MinesweeperSM | 2/3 ❌ | tela preta |

### Camada 3 — `scripts/check-protocol-sig.py` — consulte, não adivinhe
Mostra a assinatura **real** de qualquer protocolo/membro no SDK deste
toolchain:
```sh
python3 scripts/check-protocol-sig.py UIApplicationDelegate didFinishLaunching
python3 scripts/check-protocol-sig.py --grep "func application"
```
**Antes de implementar qualquer delegate do sistema, consulte aqui.** Copiar da
documentação da Apple ou escrever de memória é o caminho direto para este bug.

### `assets/AppEntry.swift` — template do entry point
Já vem com a assinatura correta e a explicação. Copie dele.

### `port-third-party.py` — corrige sozinho
`fix_delegate_signature()` reescreve `application(_:didFinishLaunchingWithOptions:)`
→ `applicationDidFinishLaunching(_:)` (todo app de terceiros usa a da Apple).

## Como investigar um "compila mas não funciona" (receita)

1. **Leia os warnings do build.** `grep -c "nearly matches" *.err`. Não pule.
2. **Rode `check-warnings.py`** sobre os logs.
3. Se limpo, aí sim bissecte por camadas — e use apps MÍNIMOS (15 KB, segundos
   de build), nunca o app inteiro (10 min por 1 bit de informação):
   - o entry point é chamado? (pinte a tela de uma cor no `viewDidLoad`)
   - a janela existe? o `rootViewController` foi setado?
   - só então investigue a lógica do app
4. **Cor de fundo distinta em cada teste** (azul/verde/roxo) — "preto" é
   ambíguo entre "não rodou" e "rodou e não desenhou".
5. **Log síncrono**, nunca via `DispatchQueue.main.async`: se a main thread
   travar ou a view nunca aparecer, o bloco assíncrono nunca roda e você fica
   sem informação nenhuma.

## Outros warnings que valem atenção

| Warning | Risco |
|---|---|
| `nearly matches optional requirement` | 🔴 **fatal** — método nunca chamado |
| `result of call to '...' is unused` em entry | 🟡 pode indicar `UIApplicationMain` mal formado |
| `was deprecated in iOS` | 🟢 ruído (ignorado pelo checker) |
| `'retroactive' attribute does not apply` | 🟢 ruído |
| `auto-linked framework not found: UIUtilities` | 🟢 ruído conhecido do lld |

---

# Erros FANTASMA — quando o erro mente sobre a causa

Nem todo problema aparece como warning. Há uma classe de **erros** cuja
mensagem aponta para o lugar errado. O caso abaixo custou o recurso `--debug`
inteiro (ficou quebrado e documentado como "validado").

## 🔴 CoreGraphics degrada Foundation (whole-module) — 2026-08-23

### Sintoma

```
error: cannot find 'Bundle' in scope
error: cannot find 'NotificationCenter' in scope
error: cannot find 'OperationQueue' in scope
error: 'nil' requires a contextual type
```

O arquivo **importa `Foundation`** e o import está na ordem canônica. O tipo
existe. Compilado sozinho, o mesmo arquivo passa.

### Causa

No modo **whole-module**, se algum arquivo do módulo usa **CoreGraphics**
(`CGRect(origin:size:)`, `CGPoint`, `CGSize`), os tipos ObjC do Foundation
podem **desaparecer de OUTROS arquivos** do mesmo módulo.

A degradação é **cross-file**: o arquivo que reporta o erro pode não ter uma
linha de CoreGraphics. No caso real, `main.swift` (com 9 usos de CGRect) fez
`Bundle` sumir de um `Helper.swift` de 3 linhas.

Reproduzido de forma **determinística** (3/3) com dois arquivos:

```swift
// main.swift  — usa CGRect
// Helper.swift:
import Foundation
import UIKit
public enum Helper {
    public static func b() -> String { return Bundle.main.bundleIdentifier ?? "?" }
}
// -> error: cannot find 'Bundle' in scope
```

Também ocorre **dentro de um único arquivo**, quando a declaração que usa
CoreGraphics vem **antes** da que usa Foundation:

```swift
// ❌ FALHA
enum H {
  static func r() -> CGRect { CGRect(origin: CGPoint(x:1,y:2), size: CGSize(width:3,height:4)) }
  static func b() -> String { Bundle.main.bundleIdentifier ?? "?" }
}
// ✅ OK — mesmo código, ordem invertida
enum H {
  static func b() -> String { Bundle.main.bundleIdentifier ?? "?" }
  static func r() -> CGRect { CGRect(origin: CGPoint(x:1,y:2), size: CGSize(width:3,height:4)) }
}
```

**Descartados por teste** (não são a causa): `public`, `import Darwin`, ordem
alfabética dos arquivos, string literal multilinha grande, tamanho do arquivo,
ordem dos imports.

### ✅ Solução: `-primary-file`

O mesmo código, **sem nenhuma alteração**, compila em segundos no modo
arquivo-a-arquivo:

| Modo | Resultado |
|---|---|
| whole-module | ❌ `cannot find 'Bundle' in scope` |
| `-primary-file` (`build-parallel.py`) | ✅ 6 s |

Por isso `build-pure-ui.sh` usa **`--primary-file` como padrão** desde
2026-08-23 (com 2+ arquivos). Para forçar o modo antigo: `--whole-module`.

> ⚠️ `-primary-file` não é só "para app grande com TCA/genéricos pesados",
> como a documentação anterior sugeria. Ele corrige uma **classe inteira de
> degradação de resolução de nomes** que atinge apps pequenos também.

### Se você precisa mesmo de whole-module

Ordene as declarações: tudo que usa Foundation **antes** de tudo que usa
CoreGraphics. Ver `assets/DebugSupport.swift` (funções `isbBarFrame()` /
`isbTitleFrame()` isoladas no fim do arquivo). Isso mitiga o caso intra-file,
mas **não resolve o cross-file** — para esse, só `-primary-file`.

### Guarda

`scripts/regression-suite.sh` inclui o caso `cgfoundation`, que reproduz
exatamente essa combinação nos dois modos. Rode-a após mexer nos scripts de
build.
