#!/bin/sh
# cleanup-toolchain.sh — conservative cleanup utility.
# Default is dry-run. Only removes measured, non-runtime targets with --apply.
set -eu
TC="${1:?uso: $0 <toolchain-dir> [--apply]}"
MODE="${2:-}"
[ -d "$TC" ] || { echo "toolchain ausente: $TC" >&2; exit 1; }
[ "$MODE" = "" ] || [ "$MODE" = "--apply" ] || { echo "use --apply ou omita para dry-run" >&2; exit 2; }
# These are not used by the cross-compile path; never remove swift-frontend,
# clang, lld, libexec, or usr/lib/swift without a separate measured review.
TARGETS="usr/lib/swift_static usr/share/doc"
JUNK="swift-package sourcekit-lsp lldb lldb-server lldb-argdumper lldb-instr lldb-vscode lldb-dap clangd docc swift-format swift-build swift-test swift-run swift-package-collection swift-package-registry swift-experimental-sdk swift-sdk swift-plugin-server swift-symbolgraph-extract swift-refactor swift-demangle swift-api-digester swift-api-extract swift-inspect swift-backtrace swift-build-sdk-interfaces repl_swift docc-linux"
for x in $JUNK; do TARGETS="$TARGETS usr/bin/$x"; done
total=0
for rel in $TARGETS; do
  p="$TC/$rel"; [ -e "$p" ] || continue
  kb=$(du -sk "$p" 2>/dev/null | cut -f1); total=$((total+kb))
  if [ "$MODE" = "--apply" ]; then rm -rf "$p"; echo "removido: $rel (${kb}K)"; else echo "removeria: $rel (${kb}K)"; fi
done
echo "---"; echo "total: $((total / 1024)) MB"
[ "$MODE" = "--apply" ] || echo "dry-run: nada foi removido; use --apply explicitamente"
