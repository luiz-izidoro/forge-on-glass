# Melhores práticas normativas — ios-swift-builder

> **Fonte normativa.** Este documento consolida as decisões que devem orientar
> novos projetos e novas sessões. Um documento histórico pode explicar como uma
> descoberta foi feita, mas não pode substituir estas regras. Estado consolidado
> em 2026-08-29.

## 1. Regra principal: declarar o nível de evidência

Nunca use “funciona” sem dizer **onde** foi verificado. Use esta classificação:

| Nível | Significado | Pode ser anunciado como |
|---|---|---|
| S0 | não compilado ou apenas hipótese | planejado/hipótese |
| S1 | compilou | compilado |
| S2 | IPA passou validações Mach-O, SDK, símbolos e assinatura | estruturalmente válido |
| S3 | IPA nova abriu no device/LiveContainer | runtime validado naquele host/device |
| S4 | fluxo funcional relevante foi exercitado no device | funcional no cenário testado |

`validate-ipa.sh`, `check-slice.py`, `check-entry.py` e chained fixups provam
S2; **não provam S3**. Um host LiveContainer transforma e reassina o Mach-O,
portanto a validação antes da importação não observa o arquivo efetivamente
carregado depois.

Ao atualizar documentação, registre sempre: data, commit, arquitetura, SDK,
versão do iOS/device, host (se houver), comando executado e resultado.

## 2. Escolha de arquitetura e caminho de build

### Perfil canônico

- Builds arm64e.v1/PAC are the only supported operational and release path.


### Caminho padrão para um app novo

1. Use um **módulo Swift único**.
2. Com dois ou mais arquivos, use `build-pure-ui.sh`, que usa
   `-primary-file` por padrão.
3. Comece pelo template `assets/AppEntry.swift` e confirme a assinatura real do
   protocolo no SDK patchado.
4. Use `PlatformVersionShim.swift` quando houver `#available`.
5. Compile um app mínimo visível antes de adicionar rede, persistência, IA ou
   dependências.
6. Rode as guardas e uma validação de runtime antes de chamar o caminho de
   produção.

Comando-base:

```sh
sh scripts/check-env.sh
sh scripts/build-pure-ui.sh MeuApp com.exemplo.meuapp main.swift Views.swift
sh scripts/validate-ipa.sh /var/minis/workspace/MeuApp.ipa
python3 scripts/check-debug-ipa.py /var/minis/workspace/MeuApp.ipa # somente --debug
```

### Perfis

- **arm64e.v1/PAC**: único perfil operacional, usado em builds locais,
  LiveContainer e release.

- **híbrido Swift + ObjC:** plano B maduro quando uma API Swift do SDK
  patchado degrada. Use Swift para a lógica e ObjC/UIKit para a camada que
  realmente precisa dos headers ObjC.
- **projeto de terceiro:** use `port-third-party.py`, mas preserve o projeto
  original e registre cada adaptação. Não converta um port bem-sucedido em
  prova de que todos os projetos SPM são compatíveis.

### Nunca misture artefatos

Separe, no mínimo, o cache arm64e, o diretório temporário de compilação,
IPAs de saída, logs e bundle IDs de teste.

Use `ISB_OUTPUT` para nomes estáveis e únicos. Não deixe builds concorrentes
escreverem `MeuApp.ipa`, nem reutilize objetos de outra arquitetura. PCMs e
`.swiftmodule` carregam a identidade do compilador/tripla; misturá-los pode
produzir erro explícito ou, pior, um diagnóstico enganoso.

## 3. Regras do Swift e do SDK patchado

### Entry point e delegates

Antes de implementar qualquer protocolo Apple:

```sh
python3 scripts/check-protocol-sig.py UIApplicationDelegate didFinishLaunching
```

No SDK usado nesta skill, o entry point validado é o de
`applicationDidFinishLaunching(_:)`. Não substitua por
`application(_:didFinishLaunchingWithOptions:)` por memória: a assinatura
exposta pode usar `NSDictionary`, gerar só warning e impedir o UIKit de chamar
o método. Resultado típico: app vivo com tela preta.

Nunca ignore:

- `nearly matches optional requirement`;
- warning de conformidade de protocolo;
- warning de bridging em delegate;
- ausência do thunk ObjC correspondente.

