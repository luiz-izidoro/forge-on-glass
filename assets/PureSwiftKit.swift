// PureSwiftKit.swift — compatibility layer for 100% Swift apps on iSH.
//
// Collects workarounds maintained by the arm64e/PAC profile.
//
// USAGE: add this file to the build along with your sources:
//   build-pure-ui.sh MeuApp com.x.y "Views.swift PureSwiftKit.swift main.swift"
//
// IMPORT ORDER (rule #0 — applies to ALL your files):
//   import Foundation      // always 1st
//   import SwiftUI         // if used
//   import UIKit
//   import CoreText        // for NSAttributedString.Key
//   import Dispatch        // always AFTER UIKit
import Foundation
import UIKit
import CoreText
import Dispatch

// ============================================================== BUG 3 =======
// `TimeInterval` goes out of scope when UIKit is imported. `Double` is the
// same type — use this alias to keep the intent readable.
public typealias Seconds = Double

// ======================================================== BUGS 5 and CGRect ===
// The convenience members of CGRect/CGPoint/CGSize live in an
// `extension CoreFoundation.CGRect` marked @_alwaysEmitIntoClient and remain
// invisible. The equivalent C functions work — that is what we use here.
// VALIDATED AT RUNTIME: TortureTest 37/37 on device.

@inline(__always)
public func cgRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    var r = CGRect()
    r.origin.x = CGFloat(x); r.origin.y = CGFloat(y)
    r.size.width = CGFloat(w); r.size.height = CGFloat(h)
    return r
}

@inline(__always)
public func cgPoint(_ x: Double, _ y: Double) -> CGPoint {
    return CGPoint(x: CGFloat(x), y: CGFloat(y))   // this init works
}

@inline(__always)
public func cgSize(_ w: Double, _ h: Double) -> CGSize {
    return CGSize(width: CGFloat(w), height: CGFloat(h))  // same
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
    /// BUG 5: `.width`/`.height` do not exist either.
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
// CGContext uses the modern instance API in this patched SDK. The equivalent
// C functions are marked unavailable and must not be used here.
// (They work in the overlay: setFillColor, fill, setStrokeColor, setLineWidth,
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
    /// Dashed line. Empty `lengths` = back to a solid stroke.
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
// UIEdgeInsetsMake does not exist; the init works. Helper for symmetry.
@inline(__always)
public func edgeInsets(_ top: Double, _ left: Double,
                       _ bottom: Double, _ right: Double) -> UIEdgeInsets {
    UIEdgeInsets(top: CGFloat(top), left: CGFloat(left),
                 bottom: CGFloat(bottom), right: CGFloat(right))
}

// ============================================================== BUG 7 =======
// The DiffableDataSource closure delivers `IndexPath`, but
// `dequeueReusableCell(withReuseIdentifier:for:)` expects `NSIndexPath`.
// VALIDATED AT RUNTIME (TortureTest: "numberOfItems via UIKit = 2").
//
// ⚠️ MEASURED SUBTLETY: the correct form CHANGES with context —
//   • inside `extension`/method .......... WITHOUT `as IndexPath`
//   • in an inline closure in a function body .. WITH `as IndexPath`
// Use the helpers below and stop thinking about it.

extension UICollectionView {
    /// Safe dequeue from the IndexPath delivered by the cellProvider.
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
// FileManager becomes unstable with UIKit in scope (Accessibility reexports
// NSFileManager differently) and the URL-based overload of the enumerator disappears.
// These helpers ALWAYS use the path-based APIs, which are reliable.

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

    /// Recursive listing. Uses `enumerator(atPath:)` — the URL-based version
    /// disappears when UIKit is imported (BUG 4).
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
