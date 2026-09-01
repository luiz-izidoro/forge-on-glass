// NativeEmbeddings.swift — Swift-facing declarations for the reusable
// NaturalLanguage/NLEmbedding bridge. This file does not import NaturalLanguage,
// so it also works in the proven arm64 profile; the ObjC bridge links the SDK
// 26.5 framework and executes the system's on-device language model.
import Foundation

@_silgen_name("radar_sentence_embedding")
public func radar_sentence_embedding(_ text: NSString) -> NSData?

@_silgen_name("radar_native_embedding_available")
public func radar_native_embedding_available() -> Bool

public enum NativeEmbeddings {
    public static var isAvailable: Bool { radar_native_embedding_available() }

    /// Returns Float64 components encoded in NSData, or nil when the OS model
    /// is unavailable for the installed language pack.
    public static func vector(for text: String) -> [Double]? {
        guard let data = radar_sentence_embedding(text as NSString) else { return nil }
        let count = data.length / MemoryLayout<Double>.size
        var result = Array(repeating: 0.0, count: count)
        data.getBytes(&result, length: data.length)
        return result
    }
}
