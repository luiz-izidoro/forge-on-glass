# FoundationModels runtime validation

`FoundationModelsSafeProbe.swift` proves only capability availability. The
separate `FoundationModelsProbe.swift` contains `LanguageModelSession.respond(to:)`
but generation requires a real iOS runtime and is not claimed by structural
acceptance. On-device validation must record:

- device model and iOS version;
- arm64/arm64e slice and host (LiveContainer or native);
- exact prompt, response, and latency;
- availability result and whether Apple Intelligence/model preparation was
  complete.

Until the manual device flow was exercised, generation was S0/S1. The user
confirmed that the generated runtime IPA executed successfully and completed
the real `LanguageModelSession.respond(to:)` path on the iPhone17,1 / iOS 26.6
host used for this project. This upgrades the flow to **S4**. The exact prompt,
response, and latency values were not included in the confirmation, so they are
not reproduced here.
