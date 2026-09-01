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

Until that manual flow is exercised, the evidence level is S0/S1 for generation
and S2 for the arm64e IPA. `available` is a device capability, not proof that
this builder or a particular binary can generate text.
