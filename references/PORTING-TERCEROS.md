# Porting de apps de terceiros — guia completo (2026-08-19)

> **Entrada obrigatória:** leia [`BEST-PRACTICES.md`](BEST-PRACTICES.md) antes
> de portar. Este documento contém detalhes de adaptação; o guia normativo
> define evidência, isolamento, ordem de diagnóstico e o que não prometer.

Este documento consolida TODAS as lições de portar projetos open source do
GitHub para IPA com o toolchain do iSH. Dois casos reais validados:

| App | Origem | Dependências | Resultado |
|---|---|---|---|
| Game2048 | unixzii/SwiftUI-2048 (732⭐) | nenhuma (SwiftUI puro) | IPA ✅ 87KB |
| Minesweeper | RogyMD/TCAminesweeper (137⭐) | TCA 0.39.1 + 6 pacotes SPM | ver HANDOFF |

## Fluxo recomendado (1 comando)

```sh
git clone <repo> /tmp/projeto
python3 scripts/port-third-party.py /tmp/projeto AppName com.x.y.bundle
# flags disponíveis (ver abaixo)
```

O script faz sozinho: coleta → pre-adapta (entry + imports) → strip de imports
→ merge anti-instabilidade → loop de build reativo com fixes automáticos →
validação → relatório `<App>-port.md`.

## As flags

```sh
--extra DIR            # mais diretórios de fontes (ex: dependências SPM)
--resources DIR        # recursos do bundle (ROMs, JSONs, imagens)
--strip-imports "A B"  # remove `import A`/`import B` (módulos unificados)
--exclude "X.swift"    # exclui arquivos do build (basename)
--no-kit               # NÃO inclui PureSwiftKit.swift no build
--merge-mode dep|subdir  # como agrupar a concatenação de arquivos
--debug                # overlay, get-task-allow e attach StikDebug
--stikdebug-bundle-id ID # bundle ID do host para retorno no LiveContainer
```

## Debug durante o porting

Para depurar o app portado no LiveContainer, use as três camadas descritas em
[`DEBUG-LIVECONTAINER-STIKDEBUG.md`](DEBUG-LIVECONTAINER-STIKDEBUG.md): trace
visual para callbacks/UI; attach/script para confirmar PID e debugserver; e
sessão persistente com breakpoints de evento para monitoramento contínuo.
Exemplo:

```sh
python3 scripts/port-third-party.py /tmp/projeto AppName com.x.y.bundle \
  --debug --stikdebug-bundle-id com.kdt.livecontainer.A4658DGR7V
```

Não interprete `debug stop/continue #1` como crash: significa que `c` está
aguardando uma parada. `universal.js` é específico do JIT e não é logger
universal. Para bugs de fluxo, prefira um trace dentro do app com eventos como
`didPick`, carregamento de recursos e `frame: ok lit=N`.



O Xcode baixa pacotes; nós clonamos e unificamos TUDO num módulo único:

1. Identifique a versão: `grep -A5 'XCRemoteSwiftPackageReference' *.xcodeproj/project.pbxproj`
   (ex: TCA 0.39.1 = `kind = exactVersion`).
2. Clone a árvore de deps na versão certa (o Package.swift de cada pacote lista
   as suas deps — combine-schedulers → xctest-dynamic-overlay, etc.).
3. `--extra` cada `Sources/<Target>/` + `--strip-imports` com TODOS os módulos
   unificados (inclusive os `@_exported import` — o strip os remove).
4. Targets internos do app (ex: `TCAminesweeperCommon`, `GameCore`) também vão
   para o strip.

### Árvore real do TCA 0.39.1 (medida)
```
ComposableArchitecture 0.39.1
├── CombineSchedulers 0.7.4 ──→ XCTestDynamicOverlay 0.4.1
├── CasePaths 0.10.1
├── CustomDump 0.8.0
├── IdentifiedCollections 0.5.0 ──→ swift-collections 1.0.4 (OrderedCollections)
└── XCTestDynamicOverlay 0.4.1
```
Todas pré-macros (0.x) = Swift puro compilável. TCA 1.x usa macros → NÃO portável.

## Casos especiais e suas soluções

