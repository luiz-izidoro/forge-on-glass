---
name: ios-swift-builder
version: 0.2.0
description: >-
  Build native iOS .ipa apps with modern Swift, entirely inside iSH (Alpine
  Linux on iPhone/iPad), no Mac at build time. Use this skill whenever the user
  wants to create, compile, or package an iOS app / .ipa on-device using Swift,
  UIKit, or "Swift on iSH". Covers a working Swift 6.3.2 → Mach-O arm64 iOS
  toolchain with a prebuilt iOS 26.5 stdlib, a hybrid Swift-logic + ObjC-UIKit
  architecture (the way to get a real UI), ad-hoc code signing, and IPA
  packaging. Also documents every known limitation and how to work around or
  fully solve it in a fresh session. Trigger on: "compilar Swift no iSH",
  "gerar IPA", "app iOS sem Mac", "SwiftApp", "ios-swift-builder", UIKit/SwiftUI
  on device.
---

# iOS Swift Builder (on-device, no Mac)

> **Política normativa:** leia [`references/BEST-PRACTICES.md`](references/BEST-PRACTICES.md) antes de iniciar qualquer projeto. Ela é a fonte de verdade para escolha de perfil, evidência de runtime, validação, LiveContainer, IA nativa, isolamento de artefatos e prevenção de retrabalho.

Compile modern Swift into a signed native iOS `.ipa`, 100% inside iSH. Proven
working: Swift 6.3.2 → Mach-O arm64 (iOS 26.5 SDK) → linked with UIKit →
ad-hoc signed → `.ipa`. This skill is the distilled, replayable result of a long
research session; read `references/CONTEXT.md` for the full story and rationale.

## Preconditions (verify first)

Run `scripts/check-env.sh`. It confirms every dependency exists. Expected layout
(all already present on this device from the original session):

- `/opt/swift6.3/usr/bin/swift-frontend` — Swift 6.3.2 Linux, patchelf'd to the
  glibc loader in `/opt/xtool-glibc/lib`. Must print `Swift version 6.3.2`.
- `/opt/ios-toolchain/iPhoneOS26.5.sdk` — open iOS 26.5 SDK (headers + .tbd).
- `/opt/ios-toolchain/exp63/modules/` — prebuilt binary Swift stdlib for iOS:
  `Swift`(15MB), `_Concurrency`, `_StringProcessing`, `SwiftOnoneSupport`.
- `/opt/ios-toolchain/exp63/SwiftShims.pcm` — Clang shims PCM.
- Tools: `clang`, `ld64.lld`, `ldid`, `llvm-strip`, `zip`.

If any binary module is missing, restore from
`/var/minis/shared/darwin-sdk/swift-modules-full/` (backup). If the whole
toolchain is gone, `references/BOOTSTRAP.md` rebuilds it from scratch (needs a
Mac once for the SDK bundle).

## Golden rule of this environment

**iSH's `/proc` lies** — `cpu_ticks=0` and `VmRSS=0` even for a working process.
Never conclude "deadlock" from CPU/RSS. The ONLY reliable signal is the output
file appearing + a real rc. There is a ~15-25% non-deterministic startup race
(SIGTRAP / silent exit) on every `swift-frontend` call → **always retry** (the
provided scripts do this). A large compile can legitimately take 15-20 min.

## Architecture: how to get a real UI

**Desde 2026-08-19 há duas opções:**

### A) Swift puro (novo — `import UIKit` / `import SwiftUI`)
Use `scripts/build-pure-ui.sh`. Zero Objective-C. Leia
`references/PURE-SWIFT-UI-STATUS.md` para as duas ressalvas de sintaxe.

### B) Híbrido Swift + ObjC (maduro, usado em apps reais)
Continua sendo a rota mais previsível para UI complexa, sem ressalvas:

- **Swift logic** (`AppLogic.swift`): pure Swift — arrays, generics, closures,
  algorithms, structs. Export entry points to C with `@_cdecl("name")`.
- **ObjC UIKit shell** (`AppShell.m`): the whole UI in Objective-C + UIKit,
  declares the Swift functions as `extern` and calls them.
- Link both objects → one Mach-O executable that links UIKit + libswiftCore.

You write ALL app logic in modern Swift; only the view layer is ObjC/UIKit.

## Build an app (the happy path)

1. Copy the two source templates from `assets/` and edit them:
   - `assets/AppLogic.swift` — put Swift logic here; expose with `@_cdecl`.
   - `assets/AppShell.m` — build the UI; call the Swift functions.
2. Run `scripts/build-ipa.sh <AppName> <BundleID> <AppLogic.swift> <AppShell.m>`.
   It compiles Swift (with retry), compiles ObjC, links, signs (ldid), zips.
   Output: `/var/minis/workspace/<AppName>.ipa`.
3. Validate: `scripts/validate-ipa.sh /var/minis/workspace/<AppName>.ipa`.
   Must show `platform ios / sdk 26.5`, links `libswiftCore.dylib` + `UIKit`,
   and a swift-mangled symbol (proof Swift is embedded).

