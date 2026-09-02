# FoundationModels runtime validation — S4 confirmed 2026-09-02

The `FoundationModelsSafeProbe.swift` IPA reports availability. The separate
`FoundationModelsRuntimeMain.swift` exercises the real
`LanguageModelSession.respond(to:)` path.

On iPhone17,1 / iOS 26.6 via LiveContainer, the user confirmed:

```text
availability=available
response=OK
latency=1995 ms
```

This is S4 for the FoundationModels runtime scenario. It is evidence for the
specific device, iOS, host and model state; it is not a universal availability
claim.

NLEmbedding bridge was also confirmed in the same environment with its phased
diagnostic:

```text
availability=true
error=none
dimension=640
vector_count=640
first=1.4632570128014777e-05
Fase 3=PASS
```

This is S4 for the NaturalLanguage bridge and its Objective-C-to-Swift buffer
path. The exact LiveContainer version was not recorded.
