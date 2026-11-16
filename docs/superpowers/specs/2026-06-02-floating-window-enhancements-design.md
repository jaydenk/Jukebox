# Floating Window Enhancements — Design

- **Date:** 2026-06-02
- **Status:** Shipped in v1.3.0
- **Branch:** `feature/floating-window-enhancements`
- **Target release:** v1.3.0

## Summary

Four related improvements to the pinned "now playing" floating window
(`NowPlayingWindow` + `NowPlayingCompactView`):

1. Move the un-pin affordance from a hover button to a **right-click context menu**.
2. Add a **seekable progress bar** (click + drag to scrub) shown on hover.
3. Make the window **resizable**, locked to a square aspect ratio.
4. **Remember** the window's size as well as its (already-remembered) position.

All four touch the same surface and ship together as one PR.

## Goals / Non-goals

**Goals**
- Cleaner floating window: no permanent pin button; art stays unobstructed at rest.
- Scrub playback from the floating window for **both** Spotify and Apple Music.
- User-resizable square window with sensible bounds; size + position persist across
  hide/show and app relaunch.

**Non-goals**
- No change to the menu-bar popover's own pin button (that remains how you *enter*
  floating mode).
- No change to the menu-bar progress indicator (it already re-syncs after a seek via
  the v1.2.1 1 Hz reconciliation poll).
- No free-aspect resizing; no per-track dynamic max bound.

## Decisions (locked during brainstorming)

| Topic | Decision |
|---|---|
| Pin → right-click | Context menu: **Unpin**, **Keep on top** (✓ toggle), divider, **Preferences…**, **Quit Jukebox** |
| Progress bar | Appears on hover, above the playback controls; fades with them |
| Seek gesture | Click to jump **and** drag to scrub continuously |
| Resize | Locked to **square** aspect ratio |
| Size bounds | min **200 pt**, default **240 pt**, max **360 pt** |
| Persistence | Remember width/height + origin |

**Size-bound rationale:** Spotify exposes 640×640 artwork via its scripting bridge
(the `ab67616d0000b273` variant); Apple Music via ScriptingBridge is variable but
usually ≥600 px. On a 2× Retina display, 640 px art is pixel-crisp up to 320 pt
(640 ÷ 2). 360 pt upscales only ~1.12× (imperceptible) and stays well within
"no more than double the default". 200 pt is modestly below the 240 pt default.

## Architecture / components

| File | Change |
|---|---|
| `Jukebox/JukeboxApp.swift` | `NowPlayingWindow`: add `.resizable`, square `aspectRatio`, content min/max size. `AppDelegate`: persist + restore size; add `nowPlayingWindowWidth/Height` AppStorage; extend `windowDidEndLiveResize`; add `@objc toggleAlwaysOnTop`. |
| `Jukebox/Views/NowPlayingCompactView.swift` | Remove hover pin button; fill window instead of fixed frame; add `.contextMenu`; add `ScrubBar` to the hover overlay; drive the 0.1 s position timer while visible. |
| `Jukebox/Views/ScrubBar.swift` (new) | Small, single-purpose seekable bar (track + fill + click/drag gesture). |
| `Jukebox/ViewModels/ContentViewModel.swift` | Replace Spotify-only `seekTrack()` with `seek(to:)` covering both apps; add an `isScrubbing` guard so live polling doesn't fight an in-progress drag. |
| `Jukebox/Utilities/Constants.swift` | Add `NowPlaying.minWindowSize` / `maxWindowSize` (and keep `windowSize` as the default). |
| `README.md` | Changelog entry for v1.3.0. |

### 1 — Resizable, square, remembered size

- `NowPlayingWindow` style mask becomes `[.borderless, .resizable]` (still chrome-less;
  `.resizable` only adds invisible drag edges). Set `aspectRatio = NSSize(1, 1)`,
  `contentMinSize = 200×200`, `contentMaxSize = 360×360`.
- `NowPlayingCompactView` stops hard-framing to `Constants.NowPlaying.windowSize`; it
  fills the window (`.frame(maxWidth: .infinity, maxHeight: .infinity)`), letting the
  panel drive size. Album art already uses `scaledToFill().clipped()`.
