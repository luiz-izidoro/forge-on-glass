// PureSwiftKit.swift — camada de compatibilidade para apps 100% Swift no iSH.
//
// Reúne, num arquivo só, os workarounds de TODAS as degradações conhecidas do
// toolchain (ver references/BUG-REPORTS-2026-08-19.md). Substitui o antigo
// CGCompat.swift, que cobria apenas a geometria.
//
// USO: adicione este arquivo ao build junto dos seus fontes:
//   build-pure-ui.sh MeuApp com.x.y "Views.swift PureSwiftKit.swift main.swift"
//
// ORDEM DOS IMPORTS (regra nº 0 — vale para TODOS os seus arquivos):
//   import Foundation      // sempre 1º
//   import SwiftUI         // se usar
//   import UIKit
//   import CoreText        // p/ NSAttributedString.Key
//   import Dispatch        // sempre DEPOIS de UIKit
import Foundation
import UIKit
import CoreText
import Dispatch

// ============================================================== BUG 3 =======
// `TimeInterval` sai de escopo quando UIKit está importado. `Double` é o
// mesmo tipo — use este alias para manter a intenção legível.
public typealias Seconds = Double

// ======================================================== BUGS 5 e CGRect ===
// Os membros de conveniência de CGRect/CGPoint/CGSize vivem numa
// `extension CoreFoundation.CGRect` marcada @_alwaysEmitIntoClient e ficam
// invisíveis. As funções C equivalentes funcionam — é o que usamos aqui.
// VALIDADO EM RUNTIME: TortureTest 37/37 no device.

@inline(__always)
public func cgRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    var r = CGRect()
    r.origin.x = CGFloat(x); r.origin.y = CGFloat(y)
    r.size.width = CGFloat(w); r.size.height = CGFloat(h)
    return r
}

@inline(__always)
public func cgPoint(_ x: Double, _ y: Double) -> CGPoint {
    return CGPoint(x: CGFloat(x), y: CGFloat(y))   // este init funciona
}

@inline(__always)
public func cgSize(_ w: Double, _ h: Double) -> CGSize {
    return CGSize(width: CGFloat(w), height: CGFloat(h))  // idem
}

public let cgRectZero = CGRectZero
public let cgRectNull = CGRectNull
public let cgRectInfinite = CGRectInfinite
public let cgPointZero = CGPointZero
public let cgSizeZero = CGSizeZero
public let cgAffineIdentity = CGAffineTransformIdentity

extension CGRect {
    public var cgMinX: CGFloat { CGRectGetMinX(self) }
    public var cgMidX: CGFloat { CGRectGetMidX(self) }
    public var cgMaxX: CGFloat { CGRectGetMaxX(self) }
    public var cgMinY: CGFloat { CGRectGetMinY(self) }
    public var cgMidY: CGFloat { CGRectGetMidY(self) }
    public var cgMaxY: CGFloat { CGRectGetMaxY(self) }
    /// BUG 5: `.width`/`.height` também não existem.
    public var cgWidth: CGFloat { CGRectGetWidth(self) }
    public var cgHeight: CGFloat { CGRectGetHeight(self) }
    public var cgIsEmpty: Bool { CGRectIsEmpty(self) }
    public var cgIsNull: Bool { CGRectIsNull(self) }
    public var cgStandardized: CGRect { CGRectStandardize(self) }
    public var cgIntegral: CGRect { CGRectIntegral(self) }

    public func cgInsetBy(dx: Double, dy: Double) -> CGRect {
        CGRectInset(self, CGFloat(dx), CGFloat(dy))
    }
    public func cgOffsetBy(dx: Double, dy: Double) -> CGRect {
        CGRectOffset(self, CGFloat(dx), CGFloat(dy))
    }
    public func cgUnion(_ o: CGRect) -> CGRect { CGRectUnion(self, o) }
    public func cgIntersection(_ o: CGRect) -> CGRect { CGRectIntersection(self, o) }
    public func cgIntersects(_ o: CGRect) -> Bool { CGRectIntersectsRect(self, o) }
    public func cgContains(_ p: CGPoint) -> Bool { CGRectContainsPoint(self, p) }
    public func cgContains(_ r: CGRect) -> Bool { CGRectContainsRect(self, r) }
    public func cgEquals(_ r: CGRect) -> Bool { CGRectEqualToRect(self, r) }
}

extension CGPoint {
    public func cgEquals(_ p: CGPoint) -> Bool { CGPointEqualToPoint(self, p) }
}

extension CGSize {
    public func cgEquals(_ s: CGSize) -> Bool { CGSizeEqualToSize(self, s) }
}

@inline(__always)
public func cgAffineTranslate(_ tx: Double, _ ty: Double) -> CGAffineTransform {
    CGAffineTransformMakeTranslation(CGFloat(tx), CGFloat(ty))
}

@inline(__always)
public func cgAffineScale(_ sx: Double, _ sy: Double) -> CGAffineTransform {
    CGAffineTransformMakeScale(CGFloat(sx), CGFloat(sy))
}

