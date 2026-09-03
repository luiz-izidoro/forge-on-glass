# ios-swift-builder — documentação

> **Regra de entrada:** leia [`../references/BEST-PRACTICES.md`](../references/BEST-PRACTICES.md) antes de iniciar ou retomar um build. Ele é a fonte normativa para evitar retrabalho; esta página lista os fluxos operacionais.

Esta pasta reúne os fluxos de uso da skill. As referências técnicas detalhadas
continuam em [`../references/`](../references/).

## Fluxos principais

- [Debug com LiveContainer + StikDebug](../references/DEBUG-LIVECONTAINER-STIKDEBUG.md) — três camadas: trace visual, attach e sessão persistente
- [Porting de apps de terceiros](../references/PORTING-TERCEROS.md)
- [Status do Swift/UIKit/SwiftUI puro](../references/HANDOFF.md) — perfil atual e evidência
- [Warnings fatais e tela preta](../references/WARNINGS-FATAIS.md)
- [Handoff do projeto](../references/HANDOFF.md)
- [Limitações](../references/LIMITATIONS.md)

## Comandos rápidos

```sh
# Build normal
sh scripts/build-pure-ui.sh MeuApp com.exemplo.meuapp main.swift

# Build instrumentado para LiveContainer + StikDebug
sh scripts/build-pure-ui.sh MeuApp com.exemplo.meuapp main.swift --debug

# Port de terceiro com retorno ao host do LiveContainer
python3 scripts/port-third-party.py /tmp/projeto MeuApp com.exemplo.meuapp \
  --debug --stikdebug-bundle-id com.kdt.livecontainer.A4658DGR7V

# Verificar a IPA de debug antes de instalar
python3 scripts/check-debug-ipa.py /var/minis/workspace/MeuApp.ipa
```

O modo `--debug` é opt-in. Builds normais não recebem overlay, URL do
StikDebug nem o entitlement adicional `get-task-allow`.
