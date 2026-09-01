# HANDOFF — retomada dos itens externos e pendências finais

**Projeto:** `forge-on-glass` / `ios-swift-builder`  
**Data do estado:** 2026-09-01  
**Último commit público:** `125e2f1` — `Record external VM reproducibility validation`  
**Árvore esperada:** limpa  
**Objetivo deste handoff:** permitir que uma nova conversa continue sem repetir auditorias, sem perder evidência e sem publicar artefatos licenciados.

> Leia primeiro `SKILL.md`, `references/BEST-PRACTICES.md`, este arquivo e os
> relatórios `references/VALIDATION-2026-09-01.md` e
> `references/VALIDATION-VM-2026-09-01.md`.

---

## 1. Regras não negociáveis

1. Não confiar na documentação como estado atual: executar `git status`,
   `check-env.sh`, regressão e um build novo.
2. Toda afirmação deve declarar S0–S4:
   - **S0:** hipótese/planejado;
   - **S1:** compilou;
   - **S2:** IPA passou validações estruturais;
   - **S3:** IPA nova abriu no device/LiveContainer;
   - **S4:** fluxo funcional exercitado no device.
3. Nunca concluir travamento por `/proc`, CPU ou RSS do iSH.
4. Não misturar caches arm64 e arm64e.
5. Não commitar `.sdk`, `.tbd`, `.pcm`, `.swiftmodule`, `.swiftinterface`,
   `.ipa`, `.o`, `.dylib`, toolchain, patchset de SDK, credenciais ou arquivos
   gerados grandes.
6. O build normal não deve depender de SSH, VM ou rede.
7. O SDK Apple e o cache de módulos são fornecidos pelo usuário e devem ser
   gerados/obtidos sob a licença aplicável.
8. Executar suítes serialmente: `regression-suite.sh` e as suítes de aceitação
   usam diretórios temporários fixos e podem corromper resultados se rodarem em
   paralelo.

---

## 2. Estado público atual

O histórico antigo foi recriado antes da publicação pública. O histórico
contaminado permanece somente fora do repositório, em bundle/diretório privado.
Não usar nem copiar esse histórico para o GitHub.

Commits relevantes recentes:

```text
125e2f1 Record external VM reproducibility validation
baa04f2 Complete VM bootstrap and device validation tools
9c26511 Integrate AI diagnostic into arm64e acceptance
20c19a0 Harden incremental keys and public documentation
6cc19ec Add FoundationModels runtime diagnostic
124b801 Complete reproducibility and pending diagnostics
```

O repositório público contém somente código/documentação original. A guarda
pública já passou com 122 arquivos rastreados:

```text
python3 scripts/check-repo-clean.py  → REPO CLEAN: PASS
sh scripts/verify-docs.sh             → DOCS: PASS
```

Não há host, usuário pessoal, chave privada, SDK ou binário derivado rastreado.
Ainda não existe remote Git configurado; não fazer `git push` até o usuário
fornecer a URL do repositório público.

---

## 3. O que já foi implementado

### Build e guardas

- `-primary-file` continua sendo o padrão para 2+ fontes.
- `ISB_OPT=none|O|Osize`; padrão `O`.
- `-dead_strip` no linker.
- `ISB_STRIP=1` opcional, antes das guardas e assinatura.
- `check-entry.py` identifica Swift por metadado Mach-O e não faz downgrade
  inseguro para ObjC após strip.
- Matriz de regressão cobre Swift válido, Swift strippado e delegates inválidos.
- `acceptance-suite.sh` mostra o log no terminal.
- `ISB_WORKSPACE`, `ISB_OUTPUT`, `ISB_SYSROOT` e caches isolados são suportados.

### Publicação e segurança

- `NOTICE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`.
- `.github/workflows/static.yml` com sintaxe shell/Python e guardas.
- `scripts/check-repo-clean.py` e wrapper `.sh`.
- Patchsets Apple permanecem fora do repositório e o gerador avisa que seu
  conteúdo contém texto licenciado do SDK.
