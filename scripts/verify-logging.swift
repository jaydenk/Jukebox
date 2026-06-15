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

        print("verify-logging: all checks passed")
    }
}
