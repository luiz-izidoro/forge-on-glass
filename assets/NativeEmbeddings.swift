import Foundation

@_silgen_name("radar_native_embedding_available")
public func radar_native_embedding_available() -> Int32

@_silgen_name("radar_sentence_embedding_dimension")
public func radar_sentence_embedding_dimension() -> Int32

@_silgen_name("radar_get_sentence_embedding")
public func radar_get_sentence_embedding(
    _ text: NSString,
    _ output: UnsafeMutablePointer<Double>,
    _ capacity: Int32,
    _ count: UnsafeMutablePointer<Int32>
) -> Int32

@_silgen_name("radar_native_embedding_error")
public func radar_native_embedding_error() -> NSString?

public enum NativeEmbeddings {
    public static var isAvailable: Bool { radar_native_embedding_available() != 0 }

    public static var lastError: String? { radar_native_embedding_error() as String? }

    public static var dimension: Int32 { radar_sentence_embedding_dimension() }

    /// Returns the system sentence embedding through a caller-owned buffer.
    public static func vector(for text: String) -> [Double]? {
        var values = Array(repeating: 0.0, count: 4096)
        var count: Int32 = 0
        let ok = values.withUnsafeMutableBufferPointer { buffer in
            radar_get_sentence_embedding(
                text as NSString, buffer.baseAddress!, Int32(buffer.count), &count)
        }
        guard ok != 0, count > 0, Int(count) <= values.count else { return nil }
        return Array(values.prefix(Int(count)))
    }
}
