# Validation report — 2026-09-01

This report records commands executed against the public repository tree.
Generated SDK/toolchain artifacts are not stored here.

## Retomada local — 2026-09-01

The public tree was rechecked from commit `76cee60`; it remained clean. The
following fresh checks passed serially on the iSH host:

- `sh bootstrap.sh --check`;
- `sh scripts/verify-docs.sh`;
- `python3 scripts/check-repo-clean.py`;
- `ISB_ARCH=arm64e sh scripts/check-env.sh`;
- `sh scripts/regression-suite.sh --quick`;
- `sh scripts/acceptance-suite.sh`;
- `ISB_ARCH=arm64e ISB_WORKSPACE=/var/minis/workspace/arm64e-final sh scripts/acceptance-suite-arm64e.sh`;
- `python3 scripts/check-module-cache.py /opt/ios-toolchain/foundation-build633-arm64e`.

The final cache check reported `files=100 nonempty=100 neutral_refs=61
personal_refs=0`. The arm64e acceptance generated five fresh IPAs and passed
all structural guards; this remains S2 evidence only.

The device benchmark was regenerated with distinct compile-time labels and
bundle IDs, avoiding a LiveContainer collision between variants:

| Variant | Bundle ID | Artifact |
|---|---|---|
| `none` (`-Onone`) | `com.forge.benchdevice.none` | `BenchDevice-none.ipa` |
| `O` (`-O`) | `com.forge.benchdevice.O` | `BenchDevice-O.ipa` |

Both fresh IPAs passed `validate-ipa.sh`, entry/delegate checks, and
LiveContainer structural checks. They still require manual installation and
tapping on the device for S4 runtime numbers.

### Device gate (retomada 2026-09-01)

`apple-device info --compact` confirmou o host físico `iPhone17,1`, iOS 26.6,
com 7.46 GiB de memória. O usuário confirmou que todas as IPAs geradas nesta
retomada abriram e rodaram com sucesso no device/LiveContainer. Isso fornece
S3 para os guests arm64 e arm64e testados. O fluxo FoundationModels, incluindo
o `LanguageModelSession.respond(to:)`, e o fluxo das duas variantes de
benchmark também foram confirmados pelo usuário, portanto são S4 no cenário
testado. Latências e resposta textual exatas não foram fornecidas e não são
inventadas neste relatório.

The final device-ready benchmark IPAs are in:

```text
/var/minis/workspace/bench-device-final2/BenchDevice-none.ipa
/var/minis/workspace/bench-device-final2/BenchDevice-O.ipa
```

Both have distinct bundle IDs and compile-time labels, so the manual test can
install them side by side without a LiveContainer bundle collision.


| Check | Result | Evidence |
|---|---|---|
| `sh scripts/verify-docs.sh` | PASS | syntax, repository policy, documentation assertions |
| `sh bootstrap.sh --check` | PASS | repository, Swift frontend, SDK, stdlib cache, pure cache, neutral sysroot |
| `python3 scripts/check-repo-clean.py` | PASS | 123 tracked files; no generated/licensed binaries or private paths |
| fresh `git clone --no-local` | PASS | clone completed in `/tmp/forge-on-glass-clean` |
| build from fresh clone | PASS | arm64, SDK 26.5, `-primary-file`, unsigned IPA |

## Local build benchmark

Command: `sh scripts/benchmark-build.sh` on the iSH host, one minimal UIKit
sample, no device runtime measurement.

| Mode | Build seconds | Executable bytes | IPA bytes |
|---|---:|---:|---:|
| `none` (`-Onone`) | 11 | 97,504 | 15,045 |
| `O` (`-O`) | 26 | 76,328 | 11,110 |
| `Osize` (`-Osize`) | 42 | 77,312 | 11,530 |

The release default is `ISB_OPT=O`. These numbers measure compilation and
artifact size only; they are not S4 device performance results.

## Incremental cache validation

With `ISB_INCREMENTAL=1`, the first two-file build compiled both objects in
15 seconds. The second build reported `incremental: reutilizando 2 objeto(s)`
and compiled zero objects. The final executables from both IPAs were identical
byte-for-byte. Cache keys include sources, compiler, target, SDK, VFS, flags,
module paths, and module bytes; a mismatch invalidates cached objects.

## Acceptance levels

- **S2 arm64:** fresh local IPA passed SDK/platform, exact slice, `LC_MAIN`,
  chained-fixup, entry/delegate, warning, and undefined-symbol guards.
- **S2 arm64e:** fresh local PAC IPA set passed the offline linker, exact
  `arm64e` subtype, FoundationModels weak-link, NaturalLanguage, embeddings,
  `LC_MAIN`, chained fixups, entry/delegate, and IPA guards.
- **S3 arm64:** previously recorded on iOS 26.6 / iPhone17,1 in LiveContainer.
- **S3 arm64e:** user-confirmed fresh arm64e IPAs opened and ran successfully on
  the same iPhone17,1 / iOS 26.6 test host. This is runtime evidence for the
  generated arm64e guests, not a claim that every LiveContainer version accepts
  every PAC binary.
- **S4 FoundationModels generation:** user-confirmed the generated runtime IPA
  executed successfully, including the real `respond(to:)` path. Exact
  response/latency telemetry was not supplied in the confirmation, so this
  report does not invent those values.
- **S4 benchmark flow:** user-confirmed the generated benchmark IPAs ran
  successfully. Exact per-variant timings were not supplied, so the local
  compile-time benchmark numbers below remain separate from device timings.

## Space decision

The two host `usr/lib/swift/embedded` directories were removed after a
reversible hidden-directory test and a complete arm64e acceptance pass. The
exact duplicate arm64e linker was replaced by a symlink to the active copy.
Measured recovery was approximately 1.1 GB. Swift 6.3.2 was retained.