Pure-Swift console apps (no UI) also work: skip AppShell.m and compile+link
`AppLogic.swift` alone (see `scripts/build-ipa.sh --pure`).

## Swift modules that DO import directly (no ObjC needed)

`Swift`, `_Concurrency`, `_StringProcessing`, `Darwin`, `ObjectiveC`,
`CoreFoundation`, `Combine`, `Observation`, `System`, `_DarwinFoundation1/2/3`,
`_Builtin_float`. When importing these you MUST inject both shims:
`-Xcc -fmodule-file=SwiftShims=… -Xcc -fmodule-file=_SwiftConcurrencyShims=…`
(the prebuilt `.swiftmodule`s live in `/opt/ios-toolchain/foundation-build/`).

**Since 2026-08-18, `Foundation`, `Dispatch`, `os`, `simd`, `Spatial`, `Symbols`
and `Accessibility` ALSO import in pure Swift** — the Foundation chain was
built on a real Linux (VM) with the matching swift.org 6.3.2 and copied back.
Use `scripts/build-pure-foundation.sh <App> <main.swift>` (compile+link in one
step). `import Foundation` + `import Dispatch` work end-to-end (validated:
Mach-O arm64 iOS 26.0, 186 Swift symbols). See
`references/DISPATCH-VIA-LINUX.md` (now SOLVED) for the VM recipe + the iSH
symlinks that the prebuilt `.pcm` files require.

## Pure-Swift UIKit / SwiftUI — ✅ FUNCIONA (desde 2026-08-19)

`import UIKit` e `import SwiftUI` compilam em Swift puro. Dois IPAs validados,
sem uma linha de ObjC:
- `/var/minis/workspace/PureSwiftDemo.ipa` (UIKit)
- `/var/minis/workspace/SwiftUIDemo.ipa` (SwiftUI)

```sh
scripts/build-pure-ui.sh <AppName> <BundleID> <main.swift> [outro.swift ...]
```
Comece por `assets/PureSwiftDemo.swift` (UIKit) ou `assets/SwiftUIDemo.swift`
(SwiftUI).

### Modo de compilação (mudou em 2026-08-23)

Com **2+ arquivos**, o padrão agora é `--primary-file` (arquivo-a-arquivo via
`build-parallel.py` + `link-ipa.sh`). O modo antigo continua disponível como
`--whole-module`.

**Por quê:** em whole-module, um arquivo que usa CoreGraphics faz os tipos do
Foundation **sumirem de outros arquivos** do mesmo módulo:
`error: cannot find 'Bundle' in scope`, mesmo com `import Foundation` correto.
A degradação é cross-file e determinística. Medido em `regression-suite.sh`:

| Caso | `--primary-file` | `--whole-module` |
|---|---|---|
| UIKit 1 arquivo | ✅ | ✅ |
| SwiftUI 1 arquivo | ✅ | ✅ |
| App + PureSwiftKit | ✅ | ✅ |
| **App(CGRect) + Helper(Bundle)** | ✅ | ❌ `cannot find 'Bundle'` |
| `--debug` (DebugSupport) | ✅ | ❌ |

✅ **Validado em runtime (2026-08-23):** `B2Debug.ipa`, gerado por
`-primary-file` + `link-ipa.sh` com `--debug`, **abriu no LiveContainer** com o
overlay DBG.

Detalhes: `references/WARNINGS-FATAIS.md` → "CoreGraphics degrada Foundation".

⚠️ **Três regras mudam como você escreve o código:**

1. 🔴 **ENTRY POINT — use `applicationDidFinishLaunching(_:)`.**
   **NÃO** use `application(_:didFinishLaunchingWithOptions:)`: no SDK patchado
   o `launchOptions` é `NSDictionary`, a assinatura da Apple **não casa** com o
   protocolo, o Swift emite apenas um *warning* — e o UIKit **nunca chama** o
   seu método. O app abre, fica vivo e mostra **TELA PRETA**, sem crash nem log.
   Copie de `assets/AppEntry.swift`. Leia `references/WARNINGS-FATAIS.md`.
   Antes de implementar QUALQUER delegate do sistema, consulte a assinatura real:
   ```sh
   python3 scripts/check-protocol-sig.py UIApplicationDelegate didFinishLaunching
   ```
2. **ORDEM DOS IMPORTS:** `Foundation` → `SwiftUI` → `UIKit` → `CoreText` →
   `Dispatch` → `Combine`. (`Dispatch` **depois** de `UIKit`, senão o
   `DispatchQueue` perde o overlay Swift e os erros mentem.)
3. **Inclua `assets/PureSwiftKit.swift` no build** — resolve as degradações
   conhecidas (CGRect, CGContext, FileManager, dequeue, edge insets,
   TimeInterval):
   ```sh
   build-pure-ui.sh MeuApp com.x.y "Views.swift PureSwiftKit.swift main.swift"
   ```
   ⚠️ Em módulos GRANDES o kit degrada (usa FileManager/NSString): use
   `--no-kit` e helpers mínimos locais. `CGRectMake` **não existe** no SDK 26.5
   (falha só no LINK) — para criar rects use `CGRect(origin:size:)`.

