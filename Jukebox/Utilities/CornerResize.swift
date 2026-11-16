//
//  CornerResize.swift
//  Jukebox
//
//  Pure geometry for the floating window's corner resize grips. Foundation + CoreGraphics only, so
//  scripts/verify-corner-resize.swift can compile and check it without AppKit/SwiftUI.
//

import Foundation
import CoreGraphics

enum WindowCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

enum CornerResize {

    /// The window frame for a square resize dragged from `corner`.
    ///
    /// AppKit screen coordinates (origin bottom-left, y up). `delta` is the current mouse
    /// location minus the mouse location at the press. The corner opposite `corner` stays
    /// fixed; the side length follows whichever axis moved further (so diagonal jitter on
    /// the other axis can't stop a shrink) and is clamped to `minSide...maxSide`.
    static func frame(start: CGRect, corner: WindowCorner, delta: CGVector,
                      minSide: CGFloat, maxSide: CGFloat) -> CGRect {
        let sx: CGFloat = (corner == .topRight || corner == .bottomRight) ? 1 : -1   // outward x
        let sy: CGFloat = (corner == .topLeft || corner == .topRight) ? 1 : -1       // outward y
        let gx = sx * delta.dx
        let gy = sy * delta.dy
        let grow = abs(gx) >= abs(gy) ? gx : gy
        let side = min(max(start.width + grow, minSide), maxSide)
        let x = sx > 0 ? start.minX : start.maxX - side
        let y = sy > 0 ? start.minY : start.maxY - side
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// The corner within `radius` of `point`, if any (the nearest one wins).
    ///
    /// SwiftUI view coordinates (origin top-left, y down), Euclidean distance.
    static func corner(near point: CGPoint, in size: CGSize, within radius: CGFloat) -> WindowCorner? {
        let corners: [(WindowCorner, CGPoint)] = [
            (.topLeft, CGPoint(x: 0, y: 0)),
            (.topRight, CGPoint(x: size.width, y: 0)),
            (.bottomLeft, CGPoint(x: 0, y: size.height)),
            (.bottomRight, CGPoint(x: size.width, y: size.height)),
        ]
        let nearest = corners
            .map { ($0.0, hypot(point.x - $0.1.x, point.y - $0.1.y)) }
            .min { $0.1 < $1.1 }
        guard let nearest, nearest.1 <= radius else { return nil }
        return nearest.0
    }
}
