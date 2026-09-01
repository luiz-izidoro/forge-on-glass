# P0 — relatório de execução e bloqueio arm64

**Data:** 2026-09-01  · **Base:** `c3fb2a3`  · **Execução:** `2b4f2fe` + `8821c46`

## Resultado

A Etapa 1 foi concluída. A Etapa 2 foi iniciada em um diretório novo, mas foi
interrompida conforme o plano depois de duas janelas de execução de uma hora.
O cache arm64 ativo nunca foi alterado ou promovido.

## Etapa 1 — concluída

- `bootstrap.sh --check` agora valida ambos os caches.
- O cache arm64 legado é reportado como `NOT-NEUTRAL`.
- O cache arm64e é reportado como `OK`.
- `check-sysroot-independence.sh` foi criado com `trap` de restauração para
  `EXIT`, `INT` e `TERM`.
- O teste destrutivo foi executado: falhou como esperado porque o PCM legado
  referencia o espelho pessoal ausente quando o diretório em `/home` é movido.
- A restauração e a limpeza do backup foram verificadas como `PASS`.

## Etapa 2 — bloqueio reproduzido

O gerador `scripts/build-arm64-modules.sh` foi executado com:

```text
ISB_TARGET=arm64-apple-ios26.0
ISB_VM_ROOT=/opt/isb/sysroot
ISB_VM_SW=/opt/swift6.3.3
ISB_VM_SDK=/opt/isb/sysroot/iPhoneOS26.5.sdk
ISB_VM_VFS=/opt/isb/sysroot/vfs/overlay.yaml
ISB_VM_OUT=/opt/ios-toolchain/foundation-build633-neutral
```

A varredura encontrou 91 módulos. A geração criou temporariamente 70 artefatos
não vazios, sem referências pessoais, mas não concluiu os módulos Swift de UI.
O erro determinístico emitido pelo Swift foi:

```text
failed to build module 'CoreGraphics'; this SDK is not supported by the compiler
(the SDK is built with Apple Swift version 6.3.2 ... while this compiler is
Swift version 6.3.3 ...)
```

As interfaces Swift disponíveis no SDK local são `arm64e-apple-ios.swiftinterface`;
não há interfaces `arm64-apple-ios` genuínas disponíveis nos caminhos locais
consultados. O teste adicional com o frontend Swift 6.3.2 também não concluiu
em dez minutos e não foi usado como base para promoção.

## Limpeza e preservação

- O candidato parcial `/opt/ios-toolchain/foundation-build633-neutral` foi
  removido somente depois de confirmar que não havia workers Swift ativos.
- O cache ativo `/opt/ios-toolchain/foundation-build633` foi preservado.
- O cache ativo arm64e `/opt/ios-toolchain/foundation-build633-arm64e` foi
  preservado.
- O espelho de SDK do usuário foi preservado e verificado.
- Nenhuma etapa de equivalência, promoção ou remoção do legado foi executada.
- Espaço livre após a limpeza: aproximadamente 3,2 GB.

## Níveis de evidência

- Guardas e script do gerador: **S1** — scripts compilam/verificam sintaxe.
- Cache arm64 neutro: **não alcançou S1 completo**; geração bloqueada.
- Cache arm64 legado: permanece no estado anterior, com S3 de runtime já
  registrado separadamente; não foi reclassificado.
- Nenhuma afirmação nova de S2/S3 foi feita para o cache candidato.

## Próximo desbloqueio

Obter um SDK/interface graph genuinamente arm64 compatível com o frontend usado,
ou uma receita comprovada para gerar o cache arm64 com a mesma identidade de
compiler/interface. Depois disso, reexecutar a Etapa 2 em diretório novo e só
prosseguir para equivalência após `personal_refs=0`, cobertura completa e todas
as guardas passarem.
