import Foundation

// Standalone verification of the floating window's corner-resize geometry.
// Compiled together with the real source file (no copies). Run via:
//
//   swiftc Jukebox/Utilities/CornerResize.swift \
//          scripts/verify-corner-resize.swift -o "$TMPDIR/verify-corner-resize" \
//     && "$TMPDIR/verify-corner-resize"

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

@main
struct VerifyCornerResize {
    static func main() {
        // frame(start:corner:delta:minSide:maxSide:) — AppKit screen coordinates (y up).
        let start = CGRect(x: 100, y: 100, width: 240, height: 240)
        func frame(_ corner: WindowCorner, _ dx: CGFloat, _ dy: CGFloat) -> CGRect {
            CornerResize.frame(start: start, corner: corner, delta: CGVector(dx: dx, dy: dy),
                               minSide: 200, maxSide: 360)
        }

        var r = frame(.bottomRight, 40, -40)
        expect(r == CGRect(x: 100, y: 60, width: 280, height: 280),
               "bottomRight grows outward with top-left fixed, got \(r)")

        r = frame(.topLeft, -30, 10)
        expect(r == CGRect(x: 70, y: 100, width: 270, height: 270),
               "topLeft grows outward with bottom-right fixed, got \(r)")

        r = frame(.topRight, 500, 500)
        expect(r == CGRect(x: 100, y: 100, width: 360, height: 360),
               "topRight clamps to max with bottom-left fixed, got \(r)")

        r = frame(.bottomLeft, 100, 100)
        expect(r == CGRect(x: 140, y: 140, width: 200, height: 200),
               "bottomLeft clamps to min with top-right fixed, got \(r)")

        r = frame(.bottomRight, -50, -10)
        expect(r == CGRect(x: 100, y: 140, width: 200, height: 200),
               "dominant axis (inward x) wins over outward y jitter, got \(r)")

        for corner in WindowCorner.allCases {
            r = frame(corner, 0, 0)
            expect(r == start, "zero delta at \(corner) leaves the frame unchanged, got \(r)")
        }

        // corner(near:in:within:) — SwiftUI view coordinates (origin top-left, y down).
        let size = CGSize(width: 240, height: 240)
        func near(_ x: CGFloat, _ y: CGFloat, in s: CGSize = size) -> WindowCorner? {
            CornerResize.corner(near: CGPoint(x: x, y: y), in: s, within: 48)
        }
        expect(near(10, 10) == .topLeft, "(10,10) is near topLeft")
        expect(near(230, 230) == .bottomRight, "(230,230) is near bottomRight")
        expect(near(230, 10) == .topRight, "(230,10) is near topRight")
        expect(near(10, 230) == .bottomLeft, "(10,230) is near bottomLeft")
        expect(near(120, 120) == nil, "centre is near no corner")
        expect(near(40, 40) == nil, "(40,40) is 56.6 pt from the corner, outside 48")
        expect(near(100, 5, in: CGSize(width: 200, height: 200)) == nil,
               "at the 200 pt minimum no reveal zone reaches the middle of an edge")

        print("verify-corner-resize: all checks passed")
    }
}
