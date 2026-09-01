# Version matrix

| Host compiler | Target slice | SDK / minimum OS | Status and evidence |
|---|---|---|---|
| Swift 6.3.2 | arm64 | iOS SDK 26.5 / iOS 26.0 | production LiveContainer route; S3 recorded on iOS 26.6 / iPhone17,1 |
| Swift 6.3.3 | arm64 | iOS SDK 26.5 / iOS 26.0 | pure Swift UIKit/SwiftUI build; S3 runtime validated on iPhone17,1 / iOS 26.6 via LiveContainer |
| Swift 6.3.3 | arm64e | iOS SDK 26.5 / iOS 26.5 | local PAC linker and module cache; S3 runtime validated on iPhone17,1 / iOS 26.6 via LiveContainer; FoundationModels generation S4 confirmed by user |

The Apple SDK and generated modules are user-provided and are not shipped in
this repository. `ISB_SYSROOT` defaults to `/opt/isb/sysroot`; existing local
mirrors may be selected explicitly during migration. Keep module caches isolated
by architecture and regenerate PCMs when changing the prefix.

The `embedded/` host Swift directories were hidden during the Fase 5.2 test;
the complete arm64e acceptance still passed. They are therefore not required by
the active target module cache, but remain local cleanup candidates.
