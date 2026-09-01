// AppLogic.swift — pure-Swift business logic for an iOS app built on-device.
//
// Write ALL your app logic here in modern Swift: structs, enums, generics,
// closures, arrays, string processing, algorithms, etc. These modules import
// fine on iSH: Swift, _Concurrency, _StringProcessing, Darwin, ObjectiveC,
// CoreFoundation, Combine, Observation, System.
//
// Do NOT `import UIKit`/`import SwiftUI` here (blocked on iSH — see
// references/LIMITATIONS.md). The UI lives in AppShell.m (Objective-C).
//
// Expose entry points to the ObjC shell with @_cdecl("c_symbol_name").
// Only C-compatible types cross the boundary (Int32, Double, C pointers).
// To return strings, fill a caller-provided C buffer (see example below).

@_cdecl("swift_fibonacci")
public func swiftFibonacci(_ n: Int32) -> Int32 {
    var a = 0, b = 1
    for _ in 0..<Int(n) { (a, b) = (b, a + b) }
    return Int32(a)
}

@_cdecl("swift_sum_of_squares")
public func swiftSumOfSquares(_ n: Int32) -> Int32 {
    let squares = (1...max(1, Int(n))).map { $0 * $0 }
    return Int32(squares.reduce(0, +))
}

// Returning text across the boundary: write UTF-8 into a C char buffer.
// ObjC side: char buf[128]; swift_describe(n, buf, sizeof(buf));
@_cdecl("swift_describe")
public func swiftDescribe(_ n: Int32, _ out: UnsafeMutablePointer<CChar>, _ cap: Int32) {
    let text = "n=\(n) · fib=\(swiftFibonacci(n)) · Σi²=\(swiftSumOfSquares(n))"
    let bytes = Array(text.utf8)
    let count = min(bytes.count, Int(cap) - 1)
    for i in 0..<count { out[i] = CChar(bitPattern: bytes[i]) }
    out[count] = 0
}
