// PlatformVersionShim.swift — provides `__isPlatformVersionAtLeast`.
//
// WHY (measured 2026-08-22): any `if #available(iOS X, *)` in the code
// (or coming from a dependency) generates a call to
// `_$ss31_stdlib_isOSVersionAtLeast...` which in turn calls the compiler-rt
// builtin `___isPlatformVersionAtLeast`. That symbol lives in
// `libclang_rt.ios.a`, which only exists in Apple's toolchain — the
// swift.org toolchain for Linux does not ship the iOS variant. Result at link time:
//
//   ld64.lld: error: undefined symbol: ___isPlatformVersionAtLeast
//
// This shim implements the builtin in pure Swift by querying the system
// itself via ProcessInfo, which gives the CORRECT runtime behavior (it is not
// a stub that always says "yes").
//
// C signature (compiler-rt):
//   int32_t __isPlatformVersionAtLeast(uint32_t Platform, uint32_t Major,
//                                      uint32_t Minor, uint32_t Subminor)
//
// Include this file in the build whenever the link complains about the symbol.
import Foundation

@_cdecl("__isPlatformVersionAtLeast")
public func __isPlatformVersionAtLeast(_ platform: UInt32,
                                       _ major: UInt32,
                                       _ minor: UInt32,
                                       _ subminor: UInt32) -> Int32 {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    let curMajor = v.majorVersion
    let curMinor = v.minorVersion
    let curPatch = v.patchVersion
    let wantMajor = Int(major)
    let wantMinor = Int(minor)
    let wantPatch = Int(subminor)
    if curMajor != wantMajor { return curMajor > wantMajor ? 1 : 0 }
    if curMinor != wantMinor { return curMinor > wantMinor ? 1 : 0 }
    return curPatch >= wantPatch ? 1 : 0
}

// Variant with "device version" used by some targets (same semantics).
@_cdecl("__isOSVersionAtLeast")
public func __isOSVersionAtLeast(_ major: Int32, _ minor: Int32, _ subminor: Int32) -> Int32 {
    return __isPlatformVersionAtLeast(2, UInt32(max(0, major)),
                                      UInt32(max(0, minor)), UInt32(max(0, subminor)))
}
