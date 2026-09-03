# Debug on-device com LiveContainer + StikDebug

> **Fluxo subordinado à política:** leia
> [`../references/BEST-PRACTICES.md`](../references/BEST-PRACTICES.md) antes de
> depurar. Use a camada mais barata que responda à pergunta e não confunda
> validação estrutural com runtime.

Guia operacional do debug de apps Swift/UIKit no device usando LiveContainer e
StikDebug. O StikDebug fica instalado externamente; o builder apenas instrumenta
o IPA. O fluxo foi validado durante o desenvolvimento do Chip8Emu.

## Princípio: debug em camadas

Use a camada mais barata que responde à pergunta:

1. **Trace visual dentro do app** — eventos de UI, callbacks, arquivos, estado e
   renderização. É a primeira escolha para bugs de interface.
2. **Attach/script no StikDebug** — confirma PID, attach, threads, registradores e
   capacidades do debugserver.
3. **Sessão persistente de baixo nível** — mantém `debugserver` anexado enquanto o
   app roda e captura paradas, registradores e breakpoints de evento.

O console do StikDebug mostra principalmente o script/debugserver. `print` e
`NSLog` do app não aparecem automaticamente nessa tela; use trace visual ou um
syslog apropriado.

## Gerar IPA de debug

```sh
# Swift/UIKit puro
sh /var/minis/skills/ios-swift-builder/scripts/build-pure-ui.sh \
  MeuApp com.example.meuapp main.swift Views.swift --debug

# Projeto de terceiro dentro do LiveContainer
python3 /var/minis/skills/ios-swift-builder/scripts/port-third-party.py \
  /tmp/projeto MeuApp com.example.meuapp \
  --debug --stikdebug-bundle-id com.kdt.livecontainer.A4658DGR7V

# Validar antes de instalar
python3 /var/minis/skills/ios-swift-builder/scripts/check-debug-ipa.py \
  /var/minis/workspace/MeuApp.ipa
```

For the normal signed debug path, run:

```sh
sh scripts/build-pure-ui.sh App com.example.app main.swift --debug
python3 scripts/check-debug-ipa.py /var/minis/workspace/App.ipa
```

Use `--unsigned` only when the next component explicitly re-signs the guest.

- `assets/DebugSupport.swift`;
- `get-task-allow=true`;
- `LSApplicationQueriesSchemes=stikdebug`;
- overlay azul `DBG • toque: StikDebug`;
- PID, bundle ID e detecção de `LC_HOME_PATH`;
- URL `stikdebug://enable-jit` com PID atual.

A reassinatura pós-processamento deve preservar `get-task-allow`. O instalador
pode removê-lo; sempre valide a IPA que será instalada.

## Bundle IDs no LiveContainer

Há dois IDs diferentes:

```text
app convidado:  com.minis.chip8emu.debug
host:          com.kdt.livecontainer.A4658DGR7V
```

O `--stikdebug-bundle-id` é o ID para retorno ao host. Sem ele, o StikDebug pode
tentar retornar ao bundle do convidado e mostrar `Failed to return`. Isso não
prova falha no attach. Use o ID real exibido pelo LiveContainer/StikDebug.

## Camada 1 — trace visual

Para investigar um fluxo de UI, adicione um painel temporário que registre de
forma síncrona:

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
main: displayLink adicionado
frame: ok lit=119
```

Isso responde rapidamente se o toque chegou, se o delegate foi chamado, se o
arquivo existe, se o estado mudou e se a imagem foi criada. Para renderização,
registre também `UIImage=nil`, `lit=0` e `lit=N` no caminho framebuffer → Bitmap
→ CGImage → UIImage → UIImageView.

Não coloque o primeiro diagnóstico em `DispatchQueue.main.async`: se a tela não
for criada, o bloco pode nunca executar.

## Camada 2 — attach no StikDebug

O overlay DBG abre o StikDebug com o PID. Um script de attach de diagnóstico
deve registrar:

```text
vAttach
qSupported
qfThreadInfo
qC
register_packet_length
register_packet_prefix
D
```

`D = OK` significa que a sessão foi encerrada pelo script. Um script finito é
útil para confirmar attach, mas não é monitoramento contínuo.

O `universal.js` **não é um capturador genérico de logs**. Ele implementa o
protocolo JIT baseado em `BRK`; em um app comum pode ficar em `Handling signal 1`
ou aguardando indefinidamente. Use-o somente quando o processo realmente usa o
protocolo JIT compatível.

## Camada 3 — sessão persistente

Para monitoramento contínuo, o script deve manter a sessão aberta:

```text
vAttach
qSupported/qfThreadInfo/qC
c
registrar parada/sinal
ler qC, thread e g
c
...
```

A linha `debug stop/continue #1` significa que o script está bloqueado no `c`,
aguardando uma parada. Sozinha, não significa crash nem detach. Se o app não
gera sinais, o contador não avança.

Para obter eventos úteis, adicione breakpoints de instrumentação nos pontos de
interesse: toque, callback, seleção, carregamento e renderização. Eles só devem
ser armados depois que o usuário toca DBG; antes disso o app precisa funcionar
normalmente sem `SIGTRAP`. O comportamento esperado é:

```text
#1 attach/estado inicial
#2 toque Load ROM
#3 ROM selecionada
#4 ROM carregada
```

Ao encerrar a sessão no StikDebug, espere o `D`/detach e retorne manualmente ao
LiveContainer se o retorno automático falhar.

## Procedimento no device

1. Instale a IPA pelo método que preserva `get-task-allow`.
2. Abra o app pelo LiveContainer.
3. Confirme que o overlay DBG aparece dentro do app.
4. Para bug de UI, reproduza primeiro com o trace visual.
5. Para attach, toque DBG e mantenha LocalDevVPN/túnel ativos.
6. No StikDebug, confirme a solicitação e observe o PID.
7. Para sessão persistente, mantenha a tela do script aberta.
8. Gere os eventos instrumentados e confira o avanço do contador.
9. O PID muda em cada lançamento; nunca reutilize PID antigo.

## Interpretação rápida

| Mensagem | Significado |
|---|---|
| `attach_response = T...` | debugserver respondeu ao attach |
| `qSupported = ...` | capacidades disponíveis |
| `qfThreadInfo = m...` | threads retornadas |
| `qC = QC...` | thread atual |
| `register_packet_length = 0` | `g` não retornou pacote naquele estado; não é prova isolada de falha |
| `detach = OK` | sessão terminou |
| `Handling signal 1` | universal.js aguardando/processando sinal |
| `debug stop/continue #1` | sessão persistente aguardando uma parada |
| `frame: ok lit=N` | framebuffer tem pixels e imagem foi criada |
| `UIImage=nil` | falha na conversão para UIImage |

## Limitações

- O attach e o console só existem no device; iSH não simula a sessão.
- `get-task-allow` pode ser removido pelo instalador.
- StikJIT/helper não é embutido: o StikDebug é externo e extensões de apps
  convidados não são suportadas pelo LiveContainer.
- O retorno automático ao host é conveniência; se falhar, abra manualmente o
  LiveContainer. Isso não invalida necessariamente o attach.
- Não salve pairing files, tokens ou credenciais nos fontes/relatórios.

Referências: [StikDebug](https://github.com/StikDebug/StikDebug),
[LiveContainer](https://github.com/LiveContainer/LiveContainer) e
`assets/DebugSupport.swift`.
