#!/bin/sh
# make-patchset.sh — gera diffs unificados de CADA .swiftinterface modificado,
# comparando o SDK de trabalho (VM, patchado) com o SDK ORIGINAL (iSH, limpo).
#
# POR QUE: os interfaces da VM foram editados in-place por ~15 scripts + edicoes
# manuais. Sem isto, um `rm -rf` perde ~40h de trabalho e nao ha como reproduzir
# o build num ambiente novo.
#
# Uso (no iSH, com a VM acessivel via ssh):
#   ./make-patchset.sh <dir-de-saida>
set -e
OUTDIR="${1:-/var/minis/shared/darwin-sdk/patchset}"
VM="${VM_HOST:-${ISB_REMOTE_USER:?ISB_REMOTE_USER ausente}@${ISB_REMOTE_HOST:?ISB_REMOTE_HOST ausente}}"
VMSDK="${VM_SDK:-/opt/isb/sysroot/iPhoneOS26.5.sdk}"
ORIG="${ORIG_SDK:-/opt/ios-toolchain/iPhoneOS26.5.sdk}"
TMP=/tmp/patchset-work
mkdir -p "$OUTDIR" "$TMP"

# arquivos que sabemos estar patchados (tamanho divergente do original)
FILES="System/Library/Frameworks/UIKit.framework/Modules/UIKit.swiftmodule/arm64e-apple-ios.swiftinterface
System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface
System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface
System/Library/Frameworks/Accessibility.framework/Modules/Accessibility.swiftmodule/arm64e-apple-ios.swiftinterface
System/Library/Frameworks/CoreText.framework/Modules/CoreText.swiftmodule/arm64e-apple-ios.swiftinterface
System/Library/Frameworks/CoreTransferable.framework/Modules/CoreTransferable.swiftmodule/arm64e-apple-ios.swiftinterface
System/Library/Frameworks/DataDetection.framework/Modules/DataDetection.swiftmodule/arm64e-apple-ios.swiftinterface
System/Library/Frameworks/Foundation.framework/Headers/Foundation.h
usr/lib/swift/Metal.swiftmodule/arm64e-apple-ios.swiftinterface"

echo "==> baixando interfaces patchados da VM"
for f in $FILES; do
  name=$(echo "$f" | sed 's|.*/\([A-Za-z]*\)\.\(framework\|swiftmodule\).*|\1|; s|.*/||')
  mkdir -p "$TMP/$(dirname "$f")"
  scp -q "$VM:$VMSDK/$f" "$TMP/$f" 2>/dev/null || { echo "  ! nao encontrado: $f"; continue; }
done

echo "==> gerando diffs contra o SDK original"
total=0
for f in $FILES; do
  [ -f "$TMP/$f" ] || continue
  [ -f "$ORIG/$f" ] || { echo "  ! sem original: $f"; continue; }
  # nome do patch: derivado do NOME DO MODULO (nao do diretorio)
  case "$f" in
    *Foundation.framework/Headers/Foundation.h) base="Foundation-umbrella" ;;
    *.framework/Modules/*.swiftmodule/*)
        base=$(echo "$f" | sed 's|.*/\([A-Za-z0-9_]*\)\.framework/.*|\1|') ;;
    usr/lib/swift/*.swiftmodule/*)
        base=$(echo "$f" | sed 's|.*/\([A-Za-z0-9_]*\)\.swiftmodule/.*|\1|') ;;
    *)  base=$(basename "$f") ;;
  esac
  out="$OUTDIR/$base.patch"
  if diff -u "$ORIG/$f" "$TMP/$f" > "$out" 2>/dev/null; then
    rm -f "$out"   # identico, sem patch
    continue
  fi
  # grava o path relativo no cabecalho para o applier saber onde aplicar
  sed -i "1i # TARGET: $f" "$out" 2>/dev/null || \
    { printf '# TARGET: %s\n' "$f" | cat - "$out" > "$out.tmp" && mv "$out.tmp" "$out"; }
  lines=$(grep -c '^[+-]' "$out" || true)
  echo "  $base.patch ($lines linhas alteradas)"
  total=$((total + 1))
done

echo "---"
echo "$total patches em $OUTDIR"
rm -rf "$TMP"