- `scripts/verify-docs.sh` testa afirmações verificáveis da documentação.

### Reprodução

- `bootstrap.sh` e `scripts/bootstrap.sh`: etapas idempotentes, checksums
  obrigatórios para downloads e nenhuma redistribuição automática do SDK.
- `REPRODUCE-FROM-ZERO.md`: receita pública do zero.
- `references/VERSION-MATRIX.md`: Swift/SDK/target/perfil.
- `scripts/scan-dependencies.sh`: scanner de grafo por target no Linux real.
- `scripts/check-module-cache.py`: rejeita PCMs vazios ou com `/home/`.
- `Dockerfile` e `references/LINUX-MODULE-CACHE.md`: runner opcional Linux com
  mounts explícitos de Swift, SDK, VFS, grafo e saída.
- `scripts/build-parallel.py --incremental` + `ISB_INCREMENTAL=1`: cache de
  objetos com chave de fontes, flags, target, compilador, SDK, VFS, caminhos e
  bytes dos módulos.

### Diagnósticos

- `assets/BenchApp.swift` e `scripts/benchmark-device-build.sh`: geram IPAs
  `none` e `O` para instalar no device e comparar tempos exibidos na tela.
- `assets/FoundationModelsRuntimeMain.swift`: consulta disponibilidade,
  executa `LanguageModelSession.respond(to:)`, exibe resposta e latência e
  trata erros sem crash.
- `acceptance-suite-arm64e.sh` gera e valida estruturalmente esse diagnóstico.

---

## 4. Evidência já obtida

### Validação local serializada

Passaram no estado atual:

```text
check-module-cache.py       PASS (100 artefatos; 100 não vazios; 0 pessoais)
verify-docs.sh              PASS
check-repo-clean.py         PASS
regression-suite.sh --quick PASS
acceptance-suite.sh         PASS
acceptance-suite-arm64e.sh  PASS
benchmark-build.sh          PASS
benchmark-device-build.sh   PASS (duas IPAs S2)
```

A regressão reproduz intencionalmente a falha conhecida de `whole-module` com
CoreGraphics/`Bundle`; os casos `primary-file` passam.

Benchmark local mais recente, apenas compilação/tamanho no iSH:

```text
none   23s   97504 bytes executable   15045 bytes IPA
O      50s   76328 bytes executable   11110 bytes IPA
Osize  45s   77312 bytes executable   11530 bytes IPA
```

Esses números não são benchmark de runtime no device.

### Cache incremental

Validação já realizada:

```text
primeiro build de 2 fontes: 15s, 2 objetos compilados
segundo build: 0s, “incremental: reutilizando 2 objeto(s)”
executáveis descompactados: idênticos byte a byte
```

### Perfil arm64

- Caminho de produção: `build-livecontainer.sh`, guest arm64 unsigned.
- IPA nova passa Mach-O/SDK/slice/LC_MAIN/chained fixups/entry/delegate.
- S3 arm64/LiveContainer existe em registro anterior: iOS 26.6, iPhone17,1.
- A aceitação local atual é estrutural; não reclassificar S3 sem nova abertura.

### Perfil arm64e

- Swift 6.3.3 + SDK 26.5 + linker PAC local.
- `foundation-build633-arm64e`: 40 Swift modules + 60 PCMs consumidos no iSH.
- IPA arm64e usa subtype `0x80000002`.
- FoundationModels é weak-linked.
- NaturalLanguage e embeddings passam.
- O cache arm64e é S2; ainda não há S3 em runtime arm64e.

---

## 5. Trabalho externo feito na VM

A conexão SSH foi recuperada de sessões anteriores usando configuração/chave
local, sem colocar os dados da conexão neste repositório. Para uma nova conversa,
recupere os parâmetros somente de `memory_get`/`minis-sessions-cli` e valide a
conexão em `BatchMode`; nunca imprima chave, token ou segredo.

A VM confirmou:

- Ubuntu x86_64;
- Swift 6.3.3;
- SDK iOS 26.5;
- `tmux` disponível;
- sem Docker instalado;
- `scan-dependencies` embutido no Swift disponível;
- `fscan.json` arm64e disponível.

