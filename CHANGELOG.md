# Changelog

## Unreleased — 2026-08-31

- Completed hygiene and entry-guard hardening.
- Acceptance output is mirrored to the terminal with a persistent log path.
- Added `ISB_OPT=none|O|Osize`; optimized `-O` is now the default.
- Added linker `-dead_strip` and optional `ISB_STRIP=1`.
- Added the tracked-artifact/publication guard.
- Replaced author-specific VM paths and remote defaults with configurable values.
- Tested hiding both `swift/*/usr/lib/swift/embedded` directories: the arm64e
  acceptance suite still passed. They remain local removable candidates and are
  not required by the active native module cache.
- arm64 remains the production LiveContainer profile; arm64e remains an
  advanced, structurally validated profile pending runtime evidence.