### 🛡️ Guarda automática contra "compila mas não funciona"
Os builds verificam **duas** camadas sozinhos e **abortam** se o app não fosse
iniciar:
1. `check-warnings.py` — warnings que quebram o app (ex.: assinatura de
   protocolo divergente);
2. `check-entry.py` — inspeciona o **binário linkado**: `_main` chama
   `UIApplicationMain`? o método do delegate tem **thunk ObjC** (`...To`)?

A camada 2 existe porque **o warning é inconstante** (o mesmo código avisa num
contexto e não avisa em outro). Ausência de warning não prova nada; o thunk
prova. Nunca ignore `nearly matches optional requirement` — significa "este
método jamais será chamado".

Detalhes e tabela por área: `references/PURE-SWIFT-UI-STATUS.md`;
casos com log: `references/BUG-REPORTS-2026-08-19.md`.

## Debug no device: LiveContainer + StikDebug

Quando o desenvolvimento precisa de inspeção no device, use debug em camadas.
O `--debug` é **opt-in** e não substitui a validação visual do app:

```sh
# SwiftUI/UIKit puro
sh scripts/build-pure-ui.sh MeuApp com.exemplo.meuapp \
  main.swift Views.swift --debug

# Projeto de terceiro
python3 scripts/port-third-party.py /tmp/projeto MeuApp com.exemplo.meuapp \
  --debug --stikdebug-bundle-id com.kdt.livecontainer.A4658DGR7V

# Guarda antes de instalar
python3 scripts/check-debug-ipa.py /var/minis/workspace/MeuApp.ipa
```

### O que uma IPA `--debug` contém

- `assets/DebugSupport.swift`, adicionado apenas à cópia de trabalho;
- entitlement `get-task-allow=true`, necessário para attach;
- `LSApplicationQueriesSchemes=stikdebug`;
- overlay azul **DBG • toque: StikDebug** dentro da janela do app;
- PID, bundle ID, detecção de `LC_HOME_PATH` e logs `[ios-swift-builder]`;
- URL oficial `stikdebug://enable-jit` com o PID atual;
- no port de terceiros, `--stikdebug-bundle-id HOST_ID` define o app para o
  qual o StikDebug deve retornar. Para LiveContainer, use o bundle ID real do
  host, por exemplo `com.kdt.livecontainer.A4658DGR7V`.

A reassinatura pós-processamento (manifest, recursos e storyboard recriado)
preserva `get-task-allow`. Um instalador pode remover esse entitlement; sempre
rode `check-debug-ipa.py` sobre a IPA que será instalada.

### Três camadas de diagnóstico

**Camada 1 — trace visual dentro do app (primeira escolha).**
Para fluxos UIKit, instrumente uma `Trace` que escreve na tela eventos síncronos:

```text
main: viewDidLoad
main: Load ROM handler
main: criando picker
picker: viewDidLoad
picker: ROMs=25
picker: tocou INVADERS
picker: delegate didPick chamado
main: load INVADERS, url=true
main: ROM carregada INVADERS
frame: ok lit=119
```

Essa camada responde rapidamente: o toque chegou? o delegate foi chamado? o
arquivo existe? o modelo mudou? a imagem foi criada? É preferível a iniciar um
attach para investigar uma falha de UI simples. Não use `DispatchQueue.main.async`
para o primeiro log de diagnóstico: o bloco pode nunca executar se a tela não
for criada.

**Camada 2 — attach/script no StikDebug.**
O overlay abre o StikDebug com o PID do processo convidado. O script inline de
attach deve registrar `vAttach`, `qSupported`, `qfThreadInfo`, `qC`, pacote de
registradores e `D`/detach. O retorno ao LiveContainer é parte da sessão de
script, não prova de que o app foi relançado.

O bundle ID de retorno é diferente do bundle ID do app convidado:

```text
app convidado:  com.minis.chip8emu.debug
host:          com.kdt.livecontainer.A4658DGR7V
```

Se o StikDebug mostrar “Failed to return to com.minis...” use o host ID. Se
mostrar “JIT request completed for com.kdt.livecontainer...” o host foi
localizado; isso não significa que o log do app esteja naquela tela.

**Camada 3 — sessão persistente de baixo nível.**
Para acompanhar o processo enquanto ele roda, o script precisa manter:

```text
vAttach → qSupported/qfThreadInfo/qC → c → registrar parada → g → c ...
```

Não envie `D` logo após as consultas se a intenção é monitoramento contínuo.
`universal.js` não é um capturador genérico de logs: ele interpreta `BRK` do
protocolo JIT. Em um app comum, pode ficar parado em `Handling signal 1` ou em
`debug stop/continue #1` simplesmente aguardando um sinal. Isso não prova crash.

