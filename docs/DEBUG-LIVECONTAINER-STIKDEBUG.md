# Debug on-device com LiveContainer + StikDebug

> **Fluxo subordinado à política:** leia
> [`../references/BEST-PRACTICES.md`](../references/BEST-PRACTICES.md) antes de
> depurar. Use a camada mais barata que responda à pergunta e não confunda
> validação estrutural com runtime.

> ⚠️ Este arquivo é **apenas um ponteiro**. O guia canônico — e o único que
> deve ser editado — é:
>
> ### 📄 [`references/DEBUG-LIVECONTAINER-STIKDEBUG.md`](../references/DEBUG-LIVECONTAINER-STIKDEBUG.md)

Não duplique conteúdo aqui: uma cópia resumida já divergiu do original uma vez.

## Atalhos

```sh
# build com instrumentação de debug
sh scripts/build-pure-ui.sh MeuApp com.exemplo.meuapp main.swift --debug

# projeto de terceiro, apontando o host do LiveContainer
python3 scripts/port-third-party.py /tmp/projeto MeuApp com.exemplo.meuapp \
  --debug --stikdebug-bundle-id com.kdt.livecontainer.A4658DGR7V

# guarda: valide a IPA que será realmente instalada
python3 scripts/check-debug-ipa.py /var/minis/workspace/MeuApp.ipa
```
