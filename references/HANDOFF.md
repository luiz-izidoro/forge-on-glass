# Handoff técnico — estado e retomada

> **Leia primeiro:** [`BEST-PRACTICES.md`](BEST-PRACTICES.md). Este arquivo é
> o inventário de estado e histórico operacional; não substitui as regras
> normativas. Claims abaixo devem ser interpretados com o nível S0–S4 definido
> no guia.


## 0.3. Política normativa de retomada

Para qualquer nova sessão, leia primeiro `references/BEST-PRACTICES.md`. Os
blocos abaixo são handoff histórico e podem conter números/paths de uma data
anterior. Não reutilize um comando ou artefato sem conferir o estado atual com
`git status`, `check-env.sh` e uma IPA recém-gerada.

`/opt/ios-toolchain/ld64.lld-arm64e`, compilado para Linux/aarch64 a partir do
LLVM PR #188378 e executado diretamente no iSH. Após o bootstrap, o build não
usa SSH, SCP ou VM.

Comandos canônicos:

```sh
sh scripts/acceptance-suite.sh
ISB_ARCH=arm64e sh scripts/acceptance-suite-arm64e.sh
```

A suíte arm64e gera e valida três IPAs novas: Foundation + FoundationModels,
NaturalLanguage Swift e embeddings via bridge Objective-C. Todas passaram com
Mach-O arm64e, subtype `0x80000002`, SDK/minOS 26.5, `LC_MAIN`, chained fixups,
entry point e frameworks linkados. O caminho LiveContainer arm64 permanece
intacto e validado em runtime no iOS 26.6/iPhone17,1.

> Histórico anterior abaixo: a referência a linker remoto não vale mais para
> o build normal; o LLD remoto é apenas bootstrap/recuperação.

## 0. 🟢 ESTADO 2026-08-28 — aceitação local concluída e arm64e isolado

Esta retomada fechou o plano de testes e melhorias solicitado. O caminho de
produção para o LiveContainer é agora explicitamente aceito como:

```sh
sh scripts/acceptance-suite.sh
sh scripts/build-livecontainer.sh MeuApp com.exemplo.meuapp main.swift
```

### Plano implementado e medido

| Etapa | Resultado |
|---|---|
| Sintaxe de todos os `.sh` e `.py` | ✅ PASS |
| `check-env.sh` nos perfis `arm64` e `arm64e` | ✅ READY; caches isolados preservados |
| Regressão rápida (`regression-suite.sh --quick`) | ✅ PASS; `primary-file` passa; falha `whole-module` conhecida reproduz |
| IPA nova pelo caminho 100% local | ✅ `/var/minis/workspace/LocalAcceptance.ipa` |
| `validate-ipa.sh` + `check-livecontainer.py` + `check-entry.py` | ✅ PASS |
| Guarda de arquitetura negativa | ✅ arm64 é rejeitado quando solicitado como arm64e |
| Runtime real | ✅ `LocalLCFinal.ipa` abriu no LiveContainer em iOS 26.6 |

Melhorias adicionadas nesta sessão:

- `scripts/acceptance-suite.sh`: aceitação/release reproduzível sem SSH, com
  build novo, validações estruturais e regressão.
- `check-slice.py`: agora lê `cputype/cpusubtype` do Mach-O e exige a slice
  exata; não confunde `arm64e` com `arm64` por substring.
- `check-livecontainer.py`: lê `LC_MAIN` como `uint64` e exibe o `entryoff`
  correto; antes imprimia o campo `stacksize`.

### Estado arm64e/PAC

O cache arm64e de 46/46 módulos continua válido e o LLD com suporte PAC de
LLVM PR #188378 continua reproduzível na VM via `link-remote-arm64e.sh`. A
tentativa de backport totalmente local foi mantida isolada em `/tmp` e não
substituiu o linker de produção: o Clang do iSH abortou com `std::bad_alloc`
ao compilar `InputFiles.cpp` do backend Mach-O, com 4 GB e sem `swapon`
disponível. Isso é uma limitação de recursos reproduzível, não uma falha do
patch PAC. O caminho LiveContainer não depende dela: usa arm64 unsigned local,
que já abriu no dispositivo arm64e. Nunca ativar o linker experimental sem
passar a suíte de aceitação e um teste runtime.