- New `@AppStorage` keys `nowPlayingWindowWidth` / `nowPlayingWindowHeight` (defaulting
  to 240). `showNowPlayingWindow` restores size + origin via `setFrame(_:display:)`.
  `windowDidEndLiveResize` stores the new size alongside the origin it already stores.

### 2 — Right-click context menu

- Delete the hover `pinButton` from `NowPlayingCompactView` (and its now-unused state).
- Add `.contextMenu { … }` on the compact view root. Items invoke existing AppDelegate
  `@objc` actions via `NSApplication.shared.sendAction(_:to:from:)`, matching the current
  pin pattern:
  - **Unpin** → `togglePinnedMode`
  - **Keep on top** (checkmark bound to `@AppStorage("nowPlayingAlwaysOnTop")`) → new
    `@objc func toggleAlwaysOnTop` that flips the pref and calls
    `applyNowPlayingWindowLevel()`.
  - divider
  - **Preferences…** → `showPreferences`
  - **Quit Jukebox** → `NSApplication.terminate`
- Routing through AppDelegate actions (not a direct `@AppStorage` write from SwiftUI) is
  required because the AppDelegate's `nowPlayingAlwaysOnTop` `didSet` does **not** fire on
  external UserDefaults changes.

### 3 — Seekable progress bar

- New `ScrubBar` view: dim rounded track + solid fill where
  `fraction = position / duration` (guarded for duration > 0). Thin (≈4 pt), full width
  of the controls cluster, placed just above `playbackControls` inside the hover overlay
  so it fades in/out with the controls.
- Gesture: a `DragGesture(minimumDistance: 0)` so a bare click registers. While dragging,
  a local `@State dragFraction` drives the fill and the VM's `isScrubbing` flag is set so
  live polling is suppressed. On `.onEnded`, call
  `contentViewVM.seek(to: clamp(fraction) * duration)` and clear `isScrubbing`.
- Live position while the window is visible: `NowPlayingCompactView` calls
  `contentViewVM.getCurrentSeekerPosition()` from `.onReceive(contentViewVM.timer)` (the
  existing 0.1 s publisher), exactly like the popover's `ContentView`. The timer is
  started when the floating window is shown and stopped when it's hidden (popover and
  pinned window are mutually exclusive, so the start/stop lifecycle is shared).
- A tiny pure helper maps gesture-x ↔ fraction ↔ seconds so the arithmetic is unit-clear
  and reviewable.

### 4 — `ContentViewModel.seek(to:)`

```swift
func seek(to seconds: Double) {
    switch connectedApp {
    case .spotify:    spotifyApp?.setPlayerPosition?(seconds)
    case .appleMusic: appleMusicApp?.setPlayerPosition?(seconds)   // newly wired up
    }
    seekerPosition = seconds
}
```

Both scripting protocols already declare `setPlayerPosition(_:)`; Apple Music's was never
called before. After a seek, the menu-bar bar re-anchors automatically via the existing
1 Hz poll.

## Persistence summary

| Key | Existing? | Purpose |
|---|---|---|
| `nowPlayingWindowX` / `Y` | yes | window origin |
| `nowPlayingWindowHasPosition` | yes | origin-set flag |
| `nowPlayingWindowWidth` / `Height` | **new** | window size (square; both stored for safety) |
| `nowPlayingAlwaysOnTop` | yes | level (now toggled from the context menu too) |

## Verification (manual — no test target exists)

Build Release, then:

1. Pin from the popover → floating window appears.
2. **Resize** by dragging an edge — stays square; clamps at 200 / 360.
3. Hide + reshow, then quit + relaunch — **size and position persist**.
4. Hover — progress bar fades in above the controls; reflects current position.
5. **Click** the bar to jump; **drag** to scrub — verify on **both** Spotify and Apple Music.
6. Right-click — menu shows; **Unpin**, **Keep on top** (check state correct), **Preferences…**,
   **Quit** all work.
7. After a window scrub, confirm the **menu-bar** progress line re-syncs within ~1 s.

The fraction↔seconds helper is pure and could carry a lightweight check if a test target
is ever added; for now verification is manual.

## Out of scope / future

- Dynamically capping max size to the *actual* per-track artwork resolution (variable,
  confusing UX) — fixed 360 pt instead.
- Reworking Sparkle/release infra (tracked separately).
