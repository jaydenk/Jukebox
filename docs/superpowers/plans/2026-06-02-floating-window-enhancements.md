# Floating Window Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the pinned now-playing floating window resizable (square, remembered), replace its hover pin button with a right-click context menu, and add an on-hover click+drag seek bar that works for both Spotify and Apple Music.

**Architecture:** All changes are confined to the floating-window surface — `NowPlayingWindow`/`AppDelegate` in `JukeboxApp.swift`, `NowPlayingCompactView.swift`, plus a unified `seek(to:)` and an `isScrubbing` guard in `ContentViewModel`, and two size constants. Live position reuses the existing 0.1 s `ContentViewModel.timer`; the menu-bar bar re-syncs via the existing 1 Hz poll.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSPanel`), ScriptingBridge. macOS app, no test target — verification is `xcodebuild` compile + a manual checklist.

**Deviation from spec:** `ScrubBar` is a self-contained `struct` colocated in `NowPlayingCompactView.swift` (not its own file) because the project uses explicit `project.pbxproj` file references; a new file would need manual UUID surgery. Isolation is preserved at the struct level.

**Conventions:** Australian English in UI/docs. No `Co-Authored-By` in commits. Stage files explicitly — never `git add -A` (keeps the untracked `docs/superpowers/` spec+plan and `xcuserstate` out of commits).

---

### Task 1: Add window-size constants

**Files:**
- Modify: `Jukebox/Utilities/Constants.swift`

- [ ] **Step 1: Add min/max to the `NowPlaying` enum**

Replace:
```swift
    enum NowPlaying {
        static let windowSize = CGSize(width: 240, height: 240)
        static let cornerRadius: CGFloat = 12
        static let controlPadding: CGFloat = 10
    }
