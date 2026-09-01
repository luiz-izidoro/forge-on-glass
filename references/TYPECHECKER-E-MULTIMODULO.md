# Type-checker do iSH — travas, causas e receitas (2026-08-22)

> **Regra atual:** leia [`BEST-PRACTICES.md`](BEST-PRACTICES.md) primeiro. O
> modo single-module + `-primary-file` é o caminho padrão; este arquivo explica
> as causas e preserva reproduções históricas, inclusive do modo multi-módulo
> deliberadamente reprovado.

> Documento nascido do port do **TCAminesweeper** (TCA 0.39.1 + 6 deps, ~27k
> linhas). O port ficou 4 sessões travado num sintoma mal diagnosticado
> ("o iSH não aguenta compilações grandes"). **A causa era outra** — e a
> solução derrubou o tempo de build de *60+ min travado* para **~2,5 min**.

## TL;DR — as 5 descobertas

| # | Descoberta | Efeito |
|---|---|---|
| 1 | **`-primary-file` (arquivo-a-arquivo) em vez de whole-module** | 60+ min travado → 145 s |
| 2 | **Ordem `Foundation → UIKit → Dispatch → <SeuModulo>`** | resolve `DispatchQueue` (Scheduler, `.main`, `init(label:qos:)`) |
| 3 | **Prelúdio: o 1º arquivo do módulo precisa importar Foundation** | 58 erros → 0 |
| 4 | **`-parse-as-library` no módulo de deps** | some o `duplicate symbol: _main` |
| 5 | **Shim `__isPlatformVersionAtLeast`** | resolve o `undefined symbol` do link |
| 6 | **`-primary-file` também corrige degradação de NOMES** (2026-08-23) | `cannot find 'Bundle' in scope` → compila |

Tudo isso está automatizado em `scripts/build-parallel.py` + `scripts/link-ipa.sh`.
(O `build-multimodule.sh` foi **deprecado** — ver §0.1.) Você **não precisa** repetir o diagnóstico.

---

## 0.1 🔴 Multi-módulo: DEPRECADO (2026-08-23)

Este documento descrevia o **build multi-módulo** (deps num `.swiftmodule`
separado) como caminho para apps grandes. Ele foi **testado e reprovado**.

Caso mínimo — app de 19 linhas com um módulo `DepMod` de 6:

```swift
l.text = "literal direto"
// error: cannot assign value of type 'String' to type 'NSString'
```

O **mesmo arquivo**, removendo apenas o `import DepMod`, compila e empacota
sem nenhuma outra alteração (`build-pure-ui.sh` → IPA de 9,5 KB).

⇒ Importar um módulo separado **degrada o bridging `String`↔`NSString`** no
módulo do app. Isso explica a tela preta de **todos** os apps gerados pelo
`build-multimodule.sh` — nunca houve um que abrisse.

O script agora recusa executar sem `ISB_ALLOW_MULTIMODULE=1`.

**O caminho correto é módulo ÚNICO + `-primary-file`**, que já compila 27k
linhas (TCA 0.39.1 + 6 deps) e tem app validado no device. As descobertas 2-5
deste documento continuam válidas; apenas o *empacotamento em módulos
separados* está descartado.

---

## 0.2 ⚠️ `-primary-file` não é só para app grande (2026-08-23)

Este documento nasceu tratando `-primary-file` como remédio para **travamento**
do type-checker em módulos grandes com genéricos pesados. Isso está correto,
mas é **incompleto**.

Medido em 2026-08-23 com **dois arquivos** (nenhum genérico, ~15 linhas):

```swift
// main.swift usa CGRect;  Helper.swift usa Bundle
// whole-module -> error: cannot find 'Bundle' in scope
// -primary-file -> compila em 6 s, sem alterar o código
```

Em whole-module, um arquivo que usa **CoreGraphics** faz os tipos ObjC do
**Foundation** sumirem de **outros arquivos** do mesmo módulo. É uma
degradação de **resolução de nomes**, não de performance — e atinge apps
pequenos.

**Consequência prática:** `build-pure-ui.sh` passou a usar `--primary-file`
como **padrão** com 2+ arquivos. Whole-module virou opção explícita
(`--whole-module`) e é considerada legado.

Detalhes e caso mínimo: `references/WARNINGS-FATAIS.md` →
"CoreGraphics degrada Foundation".

---

## 1. O sintoma que enganou 4 sessões

```
swift-frontend rodando há 60 min
0% CPU, processo vivo
swift.err parado, nenhum .o gerado
```

Diagnóstico anterior: *"o iSH não aguenta ~45k linhas num processo (OOM ou
type-checking travado)"*. **Errado nas duas partes.**

