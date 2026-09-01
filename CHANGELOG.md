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
- Added a real zero-to-checkout recipe and staged `bootstrap.sh` with explicit
  user-provided artifact hashes; Apple SDK and Linux module caches remain local.
- Added opt-in incremental object caching with source/toolchain/module-content
  invalidation; verified a two-file rebuild drops from 15s to 0s and produces
  byte-identical executables.
- Added `benchmark-build.sh` and public validation report with measured
  `-Onone`/`-O`/`-Osize` build and artifact sizes.
- Added `FoundationModelsRuntimeMain.swift`, which displays availability,
  response, and latency; actual `respond(to:)` execution remains device-only.
- External VM regeneration recorded in `references/VALIDATION-VM-2026-09-01.md`:
  target-specific graph `91` modules, orchestrator `93/93`, transferred cache
  `40` Swift modules + `60` PCMs, and zero `/home/` references in valid artifacts.
- Full arm64e acceptance includes a fresh structural build of the
  FoundationModels generation diagnostic; device execution remains manual.
