import Foundation

/// Whether the currently-playing track is a local file or streamed.
enum TrackSourceType: String {
    case localFile
    case streamed
    case internetRadioStream
    case unknown
}

/// Raw signals captured from a Music track plus the derived source type.
/// The classifier is pure (primitive inputs) so it is verifiable in isolation.
struct TrackDiagnostics: CustomStringConvertible {
    let sourceType: TrackSourceType
    let cloudStatus: String
    let kind: String
    let mediaKind: String
    let hasLocation: Bool
    let sizeBytes: Int64
    let address: String?

    /// Cloud statuses that indicate an Apple Music cloud/catalogue track.
    private static let cloudStatuses: Set<String> = ["subscription", "purchased", "matched", "uploaded"]

    /// Size is the local-file discriminator: a genuine local file has a file:// location
    /// AND a non-zero byte size. On macOS 26.5 streamed Apple Music tracks also report a
    /// location, so location alone is not sufficient — a zero size (no local bytes) means
    /// the track is streamed/cloud, not local. A known iCloud/Apple-Music cloud status wins
    /// outright.
    static func classify(hasAddress: Bool, hasFileLocation: Bool, cloudStatus: String, sizeBytes: Int64) -> TrackSourceType {
        if hasAddress { return .internetRadioStream }
        if cloudStatuses.contains(cloudStatus) { return .streamed }
        if hasFileLocation && sizeBytes > 0 { return .localFile }
        if sizeBytes == 0 { return .streamed }
        return .unknown
    }

    /// Single-line, log-friendly summary.
    var description: String {
        let addr = address.map { ", address=\($0)" } ?? ""
        return "source=\(sourceType.rawValue) cloudStatus=\(cloudStatus) kind=\"\(kind)\" "
            + "mediaKind=\(mediaKind) hasLocation=\(hasLocation) size=\(sizeBytes)\(addr)"
    }
}
