#!/bin/sh
# apply-patchset.sh — aplica o patch-set num SDK ORIGINAL limpo, tornando o build
# reproduzivel a partir do zero.
#
# Cada .patch tem, na 1a linha, `# TARGET: <caminho relativo no SDK>`.
# Idempotente: se o patch ja estiver aplicado, apenas avisa e segue.
#
# Uso: ./apply-patchset.sh <sdk-dir> [patchset-dir]
set -e
SDK="${1:?uso: $0 <sdk-dir> [patchset-dir]}"
PATCHES="${2:-/var/minis/shared/darwin-sdk/patchset}"

[ -d "$SDK" ] || { echo "SDK nao existe: $SDK"; exit 1; }
[ -d "$PATCHES" ] || { echo "patchset nao existe: $PATCHES"; exit 1; }
command -v patch >/dev/null 2>&1 || { echo "precisa do comando 'patch' (apk add patch)"; exit 1; }

ok=0; skip=0; fail=0
for p in "$PATCHES"/*.patch; do
  [ -f "$p" ] || continue
  name=$(basename "$p" .patch)
  target=$(head -1 "$p" | sed -n 's|^# TARGET: ||p')
  if [ -z "$target" ]; then
    echo "!! $name: sem cabecalho TARGET"; fail=$((fail+1)); continue
  fi
  full="$SDK/$target"
  if [ ! -f "$full" ]; then
    echo "!! $name: alvo ausente ($target)"; fail=$((fail+1)); continue
  fi
  # o cabecalho TARGET nao faz parte do diff -> descartar a 1a linha
  body=/tmp/.patchbody.$$
  tail -n +2 "$p" > "$body"

  if patch --dry-run -s -p0 -R "$full" < "$body" >/dev/null 2>&1; then
    echo "== $name: ja aplicado"; skip=$((skip+1)); rm -f "$body"; continue
  fi
  if patch -s -p0 "$full" < "$body" >/dev/null 2>&1; then
    echo "-> $name: aplicado"; ok=$((ok+1))
  else
    echo "!! $name: FALHOU"; fail=$((fail+1))
  fi
  rm -f "$body"
done

echo "---"
echo "aplicados: $ok | ja aplicados: $skip | falhas: $fail"
[ "$fail" -eq 0 ] || exit 1
