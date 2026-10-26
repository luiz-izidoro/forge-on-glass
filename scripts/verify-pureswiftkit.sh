#!/bin/sh
# verify-pureswiftkit.sh — prove the compatibility helpers with the configured profile.
set -eu
SKILL=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
A="$SKILL/assets"
W=/tmp/verify-pskit
rm -rf $W && mkdir -p $W

cat > $W/uses.swift <<'EOF'
import Foundation
import UIKit
import CoreText
import Dispatch

// BUG 5 + CGRect: complete geometry via helpers
func geo() -> [CGFloat] {
    let r = cgRect(10, 20, 100, 50)
    return [r.cgMinX, r.cgMidX, r.cgMaxX, r.cgMinY, r.cgMidY, r.cgMaxY,
            r.cgWidth, r.cgHeight,
            r.cgInsetBy(dx: 5, dy: 5).cgWidth,
            r.cgOffsetBy(dx: 5, dy: 5).cgMinX,
            r.cgUnion(cgRect(0, 0, 10, 10)).cgWidth,
            r.cgIntersection(cgRect(0, 0, 50, 50)).cgWidth,
            cgRectZero.cgWidth, cgPointZero.x, cgSizeZero.width,
            cgAffineIdentity.a,
            cgAffineTranslate(1, 2).tx,
            cgAffineScale(2, 2).a,
            cgAffineRotate(1.0).a]
}
func geoBools() -> [Bool] {
    let r = cgRect(0, 0, 100, 100)
    return [r.cgIntersects(cgRect(50, 50, 100, 100)),
            r.cgContains(cgPoint(10, 10)),
            r.cgContains(cgRect(1, 1, 2, 2)),
            r.cgEquals(r), r.cgIsEmpty, r.cgIsNull,
            cgPointZero.cgEquals(cgPointZero),
            cgSizeZero.cgEquals(cgSizeZero)]
}

// BUG 2: CGContext
final class Desenho: UIView {
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.cgSaveState()
        ctx.cgMove(to: cgPoint(0, 0))
        ctx.cgAddLine(to: cgPoint(10, 10))
        ctx.cgAddArc(center: cgPoint(5, 5), radius: 3, startAngle: 0, endAngle: 3.14)
        ctx.cgSetLineDash(phase: 0, lengths: [3, 3])
        ctx.cgAddRect(cgRect(0, 0, 5, 5))
        ctx.cgStrokeRect(cgRect(0, 0, 5, 5))
        ctx.cgSetLineDash(phase: 0, lengths: [])
        ctx.cgClosePath()
        ctx.strokePath()
        ctx.cgRestoreState()
    }
}

// BUG 3: Seconds instead of TimeInterval
func anima(_ v: UIView, duracao: Seconds = 0.3, atraso: Seconds = 0) -> Seconds {
    return duracao + atraso
}

// BUG 6: edge insets
func insets() -> UIEdgeInsets { edgeInsets(1, 2, 3, 4) }

// BUG 4: FileManager by path
func files() -> [String] {
    let d = FS.documentsPath
    FS.makeDirectory(d + "/x")
    _ = FS.exists(d); _ = FS.isDirectory(d)
    _ = FS.size(d); _ = FS.modified(d)
    _ = FS.copy(d + "/a", to: d + "/b")
    _ = FS.tempPath
    return FS.listRecursive(d, suffix: ".json")
}

// BUG 7: dequeue in both collections
final class Listas: NSObject {
    func collection() -> UICollectionViewDiffableDataSource<Int, Int> {
        let l = UICollectionViewFlowLayout()
        l.itemSize = cgSize(50, 50)
        let cv = UICollectionView(frame: cgRect(0, 0, 100, 100), collectionViewLayout: l)
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "c")
        return UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) { cv, ip, _ in
            cv.cgDequeueCell("c", ip)
        }
    }
    func tabela() -> UITableViewDiffableDataSource<Int, Int> {
        let tv = UITableView(frame: cgRect(0, 0, 100, 100), style: .plain)
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "t")
        return UITableViewDiffableDataSource<Int, Int>(tableView: tv) { tv, ip, _ in
            tv.cgDequeueCell("t", ip)
        }
    }
}
EOF

cat > $W/main.swift <<'EOF'
import Foundation
import UIKit
import CoreText
import Dispatch
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func applicationDidFinishLaunching(_ a: UIApplication) {
        _ = geo(); _ = geoBools(); _ = insets(); _ = files()
        _ = Listas().collection(); _ = Listas().tabela()
        _ = anima(UIView())
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))
EOF

echo "==> compiling an app that exercises ALL workarounds..."
/var/minis/skills/forge-on-glass/scripts/build-pure-ui.sh \
  VerifyPSKit ro.izido.verify "$W/uses.swift $A/PureSwiftKit.swift $W/main.swift"

echo ""
echo "✅ PureSwiftKit covers all catalogued degradations."
rm -f /var/minis/workspace/VerifyPSKit.ipa