- Não é OOM: OOM mata o processo (rc<0, sem mensagem) — aqui o processo fica
  **vivo e ocioso**.
- Não é o tamanho: os MESMOS 27k linhas compilam em 145 s quando cada arquivo
  é compilado com `-primary-file`.

### Causa real
No modo **whole-module**, o type-checker resolve TODOS os corpos de função de
TODOS os arquivos num só grafo de constraints. Com genéricos pesados (TCA:
`Effect<Output, Failure>`, `Store<State, Action>`, `AnySchedulerOf<...>`) e
inferência implícita (`Self(...)`, `.live`, `.fireAndForget`), esse grafo
explode combinatorialmente. O compilador não trava por *bug*: ele está
resolvendo, num espaço de busca que não termina em tempo humano.

Com `-primary-file`, os outros arquivos entram apenas como **declarações**
(sem corpos) → o grafo por arquivo é pequeno e fecha em segundos.

> É exatamente o que o Xcode faz por padrão (modo incremental). O
> "whole-module-optimization" só é viável com muita RAM e CPU.

## 2. A receita do build (use isto)

```sh
# 1 comando: deps -> modulo, app -> objetos, link, IPA
sh scripts/build-multimodule.sh <App> <bundle.id> <DepModulo> <dep_dir> <app_dir>
```

O script faz, nesta ordem:
1. injeta `_00_Prelude.swift` em cada dir (regra 3);
2. compila as deps **whole-module** com `-parse-as-library` + `-emit-module`
   (deps são majoritariamente declarações — aqui o whole-module funciona e é
   necessário para gerar o `.swiftmodule`);
3. compila o app com `build-parallel.py` (`-primary-file`, 3 jobs);
4. linka `app*.o + dep.o` e empacota o IPA.

Para compilar só o app (iteração rápida):
```sh
python3 scripts/build-parallel.py --module App --src app-src --out /tmp/obj \
  --dep-module DepModulo=/tmp/mm-App/DepModulo.swiftmodule --jobs 3
```

### Paralelismo: 3 jobs, não mais
Cada `swift-frontend` carrega ~90 pcm/swiftmodule. Com 13 jobs simultâneos o
iSH devolve:
```
module file '.../clang_UIKit.pcm' not found: Cannot allocate memory
```
que **parece** erro de configuração e é só OOM. O `build-parallel.py`
reconhece essa mensagem e reenfileira o arquivo em vez de reportar erro.

## 3. Ordem de imports — a regra que quebra longe da causa

```swift
import Foundation   // 1º SEMPRE
import SwiftUI
import UIKit
import CoreText
import Dispatch     // DEPOIS de UIKit
import Combine
import SeuModulo    // por último
```

Medido com 4 ordens no mesmo arquivo (`DispatchQueue(label:qos:).eraseToAnyScheduler()`):

| Ordem | Resultado |
|---|---|
| `Foundation UIKit Dispatch Modulo` | ✅ rc=0 |
| `Foundation Dispatch UIKit Modulo` | ❌ 6 erros |
| `Foundation Modulo Dispatch UIKit` | ❌ 6 erros |
| `Foundation Combine Dispatch UIKit Modulo` | ❌ 6 erros |

Os erros que aparecem **não mencionam import nenhum**:
```
type 'DispatchQueue' does not conform to protocol 'Scheduler'
type 'DispatchQueue' has no member 'main'
value of type 'DispatchQueue' has no member 'eraseToAnyScheduler'
extra argument 'qos' in call
missing arguments for parameters 'attr', 'queue' in call
```
Todos significam a mesma coisa: **o overlay Swift do Dispatch não carregou**,
o `DispatchQueue` está resolvendo para a classe ObjC crua.

## 4. Prelúdio Foundation (1º arquivo do módulo)

Sem ele, o módulo de deps dava 58 erros do tipo:
```
cannot find 'NSRecursiveLock' in scope           (com import Foundation presente!)
value of type 'String' has no member 'replacingOccurrences'
property 'description' with type 'String' cannot override a property with type 'NSString'
```

O `swift-frontend` estabelece a "visão" dos tipos ObjC do Foundation a partir
do **primeiro arquivo da lista**. Se ele não importar Foundation (ex.: um
`Shims_*.swift` sem imports, que vem primeiro na ordem alfabética), os tipos
ObjC somem para o módulo inteiro.

Fix (automatizado): um `_00_Prelude.swift` com os imports canônicos.
É a mesma raiz da regra antiga "main.swift primeiro na lista".

## 5. Construções que travam o type-checker (e como reescrever)

Estas compilam isoladamente e travam dentro de um módulo grande. **Não são
erros** — são inferências caras. A regra geral: **elimine a inferência**.

