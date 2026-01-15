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
    @AppStorage("nowPlayingPinned") private var nowPlayingPinned = false

    // View Model
    @ObservedObject var contentViewVM: ContentViewModel

    // States for animations
    @State private var isShowingPlaybackControls = false

    // Constants
    let primaryOpacity = 0.8
    let secondaryOpacity = 0.4

    var body: some View {
        let size = Constants.NowPlaying.windowSize

        ZStack {
            if contentViewVM.isRunning {
                Image(nsImage: contentViewVM.track.albumArt)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
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
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        pinButton
                    }
                }
                .padding(Constants.NowPlaying.controlPadding)
                .opacity(isShowingPlaybackControls ? 1 : 0)

                VStack {
                    Spacer()
                    playbackControls
                }
                .padding(Constants.NowPlaying.controlPadding)
                .opacity(isShowingPlaybackControls ? 1 : 0)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Constants.NowPlaying.cornerRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(.linear(duration: 0.1)) {
                isShowingPlaybackControls = hovering
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
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
        .cornerRadius(100)
    }

    private var pinButton: some View {
        Button {
            NSApplication.shared.sendAction(#selector(AppDelegate.togglePinnedMode), to: nil, from: nil)
        } label: {
            Image(systemName: nowPlayingPinned ? "pin.square.fill" : "pin.square")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary.opacity(primaryOpacity))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
        .cornerRadius(100)
    }

}