### Grafo e cache arm64e neutros

Foi executado na VM:

```text
scan público: 91 módulos
orchestrator_vm633.py: 93/93 módulos
```

Com paths neutros:

```text
ISB_VM_ROOT=/opt/isb/sysroot
ISB_VM_SW=/opt/isb/sysroot/swift-6.3.3
ISB_VM_SDK=/opt/isb/sysroot/iPhoneOS26.5.sdk
ISB_VM_VFS=/opt/isb/sysroot/vfs/overlay.yaml
ISB_VM_OUT=/opt/isb/sysroot/foundation-build633-arm64e-final
ISB_TARGET=arm64e-apple-ios26.5
```

Depois da transferência e remoção de logs `.err`:

```text
files=100
nonempty=100
neutral_refs=61
personal_refs=0
```

Um build local usando o cache neutro passou com:

```text
slice OK: arm64e subtype=0x80000002
LiveContainer invariants OK
check-entry: PASS
```

O SDK/VFS exige preservar tamanho e mtime dos headers. A receita usa:

```sh
# VM
python3 scripts/sync-sdk-mtimes.py dump "$SDK" > /tmp/mtimes.tsv
# iSH
python3 scripts/sync-sdk-mtimes.py apply "$SDK" /tmp/mtimes.tsv
```

O `os.modulemap` patchado e o VFS precisam permanecer separados por perfil:

- cache arm64 legado → espelho legado compatível;
- cache arm64e neutro → `/opt/isb/sysroot`.

Não apontar os dois caches para o mesmo `os.modulemap`.

### Tentativa arm64 na VM

Não foi possível gerar cache arm64 neutro com o material disponível. O SDK/grafo
atual da VM expõe interfaces arm64e; a tentativa com target arm64 foi rejeitada
pelo próprio Swift por incompatibilidade de arquitetura/`SwiftShims`. O cache
arm64 de produção permanece intacto e separado. Não converter um grafo arm64e em
arm64 artificialmente.

Para fechar esse item, obter um SDK/interface graph genuinamente arm64 e então:

```sh
ISB_TARGET=arm64-apple-ios26.0 \
ISB_VM_ROOT=/opt/isb/sysroot \
ISB_VM_SW=/opt/isb/sysroot/swift-6.3.3 \
ISB_VM_SDK=/opt/isb/sysroot/iPhoneOS26.5.sdk \
ISB_VM_VFS=/opt/isb/sysroot/vfs/overlay.yaml \
ISB_VM_OUT=/opt/isb/sysroot/foundation-build633-arm64-neutral \
FSCAN=/caminho/fscan-arm64.json \
python3 references/linux-vm/orchestrator_vm633.py
```

---

## 6. Próximos passos obrigatórios

### P0 — confirmar e preservar estado

```sh
cd /var/minis/skills/ios-swift-builder
git status --short
git log --oneline -12
sh scripts/verify-docs.sh
python3 scripts/check-repo-clean.py
```

Se a árvore estiver suja, não apagar alterações sem inspecionar o diff.

### P1 — push público

Pendente somente porque não existe URL/remoto configurado:

```sh
git remote add origin <URL_DO_REPOSITORIO_PUBLICO>
git push -u origin master
```

Antes do push:

```sh
git log --all -S '65.109' --oneline
git grep -nE '65\.109|/home/[A-Za-z]|BEGIN .*PRIVATE KEY' || true
python3 scripts/check-repo-clean.py
```

### P2 — runtime FoundationModels S4

IPA estrutural já pronta. Nova conversa deve:

1. localizar/abrir a IPA `FoundationModelsRuntime` gerada;
2. instalar pelo caminho que preserve o comportamento de debug/LiveContainer;
3. tocar **Gerar resposta**;
4. registrar `availability`, prompt exato, resposta, latência, device, iOS,
   arquitetura e host;
5. escrever um relatório novo no repo, sem dados sensíveis.

