# Debug Logging Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in debug logging facility — a single `Log` facade fanning out to Apple unified logging plus a size-capped log file users can export — and instrument the Apple Music artwork path to diagnose the empty-album-art bug on macOS 26.5.

**Architecture:** A `Log` enum exposes one category logger each (`general`, `playback`, `artwork`, `permissions`). Each call goes to `os.Logger` (always) and to `FileLogSink` (only when the `debugLoggingEnabled` preference is on). `FileLogSink` wraps a Foundation-only `LogFileWriter` (append + single rollover). "Export Logs…" combines a `DiagnosticsReport` header with the log file and reveals it in Finder. **This plan adds logging only; it does not change artwork-fetch behaviour** (the artwork fix is a separate follow-up informed by the logs).

**Tech Stack:** Swift 5, AppKit + SwiftUI, ScriptingBridge (Music.app), `os.Logger` (unified logging). macOS 13 deployment target. Raw `.xcodeproj` (no XcodeGen/SPM). Pure logic verified by a standalone `swiftc` compile (`scripts/verify-logging.swift`); no test target.

**Spec:** `docs/superpowers/specs/2026-06-15-debug-logging-mode-design.md`

---

## File Structure

New files (flat in `Jukebox/Utilities/`, matching the existing `Constants.swift` / `Helper.swift` / `NSImage+Empty.swift` convention):

- `Jukebox/Utilities/LogLine.swift` — pure: format one log line (UTC ISO-8601 + category + level + message).
- `Jukebox/Utilities/LogFileWriter.swift` — pure (Foundation-only): append + size-capped single rollover; injected path.
- `Jukebox/Utilities/TrackSourceType.swift` — pure: `TrackSourceType` enum + `TrackDiagnostics` (raw signals + pure classifier).
- `Jukebox/Utilities/DiagnosticsReport.swift` — pure: build the export header from injected values.
- `Jukebox/Utilities/FileLogSink.swift` — singleton: resolves the Application Support path, opt-in gate, owns a `LogFileWriter`.
- `Jukebox/Utilities/Log.swift` — the facade: per-category `os.Logger` + forward to `FileLogSink`.
- `Jukebox/Utilities/LogExporter.swift` — combine header + log, write export file, reveal in Finder.
- `scripts/verify-logging.swift` — standalone verification of the four pure files.

Modified files:

- `Jukebox/Utilities/Constants.swift` — add `Constants.Logging`.
- `Jukebox/Utilities/Helper.swift` — replace `print()` with `Log.permissions`.
- `Jukebox/ViewModels/ContentViewModel.swift` — replace `print()`; add Apple Music track diagnostics; instrument the artwork poll; add `currentDiagnostics()`.
- `Jukebox/Views/PreferencesView.swift` — add a "Debugging" pane (toggle + Export button); accept the view model.
- `Jukebox/JukeboxApp.swift` — pass `contentViewVM` into `PreferencesView`.
- `docs/superpowers/specs/2026-06-15-debug-logging-mode-design.md` — sync §7 to the standalone-verify approach.
- `README.md` — add a "Debug logging" section.

---

## Task 1: Scaffold — create empty source files, add them to the target, set up the verify harness

This is the one bounded project-file change. Creating the files empty up front means later tasks only edit (never re-touch target membership), and the app keeps compiling throughout.

**Files:**
- Create (empty/stub): the seven `Jukebox/Utilities/Log*.swift` / `TrackSourceType.swift` / `DiagnosticsReport.swift` / `FileLogSink.swift` files listed above.
- Create: `scripts/verify-logging.swift`
- Modify (target membership): `Jukebox.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the seven new source files as minimal stubs**

Each file initially contains only its import so it compiles as an empty translation unit:

`Jukebox/Utilities/LogLine.swift`, `Jukebox/Utilities/LogFileWriter.swift`, `Jukebox/Utilities/TrackSourceType.swift`, `Jukebox/Utilities/DiagnosticsReport.swift`, `Jukebox/Utilities/FileLogSink.swift`:
```swift
import Foundation
```

`Jukebox/Utilities/Log.swift`:
```swift
import Foundation
import os
```

`Jukebox/Utilities/LogExporter.swift`:
```swift
import AppKit
```

- [ ] **Step 2: Add the seven files to the `Jukebox` target**

The files must be members of the `Jukebox` app target or `xcodebuild` won't compile them.

- **Recommended (interactive):** In Xcode, drag the seven files into the Project Navigator under the existing `Utilities` group, and in the add-sheet ensure **"Jukebox" target is checked** and "Copy items if needed" is unchecked (they already live on disk).
- **Headless fallback:** add a `PBXFileReference` and a `PBXBuildFile` entry per file to `Jukebox.xcodeproj/project.pbxproj`, add each `PBXFileReference` to the `Utilities` `PBXGroup`'s `children`, and add each `PBXBuildFile` to the `Jukebox` target's `PBXSourcesBuildPhase` `files` list. Mirror the exact pattern already used for `Helper.swift` (grep `Helper.swift` in `project.pbxproj` to see both entries and copy their shape with fresh 24-hex UUIDs).

- [ ] **Step 3: Create the standalone verify harness**

`scripts/verify-logging.swift`:
```swift
import Foundation