Para gerar eventos úteis em uma sessão persistente, adicione breakpoints de
instrumentação nos eventos importantes (`Load ROM`, `didPick`, carregamento,
renderização). O breakpoint deve ocorrer **somente depois que o usuário tocou
DBG**; antes disso, o app deve continuar sem `SIGTRAP`. Cada evento esperado
deve fazer o script avançar para `#2`, `#3` etc. Se ele parar em `#1`, não há
novo evento/debug trap para processar.

### Procedimento no device

1. Instale a IPA pelo método que preserva `get-task-allow`.
2. Abra o app dentro do LiveContainer.
3. Se necessário, habilite **Use LiveContainer's Bundle ID** nas opções de JIT.
4. Confirme que o overlay azul DBG aparece dentro do app.
5. Para UI: reproduza primeiro com trace visual.
6. Para baixo nível: toque DBG, mantenha LocalDevVPN/túnel e observe no
   StikDebug `vAttach`, `qSupported`, threads, `qC`, registradores e `c`.
7. Gere o evento instrumentado (toque, seleção, callback) e confira se o
   contador de paradas avança.
8. Use **Done** somente quando terminar; o script pode ficar em foreground
   durante a sessão. Ao encerrar, espere `D`/detach e retorne manualmente ao
   LiveContainer se o retorno automático falhar.
9. O PID muda a cada lançamento; nunca reutilize um PID antigo.

### O que os logs significam

| Mensagem | Interpretação |
|---|---|
| `attach_response = T...` | attach/debugserver respondeu |
| `qSupported = ...` | capacidades do debugserver disponíveis |
| `qfThreadInfo = m...` | lista de threads retornada |
| `qC = QC...` | thread atual |
| `register_packet_length = 0` | `g` não retornou pacote nesse estado; não é, sozinho, falha do app |
| `detach = OK` | sessão foi encerrada pelo script/usuário |
| `Handling signal 1` | `universal.js` aguardando/processando sinal; não prova crash |
| `debug stop/continue #1` | sessão persistente está bloqueada no `c`, aguardando parada |
| `frame: ok lit=N` | framebuffer tem N pixels acesos e a imagem foi criada |
| `UIImage=nil` | falha no caminho Bitmap → CGImage → UIImage |

### Limites e segurança do debug

- O console do StikDebug mostra logs do script/debugserver; `print`/`NSLog` do
  app não aparecem automaticamente ali. Use trace visual ou syslog apropriado.
- `universal.js` deve ser usado para o protocolo JIT compatível, não como log
  genérico de UIKit.
- `get-task-allow` pode ser removido ao instalar/reassinar; valide novamente.
- Não embutimos StikJIT/helper/extensão no app: o StikDebug é externo e o
  LiveContainer não suporta essa extensão para apps convidados.
- O attach e o console só existem no device; o iSH consegue gerar e validar a
  instrumentação, mas não simular a sessão real.

Procedimento completo e detalhes do protocolo: `references/DEBUG-LIVECONTAINER-STIKDEBUG.md`.


Baixou um projeto open source do GitHub e quer testar?
`scripts/port-third-party.py` adapta e builda sozinho:

```sh
git clone <repo> /tmp/projeto
python3 scripts/port-third-party.py /tmp/projeto MeuApp com.x.y.meuapp
# -> /var/minis/workspace/MeuApp.ipa + MeuApp-port.md (relatório das adaptações)
```

O que ele faz automaticamente:
1. **Coleta** os `.swift` do target iOS (pula pastas mac/tests/previews e `import AppKit`).
2. **Pré-adapta**: entry point (`@UIApplicationMain` → arquivo `*Main.swift` com a
   chamada `UIApplicationMain(...)` no final) e imports na ordem canônica
   (`Foundation → SwiftUI → UIKit → CoreText → Dispatch`).
3. **Loop de build reativo** (≤10 iterações): cada erro de compilação conhecido é
   corrigido na linha exata e o build repete — até passar ou sobrar erro
   desconhecido. Fixes cobertos: membros de `CGRect`/`CGAffineTransform`/`CGPoint`/
   `CGSize` (`.width` → `.cgWidth`, `CGRect.zero` → `cgRectZero`, insetBy/union/
   intersects/contains...), init `CGRect(x:y:width:height:)` → `cgRect(...)`,
   `UIEdgeInsetsMake` → init com labels, `TimeInterval` → `Double`, imports
   faltando (`CoreText` p/ `NSAttributedString.Key`, `Dispatch` p/ `DispatchQueue`,
   `Foundation` p/ math e tipos ObjC), `sync` ambíguo (rótulo `operation:`),
   prefixo `CasePaths.`, macro `@TaskLocal`, erros **fantasma** (tipo some com
   import presente → retry do build).
4. Inclui **sempre** o `PureSwiftKit.swift` no build (use `--no-kit` se o app não
   usa os helpers e o kit quebrar em módulos grandes) e valida o IPA no final.

### Flags úteis (casos de terceiros — ver references/PORTING-TERCEROS.md)
```sh
--extra DIR             # fontes extras (dependências SPM clonadas)
--resources DIR         # copia recursos (ROMs, JSONs etc.) para o .app
--strip-imports "A B"   # remove imports de módulos unificados (incl. @_exported)
--exclude "X.swift"     # exclui arquivos (basename)
--no-kit                # não inclui o PureSwiftKit
--merge-mode dep|subdir # agrupamento da concatenação anti-instabilidade
```