Só declarar S4 se `respond(to:)` realmente retornar texto no device.

### P3 — benchmark S4

```sh
ISB_WORKSPACE=/tmp/bench-device \
  sh scripts/benchmark-device-build.sh
```

Instalar ambas:

```text
BenchDevice-none.ipa
BenchDevice-O.ipa
```

Executar o mesmo fluxo no device, coletar os milissegundos exibidos e publicar
uma tabela com o host/device. Não confundir tempo de compilação com runtime.

### P4 — arm64e S3

Tentar uma vez em runtime compatível, com uma IPA nova e o host adequado. Se
falhar, manter arm64e congelado como S2 experimental e registrar erro/log. Não
alterar o linker arm64 de produção.

### P5 — cache arm64 neutro

Só executar se houver SDK/grafo arm64 compatível. Não reutilizar o `fscan.json`
arm64e. O cache arm64 legado já funciona e não deve ser destruído antes de uma
aceitação do novo cache.

### P6 — bootstrap glibc completo

O script já exige URLs/arquivos e SHA-256 para Swift/SDK. Ainda falta tornar a
montagem do loader glibc a partir de pacotes Ubuntu arm64 totalmente executável.
Isso pode ser implementado como etapa separada, exigindo explicitamente um
arquivo/espelho de pacotes e seus checksums; não baixar ou redistribuir glibc
silenciosamente.

---

## 7. Comandos de retomada rápida

### Estado local

```sh
cd /var/minis/skills/ios-swift-builder
sh scripts/check-env.sh
ISB_ARCH=arm64e sh scripts/check-env.sh
sh scripts/verify-docs.sh
python3 scripts/check-repo-clean.py
```

### Build arm64 de produção

```sh
sh scripts/build-livecontainer.sh Demo com.example.demo \
  assets/PureSwiftDemo.swift
sh scripts/validate-ipa.sh /var/minis/workspace/Demo.ipa
```

### Build arm64e neutro

```sh
ISB_ARCH=arm64e sh scripts/build-pure-ui.sh DemoE com.example.demoe \
  assets/SwiftUIDemo.swift --primary-file --unsigned
```

### Regressão/aceitação

```sh
sh scripts/regression-suite.sh --quick
sh scripts/acceptance-suite.sh
ISB_ARCH=arm64e sh scripts/acceptance-suite-arm64e.sh
```

Executar uma por vez.

---

## 8. Artefatos locais úteis

Não commitar estes arquivos:

```text
/opt/isb/sysroot/
/opt/ios-toolchain/foundation-build633/
/opt/ios-toolchain/foundation-build633-arm64e/
/var/tmp/isb-build-cache/
/var/minis/workspace/*.ipa
/tmp/accept-*/
/tmp/bench-*/
```

Relatórios versionados:

- `references/VALIDATION-2026-09-01.md`
- `references/VALIDATION-VM-2026-09-01.md`
- `references/LINUX-MODULE-CACHE.md`
- `references/FOUNDATIONMODELS-RUNTIME.md`
- `references/VERSION-MATRIX.md`

---

## 9. Critério de encerramento do plano

O plano só pode ser considerado completamente encerrado quando houver:

- remote público configurado e push confirmado;
- clone limpo que executa `verify-docs`, `bootstrap --check` e build;
- cache arm64e neutro reproduzível — já obtido e validado em S2;
- cache arm64 neutro, se o SDK/grafo arm64 for obtido;
- benchmark `none` vs `O` no device com dados S4;
- geração real `respond(to:)` com dados S4;
- decisão documentada sobre runtime arm64e S3 ou congelamento definitivo S2;
- nenhuma alteração pública contendo artefatos Apple/Swift ou segredos.

Até lá, a descrição honesta é:

```text
arm64 + LiveContainer: produção, S3 histórico
arm64e + cache neutro/PAC: S2 estrutural
FoundationModels link/diagnóstico: S2
FoundationModels geração real: S0/S1 até teste no device
benchmark local: S2/local; benchmark device: aguardando S4
```
