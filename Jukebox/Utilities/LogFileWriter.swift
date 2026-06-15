import Foundation

/// AppKit-free, size-capped append-only log writer with a single rollover.
/// The path is injected so this type is verifiable in isolation. Not
/// thread-safe alone; callers serialise access (FileLogSink uses a queue).
final class LogFileWriter {
    private let fileURL: URL
    private let rolledURL: URL
    private let maxBytes: Int
    private let fileManager: FileManager

    init(fileURL: URL, maxBytes: Int, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.rolledURL = fileURL.appendingPathExtension("1") // e.g. Jukebox.log.1
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    /// Appends one line (a trailing newline is added), rotating first if needed.
    func append(_ line: String) {
        let data = Data((line + "\n").utf8)
        ensureFileExists()
        rotateIfNeeded(incomingBytes: data.count)
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Pure rotation decision — extracted so it can be verified directly.
    static func shouldRotate(currentBytes: Int, incomingBytes: Int, maxBytes: Int) -> Bool {
        return currentBytes > 0 && currentBytes + incomingBytes > maxBytes
    }

    private func rotateIfNeeded(incomingBytes: Int) {
        guard LogFileWriter.shouldRotate(currentBytes: currentBytes(),
                                         incomingBytes: incomingBytes,
                                         maxBytes: maxBytes) else { return }
        try? fileManager.removeItem(at: rolledURL)
        try? fileManager.moveItem(at: fileURL, to: rolledURL)
        fileManager.createFile(atPath: fileURL.path, contents: nil)
    }

    private func ensureFileExists() {
        let dir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private func currentBytes() -> Int {
        let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
        return (attrs?[.size] as? Int) ?? 0
    }
}