O port também trata automaticamente projetos UIKit com `@main class AppDelegate`,
`SceneDelegate`/`UIScene` e `Main.storyboard`: recria a janela e o root view
controller em código (não há `ibtool` no iSH), injeta o `UIApplicationSceneManifest`
no `Info.plist`, copia `--resources` para o bundle e **reassina depois** dessas
alterações. Isso foi validado com o `Chip8Kit` (emulador CHIP-8 para iOS).

### Casos especiais (resumo — guia completo em PORTING-TERCEROS.md)
- **`@main struct X: App` NÃO funciona** (conflito com main.swift + degrada tipos
  Foundation) → converter para AppDelegate + UIApplicationMain + UIHostingController.
- **Dependências SPM (TCA 0.x etc.)**: clonar árvore + **build multi-módulo**
  (ver seção abaixo). TCA 1.x usa macros → não portável.
- **Macros** (`@TaskLocal`): sem plugin → remover atributo / excluir arquivo.
- **Conflitos de tipos entre deps** (ex: `Box` no TCA e no CustomDump): excluir.
- **`-swift-module-file=X=path`**: SEMPRE 1 arg (2 args = "unknown argument").

O repo original NUNCA é editado (tudo numa cópia em /tmp/port-<App>).

## Apps com dependências SPM → MÓDULO ÚNICO + `-primary-file` (2026-08-22)

✅ **Validado em runtime:** `Minesweeper.ipa` (TCAminesweeper + TCA 0.39.1 + 6
pacotes, 27k linhas) **abre e joga** no LiveContainer.

```sh
# 1. compila arquivo-a-arquivo (destrava o type-checker), 3 jobs
python3 scripts/build-parallel.py --module <App> --src <src_dir> --out /tmp/obj --jobs 3
# 2. linkar todos os .o com as flags do build-pure-ui.sh (main.o primeiro)
```

### 🔑 A regra que destrava builds "travados": `-primary-file`
Build **60 min sem terminar, com 0% de CPU** NÃO é OOM nem "arquivo grande
demais" — é o **type-checker em modo whole-module** explodindo com inferência
genérica. Arquivo-a-arquivo, o mesmo conjunto sai em minutos.

| Sintoma | Causa | Ação |
|---|---|---|
| processo vivo, **0% CPU**, sem `.o` | type-checker whole-module | `-primary-file` |
| processo morto, rc<0, sem mensagem | OOM real | menos jobs (máx **3**) |
| `module file ... Cannot allocate memory` | OOM disfarçado | menos jobs |
| erro some/volta entre execuções | módulo carregado corrompido | retry (automático) |

Regras associadas (medidas — ver `references/TYPECHECKER-E-MULTIMODULO.md`):
- **máx. 3 jobs** paralelos (cada frontend carrega ~90 módulos);
- `#available` no código → inclua `assets/PlatformVersionShim.swift`
  (senão `undefined symbol: ___isPlatformVersionAtLeast` **no link**);
- inferência pesada trava: `Self(...)` com `.membro` implícito,
  `UserDefaults.set(Data?, ...)`, `Effect.result { .success(x) }` em init
  multi-parâmetro → reescreva com tipos nominais explícitos;
- `pkill -9 -f swift-frontend` entre diagnósticos (zumbis enganam).

> 🔴 `scripts/build-multimodule.sh` está **DEPRECADO** (2026-08-23). Não é só
> "não validado": ele **quebra**. Importar um módulo separado degrada o
> bridging `String`↔`NSString` no módulo do app — um `l.text = "literal"` vira
> `error: cannot assign value of type 'String' to type 'NSString'`, e o mesmo
> arquivo **sem** o import compila normalmente. Era essa a causa da tela preta
> em todos os apps que ele gerou. Use módulo único + `-primary-file`.

Validado em 2026-08-19/22: SwiftUI-2048 (unixzii, 732⭐) e TCAminesweeper
(RogyMD, TCA 0.39.1 + 6 deps) portados sem editar os repos originais.

✅ **Runtime PROVADO no device (LiveContainer, 2026-08-19):** quatro apps
rodaram — `PureSwiftDemo` (UIKit), `SwiftUIDemo` (SwiftUI), `ResumoFit v8.1`
(app completo: SQLite, document picker, gráficos CoreGraphics, 4 abas) e o
**`TortureTest`, que passou 37/37** exercitando justamente as áreas degradadas
pelos patches. A tese está validada de ponta a ponta.

## 🔬 Quando o app compila mas NÃO funciona — protocolo de diagnóstico

Antes de mudar qualquer coisa, siga esta ordem. Ela existe porque violá-la
custou uma sessão inteira.