// Standalone verification of the AppKit-free logging core. Compiled together
// with the real source files (no copies). Run via:
//
//   swiftc Jukebox/Utilities/LogLine.swift \
//          Jukebox/Utilities/LogFileWriter.swift \
//          Jukebox/Utilities/TrackSourceType.swift \
//          Jukebox/Utilities/DiagnosticsReport.swift \
//          scripts/verify-logging.swift -o /tmp/verify-logging && /tmp/verify-logging

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

@main
struct VerifyLogging {
    static func main() {
        // Assertions are added by later tasks.
        print("verify-logging: all checks passed")
    }
}
```

- [ ] **Step 4: Build the app to confirm the stubs compile and are in the target**

Run:
```bash
xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. (If Swift Package resolution for Sparkle runs on first build, let it finish.)

- [ ] **Step 5: Commit**

```bash
git add Jukebox/Utilities/LogLine.swift Jukebox/Utilities/LogFileWriter.swift \
        Jukebox/Utilities/TrackSourceType.swift Jukebox/Utilities/DiagnosticsReport.swift \
        Jukebox/Utilities/FileLogSink.swift Jukebox/Utilities/Log.swift \
        Jukebox/Utilities/LogExporter.swift scripts/verify-logging.swift \
        Jukebox.xcodeproj/project.pbxproj
git commit -m "Scaffold logging files and standalone verify harness"
```

---

## Task 2: `LogLine` — pure line formatting

**Files:**
- Modify: `scripts/verify-logging.swift`
- Modify: `Jukebox/Utilities/LogLine.swift`

- [ ] **Step 1: Write the failing checks**

In `scripts/verify-logging.swift`, replace the `// Assertions are added by later tasks.` line inside `main()` with:
```swift
        // LogLine
        let fixedDate = Date(timeIntervalSince1970: 1_750_000_000) // 2025-06-15T13:46:40Z
        let ts = LogLine.timestamp(fixedDate)
        expect(ts.hasSuffix("Z"), "timestamp must end in Z (UTC), got \(ts)")
        expect(ts.contains("."), "timestamp must include fractional seconds, got \(ts)")
        let line = LogLine.format(date: fixedDate, category: "artwork", level: "DEBUG", message: "hello")
        expect(line.contains("[artwork]"), "line must contain bracketed category, got \(line)")
        expect(line.contains("DEBUG"), "line must contain level, got \(line)")
        expect(line.hasSuffix("hello"), "line must end with message, got \(line)")
```

- [ ] **Step 2: Run the verify to confirm it fails**

Run:
```bash
swiftc Jukebox/Utilities/LogLine.swift scripts/verify-logging.swift -o /tmp/verify-logging
```
Expected: FAIL — compile error `cannot find 'LogLine' in scope` (the type does not exist yet).

- [ ] **Step 3: Implement `LogLine`**

`Jukebox/Utilities/LogLine.swift`:
```swift
import Foundation

/// Pure, AppKit-free formatting of a single log line. Dependency-free so it
/// can be verified by scripts/verify-logging.swift.
enum LogLine {
    /// `2026-06-15T05:18:00.123Z  [category]  LEVEL  message`
    static func format(date: Date, category: String, level: String, message: String) -> String {
        return "\(timestamp(date))  [\(category)]  \(level)  \(message)"
    }

    /// ISO-8601 in UTC, millisecond precision, trailing `Z`.
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: Run the verify to confirm it passes**

Run:
```bash
swiftc Jukebox/Utilities/LogLine.swift scripts/verify-logging.swift -o /tmp/verify-logging && /tmp/verify-logging
```
Expected: `verify-logging: all checks passed`

- [ ] **Step 5: Commit**

```bash
git add Jukebox/Utilities/LogLine.swift scripts/verify-logging.swift
git commit -m "Add LogLine pure line formatter"
```

---

## Task 3: `LogFileWriter` — append + size-capped rollover

**Files:**
- Modify: `scripts/verify-logging.swift`
- Modify: `Jukebox/Utilities/LogFileWriter.swift`

- [ ] **Step 1: Write the failing checks**

In `scripts/verify-logging.swift`, add the following inside `main()` immediately before the final `print(...)`:
```swift
        // LogFileWriter.shouldRotate (pure)
        expect(LogFileWriter.shouldRotate(currentBytes: 0, incomingBytes: 100, maxBytes: 50) == false,
               "empty file must never rotate")
        expect(LogFileWriter.shouldRotate(currentBytes: 40, incomingBytes: 5, maxBytes: 50) == false,
               "under cap must not rotate")
        expect(LogFileWriter.shouldRotate(currentBytes: 48, incomingBytes: 5, maxBytes: 50) == true,
               "over cap must rotate")

        // LogFileWriter round-trip in a temp dir
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jukebox-verify-\(UUID().uuidString)", isDirectory: true)
        let logURL = tmpDir.appendingPathComponent("Jukebox.log")
        let writer = LogFileWriter(fileURL: logURL, maxBytes: 64)
        writer.append(String(repeating: "a", count: 50))   // ~51 bytes, under cap
        expect(FileManager.default.fileExists(atPath: logURL.path), "log file must be created")
        writer.append(String(repeating: "b", count: 50))   // pushes over cap -> rotates first
        let rolledURL = logURL.appendingPathExtension("1")
        expect(FileManager.default.fileExists(atPath: rolledURL.path), "rolled file Jukebox.log.1 must exist")
        let current = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        expect(current.contains("b") && !current.contains("a"),
               "after rotation, current file holds only the newest line")
        try? FileManager.default.removeItem(at: tmpDir)
