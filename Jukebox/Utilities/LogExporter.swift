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
