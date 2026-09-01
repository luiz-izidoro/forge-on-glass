// PlatformVersionShim.swift — fornece `__isPlatformVersionAtLeast`.
//
// POR QUE (medido 2026-08-22): qualquer `if #available(iOS X, *)` no codigo
// (ou vindo de uma dependencia) gera uma chamada a
// `_$ss31_stdlib_isOSVersionAtLeast...` que por sua vez chama o builtin do
// compiler-rt `___isPlatformVersionAtLeast`. Esse simbolo vive em
// `libclang_rt.ios.a`, que so existe no toolchain da Apple — o toolchain
// swift.org para Linux nao traz a variante iOS. Resultado no link:
//
//   ld64.lld: error: undefined symbol: ___isPlatformVersionAtLeast
//
// Este shim implementa o builtin em Swift puro consultando o proprio sistema
// via ProcessInfo, o que da o comportamento CORRETO em runtime (nao e' um
// stub que sempre diz "sim").
//
// Assinatura C (compiler-rt):
//   int32_t __isPlatformVersionAtLeast(uint32_t Platform, uint32_t Major,
//                                      uint32_t Minor, uint32_t Subminor)
//
// Inclua este arquivo no build sempre que o link reclamar do simbolo.
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

// Variante com "device version" usada por alguns alvos (mesma semantica).
@_cdecl("__isOSVersionAtLeast")
public func __isOSVersionAtLeast(_ major: Int32, _ minor: Int32, _ subminor: Int32) -> Int32 {
    return __isPlatformVersionAtLeast(2, UInt32(max(0, major)),
                                      UInt32(max(0, minor)), UInt32(max(0, subminor)))
}
