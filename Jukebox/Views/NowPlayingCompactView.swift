//
//  NowPlayingCompactView.swift
//  Jukebox
//
//  Created by Codex on 9/13/25.
//

import SwiftUI
import AppKit

struct NowPlayingCompactView: View {

    // User Defaults
    @AppStorage("connectedApp") private var connectedApp: ConnectedApps = .spotify
    @AppStorage("nowPlayingAlwaysOnTop") private var nowPlayingAlwaysOnTop = false
    @AppStorage("nowPlayingWindowWidth") private var nowPlayingWindowWidth = 240.0
    @AppStorage("nowPlayingWindowHeight") private var nowPlayingWindowHeight = 240.0

    // View Model
    @ObservedObject var contentViewVM: ContentViewModel

    // States for animations
    @State private var isShowingPlaybackControls = false
    @State private var window: NSWindow?
    @State private var resizeStartFrame: NSRect?

    // Constants
    let primaryOpacity = 0.8
    let secondaryOpacity = 0.4

    private var seekFraction: Double {
        let d = contentViewVM.trackDuration
        guard d > 0 else { return 0 }
        return min(max(contentViewVM.seekerPosition / d, 0), 1)
    }

    var body: some View {
        ZStack {
            if contentViewVM.isRunning {
                Image(nsImage: contentViewVM.track.albumArt)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                VisualEffectView(material: .popover, blendingMode: .withinWindow)
                Text("Play something on \(contentViewVM.name)")
                    .foregroundColor(.primary.opacity(secondaryOpacity))
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(16)
            }

            if contentViewVM.isRunning {
                // Scrub bar + transport controls (centred, bottom)
                VStack(spacing: 8) {
                    Spacer()
                    if contentViewVM.trackDuration > 0 {
                        ScrubBar(
                            fraction: seekFraction,
                            onScrub: { f in
                                contentViewVM.isScrubbing = true
                                contentViewVM.seekerPosition = f * contentViewVM.trackDuration
                            },
                            onCommit: { f in
                                contentViewVM.seek(to: f * contentViewVM.trackDuration)
                                contentViewVM.isScrubbing = false
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
                        .cornerRadius(100)
                    }
                    playbackControls
                }
                .padding(Constants.NowPlaying.controlPadding)
                .opacity(isShowingPlaybackControls ? 1 : 0)

                // Resize grip (bottom-right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        resizeHandle
                    }
                }
                .padding(Constants.NowPlaying.controlPadding)
                .opacity(isShowingPlaybackControls ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowAccessor { resolved in
            if window == nil { window = resolved }
        })
        .clipShape(RoundedRectangle(cornerRadius: Constants.NowPlaying.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.linear(duration: 0.1)) {
                isShowingPlaybackControls = hovering
            }
        }
        .onReceive(contentViewVM.timer) { _ in
            contentViewVM.getCurrentSeekerPosition()
        }
        .contextMenu {
            Button("Unpin") {
                NSApplication.shared.sendAction(#selector(AppDelegate.togglePinnedMode), to: nil, from: nil)
            }
            Toggle("Keep on Top", isOn: Binding(
                get: { nowPlayingAlwaysOnTop },
                set: { _ in
                    NSApplication.shared.sendAction(#selector(AppDelegate.toggleAlwaysOnTop), to: nil, from: nil)
                }
            ))
            Divider()
            Button("Preferences…") {
                NSApplication.shared.sendAction(#selector(AppDelegate.showPreferences), to: nil, from: nil)
            }
            Button("Quit Jukebox") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.primary.opacity(primaryOpacity))
            .padding(7)
            .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
            .clipShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let window else { return }
                        if resizeStartFrame == nil { resizeStartFrame = window.frame }
                        guard let start = resizeStartFrame else { return }
                        // Bottom-right grip: drag right/down grows; pin the top-left corner.
                        let delta = max(value.translation.width, value.translation.height)
                        let minS = Constants.NowPlaying.minWindowSize
                        let maxS = Constants.NowPlaying.maxWindowSize
                        let side = min(max(start.size.width + delta, minS), maxS)
                        let topY = start.origin.y + start.size.height
                        let frame = NSRect(x: start.origin.x, y: topY - side, width: side, height: side)
                        window.setFrame(frame, display: true)
                    }
                    .onEnded { _ in
                        if let window {
                            nowPlayingWindowWidth = window.frame.size.width
                            nowPlayingWindowHeight = window.frame.size.height
                        }
                        resizeStartFrame = nil
                    }
            )
            .help("Drag to resize")
    }

    private var playbackControls: some View {
        HStack(spacing: 6) {
            if case connectedApp = ConnectedApps.appleMusic {
                Button {
                    contentViewVM.toggleLoveTrack()
                } label: {
                    Image(systemName: contentViewVM.isLoved ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundColor(.primary.opacity(primaryOpacity))
                }.pressButtonStyle()
            }
            Button {
                contentViewVM.previousTrack()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary.opacity(primaryOpacity))
            }
            .pressButtonStyle()

            Button {
                contentViewVM.togglePlayPause()
            } label: {
                Image(systemName: contentViewVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.primary.opacity(primaryOpacity))
                    .frame(width: 25, height: 25)
            }
            .pressButtonStyle()

            Button {
                contentViewVM.nextTrack()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary.opacity(primaryOpacity))
            }
            .pressButtonStyle()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
        .cornerRadius(100)
    }
}

/// Thin click + drag seek bar. Sits inside a translucent pill for legibility.
struct ScrubBar: View {
    let fraction: Double             // 0...1 current playback fraction
    let onScrub: (Double) -> Void    // continuous drag updates
    let onCommit: (Double) -> Void   // final value on release

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.3))
                Capsule()
                    .fill(Color.primary.opacity(0.9))
                    .frame(width: min(max(fraction, 0), 1) * width)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        onScrub(min(max(value.location.x / width, 0), 1))
                    }
                    .onEnded { value in
                        guard width > 0 else { return }
                        onCommit(min(max(value.location.x / width, 0), 1))
                    }
            )
        }
        .frame(height: 6)
    }
}

/// Resolves the hosting NSWindow so SwiftUI can drive window-level resizing.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