Os builds devem passar `check-warnings.py` e `check-entry.py`. Ausência de
warning não dispensa a inspeção do binário, pois o warning pode variar conforme
o contexto de compilação.

### Imports e helpers

No caminho puro, mantenha a ordem que foi validada:

```text
Foundation → SwiftUI → UIKit → CoreText → Dispatch → Combine
```

Inclua `assets/PureSwiftKit.swift` em apps pequenos quando ele resolver as
lacunas conhecidas. Em módulos grandes, prefira helpers locais mínimos se o
kit introduzir degradações de type-checking ou bridging.

Regras práticas:

- use `CGRect(origin:size:)`; `CGRectMake` pode falhar apenas no link;
- para APIs CoreGraphics que perderam conveniências, use funções C ou
  `UIBezierPath`;
- seja explícito com tipos em closures, inicializadores e `UserDefaults`;
- evite inferência profunda (`Self(...)` com membro implícito, `.success(x)` em
  contextos genéricos e conversões `Data?` ambíguas);
- mantenha o primeiro arquivo compilado com `Foundation` importado;
- use `-parse-as-library` para módulos de biblioteca, evitando `_main` duplicado.

### `-primary-file` é o padrão

O builder usa um único módulo arm64e e `-primary-file` por padrão. O antigo
experimento de módulos separados não faz parte deste repositório nem do fluxo
de produção. Mantenha o código cross-file no módulo único e use `link-ipa.sh`
para o link final.

### Otimização medida

O padrão recomendado é `ISB_OPT=O`. No toolchain Swift 6.3.3 / SDK iOS 26.5,
`-Osize` foi medido como pior que `-O` nos dois eixos: compilou em 42 s
versus 26 s e gerou executável de 77.312 B versus 76.328 B. Essas são
medições locais de build e tamanho, não desempenho de runtime (S2 estrutural;
sem inferência de S4).


Não gaste 10 minutos compilando um app grande para descobrir um erro de
entry point. Siga esta sequência:

1. `sh scripts/check-env.sh` — toolchain, cache, espaço e perfil.
2. `sh -n` nos scripts e `python3 -m py_compile` nos scripts Python alterados.
3. `sh scripts/regression-suite.sh --quick` — especialmente após mexer em
   linker, SDK, módulos ou flags.
4. build novo com `ISB_OUTPUT` exclusivo.
5. `check-warnings.py`, `check-entry.py`, `check-undefined.py` e
   `validate-ipa.sh`.
6. `sh scripts/acceptance-suite.sh` para o perfil arm64e/PAC.
7. instalação e teste visual no device.
8. somente então adicione uma dependência ou uma capacidade complexa.

Se o processo Swift parecer parado, não confie em `/proc`: no iSH `cpu_ticks` e
`VmRSS` podem ficar em zero. Confie no arquivo de saída e no código de retorno.
A corrida de inicialização do `swift-frontend` exige retries; os scripts já os
fazem. Um processo realmente preso no type-checker deve ser reduzido a um caso
mínimo, não “curado” com espera indefinida.

Mantenha no máximo três jobs paralelos em iSH e preserve espaço livre para
objetos temporários. Nunca mate processos indiscriminadamente durante um build;
entre diagnósticos, limpe apenas workers Swift conhecidos e seus workspaces.

## 5. Diagnóstico orientado por evidência

| Sintoma | Primeira hipótese/teste |
|---|---|
| processo morre sem saída | retry; depois classifique OOM/race e leia o `.err` completo |
| app retorna da main com código 0 | `check-entry.py`; `_main` não chama `UIApplicationMain` |
| app vivo e tela preta | warning/delegate/thunk; não comece pela lógica |
| crash no launch | `check-undefined.py`, dependências, crash log e slice |
| compilação sem fim | reduzir a caso mínimo e mudar para `-primary-file` |
| falha somente após importar no LiveContainer | investigar transformação/reassinatura do host |
| sessão StikDebug parada em `Handling signal 1` | não assumir crash; `universal.js` não é logger genérico |

Para UI, use trace visual síncrono na própria tela. Dê cor de fundo diferente a
cada probe e registre `viewDidLoad`, callbacks, arquivos e renderização. Só
use attach/StikDebug depois de provar que a view e o evento existem.

