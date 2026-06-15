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
