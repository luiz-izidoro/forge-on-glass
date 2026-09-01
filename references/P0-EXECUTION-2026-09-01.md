# P0 — relatório de execução e bloqueio arm64

> **Follow-up concluído (2026-09-01):** a tentativa inicial abaixo foi
> bloqueada ao tentar regenerar módulos Swift arm64 a partir de interfaces
> `arm64e`. O SDK obtido posteriormente da fonte pública documentada foi
> comparado ao local e era idêntico; a solução segura foi reutilizar os 38
> módulos Swift arm64 já validados e reconstruir os PCMs contra o sysroot
> neutro. O candidato passou `files=97 nonempty=97 neutral_refs=59
> personal_refs=0`, a regressão e todas as aceitações. Foi promovido
> atomicamente; o estado pós-promoção é S2 local. O rollback e o espelho legado
> foram removidos após a validação final. O usuário confirmou depois a abertura
> e execução de `P0NeutralRuntime.ipa` no LiveContainer, elevando o cache a S3.

**Data:** 2026-09-01  · **Base:** `c3fb2a3`  · **Execução:** `2b4f2fe` + `8821c46`

## Resultado

A Etapa 1 foi concluída. A tentativa inicial da Etapa 2 foi interrompida com
segurança, e a continuação posterior gerou e promoveu o cache neutro. O cache
arm64 ativo foi trocado somente após a equivalência, regressão e aceitação
passarem.

## Etapa 1 — concluída

- `bootstrap.sh --check` agora valida ambos os caches.
- O cache arm64 legado é reportado como `NOT-NEUTRAL`.
- O cache arm64e é reportado como `OK`.
- `check-sysroot-independence.sh` foi criado com `trap` de restauração para
  `EXIT`, `INT` e `TERM`.
- O teste destrutivo foi executado: falhou como esperado porque o PCM legado
  referencia o espelho pessoal ausente quando o diretório em `/home` é movido.
- A restauração e a limpeza do backup foram verificadas como `PASS`.

## Etapa 2 — bloqueio inicial e resolução

A primeira execução do gerador encontrou 91 módulos, criou temporariamente 70
artefatos sem referências pessoais, mas não concluiu os módulos Swift de UI.
O erro determinístico foi a incompatibilidade entre interfaces Apple 6.3.2
`arm64e` e o frontend Swift 6.3.3 quando se tentou forçar target arm64.

O SDK público baixado depois foi comparado ao SDK local e era idêntico, também
sem interfaces `arm64` genuínas. A resolução foi preservar os 38 módulos Swift
arm64 já validados e reconstruir os PCMs clang contra o sysroot neutro. O
candidato final passou:

```text
files=97 nonempty=97 neutral_refs=59 personal_refs=0
```

## Limpeza e estado final

- O candidato parcial inicial foi removido somente depois de confirmar que não
  havia workers Swift ativos.
- O cache arm64 neutro foi promovido atomicamente para o caminho ativo.
- O cache arm64e permaneceu intacto.
- O rollback timestampado e o espelho legado foram removidos somente depois
  de todas as verificações finais passarem.
- `gc-workdirs.sh` removeu 60 workdirs temporários recentes usando `--apply
  --older-than 0`, após dry-run e confirmação de ausência de workers.
- Espaço livre final: aproximadamente 3,8 GB.

## Níveis de evidência

- Guardas e script do gerador: **S1** — scripts compilam/verificam sintaxe.
- Cache arm64 neutro candidato: **S2** — IPA estruturalmente validada e
  independência de caminho confirmada localmente.
- Cache arm64 promovido: **S3** — o usuário confirmou que
  `P0NeutralRuntime.ipa`, gerada após a promoção, abriu e rodou no LiveContainer.
- Cache arm64e: **S2** local nesta execução; o runtime S3 confirmado
  anteriormente permanece referente às IPAs arm64e testadas pelo usuário.
## Próximo passo externo

O push público continua pendente até o usuário fornecer a URL do repositório.
