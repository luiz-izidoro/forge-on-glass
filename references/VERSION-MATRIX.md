# Version matrix

| Host compiler | Target slice | SDK / minimum OS | Tested on | Status and evidence |
|---|---|---|---|---|
| Swift 6.3.3 | arm64e | iOS SDK 26.5 / iOS 26.5 | iPhone17,1 / iOS 26.6 / LiveContainer (version not recorded) | arm64e.v1/PAC; 10 IPAs from the final acceptance of this fix passed structural S2; historical S3/S4 confirmed by the user for UI, Foundation/Dispatch, TortureTest 37/37, debug, hybrid, CoreML/Vision/Accelerate, FoundationModels, NaturalLanguage, and NLEmbedding |

## Not tested / outside the operational matrix

- arm64 profile: **discontinued**, it is not a build, fallback, or acceptance
  target.
- Other iPhone/iPad models and iSH on iPad.
- Other iOS, SDK, or LiveContainer versions; the exact LiveContainer version for
  this validation was not recorded.
- Universal availability of FoundationModels: depends on region, language,
  device model, and model preparation.

The arm64e/PAC profile is the only operational and release profile.
The rows above describe observed evidence, not a promise of compatibility. The
Apple SDK and the generated modules are provided by the user and are not
distributed in this repository. `ISB_SYSROOT` defaults to
`/opt/isb/sysroot`; local mirrors can be selected explicitly.
Keep caches isolated per architecture and regenerate PCMs when the prefix
changes.

The `embedded/` host Swift directories were hidden during the Phase 5.2 test;
the complete arm64e acceptance still passed. They remain local cleanup
candidates.
