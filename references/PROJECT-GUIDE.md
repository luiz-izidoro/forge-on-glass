# Project guide — internal and external use

## Internal projects

1. Read `BEST-PRACTICES.md`, `HANDOFF.md` and `PROJECT-GOVERNANCE.md`.
2. Run `sh scripts/check-env.sh`.
3. Start with one visible SwiftUI/UIKit file and the validated delegate.
4. Build with `sh scripts/build-pure-ui.sh App BundleID main.swift`.
5. Use one Swift module and default `-primary-file` mode.
6. Add PureSwiftKit only when its helpers are required.
7. Add one capability at a time: Foundation/Dispatch, system framework,
   NaturalLanguage, FoundationModels or dependencies.
8. Use a unique `ISB_OUTPUT`, validate the fresh IPA and run acceptance.
9. Exercise the fresh IPA and record S3/S4 evidence.
10. Run `verify-release.sh` before committing.

## External projects

1. Clone outside this repository and preserve the original checkout.
2. Pin the source commit and all dependency versions.
3. Run `python3 scripts/port-third-party.py /tmp/project App BundleID`.
4. Use `--extra` for dependency source trees and `--exclude` only with a reason.
5. Prefer one module plus `-primary-file`; the separate-module builder is
   deprecated because it breaks String/NSString bridging.
6. Use `--no-kit` if the project does not need the compatibility helpers.
7. Treat macros, storyboards/XIBs and unsupported modules as explicit limits.
8. Preserve third-party licenses and attribution outside this repository.
9. Record adaptations, command, source/dependency versions and S0–S4 evidence.

## Canonical commands

```sh
sh scripts/check-env.sh
sh scripts/build-pure-ui.sh MyApp com.example.myapp main.swift
sh scripts/build-pure-foundation.sh FoundationApp main.swift
sh scripts/build-pure-ui.sh MyApp com.example.myapp main.swift --debug
python3 scripts/check-debug-ipa.py /var/minis/workspace/MyApp.ipa
python3 scripts/port-third-party.py /tmp/project MyApp com.example.myapp
sh scripts/acceptance-suite.sh
```

## Runtime triage

Use a synchronous visual trace first, then `--debug`/StikDebug. Guest and host
bundle IDs differ. A waiting `c` or `Handling signal 1` is not automatically a
crash. Availability-gated APIs may legitimately be unavailable on another
machine.

## Artifact boundaries

Keep generated IPAs, objects, module caches, SDKs, patchsets, toolchains,
credentials and device exports outside Git. Sanitize logs before sharing.