### Reposição local

A reposição não exige artefatos gerados no repositório: reaplicar os patches do
SDK com `scripts/apply-patchset.sh`, restaurar os caches correspondentes à
tripla/compiler, executar `check-env.sh`, e então `acceptance-suite.sh`.
Artefatos temporários, IPAs, SDKs, PCMs, toolchains e o backport LLD continuam
fora do Git por `.gitignore`.

---


> **LEIA ESTE ARQUIVO PRIMEIRO.** Ele substitui o `ESTADO-E-NEXT-STEPS.md`
> (que é histórico). Se você é uma IA retomando o trabalho: tudo que você
> precisa saber para continuar está aqui.

---

## 0. 🟢 ESTADO 2026-08-23 — auditoria + `-primary-file` como padrão

Sessão de auditoria: a skill foi validada **executando**, não lendo docs.
Resultado: o núcleo está saudável, mas o modo `--debug` estava **quebrado** e a
causa revelou um bug maior.

### 🔴 Bug encontrado e corrigido: CoreGraphics degrada Foundation

`build-pure-ui.sh --debug` não compilava:
`cannot find 'Bundle' / 'NotificationCenter' / 'OperationQueue' in scope`.

Causa (bissectada até caso mínimo determinístico, 3/3): em **whole-module**,
um arquivo que usa CoreGraphics faz os tipos ObjC do Foundation
**desaparecerem de OUTROS arquivos** do mesmo módulo. É **cross-file** — o
arquivo que reporta o erro pode não ter nenhuma linha de CoreGraphics.

**Descartados por teste:** `public`, `import Darwin`, ordem alfabética, string
literal grande, tamanho do arquivo, ordem dos imports.

**Solução:** `-primary-file`. O mesmo código, sem alteração, compila em 6 s.

### 🔑 O que mudou na skill

| Mudança | Arquivo |
|---|---|
| `--primary-file` virou **padrão** com 2+ arquivos | `build-pure-ui.sh` |
| Script de link/empacotamento (faltava!) | `scripts/link-ipa.sh` (novo) |
| Bateria de regressão nos dois modos | `scripts/regression-suite.sh` (novo) |
| `check-env.sh` valida os **dois perfis** + disco | `check-env.sh` |
| Frames CG isolados no fim do arquivo | `assets/DebugSupport.swift` |
| Documentação do bug | `references/WARNINGS-FATAIS.md` |

### Medição que sustenta a mudança (`regression-suite.sh`)

| Caso | `--primary-file` | `--whole-module` |
|---|---|---|
| UIKit 1 arquivo | ✅ 15s | ✅ 12s |
| SwiftUI 1 arquivo | ✅ 44s | ✅ 13s |
| App + PureSwiftKit | ✅ 49s | ✅ 18s |
| **App(CGRect) + Helper(Bundle)** | ✅ 31s | ❌ `cannot find 'Bundle'` |
| `--debug` | ✅ 36s | ❌ |

⚠️ `-primary-file` **não é só** "para app grande com genéricos pesados", como a
doc anterior dizia. Ele corrige uma **classe de degradação de resolução de
nomes** que atinge apps de 2 arquivos.

### ✅ RUNTIME PROVADO NO DEVICE (2026-08-23)

`B2Debug.ipa` — gerado pelo caminho **novo** (`build-parallel.py`
`-primary-file` → `link-ipa.sh`, modo `--debug`) — **abriu no LiveContainer
com o overlay azul DBG visível**.

Isso valida de ponta a ponta, em runtime:
- `-primary-file` como modo de compilação padrão;
- `link-ipa.sh` (link + `ldid` + empacotamento) — script novo;
- o modo `--debug` (que estava **quebrado**, sem compilar);
- `DebugSupport.swift` corrigido (bootstrap, overlay, `get-task-allow`).

⇒ O caminho `primary-file` deixou de ser hipótese e é **capacidade**.

### ⏳ Pendente
- Publicação no GitHub (`forge-on-glass`).
- `build-multimodule.sh` foi **DEPRECADO** (quebra o bridging String↔NSString;
  causa provável da tela preta em todos os apps que gerou).

---

## 0.0 Histórico: 2026-08-22 — apps com dependências SPM RODANDO NO DEVICE

