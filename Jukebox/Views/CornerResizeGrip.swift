//
//  CornerResizeGrip.swift
//  Jukebox
//
//  A resize grip for one corner of the floating now playing window: a visible arc that
//  fades in as the cursor approaches the corner, over an AppKit grab area that runs the
//  window's own square resize (NowPlayingWindow.trackCornerResize).
//

import SwiftUI
import AppKit

struct CornerResizeGrip: View {
    let corner: WindowCorner
    let isVisible: Bool
    let onTrackingChanged: (Bool) -> Void

    var body: some View {
        ZStack {
            CornerGripArc(corner: corner)
                .stroke(Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: Constants.NowPlaying.gripStrokeWidth, lineCap: .round))
                .shadow(color: .black.opacity(0.35), radius: 2)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(false)
            CornerGrabArea(corner: corner, onTrackingChanged: onTrackingChanged)
        }
        .frame(width: Constants.NowPlaying.gripHitSize, height: Constants.NowPlaying.gripHitSize)
    }
}

/// A short arc concentric with the window's rounded corner, with straight tails, drawn
/// in a grip-sized square aligned to `corner`.
private struct CornerGripArc: Shape {
    let corner: WindowCorner
    private let tail: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let inset = Constants.NowPlaying.gripInset
        let radius = max(Constants.NowPlaying.cornerRadius - inset, 1)
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let hx: CGFloat = left ? 1 : -1    // direction along the horizontal edge, away from the corner
        let vy: CGFloat = top ? 1 : -1     // direction along the vertical edge, away from the corner (y down)
        let p = CGPoint(x: left ? rect.minX + inset : rect.maxX - inset,
                        y: top ? rect.minY + inset : rect.maxY - inset)
        var path = Path()
        path.move(to: CGPoint(x: p.x, y: p.y + vy * (radius + tail)))
        path.addArc(tangent1End: p,
                    tangent2End: CGPoint(x: p.x + hx * (radius + tail), y: p.y),
                    radius: radius)
        path.addLine(to: CGPoint(x: p.x + hx * (radius + tail), y: p.y))
        return path
    }
}

/// The grab area. AppKit so it can hand the mouse-down to the window's resize tracking
/// and show the native diagonal resize cursor.
private struct CornerGrabArea: NSViewRepresentable {
    let corner: WindowCorner
    let onTrackingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> GrabView {
        let view = GrabView()
        view.corner = corner
        view.onTrackingChanged = onTrackingChanged
        return view
    }

    func updateNSView(_ view: GrabView, context: Context) {
        view.corner = corner
        view.onTrackingChanged = onTrackingChanged
    }

    final class GrabView: NSView {
        var corner: WindowCorner = .bottomRight
        var onTrackingChanged: ((Bool) -> Void)?

        // Resizing works on the first click even when Jukebox isn't the active app.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        // This view resizes; it must never start a window move.
        override var mouseDownCanMoveWindow: Bool { false }
        // rightMouseDown is deliberately not overridden: it falls through the responder
        // chain to the hosting view so the window's context menu still opens here.

        override func mouseDown(with event: NSEvent) {
            guard let window = window as? NowPlayingWindow else { return }
            onTrackingChanged?(true)
            window.trackCornerResize(from: corner, with: event)
            onTrackingChanged?(false)
        }

        // A cursor-update tracking area (rather than cursor rects, which only apply in
        // the key window) so the resize cursor shows even when the panel isn't key.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }

        override func cursorUpdate(with event: NSEvent) {
            if #available(macOS 15, *) {
                NSCursor.frameResize(position: cursorPosition, directions: .all).set()
            } else {
                super.cursorUpdate(with: event)   // no public diagonal resize cursor before macOS 15
            }
        }

        @available(macOS 15, *)
        private var cursorPosition: NSCursor.FrameResizePosition {
            switch corner {
            case .topLeft: return .topLeft
            case .topRight: return .topRight
            case .bottomLeft: return .bottomLeft
            case .bottomRight: return .bottomRight
            }
        }
    }
}
