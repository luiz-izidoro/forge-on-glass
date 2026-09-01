# Documentação do diretório

> **Comece por:** [`../references/BEST-PRACTICES.md`](../references/BEST-PRACTICES.md).
> Este é o guia normativo: define níveis de evidência, ordem de validação,
> perfis, isolamento, LiveContainer, IA nativa e o que evitar. Handoffs e
> relatórios abaixo complementam o guia, mas não o contradizem.

O diretório técnico principal é `/var/minis/skills/ios-swift-builder/`.

- `references/`: especificações, diagnósticos, limitações e histórico técnico.
- `docs/`: índices legados; o conteúdo técnico canônico fica em `references/`.
- `assets/`: templates e suporte incluído nos builds.
- `scripts/`: builders, validações e guardas automatizadas.

Para o setup LiveContainer + StikDebug, comece por:

- [`../references/DEBUG-LIVECONTAINER-STIKDEBUG.md`](../references/DEBUG-LIVECONTAINER-STIKDEBUG.md)
- [`../references/HANDOFF.md`](../references/HANDOFF.md) para o estado validado
- [`docs/README.md`](README.md)

O fluxo recomendado é: trace visual para bugs de UI; attach/script para
confirmar o debugserver; sessão persistente com breakpoints de evento para
monitoramento contínuo.
