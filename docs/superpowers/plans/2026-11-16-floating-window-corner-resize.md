# Floating Window Corner Resize Grips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Visible, easy-to-grab resize grips at all four corners of the pinned floating window, revealed as the cursor approaches a corner.

**Architecture:** Pure square-resize and corner-proximity geometry lives in an AppKit-free file verified by a standalone `swiftc` script. `NowPlayingWindow` owns an event-tracking resize loop with begin/end callbacks that `AppDelegate` wires to the same code its live-resize delegate methods use. A SwiftUI grip (arc + AppKit grab view) per corner is layered above the hover controls in `NowPlayingCompactView`, revealed by `onContinuousHover`.

**Tech Stack:** Swift, AppKit + SwiftUI, macOS 13 deployment target, raw `.xcodeproj` (no synced folders), no test target — pure logic verified by `swiftc` script.

**Spec:** `docs/superpowers/specs/2026-11-16-floating-window-corner-resize-design.md`

## Global Constraints

- Deployment target stays macOS 13.0; anything newer is gated with `#available` (the resize cursor is macOS 15+).
- Size bounds: `Constants.NowPlaying.minWindowSize` (200) … `maxWindowSize` (360); window always square.
- Reveal radius 48 pt; grab area 24 × 24 pt; grip arc follows `Constants.NowPlaying.cornerRadius` (12), inset ~4 pt, 3 pt stroke, white ~85% + soft shadow; fade in 0.12 s, out 0.4 s.
- `Jukebox/Utilities/CornerResize.swift` imports **Foundation only** (so the verify script compiles it without AppKit/SwiftUI).
- New source files must be added to `Jukebox.xcodeproj/project.pbxproj` by hand: a `PBXFileReference`, a `PBXBuildFile`, the file ref in the right `PBXGroup` `children`, the build file in the `Jukebox` target's `PBXSourcesBuildPhase` — copy the shape of the existing `LogLine.swift` entries with fresh 24-hex IDs.
- Release build must stay at zero compiler warnings. UI/docs text in Australian English.
- Branch `chore/macos-27-compat`. **No per-task commits** — Jayden tests the build, then everything (incl. the earlier macOS 27 fixes) is committed together in Task 4.

## Review Focus

1. **A click on a grip without dragging** must not resize or move the window → `frame` with zero delta returns the start frame (Task 1 test).
2. **Diagonal drag with jitter on the other axis** must follow the dominant axis, not refuse to shrink → dominant-axis test (Task 1).
3. **Right-click inside a grab area** must still open the window's context menu → manual check in Task 4 (grab view must not swallow `rightMouseDown`).
4. **Releasing the mouse outside the window** must end the resize and persist the size → tracking loop ends on any `.leftMouseUp` (Task 2) + manual check (Task 4).
5. **Window at minimum size (200)** — reveal zones (48 pt) must not overlap so only one grip shows → proximity test at size 200 (Task 1).

---

### Task 1: Pure corner-resize geometry + verification script

**Files:**
- Create: `Jukebox/Utilities/CornerResize.swift`
- Create: `scripts/verify-corner-resize.swift`
- Modify: `Jukebox.xcodeproj/project.pbxproj` (add `CornerResize.swift` to the `Utilities` group + Sources phase)

**Interfaces:**
- Produces:
  - `enum WindowCorner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }`
  - `enum CornerResize`
    - `static func frame(start: CGRect, corner: WindowCorner, delta: CGVector, minSide: CGFloat, maxSide: CGFloat) -> CGRect` — **AppKit screen coordinates (y up)**; `delta` = current mouse − mouse at press.
    - `static func corner(near point: CGPoint, in size: CGSize, within radius: CGFloat) -> WindowCorner?` — **SwiftUI view coordinates (origin top-left, y down)**; Euclidean distance to the corner point, `<= radius`; nearest corner wins.