## 6. IA nativa e frameworks do sistema

`NaturalLanguage`/`NLEmbedding` pode ser usado por bridge ObjC independente do
módulo Swift, desde que o framework seja declarado e o binário seja auditado.
`FoundationModels` é capability-gated: linkar o framework não garante que o
modelo esteja disponível; no device é necessário verificar disponibilidade,
Apple Intelligence e estado de preparação do modelo.

Para arm64e, todos os módulos, PCMs, stdlib, SDK e linker devem corresponder à
mesma tripla e versão do compilador. Não misture cache arm64 com código PAC.
Não transforme uma validação de símbolos em “geração real validada”: exercite
`LanguageModelSession.respond` em device e registre o resultado.

`BGAppRefreshTask` é oportunidade controlada pelo sistema, não daemon nem
cron. Em LiveContainer, o lifecycle e o registro podem não representar o
aplicativo instalado normalmente. Faça o código tolerar no-op e persista cada
resultado incrementalmente.

## 7. Debug, assinatura e distribuição

- `--debug` é opt-in e deve ser validado por `check-debug-ipa.py` na IPA final;
- `get-task-allow` pode ser removido por instalador/reassinatura;
- convidado e host LiveContainer têm bundle IDs diferentes; o retorno do
  StikDebug usa o ID do host;
- `ldid -S` é assinatura ad-hoc, não certificado Apple;
- não prometa push, iCloud ou outras capabilities sem provisioning e assinatura
  compatíveis;
- nunca comite SDK Apple, módulos binários, toolchain, credenciais ou IPAs
  geradas. Use `.gitignore` e diretórios de artefatos locais.

## 8. O que evitar — lista curta

- tentar combinações de CPU subtype sem log pós-importação;
- corrigir “tela preta” reescrevendo a lógica antes de checar o delegate;
- usar documentação antiga como estado atual;
- compilar o app inteiro para cada hipótese;
- não misturar caches, objetos ou IPAs de perfis diferentes;
- adicionar framework “por garantia” sem declarar a razão e validar o link;
- usar `UserDefaults` para segredo, token ou API key;
- chamar `BGTaskScheduler` como se fosse execução garantida;
- alterar o linker de produção por um backport experimental sem a suíte e
  runtime de aceitação;
- reportar “PASS” sem registrar exatamente qual nível S0–S4 foi obtido.

## 9. Checklist de encerramento

Antes de entregar uma IPA ou declarar uma etapa concluída:

- [ ] commit/árvore e origem dos artefatos identificados;
- [ ] perfil, slice, SDK, minOS e bundle ID registrados;
- [ ] caches e workspaces isolados;
- [ ] warnings, entry point e undefined symbols verificados;
- [ ] regressão e acceptance adequadas executadas;
- [ ] IPA final auditada, não uma cópia antiga;
- [ ] runtime separado de validação estática;
- [ ] limitações e host/device explicitamente registrados;
- [ ] nenhum segredo ou artefato proibido no Git;
- [ ] próximos passos definidos por evidência, não por tentativa.

Documents de apoio: `HANDOFF.md` (estado), `WARNINGS-FATAIS.md` (guards),
`NATIVE-INTELLIGENCE.md` (IA), `PROJECT-GUIDE.md` (fluxo) e
`TEST-PLAN-AND-LOCAL-REPRO.md` (aceitação).


## 13. Manutenção desta documentação

Quando uma investigação descobrir uma regra nova:

1. reproduza-a em um caso mínimo ou teste automatizado;
2. registre causa, sintoma, correção e limite;
3. atualize primeiro `references/BEST-PRACTICES.md`;
4. atualize o documento técnico detalhado e marque snapshots antigos;
5. rode a suíte relevante e registre o nível S0–S4;
6. só então faça commit com uma mensagem que descreva a evidência.
7. mantenha um único ponto de retomada corrente em
   `references/HANDOFF.md`; documentos datados são histórico e permanecem sob
   `references/`, nunca na raiz.
8. registre fatos de runtime com artefato, host/device e versão que os
   produziram.

Não acumule “estado atual” em handoffs históricos. Um fato de runtime deve
sempre mencionar o artefato, host/device e versão que o produziram.