`Minesweeper.ipa` (TCAminesweeper + TCA 0.39.1 + 6 pacotes, 27k linhas)
**abre e joga no LiveContainer**. Primeiro app com árvore de deps validado em
runtime.

### As DUAS causas que travaram esse port (independentes — não confunda)

**1. Build não terminava** — type-checker whole-module explodindo com
inferência genérica. Processo **vivo, 0% CPU**, sem `.o` após 60 min.
→ Fix: **`-primary-file`** (arquivo-a-arquivo). 60+ min → ~6 min.
→ `references/TYPECHECKER-E-MULTIMODULO.md`

**2. Build OK, app com TELA PRETA** — `application(_:didFinishLaunchingWithOptions:)`
não casa com o `.swiftinterface` patchado (`launchOptions` é `NSDictionary`
aqui). O requisito é **opcional**, então o Swift só **avisa** (às vezes nem
isso) e **não gera o thunk ObjC** → o UIKit nunca chama o método → janela
nunca criada → app vivo, tela preta, sem crash nem log.
→ Fix: **`applicationDidFinishLaunching(_:)`**
→ **`references/WARNINGS-FATAIS.md`** ← leia antes de escrever entry points

### Guardas automáticas (novas — os builds abortam sozinhos)
| Script | O que impede |
|---|---|
| `check-warnings.py` | warnings que produzem app quebrado |
| `check-entry.py` ⭐ | binário sem thunk ObjC no delegate / `_main` vazio |
| `check-protocol-sig.py` | escrever delegate "de memória" (consulte o SDK) |
| `check-undefined.py` | símbolo que o lld aceita e o dyld recusaria |

### Ferramentas de build
| Script | Para quê |
|---|---|
| `build-parallel.py` | **módulo arquivo-a-arquivo** (`-primary-file`, 3 jobs, retries) — destrava builds presos |
| `build-pure-ui.sh` | app simples → IPA (com as guardas) |
| `build-multimodule.sh` | 🔴 **DEPRECADO** — módulo separado degrada String↔NSString |
| `assets/AppEntry.swift` | template do entry point (assinatura correta) |
| `assets/PlatformVersionShim.swift` | `#available` (senão falha no link) |

### Regras medidas nesta sessão
1. `-primary-file` para código de app; whole-module só para módulos de declarações.
2. Import: `Foundation → SwiftUI → UIKit → CoreText → Dispatch → Combine`
   (**Dispatch depois de UIKit**, senão `DispatchQueue` perde o overlay Swift).
3. 1º arquivo do módulo precisa importar Foundation.
4. `-parse-as-library` em módulo de biblioteca (senão `duplicate symbol: _main`).
5. **Máx. 3 jobs** paralelos (`Cannot allocate memory` = OOM disfarçado).
6. Inferência pesada trava: `Self(...)` com `.membro`, `UserDefaults.set(Data?,...)`,
   `Effect.result { .success(x) }` → tipos nominais explícitos.
7. `pkill -9 -f swift-frontend` entre diagnósticos (zumbis enganam).
8. `PureSwiftKit` degrada em módulo grande → helpers mínimos locais.
9. `CGRectMake` não existe no SDK 26.5 (falha só no **link**) → `CGRect(origin:size:)`.

### 🔴 LIÇÃO DE PROCESSO (a mais importante desta sessão)
**Validação estática ≠ app que funciona.** Declarei uma sessão "concluída" com
o IPA passando em Mach-O/SDK/símbolos/CDHash — e o app nunca tinha aberto.
Depois passei horas em ciclos "compila → testa → preto" (10 min por **1 bit**
de informação) enquanto **a causa estava impressa no log do build desde o
primeiro minuto**, classificada como *warning*.

Regras que ficam:
- Enquanto um caminho de build não tiver **1 app aberto no device**, ele é
  hipótese — documente como tal. (O `build-multimodule.sh` era o caso; em
  2026-08-23 foi testado com um app de 19 linhas e REPROVADO.)
- **Leia os warnings antes de bissectar.**
- Bissecte com apps **mínimos** (15 KB, segundos), nunca com o app inteiro.
- Cor de fundo distinta por teste; log **síncrono** (nunca `main.async`).

Protocolo completo: **SKILL.md → "Quando o app compila mas NÃO funciona"**.

---

