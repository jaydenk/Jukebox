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
        print("verify-logging: all checks passed")
    }
}