```

- [ ] **Step 2: Run the verify to confirm it fails**

Run:
```bash
swiftc Jukebox/Utilities/LogLine.swift Jukebox/Utilities/LogFileWriter.swift \
  scripts/verify-logging.swift -o /tmp/verify-logging
```
Expected: FAIL — compile error `cannot find 'LogFileWriter' in scope`.

- [ ] **Step 3: Implement `LogFileWriter`**

`Jukebox/Utilities/LogFileWriter.swift`:
```swift
import Foundation

/// AppKit-free, size-capped append-only log writer with a single rollover.
/// The path is injected so this type is verifiable in isolation. Not
/// thread-safe alone; callers serialise access (FileLogSink uses a queue).
final class LogFileWriter {
    private let fileURL: URL
    private let rolledURL: URL
    private let maxBytes: Int
    private let fileManager: FileManager

    init(fileURL: URL, maxBytes: Int, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.rolledURL = fileURL.appendingPathExtension("1") // e.g. Jukebox.log.1
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    /// Appends one line (a trailing newline is added), rotating first if needed.
    func append(_ line: String) {
        let data = Data((line + "\n").utf8)
        ensureFileExists()
        rotateIfNeeded(incomingBytes: data.count)
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Pure rotation decision — extracted so it can be verified directly.
    static func shouldRotate(currentBytes: Int, incomingBytes: Int, maxBytes: Int) -> Bool {
        return currentBytes > 0 && currentBytes + incomingBytes > maxBytes
    }

    private func rotateIfNeeded(incomingBytes: Int) {
        guard LogFileWriter.shouldRotate(currentBytes: currentBytes(),
                                         incomingBytes: incomingBytes,
                                         maxBytes: maxBytes) else { return }
        try? fileManager.removeItem(at: rolledURL)
        try? fileManager.moveItem(at: fileURL, to: rolledURL)
        fileManager.createFile(atPath: fileURL.path, contents: nil)
    }

    private func ensureFileExists() {
        let dir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private func currentBytes() -> Int {
        let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
        return (attrs?[.size] as? Int) ?? 0
    }
}
```

- [ ] **Step 4: Run the verify to confirm it passes**

Run:
```bash
swiftc Jukebox/Utilities/LogLine.swift Jukebox/Utilities/LogFileWriter.swift \
  scripts/verify-logging.swift -o /tmp/verify-logging && /tmp/verify-logging
```
Expected: `verify-logging: all checks passed`

- [ ] **Step 5: Commit**

```bash
git add Jukebox/Utilities/LogFileWriter.swift scripts/verify-logging.swift
git commit -m "Add LogFileWriter with size-capped single rollover"
```

---

## Task 4: `TrackSourceType` — local vs streamed classifier

**Files:**
- Modify: `scripts/verify-logging.swift`
- Modify: `Jukebox/Utilities/TrackSourceType.swift`

- [ ] **Step 1: Write the failing checks**

In `scripts/verify-logging.swift`, add inside `main()` before the final `print(...)`:
```swift
        // TrackSourceType classifier (pure)
        expect(TrackDiagnostics.classify(hasAddress: true, hasFileLocation: false, cloudStatus: "unknown") == .internetRadioStream,
               "an address means internet radio stream")
        expect(TrackDiagnostics.classify(hasAddress: false, hasFileLocation: true, cloudStatus: "unknown") == .localFile,
               "a file location means local file")
        expect(TrackDiagnostics.classify(hasAddress: false, hasFileLocation: false, cloudStatus: "subscription") == .streamed,
               "subscription with no location means streamed")
        expect(TrackDiagnostics.classify(hasAddress: false, hasFileLocation: false, cloudStatus: "purchased") == .streamed,
               "purchased cloud track with no location means streamed")
        expect(TrackDiagnostics.classify(hasAddress: false, hasFileLocation: false, cloudStatus: "unknown") == .unknown,
               "no signals means unknown")
        let diag = TrackDiagnostics(sourceType: .streamed, cloudStatus: "subscription", kind: "Apple Music AAC audio file",
                                    mediaKind: "song", hasLocation: false, sizeBytes: 0, address: nil)
        expect(diag.description.contains("source=streamed"), "description must include derived source")
        expect(diag.description.contains("cloudStatus=subscription"), "description must include cloud status")
```

- [ ] **Step 2: Run the verify to confirm it fails**

Run:
```bash
swiftc Jukebox/Utilities/LogLine.swift Jukebox/Utilities/LogFileWriter.swift \
  Jukebox/Utilities/TrackSourceType.swift scripts/verify-logging.swift -o /tmp/verify-logging
```
Expected: FAIL — compile error `cannot find 'TrackDiagnostics' in scope`.

- [ ] **Step 3: Implement `TrackSourceType` + `TrackDiagnostics`**

`Jukebox/Utilities/TrackSourceType.swift`:
```swift
import Foundation

/// Whether the currently-playing track is a local file or streamed.
enum TrackSourceType: String {
    case localFile
    case streamed
    case internetRadioStream
    case unknown
}

/// Raw signals captured from a Music track plus the derived source type.
/// The classifier is pure (primitive inputs) so it is verifiable in isolation.
struct TrackDiagnostics {
    let sourceType: TrackSourceType
    let cloudStatus: String
    let kind: String
    let mediaKind: String
    let hasLocation: Bool
    let sizeBytes: Int64
    let address: String?

    /// Cloud statuses that indicate an Apple Music cloud/catalogue track.
    private static let cloudStatuses: Set<String> = ["subscription", "purchased", "matched", "uploaded"]

    static func classify(hasAddress: Bool, hasFileLocation: Bool, cloudStatus: String) -> TrackSourceType {
        if hasAddress { return .internetRadioStream }
        if hasFileLocation { return .localFile }
        if cloudStatuses.contains(cloudStatus) { return .streamed }
        return .unknown
    }

    /// Single-line, log-friendly summary.
    var description: String {
        let addr = address.map { ", address=\($0)" } ?? ""
        return "source=\(sourceType.rawValue) cloudStatus=\(cloudStatus) kind=\"\(kind)\" "
            + "mediaKind=\(mediaKind) hasLocation=\(hasLocation) size=\(sizeBytes)\(addr)"
    }
}
```

- [ ] **Step 4: Run the verify to confirm it passes**

Run:
```bash
swiftc Jukebox/Utilities/LogLine.swift Jukebox/Utilities/LogFileWriter.swift \
  Jukebox/Utilities/TrackSourceType.swift scripts/verify-logging.swift -o /tmp/verify-logging && /tmp/verify-logging
```
Expected: `verify-logging: all checks passed`

- [ ] **Step 5: Commit**

```bash
git add Jukebox/Utilities/TrackSourceType.swift scripts/verify-logging.swift
git commit -m "Add TrackSourceType classifier and TrackDiagnostics"
```

---

## Task 5: `DiagnosticsReport` — export header builder

**Files:**
- Modify: `scripts/verify-logging.swift`
- Modify: `Jukebox/Utilities/DiagnosticsReport.swift`

- [ ] **Step 1: Write the failing checks**

In `scripts/verify-logging.swift`, add inside `main()` before the final `print(...)`:
```swift
        // DiagnosticsReport header (pure)
        let report = DiagnosticsReport(
            appVersion: "1.2.1", osVersion: "Version 26.5", connectedApp: "Apple Music",
            isRunning: true, permissionStatus: "granted", debugLoggingEnabled: true,
            currentTrackSource: "source=streamed cloudStatus=subscription",
            exportedAt: Date(timeIntervalSince1970: 1_750_000_000))
        let header = report.header()
        expect(header.contains("1.2.1"), "header must include app version")
        expect(header.contains("Version 26.5"), "header must include macOS version")
        expect(header.contains("Apple Music"), "header must include connected app")
        expect(header.contains("granted"), "header must include permission status")
        expect(header.contains("source=streamed"), "header must include current track source")
```

- [ ] **Step 2: Run the verify to confirm it fails**

Run:
```bash
swiftc Jukebox/Utilities/LogLine.swift Jukebox/Utilities/LogFileWriter.swift \
  Jukebox/Utilities/TrackSourceType.swift Jukebox/Utilities/DiagnosticsReport.swift \
  scripts/verify-logging.swift -o /tmp/verify-logging
```
Expected: FAIL — compile error `cannot find 'DiagnosticsReport' in scope`.

- [ ] **Step 3: Implement `DiagnosticsReport`**

`Jukebox/Utilities/DiagnosticsReport.swift`:
```swift
import Foundation

/// Builds the human-readable header prepended to an exported log bundle.
/// Values are injected so the builder is pure and verifiable in isolation.
struct DiagnosticsReport {
    let appVersion: String
    let osVersion: String
    let connectedApp: String
    let isRunning: Bool
    let permissionStatus: String
    let debugLoggingEnabled: Bool
    let currentTrackSource: String
    let exportedAt: Date

    func header() -> String {
        return """
        Jukebox Diagnostics
        ===================
        Exported:       \(LogLine.timestamp(exportedAt))
        App version:    \(appVersion)
        macOS:          \(osVersion)
        Connected app:  \(connectedApp)
        App running:    \(isRunning ? "yes" : "no")
        Automation:     \(permissionStatus)
        Debug logging:  \(debugLoggingEnabled ? "enabled" : "disabled")
        Current track:  \(currentTrackSource)
        """
    }
}
```

- [ ] **Step 4: Run the verify to confirm it passes**

Run:
```bash
swiftc Jukebox/Utilities/LogLine.swift Jukebox/Utilities/LogFileWriter.swift \
  Jukebox/Utilities/TrackSourceType.swift Jukebox/Utilities/DiagnosticsReport.swift \
  scripts/verify-logging.swift -o /tmp/verify-logging && /tmp/verify-logging
```
Expected: `verify-logging: all checks passed`

- [ ] **Step 5: Commit**

```bash
git add Jukebox/Utilities/DiagnosticsReport.swift scripts/verify-logging.swift
git commit -m "Add DiagnosticsReport export header builder"
```

---

## Task 6: `Constants.Logging`, `FileLogSink`, and the `Log` facade

These three wire the pure pieces into the app. No standalone test (they touch `UserDefaults`/`os.Logger`); verification is the app build.

**Files:**
- Modify: `Jukebox/Utilities/Constants.swift`
- Modify: `Jukebox/Utilities/FileLogSink.swift`
- Modify: `Jukebox/Utilities/Log.swift`

- [ ] **Step 1: Add `Constants.Logging`**

In `Jukebox/Utilities/Constants.swift`, add this case inside the `enum Constants { … }`, after the `AppleMusic` enum:
```swift
    enum Logging {
        static let subsystem = "com.jaydenkerr.Jukebox"
        static let enabledKey = "debugLoggingEnabled"
        static let logFileName = "Jukebox.log"
        static let maxLogBytes = 5 * 1024 * 1024  // 5 MB; rolls once to Jukebox.log.1
    }
```

- [ ] **Step 2: Implement `FileLogSink`**

`Jukebox/Utilities/FileLogSink.swift` (replace the stub):
```swift
import Foundation

/// Singleton file sink. Resolves the Application Support log path, gates
/// writes on the opt-in `debugLoggingEnabled` preference, and serialises
/// appends on a dedicated queue. Delegates rotation to LogFileWriter.
final class FileLogSink {
    static let shared = FileLogSink()

    /// nil if Application Support could not be resolved.
    let logFileURL: URL?
    private let writer: LogFileWriter?
    private let queue = DispatchQueue(label: "\(Constants.Logging.subsystem).filelog", qos: .utility)

    private init() {
        let url = FileLogSink.defaultLogFileURL()
        logFileURL = url
        writer = url.map { LogFileWriter(fileURL: $0, maxBytes: Constants.Logging.maxLogBytes) }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.Logging.enabledKey)
    }

    func write(category: String, level: String, message: String) {
        guard isEnabled, let writer else { return }
        let line = LogLine.format(date: Date(), category: category, level: level, message: message)
        queue.async { writer.append(line) }
    }

    private static func defaultLogFileURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        return support
            .appendingPathComponent("Jukebox", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(Constants.Logging.logFileName)
    }
}
```

- [ ] **Step 3: Implement the `Log` facade**

`Jukebox/Utilities/Log.swift` (replace the stub):
```swift
import Foundation
import os

/// App-wide logging facade. Every call goes to os.Logger (always) and to
/// FileLogSink (only when debug logging is enabled).
enum Log {
    static let general = LogCategory("general")
    static let playback = LogCategory("playback")
    static let artwork = LogCategory("artwork")
    static let permissions = LogCategory("permissions")
}

struct LogCategory {
    enum Level: String { case debug = "DEBUG", info = "INFO", notice = "NOTICE", error = "ERROR" }

    let name: String
    private let logger: Logger

    init(_ name: String) {
        self.name = name
        self.logger = Logger(subsystem: Constants.Logging.subsystem, category: name)
    }

    func debug(_ message: String)  { emit(.debug, message) }
    func info(_ message: String)   { emit(.info, message) }
    func notice(_ message: String) { emit(.notice, message) }
    func error(_ message: String)  { emit(.error, message) }

    private func emit(_ level: Level, _ message: String) {
        // .public so values are readable in Console.app and exported logs —
        // this is opt-in diagnostic logging the user chooses to share.
        switch level {
        case .debug:  logger.debug("\(message, privacy: .public)")
        case .info:   logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .error:  logger.error("\(message, privacy: .public)")
        }
        FileLogSink.shared.write(category: name, level: level.rawValue, message: message)
    }
}
```

- [ ] **Step 4: Build the app**

Run:
```bash
xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Jukebox/Utilities/Constants.swift Jukebox/Utilities/FileLogSink.swift Jukebox/Utilities/Log.swift
git commit -m "Wire Log facade and FileLogSink into the app"
```

---

## Task 7: Replace existing `print()` calls with the facade

Swap the scattered `print()` debugging for categorised facade calls. Behaviour is unchanged.

**Files:**
- Modify: `Jukebox/Utilities/Helper.swift`
- Modify: `Jukebox/ViewModels/ContentViewModel.swift`

- [ ] **Step 1: Update `Helper.swift`**

In `Jukebox/Utilities/Helper.swift`, replace the four `print(...)` lines in the `switch status` block with facade calls (keep the `return` lines unchanged):
```swift
        switch status {
        case -600:
            Log.permissions.notice("Automation target not open: \(appBundleID)")
            return .closed
        case -0:
            Log.permissions.info("Automation permission granted: \(appBundleID)")
            return .granted
        case -1744:
            Log.permissions.notice("Automation consent required but not prompted: \(appBundleID)")
            return .notPrompted
        default:
            Log.permissions.notice("Automation permission denied: \(appBundleID)")
            return .denied
        }
```

- [ ] **Step 2: Update the non-artwork `print()` calls in `ContentViewModel.swift`**

Make these four replacements:

In `setupMusicApps()`, replace `print("Setting up music apps")` with:
```swift
        Log.general.info("Setting up music apps for \(name)")
```

In `playStateOrTrackDidChange(_:)`, replace `print("The play state or the currently playing track changed")` with:
```swift
        Log.playback.debug("Play state or current track changed")
```

In `getTrackInformation()`, replace `print("Getting track information...")` with:
```swift
        Log.playback.debug("Getting track information for \(name)")
```

In `toggleLoveTrack()` (Spotify case), replace `print("Not supported")` with:
```swift
            Log.playback.notice("Love is not supported for Spotify")
```

- [ ] **Step 3: Build the app**

Run:
```bash
xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Jukebox/Utilities/Helper.swift Jukebox/ViewModels/ContentViewModel.swift
git commit -m "Replace scattered print() calls with the Log facade"
```

---

## Task 8: Apple Music track diagnostics + artwork instrumentation

This is the diagnostic payload that confirms the root cause. **Behaviour is unchanged** — only logging is added around the existing artwork poll.

**Files:**
- Modify: `Jukebox/ViewModels/ContentViewModel.swift`

- [ ] **Step 1: Add the track-diagnostics builder and enum-name helpers**

In `Jukebox/ViewModels/ContentViewModel.swift`, add these private methods inside the class (e.g. just below `getTrackInformation()`):
```swift
    // MARK: - Diagnostics

    /// Reads the current Apple Music track's source signals via ScriptingBridge.
    /// Property reads are optional-guarded — an inapplicable property (e.g.
    /// `location` on a streamed track) returns nil rather than crashing.
    private func makeAppleMusicTrackDiagnostics() -> TrackDiagnostics? {
        guard let track = appleMusicApp?.currentTrack else { return nil }
        let address = (track as? MusicURLTrack)?.address
        let hasAddress = !(address?.isEmpty ?? true)
        let hasLocation = (track as? MusicFileTrack)?.location != nil
        let cloudStatusName = Self.cloudStatusName(track.cloudStatus)
        let source = TrackDiagnostics.classify(hasAddress: hasAddress,
                                                hasFileLocation: hasLocation,
                                                cloudStatus: cloudStatusName)
        return TrackDiagnostics(
            sourceType: source,
            cloudStatus: cloudStatusName,
            kind: track.kind ?? "",
            mediaKind: Self.mediaKindName(track.mediaKind),
            hasLocation: hasLocation,
            sizeBytes: track.size ?? 0,
            address: hasAddress ? address : nil)
    }

    private static func cloudStatusName(_ status: MusicEClS?) -> String {
        switch status {
        case .purchased: return "purchased"
        case .matched: return "matched"
        case .uploaded: return "uploaded"
        case .subscription: return "subscription"
        case .ineligible: return "ineligible"
        case .removed: return "removed"
        case .error: return "error"
        case .duplicate: return "duplicate"
        case .noLongerAvailable: return "noLongerAvailable"
        case .notUploaded: return "notUploaded"
        case .unknown: return "unknown"
        case .none: return "unavailable"
        @unknown default: return "unrecognised"
        }
    }

    private static func mediaKindName(_ kind: MusicEMdK?) -> String {
        switch kind {
        case .song: return "song"
        case .musicVideo: return "musicVideo"
        case .unknown: return "unknown"
        case .none: return "unavailable"
        @unknown default: return "unrecognised"
        }
    }
```

- [ ] **Step 2: Instrument the Apple Music artwork branch**

In `getTrackInformation()`, replace the entire Apple Music album-art block (from the `if (self.appleMusicApp?.currentTrack?.artworks?().count ?? 0) == 0 {` line through the matching closing `}` that ends `waitForData()`) with this instrumented version. The poll timing and the assigned image are identical — only `Log.artwork` calls are added:
```swift
            // Album art. A track with no artwork must clear any art left over
            // from the previously playing track. Apple Music delivers artwork
            // data asynchronously, so when artwork exists we poll briefly for the
            // data to arrive — and still clear it if it never materialises.
            if let diagnostics = makeAppleMusicTrackDiagnostics() {
                Log.artwork.debug("Apple Music track: \(diagnostics.description)")
            }
            let artworkCount = self.appleMusicApp?.currentTrack?.artworks?().count ?? 0
            Log.artwork.debug("artworks().count = \(artworkCount)")

            if artworkCount == 0 {
                Log.artwork.notice("No artwork present for current track; clearing album art")
                self.track.albumArt = NSImage()
            } else {
                var count = 0
                var waitForData: (() -> Void)!
                waitForData = {
                    let art = self.appleMusicApp?.currentTrack?.artworks?()[0] as! MusicArtwork
                    let dataImage = art.data
                    let dataIsEmpty = dataImage?.isEmpty() ?? true
                    if dataImage != nil && !dataIsEmpty {
                        Log.artwork.info("Artwork resolved from `data` on attempt \(count) "
                            + "(size \(Int(dataImage!.size.width))x\(Int(dataImage!.size.height)))")
                        self.track.albumArt = dataImage!
                    } else {
                        // Diagnose why `data` is unusable and whether `rawData` has bytes.
                        let rawDesc: String
                        switch art.rawData {
                        case let bytes as Data:   rawDesc = "Data(\(bytes.count) bytes)"
                        case let bytes as NSData: rawDesc = "NSData(\(bytes.length) bytes)"
                        case let other?:          rawDesc = "\(type(of: other))"
                        default:                  rawDesc = "nil"
                        }
                        Log.artwork.debug("attempt \(count): "
                            + "data=\(dataImage == nil ? "nil" : "empty=\(dataIsEmpty)") "
                            + "format=\(art.format.map { "\($0)" } ?? "nil") "
                            + "downloaded=\(art.downloaded.map { "\($0)" } ?? "nil") "
                            + "rawData=\(rawDesc)")
                        if count > 20 {
                            Log.artwork.error("Artwork timed out after \(count) attempts; "
                                + "`data` never produced a usable image. rawData=\(rawDesc)")
                            self.track.albumArt = NSImage()
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            waitForData()
                        }
                    }
                    count += 1
                }
                waitForData()
            }
```

- [ ] **Step 3: Instrument the Spotify artwork error**

In `getTrackInformation()` (Spotify case), replace `print(error!.localizedDescription)` with:
```swift
                        Log.artwork.error("Spotify artwork fetch failed: \(error!.localizedDescription)")
```

- [ ] **Step 4: Build the app**

Run:
```bash
xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Jukebox/ViewModels/ContentViewModel.swift
git commit -m "Instrument Apple Music artwork path and track source diagnostics"
```

---

## Task 9: `currentDiagnostics()` + `LogExporter`

**Files:**
- Modify: `Jukebox/ViewModels/ContentViewModel.swift`
- Modify: `Jukebox/Utilities/LogExporter.swift`

- [ ] **Step 1: Add `currentDiagnostics()` to `ContentViewModel`**

In `Jukebox/ViewModels/ContentViewModel.swift`, add inside the class (e.g. below `makeAppleMusicTrackDiagnostics()`):
```swift
    /// Snapshot of current app/track state for the exported diagnostics header.
    func currentDiagnostics() -> DiagnosticsReport {
        let bundleID = connectedApp == .spotify ? Constants.Spotify.bundleID : Constants.AppleMusic.bundleID
        let permission = Helper.promptUserForConsent(for: bundleID)
        let trackSource: String
        switch connectedApp {
        case .appleMusic:
            trackSource = makeAppleMusicTrackDiagnostics()?.description ?? "no track"
        case .spotify:
            trackSource = "source=streamed (Spotify)"
        }
        return DiagnosticsReport(
            appVersion: Constants.AppInfo.appVersion ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            connectedApp: name,
            isRunning: isRunning,
            permissionStatus: Self.permissionName(permission),
            debugLoggingEnabled: UserDefaults.standard.bool(forKey: Constants.Logging.enabledKey),
            currentTrackSource: trackSource,
            exportedAt: Date())
    }

    private static func permissionName(_ status: Helper.PermissionStatus) -> String {
        switch status {
        case .closed: return "app not open"
        case .granted: return "granted"
        case .notPrompted: return "not prompted"
        case .denied: return "denied"
        }
    }
```

- [ ] **Step 2: Implement `LogExporter`**

`Jukebox/Utilities/LogExporter.swift` (replace the stub):
```swift
import AppKit

/// Combines the diagnostics header with the log file into a single .txt and
/// reveals it in Finder for the user to send.
enum LogExporter {
    enum Outcome {
        case revealed(URL)
        case noLogs
        case failed(Error)
    }

    static func export(report: DiagnosticsReport) -> Outcome {
        guard let logURL = FileLogSink.shared.logFileURL,
              let logText = try? String(contentsOf: logURL, encoding: .utf8),
              !logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .noLogs
        }
        let combined = report.header() + "\n\n===== LOG =====\n\n" + logText
        let exportURL = logURL.deletingLastPathComponent()
            .appendingPathComponent("Jukebox-Diagnostics-\(fileTimestamp(report.exportedAt)).txt")
        do {
            try combined.write(to: exportURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([exportURL])
            return .revealed(exportURL)
        } catch {
            return .failed(error)
        }
    }

    private static func fileTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 3: Build the app**

Run:
```bash
xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Jukebox/ViewModels/ContentViewModel.swift Jukebox/Utilities/LogExporter.swift
git commit -m "Add currentDiagnostics() and LogExporter"
```

---

## Task 10: Preferences "Debugging" pane

**Files:**
- Modify: `Jukebox/Views/PreferencesView.swift`
- Modify: `Jukebox/JukeboxApp.swift`

- [ ] **Step 1: Thread the view model into `PreferencesView`**

In `Jukebox/Views/PreferencesView.swift`:

Add an `@AppStorage` property alongside the existing ones (after `@AppStorage("animationsEnabled") private var animationsEnabled = true`):
```swift
    @AppStorage("debugLoggingEnabled") private var debugLoggingEnabled = false
```

Add a stored view model property after `private weak var parentWindow: PreferencesWindow!`:
```swift
    @ObservedObject private var contentViewVM: ContentViewModel
```

Replace the initialiser:
```swift
    init(parentWindow: PreferencesWindow) {
        self.parentWindow = parentWindow
    }
```
with:
```swift
    init(parentWindow: PreferencesWindow, contentViewVM: ContentViewModel) {
        self.parentWindow = parentWindow
        self.contentViewVM = contentViewVM
    }
```

- [ ] **Step 2: Add the Debugging pane and export action**

In `preferencePanes`, after the closing `}` of the `// Visualizer Pane` `VStack { … }.padding()` (the last pane), add:
```swift

            Divider()

            // Debugging Pane
            VStack(alignment: .leading) {
                Text("Debugging")
                    .font(.title2)
                    .fontWeight(.semibold)
                Toggle("Enable debug logging", isOn: $debugLoggingEnabled)
                HStack {
                    Button("Export Logs…") { exportLogs() }
                    Spacer()
                }
                Text("Logs include the names of tracks played while logging is enabled.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
```

Add the export action method inside the `struct PreferencesView` (e.g. after `preferencePanes`):
```swift
    private func exportLogs() {
        switch LogExporter.export(report: contentViewVM.currentDiagnostics()) {
        case .revealed:
            break // Finder reveals the file; no alert needed.
        case .noLogs:
            alertTitle = Text("No logs yet")
            alertMessage = Text("Turn on \u{201C}Enable debug logging\u{201D}, reproduce the problem, then export again.")
            showingAlert = true
        case .failed(let error):
            alertTitle = Text("Couldn\u{2019}t export logs")
            alertMessage = Text(error.localizedDescription)
            showingAlert = true
        }
    }
```

- [ ] **Step 3: Pass the view model when creating the view**

In `Jukebox/JukeboxApp.swift`, in `showPreferences(_:)`, replace:
```swift
            let hostedPrefView = NSHostingView(rootView: PreferencesView(parentWindow: preferencesWindow))
```
with:
```swift
            let hostedPrefView = NSHostingView(rootView: PreferencesView(parentWindow: preferencesWindow, contentViewVM: contentViewVM))
```

- [ ] **Step 4: Build the app**

Run:
```bash
xcodebuild -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Jukebox/Views/PreferencesView.swift Jukebox/JukeboxApp.swift
git commit -m "Add Debugging preferences pane with log export"
```

---

## Task 11: Docs sync + manual verification

**Files:**
- Modify: `docs/superpowers/specs/2026-06-15-debug-logging-mode-design.md`
- Modify: `README.md`

- [ ] **Step 1: Sync the spec's testing section**

In `docs/superpowers/specs/2026-06-15-debug-logging-mode-design.md`, in section **7. Testing**, replace the "Unit tests (pure pieces, no AppKit)" bullet's lead-in to state the chosen mechanism. Replace:
```markdown
- **Unit tests (pure pieces, no AppKit):**
```
with:
```markdown
- **Verification of pure pieces (standalone `swiftc`, no test target):** `scripts/verify-logging.swift`
  is compiled together with the real `LogLine`, `LogFileWriter`, `TrackSourceType`, and
  `DiagnosticsReport` source files (no copies) and run as an executable. It asserts:
```

- [ ] **Step 2: Add a "Debug logging" section to the README**

In `README.md`, add a new section (place it after the existing usage/features content, before any licence/credits footer):
```markdown
## Debug logging

If you hit a problem (for example, missing album art), you can capture logs to send along
with a bug report:

1. Open **Preferences ▸ Debugging** and turn on **Enable debug logging**.
2. Reproduce the problem (e.g. play the track whose artwork is missing).
3. Click **Export Logs…**. Jukebox writes a `Jukebox-Diagnostics-<timestamp>.txt` file and
   reveals it in Finder.
4. Attach that file to your GitHub issue or email.

The log is stored locally at
`~/Library/Application Support/Jukebox/Logs/Jukebox.log` and is never sent anywhere unless
you export and share it. It includes the names of tracks played while logging was enabled.
```

- [ ] **Step 3: Commit the docs**

```bash
git add docs/superpowers/specs/2026-06-15-debug-logging-mode-design.md README.md
git commit -m "Document debug logging and sync spec testing approach"
```

- [ ] **Step 4: Manual verification (the real point — diagnose the artwork bug)**

1. Run the app from Xcode (so you can also watch the live stream):
   `log stream --predicate 'subsystem == "com.jaydenkerr.Jukebox"' --level debug` in Terminal.
2. Connect to **Apple Music** and grant automation permission if prompted.
3. In **Preferences ▸ Debugging**, enable **Enable debug logging**.
4. Play an Apple Music **streamed** track whose artwork shows as an empty grey square.
5. Click **Export Logs…**, open the revealed `.txt`, and inspect the `[artwork]` lines. Confirm:
   - the track logs `source=streamed cloudStatus=subscription` (or similar), and
   - the poll logs show `data=nil` (or `empty=true`) **while** `rawData=Data(NNNN bytes)` is non-empty,
   - ending in `Artwork timed out after 21 attempts`.
6. That combination confirms the root cause (legacy `data` property fails for cloud artwork
   while `rawData` carries the real bytes) and is the evidence for the follow-up artwork fix.

---

## Self-Review

**Spec coverage:**

- §3 architecture (facade + two sinks) → Tasks 2–6.
- §4.1 facade, four categories, `.public` privacy → Task 6 (`Log.swift`).
- §4.2 file sink: AppSupport path, opt-in gate, UTC-`Z` format, ~5 MB single rollover, serialised queue → Tasks 3 (`LogFileWriter`) + 6 (`FileLogSink`, `Constants.Logging`).
- §4.3 track source-type + raw signals → Task 4 (pure) + Task 8 (ScriptingBridge builder + enum-name maps).
- §4.4 instrumentation (artwork detail, Spotify error, lifecycle/permissions) → Tasks 7 + 8.
- §4.5 diagnostics header + single-`.txt` export + reveal in Finder → Tasks 5 + 9.
- §4.6 Debugging preferences pane (toggle, Export button, caption, no-logs alert) → Task 10.
- §5 privacy (local-only, disclosed in caption + header) → Tasks 10 + 5.
- §6 error handling (swallow file I/O, no-logs alert, optional-guarded SB reads) → Tasks 3, 8, 9, 10.
- §7 testing (standalone verify of pure pieces + manual verification) → Tasks 2–5 + 11.
- §8 out of scope (artwork fix deferred) → stated in plan goal + Task 11 step 6.

**Placeholder scan:** No `TBD`/`TODO`/"handle edge cases"; every code step shows complete code; every command shows expected output. ✓

**Type consistency:** `LogLine.format`/`LogLine.timestamp`, `LogFileWriter.shouldRotate(currentBytes:incomingBytes:maxBytes:)`, `TrackDiagnostics.classify(hasAddress:hasFileLocation:cloudStatus:)`, `DiagnosticsReport(...).header()`, `FileLogSink.shared.logFileURL` / `.write(category:level:message:)`, `Log.<category>.<level>(_:)`, `LogExporter.export(report:) -> LogExporter.Outcome`, and `ContentViewModel.currentDiagnostics() -> DiagnosticsReport` are used consistently across the tasks that define and call them. ✓