### 1. Leia os warnings (30 segundos, resolve a maioria)
```sh
python3 scripts/check-warnings.py --dir <dir com *.err>
grep -c "nearly matches" *.err
```
`nearly matches optional requirement` = **o método nunca será chamado**.
Ver `references/WARNINGS-FATAIS.md`.

### 2. Classifique o sintoma com precisão
| Sintoma | Significa | Suspeito |
|---|---|---|
| "returned from main with code 0" | `_main` vazio | falta `UIApplicationMain(...)` |
| App **morre** no launch | dyld/símbolo | `check-undefined.py` + crash log |
| App **abre, fica vivo**, tela preta | roda mas não desenha | **delegate nunca chamado** (nº 1) |
| Tela preta só em parte da UI | lógica/estado | aí sim, investigar o app |

### 3. Bissecte com apps MÍNIMOS, nunca com o app inteiro
Um build do app grande custa ~10 min e devolve **1 bit**. Um app de 15 KB
compila em segundos. Parta de algo que **sabidamente abre** e adicione **um
fator por vez** (uma dylib, um protocolo, um framework).

### 4. Regras para os apps de teste
- **Cor de fundo distinta em cada um** (azul/verde/roxo). "Preto" é ambíguo
  entre "não rodou" e "rodou e não desenhou".
- **Log síncrono** no `viewDidLoad`, **nunca** via `DispatchQueue.main.async` —
  se a view nunca aparecer, o bloco assíncrono nunca roda e você não vê nada.
- Escreva na tela, não em arquivo: você não tem acesso ao FS do app no device.

### 5. Só confie em runtime
Um IPA que passa em `validate-ipa.sh` (Mach-O, SDK, símbolos, CDHash)
**não é** um app que funciona. Enquanto um caminho de build novo não tiver
**pelo menos um app aberto no device**, ele é hipótese — documente como tal.

### Ferramentas de forense
| Script | Responde |
|---|---|
| `check-warnings.py` | há warning que quebra o app em runtime? |
| `check-entry.py` | ⭐ **o binário vai iniciar?** (thunk ObjC do delegate + `_main`) |
| `check-protocol-sig.py` | qual a assinatura REAL deste delegate no meu SDK? |
| `check-undefined.py` | falta algum símbolo que o dyld exigiria no launch? |
| `validate-ipa.sh` | o IPA está bem formado? (necessário, não suficiente) |

## Reprodutibilidade do SDK

Os `.swiftinterface` do SDK precisam de correções para compilar com o toolchain
swift.org. Elas estão versionadas como diffs em
`/var/minis/shared/darwin-sdk/patchset/` (8 patches + README):

```sh
apk add patch
scripts/apply-patchset.sh /caminho/do/iPhoneOS26.5.sdk   # idempotente
scripts/make-patchset.sh  <outdir>                       # regerar da VM
```
Validado: aplicar sobre o SDK original reproduz os interfaces da VM byte a byte.

## Limitations & how to address them

Estado atual e próximos passos: **`references/HANDOFF.md`** (ponto de retomada).
Detalhe histórico em `references/LIMITATIONS.md` e
`references/linux-vm/ESTADO-E-NEXT-STEPS.md`. Summary:
1. **Degradações do SDK patchado.** Alguns tipos Swift viraram tipos ObjC crus
   (`NSDictionary`, `NSIndexPath`) e membros `@_alwaysEmitIntoClient` do
   CoreGraphics ficam invisíveis. → `assets/PureSwiftKit.swift` +
   `scripts/check-protocol-sig.py`. Nunca escreva delegate de memória.
   Caso especial: **CoreGraphics faz o Foundation sumir de outros arquivos**
   em whole-module → use o padrão `--primary-file`
   (`references/WARNINGS-FATAIS.md`).
2. **Ad-hoc signature only.** Installs need re-signing (AltStore/Sideloadly) or
   a jailbroken device. → `references/LIMITATIONS.md` §3 for real-cert signing.
3. **Startup race + slow first compile.** → retry wrappers; be patient.
4. **Mac needed once** for the SDK bundle. → `references/BOOTSTRAP.md`.
5. **Debug no device (resolvido para LiveContainer + StikDebug)** — use `--debug`, que preserva `get-task-allow`, instrumenta logs/overlay DBG e abre o URL oficial do StikDebug para o PID atual. Não há debugger funcional em iSH; o attach/console ocorre no device pelo StikDebug.

- `references/NATIVE-INTELLIGENCE.md` — NaturalLanguage, Foundation Models,
  arm64/arm64e, Core ML e bridges ObjC.

- `scripts/build-pure-ui.sh` — **app 100% Swift (UIKit/SwiftUI) → IPA**.
  Roda a guarda de warnings fatais automaticamente. Desde 2026-08-23 usa
  `--primary-file` por padrão com 2+ arquivos (`--whole-module` força o antigo).
- `scripts/link-ipa.sh` — **linka os `.o`, assina e empacota o IPA**. É o par
  do `build-parallel.py` (que só produzia objetos). Aceita `--debug`,
  `--resources DIR`, `--main-obj NAME`.