## 0.1 Histórico: o bloqueio anterior (resolvido acima)

> Mantido só como registro do diagnóstico ERRADO que custou 4 sessões: o
> "limite de ~45k linhas" não existe — o problema era o modo whole-module.
> As regras de ouro abaixo continuam válidas.

### Regras de ouro do port (armadilhas já pagas — ver PORTING-TERCEROS.md)
- `-swift-module-file=X=path` = SEMPRE 1 arg; main.swift PRIMEIRO na lista
- Erros "cannot find TYPE 'X'" têm "type" no meio — regex `(?: type)?`
- TimeInterval com Foundation importado = substituir por Double (não é fantasma)
- sync: renomear só o do CombineSchedulers → csSync; o do TCA em
  os_unfair_lock_t (Create.swift) NÃO pode ser renomeado
- CasePaths: shim `enum CasePaths { static func extract }` — nunca remover prefixo
- `@main struct X: App` → SEMPRE converter para UIApplicationMain
- Build script imprime só head -20 dos erros — ler swift.err do disco
- OOM = morte sem mensagem (rc<0) → retry; TRAVA (processo vivo, 0% CPU, sem
  .o) = type-checker explodindo → `-primary-file` + reescrever a inferência
  (§0 e `TYPECHECKER-E-MULTIMODULO.md`), NÃO "reduzir tamanho"

---

## 0.2 🐞 ESTADO ATUAL — debug via LiveContainer + StikDebug

A skill suporta debug em três camadas, todas validadas no desenvolvimento do
Chip8Emu:

```sh
python3 scripts/port-third-party.py /tmp/projeto MeuApp com.exemplo.meuapp \
  --debug --stikdebug-bundle-id com.kdt.livecontainer.A4658DGR7V
python3 scripts/check-debug-ipa.py /var/minis/workspace/MeuApp.ipa
```

1. **Trace visual:** registra na tela `viewDidLoad`, toques, callbacks,
   arquivos, carregamento e frames (`frame: ok lit=N`). Foi a camada que
   confirmou o Chip8: a ROM carregou e o pipeline Bitmap → UIImage → UIImageView
   renderizou.
2. **Attach/script:** registra `vAttach`, `qSupported`, `qfThreadInfo`, `qC`,
   pacote de registradores e detach.
3. **Sessão persistente:** mantém `c` aberto, registra paradas e continua. Para
   o contador avançar, o app precisa produzir sinais/breakpoints; `#1` parado
   não significa crash. Breakpoints instrumentados devem ser armados somente
   depois do toque em DBG.

O modo `--debug` inclui `assets/DebugSupport.swift`, preserva
`get-task-allow`, registra PID/bundle/`LC_HOME_PATH`, instala o overlay DBG e
abre a URL oficial. Em LiveContainer, o ID do convidado e o host são diferentes;
`--stikdebug-bundle-id` deve receber o ID real do host. O `universal.js` é
específico do protocolo JIT e não é logger genérico; em apps comuns pode ficar
em `Handling signal 1`.

**Validado no device:** Chip8Emu abriu, carregou INVADERS, mostrou
`frame: ok lit=119` e renderizou a tela. O StikDebug confirmou attach, threads,
thread atual e capacidade do debugserver. Documentação canônica:
`references/DEBUG-LIVECONTAINER-STIKDEBUG.md`.


**Os dois muros do projeto caíram.** `import UIKit` e `import SwiftUI` compilam
em Swift puro, e existem **dois IPAs 100% Swift validados**:

| IPA | O que prova |
|---|---|
| `/var/minis/workspace/PureSwiftDemo.ipa` | `import UIKit` puro (obj 58.408 B) |
| `/var/minis/workspace/SwiftUIDemo.ipa` | `import SwiftUI` puro (obj 62.008 B) |

| Capacidade | Estado |
|---|---|
| Swift puro + Foundation/Dispatch/Combine/os/simd/... | ✅ produção |
| **Swift puro + UIKit** | ✅ (1 ressalva: `CGRect`) |
| **Swift puro + SwiftUI / SwiftUICore** | ✅ |
| Híbrido Swift + ObjC/UIKit | ✅ produção (apps reais) |
| Patch-set do SDK reprodutível | ✅ validado byte a byte |
| IPA assinado ad-hoc | ✅ |
| **App rodando num device** | ✅ **PROVADO — TortureTest 37/37** |
| Assinatura com certificado real | ❌ fora de escopo |

