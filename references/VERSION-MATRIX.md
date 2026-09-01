# Version matrix

| Host compiler | Target slice | SDK / minimum OS | Testado em | Status and evidence |
|---|---|---|---|---|
| Swift 6.3.2 | arm64 | iOS SDK 26.5 / iOS 26.0 | iPhone17,1 / iOS 26.6 / LiveContainer (versão não registrada) | production LiveContainer route; S3 recorded on the listed host |
| Swift 6.3.3 | arm64 | iOS SDK 26.5 / iOS 26.0 | iPhone17,1 / iOS 26.6 / LiveContainer (versão não registrada) | pure Swift UIKit/SwiftUI build; S3 runtime validated on the listed host |
| Swift 6.3.3 | arm64e | iOS SDK 26.5 / iOS 26.5 | iPhone17,1 / iOS 26.6 / LiveContainer (versão não registrada) | local PAC linker and module cache; FoundationModels generation S4 confirmed by user in this scenario |

## Não testado

- SDKs ou iOS diferentes de iOS SDK 26.5 e iOS 26.6, respectivamente.
- Outros modelos de iPhone/iPad e outros devices arm64e.
- iSH em iPad.
- Outras versões do LiveContainer; a versão exata do host usado nas validações
  históricas não foi registrada e, portanto, permanece desconhecida.
- Compatibilidade universal de `FoundationModels`: a disponibilidade depende do
  device, região, idioma e preparação do modelo.

As linhas acima descrevem evidência observada, não uma promessa de
compatibilidade. O Apple SDK e os módulos gerados são fornecidos pelo usuário e
não são distribuídos neste repositório. `ISB_SYSROOT` defaults to
`/opt/isb/sysroot`; espelhos locais podem ser selecionados explicitamente.
Mantenha caches isolados por arquitetura e regenere PCMs ao mudar o prefixo.

The `embedded/` host Swift directories were hidden during the Fase 5.2 test;
the complete arm64e acceptance still passed. They remain local cleanup
candidates.