- `scripts/regression-suite.sh` — 🛡️ **bateria de regressão**: compila os
  assets nos dois modos e falha se o modo padrão quebrar. Inclui o caso
  `cgfoundation`, que reproduz o bug "CoreGraphics degrada Foundation".
  **Rode após mexer em qualquer script de build.**
- `scripts/verify-pureswiftkit.sh` — confere se o `PureSwiftKit.swift` ainda
  cobre todas as degradações catalogadas.
- `scripts/extract-uikitcore-tbd.sh` — gera o `.tbd` do UIKitCore, necessário
  para linkar as classes genéricas do UIKit (chamado pelo build).
- `scripts/audit_failures.py` — audita o resultado do `probe_api.py`.
- `scripts/probe_file.sh` / `scripts/probe_multifile.sh` — comparam resolução
  de nomes com 1 vs N arquivos (foram as ferramentas que expuseram a
  degradação cross-file).
- `scripts/build-parallel.py` — compila um módulo **arquivo-a-arquivo**
  (`-primary-file`, 3 jobs, retry de OOM/fantasma, guarda de warnings).
  **É o que destrava builds que ficam presos no type-checker.**
- `scripts/check-warnings.py` — 🛡️ **promove a ERRO os warnings que geram apps
  quebrados** (assinatura de protocolo divergente = tela preta). Integrado aos
  builds.
- `scripts/check-entry.py` — 🛡️⭐ **verifica no BINÁRIO se o app vai iniciar**
  (thunk ObjC do delegate + `_main` com `UIApplicationMain`). Não depende do
  warning (que é inconstante). Integrado ao build; validado em 6 IPAs.
- `scripts/check-protocol-sig.py` — mostra a assinatura **real** de um
  protocolo/membro no SDK patchado. **Consulte antes de escrever delegates.**
- `scripts/check-undefined.py` — confere os símbolos indefinidos do binário
  contra os `.tbd` do SDK (pega o que o lld aceita e o dyld recusaria).
- `assets/AppEntry.swift` — **template do entry point** (assinatura correta).
- `assets/PlatformVersionShim.swift` — `__isPlatformVersionAtLeast`
  (necessário quando o código usa `#available`).
- `references/WARNINGS-FATAIS.md` — 🔴 **compila mas não funciona**: causas,
  defesas automáticas e receita de investigação.
- `references/BUG-REPRO-MINIMOS.md` — casos mínimos reduzidos (degradação
  cross-file do Foundation, bridging quebrado por módulo importado, crash do
  SILGen), prontos para report upstream ou re-verificação.
- `references/TYPECHECKER-E-MULTIMODULO.md` — **por que builds travam** e como
  destravar (`-primary-file`, limites de job, padrões de código a reescrever).
- `scripts/build-multimodule.sh` — deps como módulo separado.
  🔴 **DEPRECADO (2026-08-23)**: o módulo separado degrada o bridging
  `String`↔`NSString` → apps quebrados / tela preta. O script agora recusa
  rodar sem `ISB_ALLOW_MULTIMODULE=1`. Use módulo único +
  `build-parallel.py` + `link-ipa.sh`.
- `scripts/fix-loop-mm.py` — loop reativo de fixes no modo multi-módulo.
- `scripts/port-third-party.py` — **porta apps de terceiros do GitHub (1 comando,
  loop de build reativo com fixes automáticos)** — ver seção acima.
- `scripts/probe_api.py` — catálogo de **101 APIs**; **79/101 compilam**
  (re-medido em 2026-08-26). Das 22 que falham, **15 são cobertas pelo
  `assets/PureSwiftKit.swift`** (CGRect/CGContext/insets); o resto exige
  workaround local (FileManager+UIKit, TimeInterval+UIKit, NSAttributedString.Key,
  DispatchQueue sem import).
- `scripts/make-patchset.sh` / `scripts/apply-patchset.sh` — patch-set do SDK.
- `scripts/test_import_ish.py` — testa `import UIKit`/`SwiftUI` no iSH.
- `scripts/sync-sdk-mtimes.py` — alinha mtimes do SDK (necessário p/ os .pcm).
- `scripts/benchmark-build.sh` — mede tempo/tamanho local de `none`, `O` e
  `Osize` (não mede performance no device). Neste toolchain, `Osize` foi pior
  que `O` em tempo (42 s vs. 26 s) e tamanho (77.312 B vs. 76.328 B).
- `scripts/bootstrap.sh` — bootstrap idempotente em etapas; exige hashes/artefatos do usuário.
- `scripts/bootstrap-glibc.sh` — monta o runtime glibc aarch64 a partir de `.deb` Ubuntu arm64 fornecidos pelo usuário, com verificação SHA-256.
- `scripts/verify-docs.sh` — verifica sintaxe, política pública e afirmações verificáveis.
- `scripts/scan-dependencies.sh` — gera grafo por target no Linux real.
- `scripts/check-module-cache.py` — valida PCMs/Swiftmodules transferidos.
- `scripts/benchmark-device-build.sh` — gera variantes none/O para medir no device.
- `scripts/benchmark-build.sh` — mede tempo/tamanho local de `none`, `O` e
  `Osize` (não mede performance no device). Neste toolchain, `Osize` foi pior
  que `O` em tempo (42 s vs. 26 s) e tamanho (77.312 B vs. 76.328 B).