```
with:
```swift
    enum NowPlaying {
        static let windowSize = CGSize(width: 240, height: 240)   // default
        static let minWindowSize: CGFloat = 200
        static let maxWindowSize: CGFloat = 360
        static let cornerRadius: CGFloat = 12
        static let controlPadding: CGFloat = 10
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Jukebox/Utilities/Constants.swift
git commit -m "Add min/max floating window size constants"
```

---

### Task 2: Unified seek + scrubbing guard in ContentViewModel

**Files:**
- Modify: `Jukebox/ViewModels/ContentViewModel.swift`

- [ ] **Step 1: Add `isScrubbing` published flag**

After the existing seeker properties:
```swift
    @Published var trackDuration: Double = 0
    @Published var seekerPosition: Double = 0
```
add:
```swift
    @Published var isScrubbing = false
```

- [ ] **Step 2: Guard live polling while scrubbing**

Replace:
```swift
    func getCurrentSeekerPosition() {
        guard isRunning else { return }
        self.seekerPosition = connectedApp == .spotify
        ? Double(spotifyApp?.playerPosition ?? 0)
        : Double(appleMusicApp?.playerPosition ?? 0)
    }
```
with:
```swift
    func getCurrentSeekerPosition() {
        guard isRunning, !isScrubbing else { return }
        self.seekerPosition = connectedApp == .spotify
        ? Double(spotifyApp?.playerPosition ?? 0)
        : Double(appleMusicApp?.playerPosition ?? 0)
    }
```

- [ ] **Step 3: Replace Spotify-only `seekTrack()` with `seek(to:)`**

`seekTrack()` is defined but never called (verified via `rg seekTrack`). Replace:
```swift
    func seekTrack() {
        spotifyApp?.setPlayerPosition?(seekerPosition)
    }
```
with:
```swift
    func seek(to seconds: Double) {
        switch connectedApp {
        case .spotify:
            spotifyApp?.setPlayerPosition?(seconds)
        case .appleMusic:
            appleMusicApp?.setPlayerPosition?(seconds)
        }
        seekerPosition = seconds
    }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Jukebox/ViewModels/ContentViewModel.swift
git commit -m "Add unified seek(to:) for both apps and isScrubbing guard"
```

---

### Task 3: Make NowPlayingWindow resizable + square + bounded

**Files:**
- Modify: `Jukebox/JukeboxApp.swift` (the `NowPlayingWindow` class)

- [ ] **Step 1: Update the panel init**

Replace:
```swift
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
```
with:
```swift
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Resize: locked square, bounded so the album art never upscales noticeably
        aspectRatio = NSSize(width: 1, height: 1)
        let minS = Constants.NowPlaying.minWindowSize
        let maxS = Constants.NowPlaying.maxWindowSize
        contentMinSize = NSSize(width: minS, height: minS)
        contentMaxSize = NSSize(width: maxS, height: maxS)
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Jukebox/JukeboxApp.swift
git commit -m "Make floating window resizable, square-locked, and bounded"
```

---

### Task 4: Persist/restore size, add Keep-on-top action, timer lifecycle

**Files:**
- Modify: `Jukebox/JukeboxApp.swift` (`AppDelegate`)

- [ ] **Step 1: Add size AppStorage keys**

After:
```swift
    @AppStorage("nowPlayingWindowX") private var nowPlayingWindowX = 0.0
    @AppStorage("nowPlayingWindowY") private var nowPlayingWindowY = 0.0
```
add:
```swift
    @AppStorage("nowPlayingWindowWidth") private var nowPlayingWindowWidth = 240.0
    @AppStorage("nowPlayingWindowHeight") private var nowPlayingWindowHeight = 240.0
```

- [ ] **Step 2: Use saved size for the floating window's initial frame**

In `setupContentView()`, replace:
```swift
        let floatingSize = Constants.NowPlaying.windowSize
```
with:
```swift
        let floatingSize = NSSize(width: nowPlayingWindowWidth, height: nowPlayingWindowHeight)
```

- [ ] **Step 3: Restore size in `showNowPlayingWindow` and start the timer**

Replace:
```swift
    private func showNowPlayingWindow(relativeTo button: NSStatusBarButton) {
        applyNowPlayingWindowLevel()
        if let savedOrigin = savedNowPlayingWindowOrigin() {
            nowPlayingWindow.setFrameOrigin(savedOrigin)
        } else {
            positionNowPlayingWindow(relativeTo: button)
        }
        nowPlayingWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
```
with:
```swift
    private func showNowPlayingWindow(relativeTo button: NSStatusBarButton) {
        applyNowPlayingWindowLevel()
        let size = NSSize(width: nowPlayingWindowWidth, height: nowPlayingWindowHeight)
        if let savedOrigin = savedNowPlayingWindowOrigin() {
            nowPlayingWindow.setFrame(NSRect(origin: savedOrigin, size: size), display: true)
        } else {
            nowPlayingWindow.setContentSize(size)
            positionNowPlayingWindow(relativeTo: button)
        }
        nowPlayingWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        contentViewVM.startTimer()
    }
```

- [ ] **Step 4: Stop the timer when the floating window is hidden**

In `toggleNowPlayingPresentation`, the pinned+visible branch:
```swift
            if nowPlayingWindow.isVisible {
                nowPlayingWindow.orderOut(nil)
            } else {
```
becomes:
```swift
            if nowPlayingWindow.isVisible {
                nowPlayingWindow.orderOut(nil)
                contentViewVM.pauseTimer()
            } else {
```

In `togglePinnedMode`, the unpin branch:
```swift
        } else {
            nowPlayingWindow.orderOut(nil)
        }
```
becomes:
```swift
        } else {
            nowPlayingWindow.orderOut(nil)
            contentViewVM.pauseTimer()
        }
```

- [ ] **Step 5: Store size on resize end**

Replace:
```swift
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == nowPlayingWindow else { return }
        storeNowPlayingWindowOrigin(window.frame.origin)
    }
```
with:
```swift
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == nowPlayingWindow else { return }
        storeNowPlayingWindowOrigin(window.frame.origin)
        nowPlayingWindowWidth = window.frame.size.width
        nowPlayingWindowHeight = window.frame.size.height
    }
