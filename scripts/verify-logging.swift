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