- `scripts/bootstrap.sh` — bootstrap idempotente em etapas; exige hashes/artefatos do usuário.
- `scripts/bootstrap-glibc.sh` — monta o runtime glibc aarch64 a partir de `.deb` Ubuntu arm64 fornecidos pelo usuário, com verificação SHA-256.
- `scripts/verify-docs.sh` — verifica sintaxe, política pública e afirmações verificáveis.
- `scripts/scan-dependencies.sh` — gera grafo por target no Linux real.
- `scripts/check-module-cache.py` — valida PCMs/Swiftmodules transferidos.
- `scripts/benchmark-device-build.sh` — gera variantes none/O para medir no device.
- `assets/PureSwiftDemo.swift`, `assets/SwiftUIDemo.swift` — templates puros.
- `references/HANDOFF.md` — **ponto de retomada (leia primeiro)**.
- `references/PURE-SWIFT-UI-STATUS.md` — ressalvas e degradações medidas.
- `references/BUG-REPORTS-2026-08-19.md` — **bug reports com logs passo a passo**
  (entry point vazio/"code 0", CGContext, TimeInterval, FileManager, CGRect,
  UIEdgeInsets) + padrão SQLite via @_silgen_name + runtime provado.
- `scripts/check-env.sh` — verify the toolchain is intact.
- `scripts/build-ipa.sh` — the end-to-end build (hybrid or `--pure`).
- `scripts/build-pure-foundation.sh` — compile+link pure-Swift app with
  Foundation/Dispatch (módulos 6.3.2; para 6.3.3 trocar SW/OUT — ver
  ESTADO-E-NEXT-STEPS.md §7).
- `scripts/check-debug-ipa.py` — 🐞 guarda de IPA de debug (`get-task-allow`, esquema e instrumentação).
- `assets/DebugSupport.swift` — logs, PID, detecção LiveContainer, overlay DBG e URL StikDebug.
- `assets/NativeNLBridge.m` + `assets/NativeEmbeddings.swift` — embeddings
  NaturalLanguage/NLEmbedding via bridge Swift/ObjC.
- `assets/FoundationModelsProbe.swift` — exemplo macro-free da IA on-device.
- `scripts/build-arm64-modules.sh` — gera o perfil completo quando o SDK fornece
  interfaces arm64; em SDKs arm64e-only use `--pcm-only` para regenerar os 59
  PCMs neutros. `--full` falha fechado com diagnóstico explícito quando não há
  interfaces arm64.
- `scripts/profile.sh` — seleção isolada `ISB_ARCH=arm64|arm64e`.
- `scripts/build-livecontainer.sh` — build totalmente local para LiveContainer:
  força arm64 (executável em dispositivos arm64e), usa o linker iSH e entrega
  IPA unsigned para o patch/re-sign do LiveContainer.
- `scripts/acceptance-suite.sh` — teste de aceitação/release totalmente local:
  recompila IPA, valida ambiente, Mach-O, entry point, invariantes do
  LiveContainer e testa negativamente a guarda de slice.
- `scripts/strip-arm64e-auth-relocs.py` — diagnóstico experimental; não usado
  pelo builder porque remove PAC.
- `references/NATIVE-INTELLIGENCE.md` — matriz e fluxo completo de IA nativa.
- `references/DEBUG-LIVECONTAINER-STIKDEBUG.md` — procedimento completo de instalação, JIT e console.
- `docs/README.md` — índice legado; o conteúdo canônico está em `references/`.
- `docs/DEBUG-LIVECONTAINER-STIKDEBUG.md` — ponteiro de compatibilidade para o guia em `references/`.
- `scripts/apply-vfs-fix.sh` — install the VFS overlay that fixes os_workgroup.
- `scripts/compile-stdlib.sh` — (re)build the iOS Swift stdlib from interfaces.
- `assets/AppLogic.swift`, `assets/AppShell.m` — starting templates.
- `references/TEST-PLAN-AND-LOCAL-REPRO.md` — plano de testes implementado, resultados e reposição do experimento arm64e.
- `references/CONTEXT.md` — the journey, decisions, and key learnings.
- `references/LIMITATIONS.md` — every limitation + concrete solution path.
- `references/DISPATCH-VIA-LINUX.md` — pure-Swift Foundation/Dispatch (SOLVED)
  + iSH symlinks que os módulos prebuilt exigem.
- `references/BOOTSTRAP.md` — rebuild the whole toolchain from zero (+ Mac step).
- `references/PUBLISHING.md` — copyright/licensing analysis for GitHub.
- `references/linux-vm/` — receita VM + orquestradores (6.3.2 e 6.3.3) +
  patches + **ESTADO-E-NEXT-STEPS.md (handoff obrigatório para nova sessão)** +
  PLANOS-UIKIT-SWIFT.md.
