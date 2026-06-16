# Debug Logging Mode — Design

- **Date:** 2026-06-15
- **Status:** Implemented and shipped on `feature/debug-logging` (PR #4). Scope grew during on-device verification — see the Addendum (§9).
- **Author:** Jayden Kerr (with Claude)
- **Branch context:** implemented on `feature/debug-logging` (stacked on `feature/floating-window-enhancements`)

## 1. Background and motivation

While testing the Apple Music integration on macOS 26.5, playback progress works but
album art renders as an empty grey square, with nothing useful in the console. The app's
only diagnostics today are bare `print()` calls scattered through `ContentViewModel` and
`Helper`, which:

- go to stdout and are therefore invisible in a shipped build a user is running, and
- have **no failure-path logging** on the artwork code (the artwork poll loop silently
  assigns `NSImage()` on timeout), so there is genuinely nothing to observe.

We need a real debug-logging facility that serves two purposes:

1. **Diagnosis** — confirm the root cause of the missing album art (and future issues).
2. **Support** — let users send us logs when they hit a problem.

### Root-cause hypothesis (to confirm, not to fix here)

Jukebox talks to Music.app via **ScriptingBridge**, not MusicKit. The Apple Music artwork
path (`ContentViewModel.getTrackInformation()`) reads `art.data`
(`MusicApplication.swift`: `data: NSImage // ...in the form of a picture`). The interface
also exposes `rawData: Any // ...in original format`. On recent macOS, Music's legacy
`data` ("picture") property frequently returns nil/empty while `rawData` (the real
JPEG/PNG bytes) still works.

**This design adds logging only. It does NOT change artwork-fetch behaviour.** The logging
is the instrument that will confirm or refute the `data`-vs-`rawData` theory. The artwork
fix is a separate follow-up, informed by what the logs show. This keeps us honest to
"diagnose the root cause before applying a fix".

> **Superseded (2026-06-16):** on-device verification on macOS 26.5 confirmed the cause and
> surfaced several ScriptingBridge breakages, so the artwork fix (and the crashes it exposed)
> landed in this same branch rather than as a later follow-up. See the Addendum (§9).

## 2. Goals / non-goals

**Goals**

- A single logging facade used throughout the app.
- Live stream viewable during development (Apple unified logging / Console.app).
- An opt-in, persisted log file users can export and send us.
- One-click "Export Logs…" that produces a single self-contained file and reveals it in
  Finder.
- Rich instrumentation of the artwork path, including a derived **track source type**
  (local file vs streamed) and the raw signals behind it.

**Non-goals (YAGNI)**

- Remote or automatic log upload; crash reporting; network telemetry.
- Multiple verbosity levels exposed in the UI (one opt-in toggle only).
- GitHub-API issue creation, share sheet, clipboard copy (explicitly deferred — only
  "save + reveal in Finder" was chosen).
- An in-app log viewer.
- The artwork **fix** itself.

## 3. Architecture

A lightweight **logging facade** — a `Log` type — fans out every call to two sinks:

1. `os.Logger` (Apple unified logging) — **always**.
2. A file writer (`FileLogSink`) — **only when the user opts in**.

Call sites look like ordinary unified-logging calls: `Log.artwork.debug("…")`. They never
know there are two sinks.

*Rejected alternative:* a protocol-based `Logging` abstraction with injectable sinks. More
testable in theory, but it is ceremony this single-app codebase does not need; the facade
still exposes its pure pieces (line formatting, rotation, header generation) for unit
testing. The enum-of-loggers shape matches the existing `Constants` / `Helper` style.

### 3.1 Components and responsibilities

| Unit | Responsibility | Depends on |
| --- | --- | --- |
| `Log` (enum) | One `Logger` per category; forwards to `os.Logger` + `FileLogSink`. | `os.Logger`, `FileLogSink` |
| `FileLogSink` (final class, singleton) | Serialised append-to-file, opt-in gating, size-capped rotation. | `FileManager`, a private `DispatchQueue` |
| `LogLine` (struct/formatter) | Pure formatting of one line (timestamp, category, level, message). | Foundation only |
| `DiagnosticsReport` (struct) | Build the export header from injected values. | injected values only |
| `LogExporter` | Combine header + log file into one export file; reveal in Finder. | `FileLogSink`, `DiagnosticsReport`, `NSWorkspace` |
| `TrackSourceType` (enum + classifier) | Derive local/streamed/etc. from track signals. | `MusicTrack` accessors |
| Debugging preference pane | Toggle + "Export Logs…" button. | `@AppStorage`, `LogExporter` |

Each unit is understandable and testable in isolation; the AppKit-touching pieces
(`LogExporter`, the pane) are thin shells over the pure pieces.

## 4. Detailed design

### 4.1 The `Log` facade

- Subsystem: `com.jaydenkerr.Jukebox` (the bundle identifier).
- Categories (four — enough to filter usefully without over-categorising):
  - `general` — lifecycle, app/connection setup, miscellaneous.
  - `playback` — play/pause/track-change events, seeker/position.
  - `artwork` — artwork retrieval (the bug surface).
  - `permissions` — automation-consent results.
- Levels: `.debug`, `.info`, `.notice`, `.error`. `os.Logger` receives all of them, so a
  developer can `log stream --predicate 'subsystem == "com.jaydenkerr.Jukebox"'` or filter
  Console.app live with no toggle. The file sink only persists when enabled.
- Privacy: because this is opt-in diagnostic logging the user chooses to share, dynamic
  values we want to see (track title/artist, byte counts, status) are interpolated
  `.public` in the `os.Logger` calls. The file sink performs no redaction.

### 4.2 `FileLogSink`

- File: `~/Library/Application Support/Jukebox/Logs/Jukebox.log`, resolved via
  `FileManager.default.url(for: .applicationSupportDirectory, …)` so it is correct whether
  or not the app is sandboxed. The `Logs` directory is created on first write.
- **Opt-in gate:** writes occur only when `@AppStorage("debugLoggingEnabled")` is `true`.
  Off by default. When on, the file captures full detail (all levels).
- **Format** (one line):
  `2026-06-15T14:48:00.123Z  [artwork]  DEBUG  message`
  Timestamps are stored in **UTC** with a trailing `Z` (per the project's UTC-storage
  rule), to milliseconds, followed by category and level.
- **Rotation:** a single file capped at ~5 MB. On exceeding the cap, roll once to
  `Jukebox.log.1` (overwriting any previous `.1`) and start a fresh `Jukebox.log`. Disk
  use is bounded to ~10 MB.
- **Concurrency:** all writes are serialised on a dedicated `DispatchQueue` so logging
  from the artwork poll, timers, and distributed-notification handlers cannot interleave
  or race.

### 4.3 Track source-type classification

A `TrackSourceType` derived from real `MusicTrack` signals (verified against the
ScriptingBridge interface):

- `internetRadioStream` — `MusicURLTrack.address` is non-empty.
- `localFile` — a file `location` URL is present (`MusicFileTrack`/`MusicAudioCDTrack`).
- `streamed` — no `location`; an Apple Music cloud/catalogue track.
- `unknown` — none of the above resolves.

Logged **alongside the derived label**, we record the raw inputs so the classification is
auditable and future-proof:

- `cloudStatus` (`MusicEClS`) mapped to a name — notably `.subscription` (Apple Music
  stream), `.purchased` / `.matched` / `.uploaded` (iCloud Music Library), `.unknown`.
- `kind` (the localised string, e.g. "Apple Music AAC audio file").
- `mediaKind` (`MusicEMdK`: song / musicVideo / unknown).
- `hasLocation` (and whether the URL scheme is `file`).
- `size` (bytes; streamed catalogue tracks typically report 0).

Property reads are guarded as optionals — accessing an inapplicable ScriptingBridge
property (e.g. `location` on a streamed track) returns nil rather than crashing.

### 4.4 Instrumentation plan (where log calls go)

- **Artwork path** (`getTrackInformation`, Apple Music branch) — the payload that confirms
  the root cause. For the current track, log: source type + raw signals (4.3);
  `artworks().count`; and for `art[0]`: whether `data` is nil, whether `data.isEmpty()`,
  plus `format`, `downloaded`, `kind`; and crucially the **`rawData` class name and byte
  count**. Log each poll attempt number and the final outcome (got data at attempt N /
  timed out after 21 attempts / no artwork present).
- **Spotify artwork** — log artwork-URL fetch success/failure (currently a bare
  `print(error.localizedDescription)`).
- **Lifecycle / playback / permissions** — replace existing scattered `print()` calls
  (`"Setting up music apps"`, `"Getting track information..."`, `Helper`'s permission
  prints) with categorised facade calls, so nothing useful is lost and stdout noise
  becomes structured, filterable logging.

### 4.5 Diagnostics header + export

- `DiagnosticsReport` builds a header from injected values: app version
  (`Constants.AppInfo.appVersion`), `macOS \(ProcessInfo.processInfo.operatingSystemVersionString)`,
  connected app, is-running, automation-permission status (reusing
  `Helper.promptUserForConsent`), whether debug logging is enabled, current track's source
  type, and an export timestamp.
- **"Export Logs…"** (`LogExporter`) writes a single combined
  `Jukebox-Diagnostics-YYYYMMDD-HHmmss.txt` (header + the full log file) into the `Logs`
  folder, then calls `NSWorkspace.shared.activateFileViewerSelecting([url])` to reveal it
  selected in Finder. One file; no zip; no network. The user drags it into an email or
  GitHub issue.
- If logging was never enabled or the log is empty, the button shows the existing
  SwiftUI `Alert` style telling the user to enable debug logging and reproduce first.

### 4.6 Preferences UI — new "Debugging" pane

A third pane below "Background" in `PreferencesView.preferencePanes`, matching the existing
style (a titled `VStack` of controls):

- `Toggle("Enable debug logging", isOn: $debugLoggingEnabled)` (`@AppStorage`).
- `Button("Export Logs…")` → `LogExporter`.
- A one-line caption: the log includes the names of tracks played while logging was
  enabled (transparency about what is being shared).

## 5. Privacy

The log file stays local and is never transmitted by the app; it leaves only when the user
explicitly exports and sends it. It contains the titles/artists of tracks played while
logging was enabled — disclosed both in the Preferences caption and the export header. No
redaction beyond that (the values are the point of a diagnostic log).

## 6. Error handling

- File I/O failures (cannot create `Logs` dir, cannot write) are swallowed for the file
  sink but still reported via `os.Logger` at `.error`, so logging never crashes or blocks
  the app.
- Export with no/empty log → user-facing alert (see 4.5), not an error.
- ScriptingBridge property reads are optional-guarded (see 4.3).

## 7. Testing

- **Verification of pure pieces (standalone `swiftc`, no test target):** `scripts/verify-logging.swift`
  is compiled together with the real `LogLine`, `LogFileWriter`, `TrackSourceType`, and
  `DiagnosticsReport` source files (no copies) and run as an executable. It asserts:
  - `LogFileWriter` rotation: write past the cap → rolls to `.1`, fresh file started,
    bounded total size.
  - `LogLine` formatting: timestamp/category/level/message shape is stable.
  - `DiagnosticsReport` header generation from injected values.
  - `TrackSourceType` classifier: each branch (address / location / subscription / unknown)
    from representative inputs.
- **Manual verification:** enable the toggle, play an Apple Music **streamed** track with
  missing art, export, read the file, and confirm whether `data` is empty while `rawData`
  carries bytes — and whether the failure correlates with `cloudStatus == .subscription`.

## 8. Out of scope / follow-ups

- The artwork **fix** (likely switching the Apple Music path to `rawData`), to be designed
  once the logs confirm the cause.
- Any of the deferred export channels (share sheet, clipboard, GitHub issue).

## 9. Addendum — on-device verification on macOS 26.5 (2026-06-16)

On-device testing on macOS 26.5 (build 25F80) confirmed the root cause and surfaced a chain
of ScriptingBridge breakages specific to that OS. Because each blocked the next, the artwork
fix that §1 deferred — plus the crashes it exposed — shipped on this branch rather than as a
later follow-up. What landed beyond the logging feature:

1. **`location` crash (`EXC_BREAKPOINT`).** The diagnostics read `MusicFileTrack.location`,
   declared non-optional `URL`; for a streamed track the missing value bridges nil into the
   non-optional value type and traps. Fixed by typing `location` as `URL?` in the generated
   ScriptingBridge header.
2. **`data` crash (`unrecognized selector`).** `MusicArtwork.data` (declared `NSImage`)
   returns an `NSAppleEventDescriptor` at runtime; `NSImage.isEmpty()` → `cgImage(...)` on it
   crashed. Stopped calling NSImage methods on `data`.
3. **Artwork fix — cross-OS resolver (resolves the original empty-grey-square bug).** Music's
   artwork accessors behave differently per OS: on **macOS ≤15** `MusicArtwork.data` is a
   genuine `NSImage` (and `rawData`/descriptor return nothing), whereas on **macOS 26.5** `data`
   is an `NSAppleEventDescriptor` and `rawData` an opaque `SBObject` proxy. The resolver now
   tries, in order: `data`-as-`NSImage` (safe on 26.5 — a descriptor fails the cast and falls
   through), then `rawData` bytes, then the resolved `rawData` proxy via `SBObject.get()`, then
   the `data` descriptor payload (`NSAppleEventDescriptor.data`), then `NSImage(data:)`. Verified
   on both OSes with correct per-track covers (macOS 15 via `data(NSImage)`, 26.5 via
   `data-descriptor`).
4. **Async artwork loading.** Apple Music populates `artworks()` asynchronously, so `count` is
   often 0 right at a track change. The poll now retries on `count == 0` (clearing stale art on
   the first miss, timing out after ~5 s) instead of bailing immediately.
5. **`SBElementArray.first` returns nil** even when `count > 0` (lazy faulting-proxy
   collection); reverted to the `[0]` subscript and made the guard log on miss.
6. **Track source-type misclassification.** Streamed Apple Music tracks report a `location`
   and `size == 0` on 26.5 (and `cloudStatus` bridges to `unrecognised`), so the
   `hasLocation → localFile` heuristic was wrong. Now size-based: a local file needs a
   `file://` location **and** `size > 0`; `size == 0` ⇒ streamed.
7. **Preferences window clipped.** The new Debugging pane overflowed the fixed 320 pt window
   (clipping "Export Logs…"); window height raised to 450 pt.
8. **Popover layout differed across OSes.** On macOS 26 `NSPopover` ignored `contentSize` and
   the host `NSHostingView.sizingOptions`, rendering larger than the macOS 15 layout; fixed by
   setting `contentViewController.preferredContentSize`.

These findings were captured as reusable gotchas: `swift-gotchas` items 6–11 (the
ScriptingBridge/artwork chain) and `appkit-gotchas` (the NSPopover-sizing one).

Still genuinely deferred: artwork for pure-streamed 26.5 tracks that expose nothing via
scripting (`count == 0` forever) — would need a non-scripting source (MediaRemote now-playing,
or MusicKit); the alternative export channels (share sheet, clipboard, GitHub issue); and an
AVFoundation embedded-artwork path for local files.