### 🎉 Runtime 100% validado — o projeto atingiu seu objetivo

Quatro apps rodaram no **LiveContainer**: `PureSwiftDemo` (UIKit),
`SwiftUIDemo` (SwiftUI), `ResumoFit v8.1` (app completo com SQLite) e o
**`TortureTest`, que passou 37/37**.

O TortureTest exercita justamente as áreas degradadas pelos patches e **todas
funcionaram**, incluindo a de maior risco: a linha
`UICollectionView.dataSource respondeu ao ObjC runtime: numberOfItems via UIKit = 2`
prova que o UIKit consulta as classes genéricas através do runtime ObjC mesmo
após a remoção do `@objc` de 25 membros.

**Conclusão:** os patches nos `.swiftinterface` (incl. 10.012 linhas do
SwiftUICore) não degradam o comportamento no device — o dylib real do iOS tem as
implementações; o interface-compile só precisa das assinaturas. O pipeline
`forge-on-glass` é real ponta a ponta: escrever Swift no iPhone → IPA → app
rodando no iPhone, sem Mac.

Detalhes e tabela por área: `references/PURE-SWIFT-UI-STATUS.md`.

---

## 2. O que fazer agora (na ordem)

### 2.1 ✅ CONCLUÍDO — runtime provado (LiveContainer, 2026-08-19)
`PureSwiftDemo.ipa` rodou no device. Ver §1.

### 2.2 ✅ CONCLUÍDO — TortureTest 37/37 no device
Todas as áreas degradadas validadas em runtime. Ver §1 e
`PURE-SWIFT-UI-STATUS.md`.

### 2.3 🔴 AGORA — publicar no GitHub (`forge-on-glass`)
É o último item que agrega valor real. Tudo pronto: LICENSE preenchido,
`.gitignore` cobrindo o que não pode subir (SDK, foundation-build, binários
Apple), `PUBLISHING.md` com a auditoria legal, patch-set versionado.
Falta apenas `git init` + push.

### 2.4 Reportar o bug do SILGen ao swiftlang/swift (P3)
Repro mínimo pronto (§5). Ver `PLANO-2026-08-19.md` §6.

---

## 3. Infraestrutura — regras que NÃO podem ser esquecidas

### 3.1 VM (`$ISB_REMOTE_USER@$ISB_REMOTE_HOST`)
```bash
# jobs SSH MORREM ao desconectar. nohup NAO basta. setsid NAO basta. Use tmux:
tmux new-session -d -s nome "comando > /tmp/nome.log 2>&1; sleep 7200"
```
- `/tmp` é **tmpfs de 1,9 GB** → NUNCA aponte module cache para lá. Use
  `~/bigtmp/`. (Um "crash do compilador" que custou dias era só o tmpfs cheio:
  a mensagem real, `IO failure on output stream: Disk quota exceeded`, estava na
  ÚLTIMA linha do log.) **Sempre leia o FIM do log, não só o grep de `error:`.**
- Artefatos: `~/swift-ios-build/foundation-build633/` (95 arquivos: 38
  swiftmodule + 57 pcm). **NÃO APAGAR.**
- SDK de trabalho (com interfaces patchados): `~/swift-ios-build/iPhoneOS26.5.sdk`.
  O **original limpo** está no iSH.
- Toolchains: `swift-6.3.3` (em uso) e `swift-6.3.2` (fallback do version-lock).

### 3.2 iSH
Os `.pcm` gravam **paths absolutos** e **(tamanho, mtime)** de cada header.
Por isso o iSH precisa espelhar a VM:
```bash
${ISB_SYSROOT:-/opt/isb/sysroot}/iPhoneOS26.5.sdk -> /opt/ios-toolchain/iPhoneOS26.5.sdk
${ISB_SYSROOT:-/opt/isb/sysroot}/swift-6.3.3      -> /opt/swift6.3.3
${ISB_SYSROOT:-/opt/isb/sysroot}/vfs/{overlay.yaml,os.modulemap}  # overlay com paths ${ISB_SYSROOT:-/opt/isb/sysroot}/...
/opt/swift6.3.3/usr/lib/swift/{dispatch,os,CoreFoundation} -> headers do SDK
```
E os mtimes precisam bater:
```bash
# VM:  python3 sync-sdk-mtimes.py dump <sdk> > /tmp/mtimes.tsv
# iSH: python3 sync-sdk-mtimes.py apply /opt/ios-toolchain/iPhoneOS26.5.sdk /tmp/mtimes.tsv
```
Sem isso: `error: file X has been modified since the module file Y`.
(`-fno-validate-pch` e `-fbuild-session-timestamp` **não** resolvem — testado.)

