# Version matrix

| Host compiler | Target slice | SDK / minimum OS | Testado em | Status and evidence |
|---|---|---|---|---|
| Swift 6.3.3 | arm64e | iOS SDK 26.5 / iOS 26.5 | iPhone17,1 / iOS 26.6 / LiveContainer (versão não registrada) | arm64e.v1/PAC; 10 IPAs da aceitação final desta correção passaram S2 estrutural; S3/S4 históricos confirmados pelo usuário para UI, Foundation/Dispatch, TortureTest 37/37, debug, hybrid, CoreML/Vision/Accelerate, FoundationModels, NaturalLanguage e NLEmbedding |

## Não testado / fora da matriz operacional

- Outros modelos de iPhone/iPad e iSH em iPad.
- Outras versões do iOS, SDK ou LiveContainer; a versão exata do LiveContainer
  desta validação não foi registrada.
- Disponibilidade universal do FoundationModels: depende de região, idioma,
  modelo do device e preparação do modelo.

O perfil arm64e/PAC é o único perfil operacional e de release.
As linhas acima descrevem evidência observada, não uma promessa de
compatibilidade. O Apple SDK e os módulos gerados são fornecidos pelo usuário e
não são distribuídos neste repositório. `ISB_SYSROOT` defaults to
`/opt/isb/sysroot`; espelhos locais podem ser selecionados explicitamente.
Mantenha caches isolados por arquitetura e regenere PCMs ao mudar o prefixo.

The `embedded/` host Swift directories were hidden during the Fase 5.2 test;
the complete arm64e acceptance still passed. They remain local cleanup
candidates.