@inline(__always)
public func cgAffineRotate(_ radians: Double) -> CGAffineTransform {
    CGAffineTransformMakeRotation(CGFloat(radians))
}

// ============================================================== BUG 2 =======
// CGContext usa a API de instância moderna neste SDK patchado. As funções C
// equivalentes são marcadas unavailable e não devem ser usadas aqui.
// (Funcionam no overlay: setFillColor, fill, setStrokeColor, setLineWidth,
//  setLineCap, strokePath, beginPath, fillEllipse.)

extension CGContext {
    public func cgMove(to p: CGPoint) { move(to: p) }
    public func cgAddLine(to p: CGPoint) { addLine(to: p) }
    public func cgAddArc(center c: CGPoint, radius r: Double,
                         startAngle a0: Double, endAngle a1: Double,
                         clockwise: Bool = false) {
        addArc(center: c, radius: CGFloat(r), startAngle: CGFloat(a0),
               endAngle: CGFloat(a1), clockwise: clockwise)
    }
    /// Linha tracejada. `lengths` vazio = volta ao traço sólido.
    public func cgSetLineDash(phase: Double = 0, lengths: [Double]) {
        setLineDash(phase: CGFloat(phase), lengths: lengths.map { CGFloat($0) })
    }
    public func cgClosePath() { closePath() }
    public func cgAddRect(_ r: CGRect) { addRect(r) }
    public func cgStrokeRect(_ r: CGRect) { stroke(r) }
    public func cgSaveState() { saveGState() }
    public func cgRestoreState() { restoreGState() }
}

// ============================================================== BUG 6 =======
// UIEdgeInsetsMake não existe; o init funciona. Helper por simetria.
@inline(__always)
public func edgeInsets(_ top: Double, _ left: Double,
                       _ bottom: Double, _ right: Double) -> UIEdgeInsets {
    UIEdgeInsets(top: CGFloat(top), left: CGFloat(left),
                 bottom: CGFloat(bottom), right: CGFloat(right))
}

// ============================================================== BUG 7 =======
// O closure do DiffableDataSource entrega `IndexPath`, mas
// `dequeueReusableCell(withReuseIdentifier:for:)` espera `NSIndexPath`.
// VALIDADO EM RUNTIME (TortureTest: "numberOfItems via UIKit = 2").
//
// ⚠️ SUTILEZA MEDIDA: a forma correta MUDA conforme o contexto —
//   • dentro de `extension`/método .......... SEM  `as IndexPath`
//   • em closure inline no corpo de função .. COM  `as IndexPath`
// Use os helpers abaixo e não pense mais nisso.

extension UICollectionView {
    /// Dequeue seguro a partir do IndexPath entregue pelo cellProvider.
    public func cgDequeueCell(_ identifier: String,
                              _ ip: IndexPath) -> UICollectionViewCell {
        return dequeueReusableCell(
            withReuseIdentifier: identifier,
            for: NSIndexPath(item: ip.item, section: ip.section) as IndexPath)
    }
}

extension UITableView {
    public func cgDequeueCell(_ identifier: String,
                              _ ip: IndexPath) -> UITableViewCell {
        return dequeueReusableCell(
            withIdentifier: identifier,
            for: NSIndexPath(row: ip.row, section: ip.section) as IndexPath)
    }
}

// ============================================================== BUG 4 =======
// FileManager fica instável com UIKit no escopo (o Accessibility reexporta
// NSFileManager de forma diferente) e a overload URL-based do enumerator some.
// Estes helpers usam SEMPRE as APIs baseadas em path, que são confiáveis.

public enum FS {
    public static var documentsPath: String {
        NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    }

    public static var tempPath: String { NSTemporaryDirectory() }

    public static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let ok = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return ok && isDir.boolValue
    }

    @discardableResult
    public static func makeDirectory(_ path: String) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: path,
                                                    withIntermediateDirectories: true)
            return true
        } catch { return false }
    }

    /// Lista recursiva. Usa `enumerator(atPath:)` — a versão URL-based some
    /// quando UIKit está importado (BUG 4).
    public static func listRecursive(_ path: String,
                                     suffix: String? = nil) -> [String] {
        guard let e = FileManager.default.enumerator(atPath: path) else { return [] }
        var out: [String] = []
        while let item = e.nextObject() as? String {
            if let s = suffix, !item.hasSuffix(s) { continue }
            out.append(path + "/" + item)
        }
        return out
    }

    public static func size(_ path: String) -> Int {
        let a = try? FileManager.default.attributesOfItem(atPath: path)
        return (a?[.size] as? NSNumber)?.intValue ?? 0
    }

    public static func modified(_ path: String) -> Double {
        let a = try? FileManager.default.attributesOfItem(atPath: path)
        return (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    }

    @discardableResult
    public static func copy(_ from: String, to: String) -> Bool {
        try? FileManager.default.removeItem(atPath: to)
        do {
            try FileManager.default.copyItem(atPath: from, toPath: to)
            return true
        } catch { return false }
    }
}
