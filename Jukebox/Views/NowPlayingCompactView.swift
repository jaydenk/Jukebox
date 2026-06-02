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

    // View Model
    @ObservedObject var contentViewVM: ContentViewModel

    // States for animations
    @State private var isShowingPlaybackControls = false

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
                VStack(spacing: 8) {
                    Spacer()
                    playbackControls
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
                        .background(.regularMaterial, in: Capsule())
                    }
                }
                .padding(Constants.NowPlaying.controlPadding)
                .opacity((isShowingPlaybackControls && !contentViewVM.isResizing) ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Constants.NowPlaying.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            // Quick fade-in on hover, graceful fade-out when the cursor leaves.
            // Resize hiding is driven by isResizing (set without animation by the
            // window delegate), so it stays instant and is excluded from this fade.
            withAnimation(.easeOut(duration: hovering ? 0.12 : 1.5)) {
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
        .background(.regularMaterial, in: Capsule())
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
