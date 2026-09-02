import Foundation

public enum HybridRuntimeLogic {
    public static func fibonacci(_ n: Int32) -> Int32 {
        var a: Int32 = 0; var b: Int32 = 1
        if n <= 0 { return a }
        for _ in 0..<n { let next = a &+ b; a = b; b = next }
        return a
    }
}