---

## 4. As ressalvas do Swift puro (importantes)

Detalhe completo em `references/PURE-SWIFT-UI-STATUS.md`. **Leia antes de codar.**

### 4.0 ORDEM DOS IMPORTS (regra nº 0)
```swift
import Foundation   // sempre 1º
import SwiftUI      // se usar
import UIKit
import CoreText     // p/ NSAttributedString.Key
import Dispatch     // sempre DEPOIS de UIKit
```

### 4.1 CGRect: membros de conveniência não existem → `assets/PureSwiftKit.swift`
`minX`/`insetBy`/`union`/`.zero`/`.identity` são `@_alwaysEmitIntoClient` numa
extension do CoreGraphics → invisíveis. As funções C (`CGRectGetMinX`,
`CGRectInset`, ...) funcionam; `PureSwiftKit.swift` as embrulha.

### 4.1b Link: `-framework UIKitCore` é obrigatório
Símbolos Swift das classes genéricas do UIKit vivem no doc do UIKitCore dentro
do `UIKit.tbd` (multi-doc), que o lld não percorre. Já automatizado no
`build-pure-ui.sh` via `scripts/extract-uikitcore-tbd.sh`.

### 4.2 ✅ RESOLVIDO — era ORDEM DOS IMPORTS, não bridging quebrado
O que parecia "o UIKit quebra o bridging String↔NSString" era ordem de import:

```swift
import Foundation   // ✅ Foundation PRIMEIRO
import UIKit
label.text = "abc"  // funciona, sem workaround

import UIKit        // ❌ invertido
import Foundation
label.text = "abc"  // error: cannot assign 'String' to 'NSString'
```
**Regra: `import Foundation` sempre primeiro.** Nenhum workaround de NSString é
necessário (o `PureSwiftDemo.swift` foi simplificado por causa disso).

Caso residual menor: o **nome curto** `NSString` pode ficar ambíguo → qualifique
`Foundation.NSString`. Na prática, use `String`.

> **NÃO refaça** o rebuild de UIKit/SwiftUICore sem `-import-module`. O
> `bisect_bridge.py` provou que nenhuma combinação resolvia — e o problema nunca
> foi esse. Os módulos atuais estão corretos.

---

## 5. Os 10 mecanismos do bug de interface-compile

Os 8 primeiros estão em `ESTADO-E-NEXT-STEPS.md` §2. Os **dois novos** desta
sessão:

**#9 — `-import-module` cria dependências circulares.** Nos módulos novos
(CoreData, SwiftUI) as flags que ajudavam os antigos causam
`circular dependency between modules 'os' and 'XPC'/'CoreText'`. Solução: aplicar
só a uma allowlist — ou, melhor, usar `add_imports.py` (§4.2).

**#10 — o overlay Swift do XPC cria ciclo.** `-swift-module-file=XPC=...` gera
ciclo `os↔XPC`. Nenhum consumidor precisa dele (só do `clang_XPC.pcm`).
**Filtrar sempre** — inclusive ao compilar código de usuário.

### Ferramenta que automatiza tudo isso: `fix_loop.py`
Compila → lê o 1º erro → aplica a regra do mecanismo → repete.
Resolveu o SwiftUI em 2 iterações. Use para qualquer módulo novo:
```bash
python3 fix_loop.py <Modulo> 40    # grava /tmp/fixlog_<Mod>.json
```

---

## 6. Mapa de arquivos