### 1. `@main struct X: App` (SwiftUI App) — INCOMPATÍVEL
O build-pure-ui.sh renomeia o entry para `main.swift`; `@main` + arquivo
`main.swift` = erro ("main attribute cannot be used in a module that contains
top-level code"). O `@main` App também degrada tipos Foundation ObjC no mesmo
módulo (NSString/FileManager somem).

**Solução**: converter para AppDelegate + UIApplicationMain + UIHostingController
(padrão do `assets/AppEntry.swift`). Exemplo real (TCAminesweeper):
```swift
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    // ⚠️ applicationDidFinishLaunching(_:) — NÃO use
    // application(_:didFinishLaunchingWithOptions:): a assinatura da Apple NÃO
    // casa com o .swiftinterface patchado, o Swift só AVISA, o UIKit nunca
    // chama o método e o app abre com TELA PRETA. Ver WARNINGS-FATAIS.md
    func applicationDidFinishLaunching(_ application: UIApplication) {
        let store = Store(initialState: MainAppState(), reducer: mainAppReducer,
                          environment: .live)
        window = UIWindow(frame: UIScreen.main.bounds)
        window!.rootViewController = UIHostingController(
            rootView: AppView(store: store.scope(state: { $0.app },
                                                 action: MainAppAction.appAction)))
        window!.makeKeyAndVisible()
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))
```
(`store.scope(state:)` recebe **closure**, não KeyPath.)
Se a View raiz estiver dentro de um Scene custom (WithViewStore + WindowGroup),
extraia o conteúdo do WindowGroup manualmente (a Scene não vira View).

### 2. Conflitos de símbolos entre dependências
Ex: TCA e CustomDump AMBOS definem `final class Box<Wrapped>`. No módulo único
= redeclaração. Solução: excluir o arquivo não usado (`--exclude "Box.swift"`
com cuidado — exclui todos com esse basename; mover o arquivo da dependência
para fora do Sources é mais cirúrgico).

### 3. Macros (`@TaskLocal`, `@Reducer`...) — sem plugin no toolchain
Erro: "external macro implementation type 'SwiftMacros.TaskLocalMacro' could
not be found". Solução: remover o atributo `@TaskLocal ` na linha; se o código
usar a API gerada pela macro (`$x.withValue`), excluir o arquivo (ex: TestStore
só serve para testes — o app não usa).

### 4. `DispatchQueue` some (Foundation.DispatchQueue)
Erros "SchedulerTimeType is not a member type of class 'Foundation.DispatchQueue'"
ou "cannot find 'DispatchQueue'" = arquivo importa Foundation mas NÃO Dispatch
(o DispatchQueue resolve para o reexport do Foundation, sem as extensions de
Scheduler). Fix automático do loop: `import Dispatch` (posição canônica 6).

### 5. PureSwiftKit NÃO é sempre bem-vindo
O kit importa UIKit e usa FileManager/NSString — em módulos grandes ele mesmo
quebra (tipos Foundation somem). Use `--no-kit` quando o app não usa os helpers
(`cgRect`, `cgWidth`, `FS`, `edgeInsets`, `cgDequeueCell`). O Minesweeper não
usa nenhum → `--no-kit` resolveu a classe de erros do kit.

### 6. Erros "fantasma" (tipos somem com import presente)
Sintoma: "cannot find 'DispatchQueue'/'FileManager'/'Bundle' in scope" em
arquivos que JÁ importam o módulo. Causa: o swift-frontend (6.3.3 no iSH)
carrega módulos de forma corrompida em compilações grandes — determinístico
por execução, varia entre execuções. O port script detecta (import presente =
fantasma) e faz retry do build (até 5×) sem aplicar fixes errados. O retry NÃO
resolve se o estado ruim for determinístico para aquele conjunto — nesse caso
reduza o tamanho (merge) ou o escopo.

### 7. Limite de tamanho de compilação no iSH (medido)
- ~45+ arquivos pequenos: módulos corrompem (fantasma) — 43 OK / 44 quebra.
- Arquivos gigantes (merged de 8000+ linhas): OOM (processo morto sem mensagem).
- 60 arquivos dummy + kit: OK → o número NÃO é o gatilho sozinho; o conteúdo
  pesado (TCA: Combine/reflection) é o fator.
- Equilíbrio empírico: ~10-25 arquivos de ~500-2000 linhas + `--no-kit`.

### 8. `-swift-module-file`: usar 1 arg (formato original)
`-swift-module-file=X=path` é o formato correto para o swift-frontend.
`-swift-module-file X=path` (2 args) = "unknown argument: '-swift-module-file'"
(ao contrário do que testes superficiais sugeriram — a regex de parse não
pegava `<unknown>:0: error:`).

### 9. main.swift PRIMEIRO na lista de arquivos
A ordem dos arquivos na linha de comando afeta a resolução de tipos ObjC do
Foundation em arquivos que importam UIKit (o main primeiro estabiliza). O
build-pure-ui.sh já garante isso.

### 10. `os.signpost` / imports exóticos
`import os.signpost` (TCA ReducerInstrumentation) pode falhar se o módulo os
não expor o submódulo — excluir o arquivo se não for crítico.

## A morte súbita do compilador (OOM)
O processo swift-frontend morre sem mensagem (rc negativo) em compilações
grandes — o iOS aperta a memória e mata. O port script trata rc<0 como retry.
Se morrer repetidamente: reduza o merge (`--merge-mode dep` para menos
arquivos ou subdir para mais/menores), ou compile as deps como módulo separado
(ver HANDOFF — multi-módulo ainda não implementado).

## Checklist de triagem rápida
1. O app usa `@main App`? → converter entry (caso 1)
2. Tem deps SPM? → clonar árvore + --extra + --strip-imports
3. Macros no código? → remover/excluir (caso 3)
4. Basenames duplicados? → o script renomeia; conflitos de TIPOS → excluir (caso 2)
5. Build grande? → --no-kit + --merge-mode + retry fantasma
6. Erros reais restantes? → o loop reativo cobre: CGRect members, init CGRect,
   UIEdgeInsetsMake, TimeInterval→Double, sync ambíguo (csSync), CasePaths (shim),
   imports CoreText/Dispatch/Foundation/UIKit/Combine, @TaskLocal, Color("asset").

## Estado do TCAminesweeper — ✅ RODANDO NO DEVICE (2026-08-22)

`Minesweeper.ipa` (1,1 MB) **abre e joga no LiveContainer**. Primeiro app com
árvore de dependências SPM (TCA 0.39.1 + 6 pacotes, 27k linhas) validado em
runtime.

### As DUAS causas que travaram este port (independentes)

**1. Type-checker travado** (build não terminava)
Modo whole-module explode com a inferência genérica do TCA. Fix: `-primary-file`
(arquivo-a-arquivo) → 60+ min travado vira **~6 min**.
Detalhes: `TYPECHECKER-E-MULTIMODULO.md`.

**2. Assinatura do AppDelegate** (build OK, app com tela preta)
`application(_:didFinishLaunchingWithOptions:)` não casa com o
`.swiftinterface` patchado → o Swift só **avisa** → o UIKit nunca chama o
método → janela nunca criada → **tela preta com o app vivo**.
Fix: `applicationDidFinishLaunching(_:)`.
Detalhes: **`WARNINGS-FATAIS.md`** ← leia antes de escrever qualquer entry point.

### Receita validada
```sh
# módulo ÚNICO + -primary-file  (o caminho provado em runtime)
python3 scripts/build-parallel.py --module <App> --src <dir> --out /tmp/obj --jobs 3
# depois linkar com as flags do build-pure-ui.sh
```

> **Multi-módulo (`build-multimodule.sh`)**: 🔴 DEPRECADO em 2026-08-23 —
> degrada o bridging String↔NSString. Historicamente: compila e linka, mas **nenhum app
> gerado por ele jamais abriu no device**. Está marcado como NÃO VALIDADO EM
> RUNTIME. Não é a causa da tela preta (o módulo único também dava preto antes
> do fix nº 2), mas continua sem prova. Prefira módulo único.

Fontes do Minesweeper: `/var/minis/workspace/minesweeper-port/`
(`single-src/` = o que roda; `dep-src/`+`app-src/` = experimento multi-módulo).

## 11. Erros de INFERÊNCIA não têm fix automático

O loop reativo conserta imports, membros ausentes e tipos degradados. Ele **não
conserta inferência**. Sintoma: o arquivo não dá erro — ele **trava**
(processo vivo, 0% CPU, sem `.o`). Ou dá erros que mentem sobre a causa
(`extra argument 'qos' in call` quando o problema é o `Self(...)` da linha
anterior).

Receita: isole com `-primary-file`, bisseccione o arquivo por blocos e
reescreva com tipos nominais explícitos. Casos concretos em
`TYPECHECKER-E-MULTIMODULO.md` §5.

## 12. Ordem de import: `Dispatch` DEPOIS de `UIKit`

Ordem canônica atualizada (medida, não suposta):
```
Foundation → SwiftUI → UIKit → CoreText → Dispatch → Combine → <SeuModulo>
```
Com `Dispatch` antes do `UIKit`, o overlay Swift do Dispatch não carrega e o
`DispatchQueue` vira a classe ObjC crua — os erros aparecem longe da causa
("does not conform to protocol 'Scheduler'", "has no member 'main'").

## 13. `#available` quebra o LINK (não a compilação)

```
ld64.lld: error: undefined symbol: ___isPlatformVersionAtLeast
```
Fix: incluir `assets/PlatformVersionShim.swift` no build (o
`build-multimodule.sh` injeta sozinho).
