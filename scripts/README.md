# Script index

All scripts are POSIX shell or Python 3 and are designed to run from the repository root. Commands
that need user-provided Apple inputs fail with an actionable message when an input is missing.

## Bootstrap and environment

| Script | Purpose |
| --- | --- |
| `bootstrap.sh` | Thin entry point for `scripts/bootstrap.sh`. |
| `scripts/bootstrap.sh` | Stage and check the SDK, Swift and module cache. |
| `scripts/bootstrap-glibc.sh` | Prepare the explicit glibc loader step. |
| `scripts/check-env.sh` | Verify toolchain, SDK, cache, linker and tools. |
| `scripts/check-module-cache.py` | Validate the arm64e module cache. |
| `scripts/scan-dependencies.sh` | Generate a dependency graph on Linux. |

## Build

| Script | Purpose |
| --- | --- |
| `scripts/build-pure-ui.sh` | SwiftUI/UIKit app builder (default arm64e/PAC). |
| `scripts/build-pure-foundation.sh` | Foundation/Dispatch-only app builder. |
| `scripts/build-ipa.sh` | Swift + Objective-C/UIKit hybrid builder. |
| `scripts/build-livecontainer.sh` | Unsigned arm64e wrapper for LiveContainer. |
| `scripts/build-arm64e-modules.sh` | Build the arm64e module cache on Linux. |
| `scripts/build-parallel.py` | Primary-file parallel compiler. |
| `scripts/link-ipa.sh` | Link and package the app bundle. |
| `scripts/profile.sh` | Shared profile defaults and paths. |
| `scripts/port-third-party.py` | Port an external project into the workflow. |

## Validation and release

| Script | Purpose |
| --- | --- |
| `scripts/validate-ipa.sh` | Structural IPA validation. |
| `scripts/check-entry.py` | Entry point and launch-method proof. |
| `scripts/check-debug-ipa.py` | Debug/StikDebug IPA checks. |
| `scripts/check-slice.py` | Enforce the arm64e slice. |
| `scripts/check-undefined.py` | Undefined-symbol guard. |
| `scripts/check-weak-link.py` | Weak/strong link policy. |
| `scripts/check-warnings.py` | Fatal warning detector. |
| `scripts/check-protocol-sig.py` | Protocol signature checker. |
| `scripts/check-livecontainer.py` | LiveContainer compatibility check. |
| `scripts/acceptance-suite.sh` | Canonical acceptance matrix. |
| `scripts/acceptance-suite-arm64e.sh` | arm64e-specific acceptance. |
| `scripts/regression-suite.sh` | Regression gate. |
| `scripts/benchmark-build.sh` | Build-time benchmark. |
| `scripts/verify-pureswiftkit.sh` | PureSwiftKit verification. |

## Repository and maintenance

| Script | Purpose |
| --- | --- |
| `scripts/verify-docs.sh` | Documentation and syntax guard. |
| `scripts/check-newcomer.sh` | Newcomer diagnostics smoke test. |
| `scripts/check-repo-clean.py` | Forbidden-artifact guard. |
| `scripts/verify-release.sh` | Release gate. |
| `scripts/gc-workdirs.sh` | Conservative temp workdir cleanup (dry-run default). |
