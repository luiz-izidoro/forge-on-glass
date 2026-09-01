// FoundationModelsProbe.swift — minimal, macro-free native on-device AI API.
// Build only with ISB_ARCH=arm64e after foundation-build633-arm64e exists.
import Foundation
import FoundationModels

@available(iOS 26.0, *)
public enum NativeFoundationModels {
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public static func summarize(_ prompt: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
