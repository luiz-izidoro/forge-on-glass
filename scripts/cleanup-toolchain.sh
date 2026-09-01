#!/bin/sh
# cleanup-toolchain.sh — remove do toolchain Swift/Linux o que NUNCA e' usado
# no pipeline de cross-compile para iOS (que so precisa de swift-frontend,
# clang, lld, e as libs do resource-dir).
#
# NAO remove: swift-frontend, swiftc, clang*, lld*, ld64*, libexec, lib/swift.
# Uso: ./cleanup-toolchain.sh /opt/swift6.3.3 [--apply]
set -e
TC="${1:?uso: $0 <toolchain-dir> [--apply]}"
APPLY="$2"

# Ferramentas de DESENVOLVIMENTO desktop: SwiftPM, LSP, debugger, docs, format.
# Nenhuma participa de: swift-frontend -compile-module-from-interface / -c / link.
JUNK="swift-package sourcekit-lsp lldb lldb-server lldb-argdumper lldb-instr
lldb-vscode lldb-dap clangd docc swift-format swift-build swift-test swift-run
swift-package-collection swift-package-registry swift-experimental-sdk
swift-sdk swift-plugin-server swift-symbolgraph-extract swift-refactor
swift-demangle swift-api-digester swift-api-extract swift-inspect
swift-backtrace swift-build-sdk-interfaces repl_swift docc-linux"

total=0
for f in $JUNK; do
  p="$TC/usr/bin/$f"
  [ -e "$p" ] || continue
  sz=$(du -sk "$p" 2>/dev/null | cut -f1)
  total=$((total + sz))
  if [ "$APPLY" = "--apply" ]; then
    rm -rf "$p"
    echo "removido: $f (${sz}K)"
  else
    echo "removeria: $f (${sz}K)"
  fi
done

# static stdlib do Linux: so serve para linkar binarios Linux estaticos
for d in "$TC/usr/lib/swift_static" "$TC/usr/share/doc"; do
  [ -e "$d" ] || continue
  sz=$(du -sk "$d" 2>/dev/null | cut -f1)
  total=$((total + sz))
  if [ "$APPLY" = "--apply" ]; then
    rm -rf "$d"
    echo "removido: $d (${sz}K)"
  else
    echo "removeria: $d (${sz}K)"
  fi
done

echo "---"
echo "total: $((total / 1024)) MB"
[ "$APPLY" = "--apply" ] || echo "(dry-run; rode com --apply para efetivar)"
