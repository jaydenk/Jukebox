# Floating Window Corner Resize Grips — Design

- **Date:** 2026-11-16
- **Status:** Implemented in 8310fea (v1.3.5, 2026-11-16) — manual pass on macOS 27; not yet released
- **Branch:** `chore/macos-27-compat`
- **Target release:** v1.3.5
- **Size:** small change (short design)

## Intent

Resizing the pinned floating window works, but it is hard to start: the only grab area
is AppKit's invisible resize border for borderless windows, a few points wide, partly
cut away by the 12 pt rounded corners. Jayden wants a visible affordance that appears
as the cursor nears a corner, making the corner easy to grab. All four corners.

## Goals / non-goals / anti-goals

- **Goals:** a grip appears at whichever corner the cursor approaches; pressing it
  resizes from that corner with a grab area much larger than today's border; the
  window stays square and within 200–360 pt; size and position are remembered as now.
- **Non-goals:** free-aspect resizing; changing the size bounds; resizing the popover.
- **Anti-goals:** grips that clutter the artwork at rest; grips that steal the
  drag-to-move gesture (`WindowDragArea`) or make the controls/scrub bar hard to use.

## Approaches

1. **Self-drawn grips with our own resize tracking — chosen.** We draw the grips and
   run the resize ourselves, so the grab area can be as large as we like.
2. **Draw grips over the native border, let AppKit resize.** Rejected: shows where to
   grab but the hit target is still the thin native border, so it doesn't fix the problem.
3. **Thicken the native resize border.** Rejected: AppKit has no public API for this on a
   borderless window (checked in the macOS 27.2 SDK `NSWindow.h`); private API would be
   fragile.

## Design

**Reveal.** The compact view tracks the cursor (`onContinuousHover`, macOS 13+). When the
cursor is within 48 pt of a corner, that corner's grip fades in (0.12 s); it fades out
(0.4 s) when the cursor moves away. At most one grip is visible at a time. *(48 pt is my
call — enough lead-in to notice before arriving at the corner.)*

**Look.** A short arc hugging the window's 12 pt corner radius, inset ~4 pt from the
edge: 3 pt stroke, white at ~85% with a soft shadow so it reads on light and dark
artwork. *(My call; tunable after seeing it.)*

```
┌──────────────────┐        ╭─────────────────╮
│                  │        │╭                │   ← grip arc at the corner the
│     artwork      │  →     │     artwork     │      cursor is near
│                  │        │                 │
└──────────────────┘        ╰─────────────────╯
```

**Grab area.** A 24 × 24 pt AppKit view in each corner, above the artwork, the drag area
and the hover controls. Inside it the grip wins: at the bottom corners it overlaps the
rounded ends of the scrub-bar pill, so the bar's very ends can't be *clicked* there, but
scrubbing to 0%/100% still works by dragging. *(My call — corners take priority because
that's the whole point of the feature.)* The native thin border stays as a fallback.

**Cursor.** The grab area shows the native diagonal resize cursor via
`NSCursor.frameResize(position:directions:)` (macOS 15+); on macOS 13–14 the cursor is
unchanged (no public diagonal cursor exists there).

**Resize behaviour.** Owned by `NowPlayingWindow` (AppKit): the grip view hands it the
mouse-down and the corner; the window tracks the drag until mouse-up. The opposite corner
stays fixed; the side length follows the larger of the horizontal/vertical drag
distances, clamped to `Constants.NowPlaying.minWindowSize`…`maxWindowSize`. The clamp/anchor
maths is a pure function.

**Integration.** Because our resize doesn't produce AppKit's live-resize notifications,
`NowPlayingWindow` exposes begin/end callbacks that `AppDelegate` wires to the same code the
live-resize delegate methods use today: hide the hover controls (`isResizing`), pause/resume
the position timer, and on end persist size + origin. The active grip stays visible while
dragging; the others stay hidden.

## Left to the builder

Exact stroke/inset/shadow values, the event-tracking loop details, and how the SwiftUI
reveal state is passed to the four grips.

## Verification (manual — no test target)

1. Hover near each corner → only that grip appears; moving away fades it out.
2. Drag each grip → opposite corner stays put, stays square, stops at 200 and 360.
3. Resize cursor shows over the grab area (macOS 15+).
4. Controls hide during the resize and return after; quit + relaunch keeps size + position.
5. Drag-to-move, controls, scrub bar and right-click menu still work.
