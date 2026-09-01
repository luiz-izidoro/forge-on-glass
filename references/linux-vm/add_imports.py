#!/usr/bin/env python3
"""add_imports.py — adiciona `import X` faltantes num .swiftinterface.

MECANISMO #8: o interface usa `Modulo.Tipo` mas nao tem `import Modulo`. O
compilador reporta como "cannot find type 'Modulo' in scope" (le o prefixo do
modulo como se fosse um tipo).

Isto substitui a gambiarra do `-import-module` na linha de comando, que tinha um
EFEITO COLATERAL GRAVE: modulos construidos com -import-module quebram o
bridging String<->NSString para quem os importa (ver PURE-SWIFT-UI-STATUS.md).

Uso: python3 add_imports.py <swiftinterface> Mod1 Mod2 ...
"""
import sys, shutil

path = sys.argv[1]
mods = sys.argv[2:]
s = open(path).read()
shutil.copy(path, path + '.bak-imports')

added = []
for m in mods:
    if f'import {m}\n' in s:
        continue
    # inserir antes de `import Swift` (ordem alfabetica nao importa ao compilador)
    if 'import Swift\n' in s:
        s = s.replace('import Swift\n', f'import {m}\nimport Swift\n', 1)
        added.append(m)

open(path, 'w').write(s)
print(f'add_imports: {added if added else "nada a fazer"}')
