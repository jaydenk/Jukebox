import Foundation
import os

/// App-wide logging facade. Logging is gated on the opt-in `debugLoggingEnabled`
/// preference: when it is off, the message autoclosure is never evaluated — so
/// building diagnostic strings (some of which make ScriptingBridge round-trips)
/// costs nothing — and nothing is written to os.Logger or the file. When it is on,
/// each line goes to os.Logger (.public, so it is readable in Console.app and in
/// exported logs the user chooses to share) and to FileLogSink.
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

    func debug(_ message: @autoclosure () -> String)  { emit(.debug, message) }
    func info(_ message: @autoclosure () -> String)   { emit(.info, message) }
    func notice(_ message: @autoclosure () -> String) { emit(.notice, message) }
    func error(_ message: @autoclosure () -> String)  { emit(.error, message) }

    private func emit(_ level: Level, _ message: () -> String) {
        // Opt-in only. Bail before evaluating the message so callers never pay for
        // building log strings (or the reads behind them) while logging is disabled.
        guard FileLogSink.shared.isEnabled else { return }
        let text = message()
        switch level {
        case .debug:  logger.debug("\(text, privacy: .public)")
        case .info:   logger.info("\(text, privacy: .public)")
        case .notice: logger.notice("\(text, privacy: .public)")
        case .error:  logger.error("\(text, privacy: .public)")
        }
        FileLogSink.shared.write(category: name, level: level.rawValue, message: text)
    }
}
