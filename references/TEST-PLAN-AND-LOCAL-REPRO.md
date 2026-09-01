# Plano de testes, melhorias e reposição local

> **Política:** [`BEST-PRACTICES.md`](BEST-PRACTICES.md) define o critério
> normativo de evidência S0–S4 e a ordem barata→cara. Este arquivo registra a
> aceitação e os comandos medidos em uma data específica.

Data da aceitação: 2026-08-28. Objetivo: manter um caminho de produção local
para compilar Swift/iOS no iSH e investigar arm64e sem misturar caches ou
substituir ferramentas funcionais prematuramente.

## 1. Critério de aceite

Um caminho só é considerado funcional quando:

1. compila a partir dos fontes;
2. gera uma IPA nova;
3. passa as guardas de Mach-O, SDK, entry point e assinatura/unsigned;
4. passa os testes negativos das guardas;
5. abre no dispositivo/LiveContainer quando esse runtime for o alvo.

Validação estática isolada não basta.

## 2. Execução normal — 100% local

```sh
cd /var/minis/skills/ios-swift-builder
sh scripts/check-env.sh
sh scripts/acceptance-suite.sh
sh scripts/build-livecontainer.sh MeuApp com.exemplo.meuapp main.swift
sh scripts/validate-ipa.sh /var/minis/workspace/MeuApp.ipa
```

`build-livecontainer.sh` força `arm64`, usa o `ld64.lld` do iSH e produz IPA
unsigned. Essa é a solução recomendada: iPhones arm64e executam arm64 e o
LiveContainer aplica sua transformação/reassinatura. Foi comprovada em iOS
26.6, iPhone17,1, com `LocalLCFinal.ipa`.

## 3. Suíte implementada

`acceptance-suite.sh` executa, em ordem:

- sintaxe de todos os shell scripts e Python;
- `check-env.sh` no perfil arm64;
- build novo local pelo caminho LiveContainer;
- `validate-ipa.sh`;
- `check-livecontainer.py` (`LC_MAIN`, segmentos e chained fixups);
- `check-slice.py` exigindo subtype exato;
- teste negativo que garante que arm64 não passa como arm64e;
- `regression-suite.sh --quick`, incluindo o reproducer
  CoreGraphics/Foundation (`primary-file` passa e `whole-module` falha como
  esperado).

Resultado medido nesta sessão: **ACCEPTANCE: PASS**.

## 4. Melhorias implementadas

- `check-slice.py` deixou de procurar somente a palavra `arm64`; agora lê
  `cputype/cpusubtype` do cabeçalho Mach-O e diferencia arm64, arm64_32 e
  arm64e.
- `check-livecontainer.py` lê os campos de `LC_MAIN` como 64-bit e exibe o
  `entryoff` real; a versão anterior exibia acidentalmente `stacksize`.
- A aceitação completa foi adicionada ao README, SKILL e HANDOFF.
- Os artefatos de SDK, módulos, toolchains, IPAs, objetos e assinaturas ficam
  fora do Git pelo `.gitignore`.

## 5. Arm64e/PAC experimental — reprodução local

O suporte upstream pesquisado é LLVM PR
[#188378](https://github.com/llvm/llvm-project/pull/188378), commit
`ac894343171b72f862b08b85983cd682bd1cedb6`. O backport foi aplicado numa árvore
isolada `/tmp/llvm19-lld`, contra LLVM 19 instalado pelo Alpine, com build em
`/tmp/arm64e-lld-local`.

A sequência reproduzível é:

```sh
apk add clang19 llvm19-dev lld-dev cmake ninja
# obter o commit do PR numa árvore de fontes LLVM/LLD
# aplicar os patches de compatibilidade LLVM19 documentados no HANDOFF
cmake -G Ninja -S /tmp/llvm19-lld/lld -B /tmp/arm64e-lld-local \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_FLAGS_RELEASE='-O0 -DNDEBUG -fno-inline -fno-omit-frame-pointer' \
  -DLLVM_DIR=/usr/lib/llvm19/lib/cmake/llvm \
  -DLLD_BUILD_TOOLS=ON -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_TARGETS_TO_BUILD=AArch64
ninja -C /tmp/arm64e-lld-local -j1 lldMachO
```

Na prática, o backend Mach-O compilou a maior parte dos objetos, mas o Clang
19 abortou em `InputFiles.cpp` com `std::bad_alloc`. O iSH tem 4 GB e o kernel
não implementa `swapon`. O linker `/usr/bin/ld64.lld` e o linker Darwin em
`/opt/ios-toolchain/darwin-toolset/bin/ld64.lld` **não foram alterados**.

Portanto, o resultado correto é manter esse experimento fora do caminho de
produção. O caminho arm64e avançado continua usando o LLD PAC já construído
num Linux real via `link-remote-arm64e.sh`; o caminho LiveContainer continua
inteiramente local arm64. Um linker local arm64e futuro só pode ser ativado
após passar `acceptance-suite.sh` e um teste real no dispositivo.

## 6. Reposição limpa

1. Restaurar/aplicar o SDK patchado com `scripts/apply-patchset.sh`.
2. Restaurar o cache correspondente à tripla e ao compilador — nunca misturar
   `foundation-build633` com `foundation-build633-arm64e`.
3. Recriar `${ISB_SYSROOT:-/opt/isb/sysroot}` e `${ISB_MODULE_CACHE:-/var/tmp/isb-cache}` conforme
   `references/BOOTSTRAP.md` e os orquestradores em `references/linux-vm/`.
4. Rodar `check-env.sh` nos perfis necessários.
5. Rodar `acceptance-suite.sh` antes de gerar apps reais.
6. Somente depois executar `build-livecontainer.sh`.

Nenhum `.swiftmodule`, `.pcm`, `.tbd`, SDK, IPA ou linker experimental é
necessário dentro do repositório para o procedimento ser auditável.
