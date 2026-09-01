# Changelog

## 0.2.0 — 2026-09-01

- Promoted a freshly generated neutral arm64 module cache with 38 Swift
  modules and 59 PCMs; validation reports zero personal-path references.
- The arm64 pure Swift profile now requires the neutral sysroot and no longer
  falls back to an author-specific `/home` mirror.
- Added a trap-protected sysroot-independence build to the arm64 acceptance
  suite; the fresh IPA passes without the legacy mirror.
- User subsequently confirmed that fresh `P0NeutralRuntime.ipa`, built with the
  promoted neutral arm64 cache, opened and ran in LiveContainer; this cache is
  now S3 for the tested host/device.
- Removed the obsolete cleanup utility that had no measured targets.
- Added `gc-workdirs.sh` with dry-run default and explicit `--apply`.
- Deduplicated the SDK tree by using `/opt/ios-toolchain/iPhoneOS26.5.sdk`
  as a symlink to the neutral `/opt/isb/sysroot` copy; both architecture
  profiles passed acceptance after the rollback window.
- Added honest `--full` and `--pcm-only` modes to the arm64 module generator;
  the current SDK has no arm64 Swift interfaces, so full regeneration fails
  closed while PCM regeneration remains available.
- Added the `check-weak-link.py` guard and a negative strong-link test for
  FoundationModels in arm64e acceptance.
- Added the newcomer onboarding smoke test, Dockerfile `COPY` validation, an
  honest tested/not-tested compatibility matrix, and issue templates requiring
  sanitized environment evidence.
- The clean arm64 `--pcm-only` regeneration measured 61 non-empty PCMs with
  zero personal-path references; the full cache remains partially inherited.

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
- User subsequently confirmed successful device execution of the generated
  arm64e IPAs, including the FoundationModels `respond(to:)` flow and both
  benchmark variants; exact benchmark timings were not supplied.
- Added an executable, checksum-gated `scripts/bootstrap-glibc.sh` and wired it
  into staged bootstrap step 6; it extracts only user-provided Ubuntu arm64
  `.deb` runtime libraries and never downloads or redistributes them.
- Updated the public handoff and validation matrix with S3/S4 evidence from the
  confirmed iPhone17,1 / iOS 26.6 LiveContainer run.
- Device benchmark variants now use compile-time mode labels and distinct
  bundle IDs (`com.forge.benchdevice.none` and `com.forge.benchdevice.O`) so
  LiveContainer installs cannot collide; both fresh IPAs passed S2 validation.
