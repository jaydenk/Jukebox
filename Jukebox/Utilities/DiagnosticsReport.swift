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