- [x] **Step 1: Write the failing verify script** `scripts/verify-corner-resize.swift`, same `expect`/`@main` shape as `scripts/verify-logging.swift`, header comment with the run command below. Assertions (start = `CGRect(x: 100, y: 100, width: 240, height: 240)`, min 200, max 360):
  - bottomRight, delta `(40, -40)` → `CGRect(x: 100, y: 60, width: 280, height: 280)` (top edge fixed at 340)
  - topLeft, delta `(-30, 10)` → `CGRect(x: 70, y: 100, width: 270, height: 270)` (bottom-right fixed)
  - topRight, delta `(500, 500)` → width/height `360`, origin `(100, 100)`
  - bottomLeft, delta `(100, 100)` (inward) → width `200`, origin `(140, 140)` (top-right fixed at 340,340)
  - bottomRight, delta `(-50, -10)` → dominant x (inward 50) → clamped `200`, origin `(100, 140)`
  - any corner, delta `(0, 0)` → equals `start`
  - `corner(near:)`, size 240, radius 48: `(10, 10)` → `.topLeft`; `(230, 230)` → `.bottomRight`; `(230, 10)` → `.topRight`; `(10, 230)` → `.bottomLeft`; `(120, 120)` → `nil`; `(40, 40)` → `nil` (56.6 > 48)
  - size 200: `(100, 5)` → `nil` (no zone reaches the mid-edge)

- [x] **Step 2: Run it to verify it fails**

Run: `swiftc Jukebox/Utilities/CornerResize.swift scripts/verify-corner-resize.swift -o "$TMPDIR/verify-corner-resize" && "$TMPDIR/verify-corner-resize"`
Expected: compile error (`CornerResize.swift` missing / `WindowCorner` not found).

- [x] **Step 3: Implement `CornerResize.swift`** (Foundation only). Algorithm for `frame` (not determined by the signature):

```swift
let sx: CGFloat = (corner == .topRight || corner == .bottomRight) ? 1 : -1   // outward x
let sy: CGFloat = (corner == .topLeft  || corner == .topRight)    ? 1 : -1   // outward y (y up)
let gx = sx * delta.dx, gy = sy * delta.dy
let grow = abs(gx) >= abs(gy) ? gx : gy                                       // dominant axis
let side = min(max(start.width + grow, minSide), maxSide)
let x = sx > 0 ? start.minX : start.maxX - side                               // anchor opposite corner
let y = sy > 0 ? start.minY : start.maxY - side
return CGRect(x: x, y: y, width: side, height: side)
```

- [x] **Step 4: Run the script to verify it passes** — same command; Expected: exits 0, no `FAIL:` output.

- [x] **Step 5: Add to the Xcode target** (pbxproj, per Global Constraints) and confirm: `xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Release -derivedDataPath "$TMPDIR/dd" build | grep -E "BUILD (SUCCEEDED|FAILED)"` → `BUILD SUCCEEDED`.

---

### Task 2: Window-side resize tracking + AppDelegate wiring

**Files:**
- Modify: `Jukebox/JukeboxApp.swift` (`NowPlayingWindow`; `AppDelegate.windowWillStartLiveResize` / `windowDidEndLiveResize`; `setupContentView`)

**Interfaces:**
- Consumes: `WindowCorner`, `CornerResize.frame(start:corner:delta:minSide:maxSide:)` (Task 1)
- Produces (on `NowPlayingWindow`):
  - `var onCornerResizeBegan: (() -> Void)?`
  - `var onCornerResizeEnded: (() -> Void)?`
  - `func trackCornerResize(from corner: WindowCorner, with mouseDown: NSEvent)`

- [x] **Step 1: Extract shared resize begin/end in `AppDelegate`:** `private func floatingResizeDidBegin()` (sets `contentViewVM.isResizing = true`, `pauseTimer()`) and `private func floatingResizeDidEnd()` (stores origin + width/height from `nowPlayingWindow.frame`, `isResizing = false`, `startTimer()`). `windowWillStartLiveResize` / `windowDidEndLiveResize` call them; behaviour unchanged.