### 5.1 `UserDefaults.set(Data?, forKey:)`
```swift
// ❌ trava (overload resolution de set(_:forKey:) com Optional<Data>)
let data: Data? = try? JSONEncoder().encode(scores)
set(data, forKey: k)

// ✅ imediato
guard let data: Data = try? JSONEncoder().encode(scores) else { return }
let obj: Any = data
set(obj, forKey: k)
```

### 5.2 `Self(...)` + membros implícitos em inicializadores de 3+ parâmetros
```swift
// ❌ trava
static let live = Self(
    minefieldEnvironment: .live,
    timerScheduler: DispatchQueue(label: "t", qos: .userInitiated).eraseToAnyScheduler(),
    selectionFeedback: { .fireAndForget { ... } }
)

// ✅ tipo nominal + funções nomeadas com tipos de retorno explícitos
private static func makeTimerScheduler() -> AnySchedulerOf<DispatchQueue> {
    let q: DispatchQueue = DispatchQueue(label: "t", qos: DispatchQoS.userInitiated)
    return q.eraseToAnyScheduler()
}
static let live = GameEnvironment(
    minefieldEnvironment: MinefieldEnvironment.live,
    timerScheduler: GameEnvironment.makeTimerScheduler(),
    selectionFeedback: GameEnvironment.liveSelectionFeedback
)
```

### 5.3 Closures inline com `.success(...)` / `.none` genéricos
```swift
// ❌ Effect.result { .success(x) } dentro de init multi-parâmetro
// ✅
static func liveScores(_ d: Difficulty) -> Effect<[UserHighScore], Never> {
    return Effect<[UserHighScore], Never>.result { () -> Result<[UserHighScore], Never> in
        let s: [UserHighScore] = db.highScores(for: d)
        return Result<[UserHighScore], Never>.success(s)
    }
}
```

### Como achar o culpado
1. `build-parallel.py` já isola por arquivo (o travado aparece sozinho).
2. Divida o arquivo travado em blocos (por `extension`/`protocol`) e compile
   cada um — o `-primary-file` aceita qualquer subconjunto.
3. Reduza o bloco travado a uma função por vez. Cada teste custa ~1 min.
4. **Mate os processos zumbis entre testes** (`pkill -9 -f swift-frontend`):
   processos travados de rodadas anteriores consomem CPU/RAM e fazem testes
   novos parecerem travados também.

## 6. Link: símbolos que faltam no toolchain Linux

### `___isPlatformVersionAtLeast`
```
ld64.lld: error: undefined symbol: ___isPlatformVersionAtLeast
>>> referenced by ...(_$ss31_stdlib_isOSVersionAtLeast...)
```
Origem: qualquer `if #available(iOS X, *)`. O símbolo vive em
`libclang_rt.ios.a`, que só existe no toolchain da Apple.

Fix: `assets/PlatformVersionShim.swift` (`@_cdecl` implementando o builtin via
`ProcessInfo.operatingSystemVersion` — comportamento correto em runtime, não um
stub). O `build-multimodule.sh` injeta automaticamente.

### `duplicate symbol: _main`
O módulo de deps sem `-parse-as-library` gera um `_main` vazio. Sempre passe a
flag ao compilar bibliotecas.

## 7. O que o modo multi-módulo resolve (e o que não)

| Situação | Whole-module único | Multi-módulo + primary-file |
|---|---|---|
| App simples (< 3k linhas) | ✅ segundos | ✅ (overhead desnecessário) |
| App + deps SPM (20k+ linhas) | ❌ trava/OOM | ✅ ~2,5 min |
| Deps só declarações (~25k linhas) | ✅ (é assim que geramos o .swiftmodule) | — |
| Inferência genérica pesada | ❌ trava | ⚠️ isola o arquivo culpado; reescreva (§5) |

**Regra prática:** use `build-pure-ui.sh` para apps sem dependências pesadas e
`build-multimodule.sh` assim que houver um pacote SPM envolvido.

## 8. Caso validado

`Minesweeper.ipa` (1,1 MB) — RogyMD/TCAminesweeper + TCA 0.39.1 + CasePaths +
CustomDump + CombineSchedulers + IdentifiedCollections + swift-collections +
XCTestDynamicOverlay.

```
dep.o    3.404.848 B   (24.798 linhas, whole-module, ~5 min)
app      15 objetos    (2.546 linhas, primary-file, 145 s)
binario  3.750.752 B   platform ios / sdk 26.5 / minos 26.0
simbolos 3.275 do app + 7.981 do TCA
entry    U _UIApplicationMain ✅
CDHash   7404ae06...
```
