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
        // LogLine
        let fixedDate = Date(timeIntervalSince1970: 1_750_000_000) // 2025-06-15T13:46:40Z
        let ts = LogLine.timestamp(fixedDate)
        expect(ts.hasSuffix("Z"), "timestamp must end in Z (UTC), got \(ts)")
        expect(ts.contains("."), "timestamp must include fractional seconds, got \(ts)")
        let line = LogLine.format(date: fixedDate, category: "artwork", level: "DEBUG", message: "hello")
        expect(line.contains("[artwork]"), "line must contain bracketed category, got \(line)")
        expect(line.contains("DEBUG"), "line must contain level, got \(line)")
        expect(line.hasSuffix("hello"), "line must end with message, got \(line)")
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

        print("verify-logging: all checks passed")
    }
}