```

- [ ] **Step 6: Add the Keep-on-top action**

After `togglePinnedMode(_:)`, add:
```swift
    @objc func toggleAlwaysOnTop(_ sender: Any?) {
        nowPlayingAlwaysOnTop.toggle()   // didSet calls applyNowPlayingWindowLevel()
    }
```

- [ ] **Step 7: Build**

Run: `xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add Jukebox/JukeboxApp.swift
git commit -m "Persist floating window size, add Keep-on-top action and timer lifecycle"
```

---

### Task 5: Rewrite NowPlayingCompactView (fill, scrub bar, context menu) + ScrubBar

**Files:**
- Modify (full replacement): `Jukebox/Views/NowPlayingCompactView.swift`

- [ ] **Step 1: Replace the file contents**

```swift
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
                        .padding(.horizontal, 4)
                    }
                    playbackControls
                }
                .padding(Constants.NowPlaying.controlPadding)
                .opacity(isShowingPlaybackControls ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                NSApplication.terminate(nil)
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
}

/// Thin click + drag seek bar overlaid on the album art.
struct ScrubBar: View {
    let fraction: Double             // 0...1 current playback fraction
    let onScrub: (Double) -> Void    // continuous drag updates
    let onCommit: (Double) -> Void   // final value on release

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule()
                    .fill(Color.white.opacity(0.9))
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
        .frame(height: 4)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Jukebox/Views/NowPlayingCompactView.swift
git commit -m "Floating window: fill-to-window, hover scrub bar, right-click context menu"
```

---

### Task 6: README changelog

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a v1.3.0 changelog section above `### v1.2.1`**

Insert after `## Changelog`:
```markdown
### v1.3.0

- **Resizable floating window** — drag any edge to resize the pinned now playing window; it stays square and remembers its size as well as its position
- **Right-click menu** — right-click the floating window to unpin, toggle "keep on top", open preferences, or quit (the hover pin button has been removed)
- **Seek from the floating window** — hover to reveal a progress bar you can click or drag to scrub, now working for both Spotify and Apple Music

```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Document floating window enhancements in changelog"
```

---

### Task 7: Final build + manual verification

- [ ] **Step 1: Clean Release build**

Run: `xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Release -destination 'platform=macOS' clean build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Manual verification** (run the built app; quit the installed copy first)

1. Pin from the popover → floating window appears at the default size.
2. Drag an edge → resizes, stays square, clamps at 200 / 360 pt.
3. Hide + reshow → size & position retained. Quit + relaunch → still retained.
4. Hover → progress bar fades in above the controls and tracks position.
5. Click the bar to jump; drag to scrub — verify on **Spotify** and **Apple Music**.
6. Right-click → Unpin, Keep on Top (check state toggles + window level changes), Preferences…, Quit all work.
7. After a window scrub, the menu-bar progress line re-syncs within ~1 s.

- [ ] **Step 3: Confirm the PR diff is clean**

Run: `git diff --stat main..HEAD`
Expected: only `Constants.swift`, `ContentViewModel.swift`, `JukeboxApp.swift`, `NowPlayingCompactView.swift`, `README.md` — no `docs/superpowers/**`, no `xcuserstate`.

---

## Self-Review

- **Spec coverage:** resize+square+bounds (T1,T3), persist size+position (T4), right-click menu incl. Keep-on-top (T4,T5), remove hover pin (T5), scrub bar on hover click+drag (T5), Apple Music seek (T2), live position via 0.1 s timer (T4,T5), menu-bar re-sync (existing poll, noted). ✓
- **Placeholders:** none — every step has full code/commands. ✓
- **Type consistency:** `seek(to:)`, `isScrubbing`, `toggleAlwaysOnTop`, `ScrubBar(fraction:onScrub:onCommit:)`, `nowPlayingWindowWidth/Height` used consistently across tasks. ✓
- **Deviation noted:** `ScrubBar` colocated (no new pbxproj entry). ✓
