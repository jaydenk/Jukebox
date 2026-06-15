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
