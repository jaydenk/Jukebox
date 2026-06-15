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