- [x] **Step 2: Implement `trackCornerResize`:** record `frame` and `NSEvent.mouseLocation` (screen coords), call `onCornerResizeBegan`, loop on `nextEvent(matching: [.leftMouseDragged, .leftMouseUp])`: on drag `setFrame(CornerResize.frame(…, delta: current − start, minSide: Constants.NowPlaying.minWindowSize, maxSide: Constants.NowPlaying.maxWindowSize), display: true)`; on **any** `.leftMouseUp` break; then call `onCornerResizeEnded`.

- [x] **Step 3: Wire callbacks in `setupContentView`** after creating `nowPlayingWindow`: `onCornerResizeBegan = { [weak self] in self?.floatingResizeDidBegin() }`, `onCornerResizeEnded = { [weak self] in self?.floatingResizeDidEnd() }`.

- [x] **Step 4: Build** — command from Task 1 Step 5 → `BUILD SUCCEEDED`, no new warnings (`grep "warning:" | grep -v SourcePackages | grep -v appintentsmetadata` empty).

---

### Task 3: Corner grip view + reveal in the compact view

**Files:**
- Create: `Jukebox/Views/CornerResizeGrip.swift` (+ pbxproj entries in the `Views` group)
- Modify: `Jukebox/Utilities/Constants.swift` (`NowPlaying`)
- Modify: `Jukebox/Views/NowPlayingCompactView.swift`

**Interfaces:**
- Consumes: `WindowCorner`, `CornerResize.corner(near:in:within:)` (Task 1); `NowPlayingWindow.trackCornerResize(from:with:)` (Task 2)
- Produces:
  - `Constants.NowPlaying.gripRevealRadius = 48`, `gripHitSize = 24`, `gripInset = 4`, `gripStrokeWidth = 3`
  - `struct CornerResizeGrip: View { let corner: WindowCorner; let isVisible: Bool; let onTrackingChanged: (Bool) -> Void }`

- [x] **Step 1: `CornerResizeGrip`** = ZStack of (a) a `Shape` drawing a quarter-arc of radius `cornerRadius` inset `gripInset` at `corner`, stroked `gripStrokeWidth`, `Color.white.opacity(0.85)`, `.shadow(radius: 2)`, `.opacity(isVisible ? 1 : 0)`, `.allowsHitTesting(false)`; (b) an `NSViewRepresentable` grab view filling the `gripHitSize` square whose `mouseDown` calls `onTrackingChanged(true)`, `(window as? NowPlayingWindow)?.trackCornerResize(from: corner, with: event)`, then `onTrackingChanged(false)`. Grab view: `acceptsFirstMouse` → `true`; `mouseDownCanMoveWindow` → `false`; does **not** override `rightMouseDown` (context menu must reach the hosting view); `resetCursorRects` adds the frame-resize cursor for `corner` inside `if #available(macOS 15, *)` (verify the exact Swift spelling of `+[NSCursor frameResizeCursorFromPosition:inDirections:]` in the 27.2 SDK swiftinterface; directions = all).

- [x] **Step 2: Reveal state in `NowPlayingCompactView`:** `@State nearCorner: WindowCorner?`, `@State activeCorner: WindowCorner?`, `@State viewSize: CGSize` (captured with a `GeometryReader` in `.background`). Add `.onContinuousHover { phase in … }` on the root: `.active(p)` → `CornerResize.corner(near: p, in: viewSize, within: Constants.NowPlaying.gripRevealRadius)`, `.ended` → `nil`; apply changes `withAnimation(.easeOut(duration: newValue != nil ? 0.12 : 0.4))`.

- [x] **Step 3: Layer the grips** as the last children of the root `ZStack` (above the hover controls): `ForEach(WindowCorner.allCases)` → `CornerResizeGrip(corner:, isVisible: nearCorner == c || activeCorner == c, onTrackingChanged: { activeCorner = $0 ? c : nil })` framed `gripHitSize` square and aligned to its corner with `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment:)`. Shown whether or not a track is playing.