### Scripts (skill `scripts/`)
| Arquivo | Para quê |
|---|---|
| `build-pure-ui.sh` | **app 100% Swift → IPA** (aceita vários .swift) |
| `probe_api.py` | mapeia quais APIs compilam (catálogo de 65) |
| `extract-uikitcore-tbd.sh` | gera o tbd do UIKitCore (necessário p/ linkar) |
| `probe_multifile.sh` | compara resolução 1 vs N arquivos |
| `build-pure-foundation.sh` | app Swift + Foundation (6.3.2) |
| `build-ipa.sh` | híbrido Swift + ObjC |
| `make-patchset.sh` | gera os diffs do SDK (VM → patchset versionado) |
| `apply-patchset.sh` | aplica os patches num SDK limpo (idempotente) |
| `test_import_ish.py` | testa imports no iSH |
| `sync-sdk-mtimes.py` | resolve mtime dos pcm (VM→iSH) |
| `cleanup-toolchain.sh` | limpeza conservadora; dry-run por padrão, sem promessa fixa de espaço |
| `validate-ipa.sh` | inspeciona um IPA |

### Templates (skill `assets/`)
`PureSwiftDemo.swift` (UIKit puro), `SwiftUIDemo.swift` (SwiftUI puro),
`PureSwiftKit.swift` (**helpers de CGRect — quase sempre necessário**),
`TortureTest.swift` + `TortureTestMain.swift` (46 testes de runtime),
`AppLogic.swift` + `AppShell.m` (híbrido).

### Patch-set do SDK
`/var/minis/shared/darwin-sdk/patchset/` — 8 diffs + README.
**Validado**: aplicar sobre o SDK original limpo reproduz os interfaces da VM
byte a byte. Precisa de `apk add patch`.

### Orquestração (skill `references/linux-vm/`, rodam na VM)
`orchestrator_vm633.py` (cadeia completa), `build_swiftui.py` (incremental),
`fix_loop.py` (auto-fix), `rebuild_clean.py` (sem `-import-module`),
`add_imports.py` (mecanismo #8), `rebuild_uikit.py`, `probe_indexpath.py`,
`patch_*.py` (patches por módulo), `sync-sdk-mtimes.py`.

### Documentação
| Arquivo | Conteúdo |
|---|---|
| **`HANDOFF.md`** (este) | ponto de retomada |
| `PURE-SWIFT-UI-STATUS.md` | ressalvas + degradações medidas |
| `NATIVE-INTELLIGENCE.md` | IA nativa, embeddings, perfis arm64/arm64e e rota LiveContainer |
| `TEST-PLAN-AND-LOCAL-REPRO.md` | plano de aceitação, melhorias e reposição local |
| `PLANO-2026-08-19.md` | plano completo + pesquisa |
| `ESTADO-E-NEXT-STEPS.md` | histórico (mecanismos #1–#8, patches) |
| `LIMITATIONS.md` | limitações gerais |
| `CONTEXT.md` | a jornada |

---

## 7. Dívidas técnicas conhecidas

1. ~~**Patches do SDK não versionados.**~~ ✅ **RESOLVIDO (sessão 4)** —
   `/var/minis/shared/darwin-sdk/patchset/` com 8 diffs + `make-patchset.sh` /
   `apply-patchset.sh`, validado byte a byte contra a VM.
2. **Runtime não verificado** (§2.1) — a maior pendência.
3. ~~**Bridging NSString**~~ ✅ **RESOLVIDO (sessão 4)** — era ordem de import (§4.2).
4. **Mac disponível é macOS 15.7.9 → Xcode até 26.3.** Nosso SDK é 26.5, gerado
   por um Xcode mais novo. O Plano C (pegar os `.swiftmodule` binários do Xcode)
   traria módulos 26.3 — **incompatíveis com o SDK 26.5 atual**. Só vale se o
   SDK também for regerado a partir do mesmo Xcode 26.3, o que muda a base
   inteira. **Custo/benefício ruim agora que UIKit e SwiftUI já compilam.**
5. **`@main struct App: App` (SwiftUI puro) não funciona** — depende de macros
   que não sobrevivem ao interface-compile. Workaround em uso: `UIApplicationMain`
   + `UIHostingController` (ver `assets/SwiftUIDemo.swift`). A UI continua 100%
   SwiftUI; só o ciclo de vida é UIKit.
6. **`fscan_swiftui.json` vive em `/tmp` na VM** (tmpfs, some no reboot).
   Backup: `~/fscan633.backup.json` é o scan ANTIGO (59 módulos), não o novo.
   Se sumir, regerar com `./scan_swiftui.sh`.
