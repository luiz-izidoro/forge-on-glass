#!/bin/sh
# extract-uikitcore-tbd.sh — extrai o documento do UIKitCore de dentro do
# UIKit.tbd e grava um .tbd standalone que o ld64.lld consegue usar.
#
# POR QUE: o UIKit.tbd do SDK e' um arquivo MULTI-DOCUMENTO (8 documentos: UIKit
# + 7 private frameworks reexportados). Varios simbolos Swift — em especial os
# das classes GENERICAS (`UICollectionViewDiffableDataSource`,
# `UITableViewDiffableDataSource`, `NSDiffableDataSourceSnapshot`) — sao
# exportados pelo documento do **UIKitCore**, nao pelo do UIKit.
# O ld64.lld NAO percorre os documentos reexportados do tbd, entao esses
# simbolos ficam "undefined" no link, mesmo com -framework UIKit.
# Pior: o `UIKitCore.tbd` que vem em PrivateFrameworks/ esta INCOMPLETO (nao tem
# os simbolos Swift), entao apontar para ele nao resolve.
#
# FIX: extrair o documento certo e materializa-lo como framework separado.
#
# Uso: ./extract-uikitcore-tbd.sh [dir-de-saida]
#      (default: /opt/ios-toolchain/extrafw)
set -e
OUTDIR="${1:-/opt/ios-toolchain/extrafw}"
SDK="${SDK:-/opt/ios-toolchain/iPhoneOS26.5.sdk}"
SRC="$SDK/System/Library/Frameworks/UIKit.framework/UIKit.tbd"

[ -f "$SRC" ] || { echo "UIKit.tbd nao encontrado: $SRC"; exit 1; }
mkdir -p "$OUTDIR/UIKitCore.framework"

python3 - "$SRC" "$OUTDIR/UIKitCore.framework/UIKitCore.tbd" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, errors='ignore').read()
docs = text.split('--- !tapi-tbd')
target = None
# criterio confiavel: o documento que EXPORTA os simbolos Swift genericos.
# (procurar so pelo install-name pega o doc de reexport, que e' um stub curto)
for d in docs[1:]:
    if 'DiffableDataSourceC010collectionC012cellProvider' in d:
        target = d
        break
if target is None:  # fallback: maior doc cujo install-name seja UIKitCore
    cands = [d for d in docs[1:] if 'UIKitCore.framework/UIKitCore' in d]
    target = max(cands, key=len) if cands else None
if target is None:
    print('ERRO: documento do UIKitCore nao encontrado no tbd', file=sys.stderr)
    sys.exit(1)
out = '--- !tapi-tbd' + target
if not out.rstrip().endswith('...'):
    out = out.rstrip() + '\n...\n'
open(dst, 'w').write(out)
print(f'gravado {dst} ({len(out)} bytes)')
PY

echo "use no link:  -F$OUTDIR -framework UIKitCore"