- [x] **Step 4: Build** (pbxproj updated) → `BUILD SUCCEEDED`, zero new warnings; re-run the Task 1 verify script → exits 0.

---

### Task 4: Clean-up, docs, verification, commit

**Files:**
- Modify: `Jukebox/JukeboxApp.swift` (remove every `[diag]` line and the diagnostic-only overrides: `NowPlayingWindow.sendEvent`, `SnapHostingView.setFrameSize`, `popoverShouldClose`, `windowWillResize(_:to:)`, `windowWillMove`, `windowDidResize`; keep the `popUp(positioning:at:in:)` menu fix, the container view, `savedNowPlayingWindowSize()`)
- Modify: `README.md` (v1.3.5 changelog), `docs/superpowers/specs/2026-06-02-floating-window-enhancements-design.md` (status line → shipped in v1.3.0), `TODO.md` (gitignored)

- [x] **Step 1: Remove instrumentation** — `grep -n "\[diag\]" Jukebox/JukeboxApp.swift` returns nothing.
- [x] **Step 2: README v1.3.5 entries** (Australian English): corner resize grips; floating window can be dragged to move again; floating window stays within its size limits and no longer crashes while resizing; right-click menu opens below the menu bar on macOS 27.
- [x] **Step 3: Clean Release build** → `BUILD SUCCEEDED`, zero compiler warnings; verify script exits 0.
- [x] **Step 4: Jayden's manual pass** (spec Verification 1–5, plus Review Focus 3 and 4).
- [x] **Step 5: Commit** everything on `chore/macos-27-compat` (macOS 27 work, fixes, grips, spec/plan docs incl. the two untracked June floating-window docs; never `TODO.md` or `xcuserstate`), message per user rules (no co-author/session trailers).

---

## Outcome (2026-11-16)

Executed inline (native) on `chore/macos-27-compat`; committed as `8310fea` with the
macOS 27 work. Verify script passes; Release build has zero warnings; Jayden's manual
pass on macOS 27 passed (reveal, resize + bounds, cursor, release outside window,
right-click on a grip, move/controls/scrub bar).

**Rulings made during execution**
- `CornerResize.swift` imports CoreGraphics as well as Foundation (`CGRect.width`/`minX`
  live there); still AppKit/SwiftUI-free, so the verify script compiles it standalone.
- No automated test for `trackCornerResize` or the grip view — AppKit event/layout code,
  no test target; covered by the geometry script plus the manual pass.
- Resize cursor uses an `.activeAlways` cursor-update tracking area instead of
  `resetCursorRects` — cursor rects only apply in the key window and the panel often isn't key.
- Grip arc radius = `cornerRadius − gripInset` (8 pt) with 6 pt straight tails.

**Final review** (fresh reviewer): 0 Critical, 2 Important — both fixed before commit:
- I1: corner resize bypassed `SnapHostingView`'s animation suppression →
  `NowPlayingWindow.isTrackingCornerResize`, checked in `SnapHostingView.layout()`.
- I2: a plain click on a grip ran the resize begin/end cycle → resize begins lazily on the
  first drag and ends only if it began.

**Deferred minors** (not fixed; candidates for a later release)
- M1 Size jumps when the dominant axis flips while dragging against the diagonal.
- M2 Tracking loop has no fallback if the system swallows the mouse-up (stays modal until the next click).
- M3 Resize start point read from `NSEvent.mouseLocation` rather than the mouse-down event.
- M4 Growing from a top corner isn't clamped to the screen's visible frame (can go under the menu bar).
- M5 The grab view's transparent outer corner tip may pass clicks to the window behind.
- M6 `popoverCloseRequested` could stay true if `popoverDidClose` never fires.
- M7 On macOS 27, right-click doesn't close an open popover before showing the menu.
- M9 Grip can stay visible after releasing outside the window until the next mouse move.
