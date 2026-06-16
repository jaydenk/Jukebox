//
//  ContentViewModel.swift
//  Jukebox
//
//  Created by Sasindu Jayasinghe on 13/10/21.
//

import Foundation
import SwiftUI
import ScriptingBridge

class ContentViewModel: ObservableObject {
    
    // Music Applications
    @AppStorage("connectedApp") private var connectedApp = ConnectedApps.spotify
    var spotifyApp: SpotifyApplication?
    var appleMusicApp: MusicApplication?
    
    var name: String {
        connectedApp == .spotify ? Constants.Spotify.name : Constants.AppleMusic.name
    }
    
    var isRunning: Bool {
        connectedApp == .spotify ? spotifyApp?.isRunning ?? false : appleMusicApp?.isRunning ?? false
    }
    
    var notification: String {
        connectedApp == .spotify ? Constants.Spotify.notification : Constants.AppleMusic.notification
    }
    
    // Popover
    @Published var popoverIsShown = true
    
    // Track
    @Published var track = Track()
    @Published var isPlaying = false
    @Published var isLoved = false
    
    // Seeker
    @Published var timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @Published var trackDuration: Double = 0
    @Published var seekerPosition: Double = 0
    @Published var isScrubbing = false
    @Published var isResizing = false

    // Menu bar progress re-anchor poll (runs independently of the popover)
    private var menuBarProgressTimer: Timer?
    private let menuBarProgressInterval: TimeInterval = 1.0

    private var observer: NSKeyValueObservation?
    
    init() {
        setupMusicApps()
        setupObservers()
        guard isRunning else { return }
        playStateOrTrackDidChange(nil)
    }
    
    deinit {
        observer?.invalidate()
        stopMenuBarProgressUpdates()
    }
    
    // MARK: - Setup
    
    private func setupMusicApps() {
        Log.general.info("Setting up music apps for \(name)")
        switch connectedApp {
        case .spotify:
            guard spotifyApp == nil else { return }
            spotifyApp = SBApplication(bundleIdentifier: Constants.Spotify.bundleID)
        case .appleMusic:
            guard appleMusicApp == nil else { return }
            appleMusicApp = SBApplication(bundleIdentifier: Constants.AppleMusic.bundleID)
        }
    }
    
    private func setupObservers() {
        
        observer = UserDefaults.standard.observe(\.connectedApp, options: [.old, .new]) { defaults, change in
            DistributedNotificationCenter.default().removeObserver(self)
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(self.playStateOrTrackDidChange),
                name: NSNotification.Name(rawValue: self.notification),
                object: nil,
                suspensionBehavior: .deliverImmediately)
            self.setupMusicApps()
            self.playStateOrTrackDidChange(nil)
        }
                
        // ScriptingBridge Observer
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playStateOrTrackDidChange),
            name: NSNotification.Name(rawValue: notification),
            object: nil,
            suspensionBehavior: .deliverImmediately)
        
        // Add observer to listen for popover open
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverIsOpening),
            name: NSPopover.willShowNotification,
            object: nil)
        
        // Add observer to listen for popover close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverIsClosing),
            name: NSPopover.didCloseNotification,
            object: nil)
        
    }
    
    // MARK: - Notification Handlers
    
    @objc func playStateOrTrackDidChange(_ sender: NSNotification?) {
        setupMusicApps()
        guard isRunning, sender?.userInfo?["Player State"] as? String != "Stopped" else {
            self.isPlaying = false
            self.track.title = ""
            self.track.artist = ""
            self.track.albumArt = NSImage()
            self.trackDuration = 0
            stopMenuBarProgressUpdates()
            updateMenuBarText(isStopped: true)
            return
        }

        Log.playback.debug("Play state or current track changed")
        getPlayState()
        getTrackInformation()
        startMenuBarProgressUpdates()
    }
    
    // MARK: - Media & Playback
    
    private func getPlayState() {
        isPlaying = connectedApp == .spotify
        ? spotifyApp?.playerState == .playing
        : appleMusicApp?.playerState == .playing
    }
    
    func getTrackInformation() {
        
        Log.playback.debug("Getting track information for \(name)")
        
        switch connectedApp {
        case .spotify:
            
            // Track
            self.track.title = spotifyApp?.currentTrack?.name ?? "Unknown Title"
            self.track.artist = spotifyApp?.currentTrack?.artist ?? "Unknown Artist"
            self.track.album = spotifyApp?.currentTrack?.album ?? "Unknown Album"
            if let artworkURLString = spotifyApp?.currentTrack?.artworkUrl,
               let url = URL(string: artworkURLString) {
                URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                    guard let data = data, error == nil else {
                        Log.artwork.error("Spotify artwork fetch failed: \(error!.localizedDescription)")
                        return
                    }
                    DispatchQueue.main.async {
                        self?.track.albumArt = NSImage(data: data) ?? NSImage()
                    }

                }.resume()
            } else {
                // No artwork URL for this track — clear stale art from the previous track.
                self.track.albumArt = NSImage()
            }

            // Seeker
            self.trackDuration = Double(spotifyApp?.currentTrack?.duration ?? 0) / 1000
            
        case .appleMusic:
            
            // Track
            self.track.title = appleMusicApp?.currentTrack?.name ?? "Unknown Title"
            self.track.artist = appleMusicApp?.currentTrack?.artist ?? "Unknown Artist"
            self.track.album = appleMusicApp?.currentTrack?.album ?? "Unknown Album"
            self.isLoved = appleMusicApp?.currentTrack?.loved ?? false

            // Album art. A track with no artwork must clear any art left over
            // from the previously playing track. Apple Music delivers artwork
            // data asynchronously, so when artwork exists we poll briefly for the
            // data to arrive — and still clear it if it never materialises.
            // These diagnostics make extra ScriptingBridge round-trips purely for
            // logging, so skip them entirely unless debug logging is enabled.
            if FileLogSink.shared.isEnabled {
                if let diagnostics = makeAppleMusicTrackDiagnostics() {
                    Log.artwork.debug("Apple Music track: \(diagnostics.description)")
                }
                let artworkCount = self.appleMusicApp?.currentTrack?.artworks?().count ?? 0
                Log.artwork.debug("artworks().count = \(artworkCount)")
            }

            // Always poll: Apple Music loads streamed artwork asynchronously, so artworks()
            // is frequently empty (count 0) at the moment of a track change and populates a
            // second or two later. Re-check each attempt rather than bailing on the first
            // empty read; clear stale art immediately, and time out if it never arrives.
            do {
                var count = 0
                var waitForData: (() -> Void)!
                waitForData = {
                    // SBElementArray is a lazy ScriptingBridge collection: use its [index]
                    // subscript (a faulting proxy element), NOT Swift's `.first`, which
                    // yields nil for it even when count > 0. Never return silently.
                    let artworks = self.appleMusicApp?.currentTrack?.artworks?()
                    guard let artworks, artworks.count > 0, let art = artworks[0] as? MusicArtwork else {
                        // No artwork yet — Apple Music may still be loading it. Clear any stale
                        // art on the first miss, then keep polling until it appears or we time out.
                        if count == 0 { self.track.albumArt = NSImage() }
                        if count > 20 {
                            Log.artwork.notice("No artwork after \(count) attempts "
                                + "(count=\(artworks?.count ?? 0)); cleared album art")
                            self.track.albumArt = NSImage()
                            return
                        }
                        Log.artwork.debug("attempt \(count): artworks empty "
                            + "(count=\(artworks?.count ?? 0)); waiting for async load")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { waitForData() }
                        count += 1
                        return
                    }
                    // Resolve artwork across OS versions. On macOS <= 15 `data` is a genuine
                    // NSImage — use it directly. On macOS 26.5 `data` is an NSAppleEventDescriptor
                    // and `rawData` an opaque SBObject proxy, so fall back to recovering bytes via
                    // SBObject.get() / the descriptor payload. `as? NSImage` is safe on 26.5 (a
                    // descriptor isn't an NSImage -> nil), so we never call NSImage methods on a
                    // descriptor.
                    func imageBytes(_ value: Any?) -> Data? {
                        switch value {
                        case let d as Data where !d.isEmpty:     return d
                        case let d as NSData where d.length > 0: return d as Data
                        default:                                 return nil
                        }
                    }
                    let dataValue = art.data
                    let rawValue = art.rawData
                    let dataImage = (dataValue as AnyObject?).flatMap { $0 as? NSImage }
                    let rawDirect = imageBytes(rawValue)
                    let rawResolved = imageBytes(rawValue.flatMap { $0 as? SBObject }?.get())
                    let descBytes = (dataValue as AnyObject?).flatMap { $0 as? NSAppleEventDescriptor }?.data
                    let descResolved = (descBytes?.isEmpty == false) ? descBytes : nil

                    let resolved: (source: String, image: NSImage)? = {
                        if let dataImage, !dataImage.isEmpty() {
                            return ("data(NSImage)", dataImage)   // macOS <= 15
                        }
                        let byteRoutes: [(String, Data)] = [
                            ("rawData", rawDirect),
                            ("rawData.get()", rawResolved),
                            ("data-descriptor", descResolved),
                        ].compactMap { pair in pair.1.map { (pair.0, $0) } }
                        if let hit = byteRoutes.first(where: { NSImage(data: $0.1) != nil }),
                           let image = NSImage(data: hit.1) {
                            return ("\(hit.0)(\(hit.1.count)b)", image)   // macOS 26.5
                        }
                        return nil
                    }()

                    if let resolved {
                        Log.artwork.info("Artwork resolved via \(resolved.source) on attempt \(count) "
                            + "(\(Int(resolved.image.size.width))x\(Int(resolved.image.size.height)))")
                        self.track.albumArt = resolved.image
                    } else {
                        Log.artwork.debug("attempt \(count): "
                            + "data(NSImage)=\(dataImage != nil) "
                            + "rawData=\(rawDirect?.count.description ?? "nil") "
                            + "rawData.get()=\(rawResolved?.count.description ?? "nil") "
                            + "data-descriptor=\(descResolved?.count.description ?? "nil") "
                            + "data-class=\((dataValue as AnyObject?).map { "\(type(of: $0))" } ?? "nil") "
                            + "rawData-class=\((rawValue as AnyObject?).map { "\(type(of: $0))" } ?? "nil") "
                            + "format=\(art.format.map { "\($0)" } ?? "nil") "
                            + "downloaded=\(art.downloaded.map { "\($0)" } ?? "nil")")
                        if count > 20 {
                            Log.artwork.error("Artwork timed out after \(count) attempts; no accessor "
                                + "(data NSImage / rawData / rawData.get() / data descriptor) yielded an image")
                            self.track.albumArt = NSImage()
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            waitForData()
                        }
                    }
                    count += 1
                }
                waitForData()
            }
            
            // Seeker
            self.trackDuration = Double(appleMusicApp?.currentTrack?.duration ?? 0)
            
        }
        
        // Post notification to update the menu bar track title
        updateMenuBarText()

    }

    // MARK: - Diagnostics

    /// Reads the current Apple Music track's source signals via ScriptingBridge.
    /// Property reads are optional-guarded — an inapplicable property (e.g.
    /// `location` on a streamed track) returns nil rather than crashing.
    private func makeAppleMusicTrackDiagnostics() -> TrackDiagnostics? {
        guard let track = appleMusicApp?.currentTrack else { return nil }
        let address = (track as? MusicURLTrack)?.address
        let hasAddress = !(address?.isEmpty ?? true)
        // On macOS 26.5 streamed Apple Music tracks also report a `location`, so a genuine
        // local file is distinguished by a file:// URL AND a non-zero byte size — not by the
        // mere presence of a location.
        // `location` is doubly-optional here (the @objc-optional member returns URL?),
        // so collapse URL?? -> URL? before testing the scheme.
        let locationURL = (track as? MusicFileTrack)?.location ?? nil
        let hasFileLocation = locationURL?.isFileURL == true
        let sizeBytes = track.size ?? 0
        let cloudStatusName = Self.cloudStatusName(track.cloudStatus)
        let source = TrackDiagnostics.classify(hasAddress: hasAddress,
                                                hasFileLocation: hasFileLocation,
                                                cloudStatus: cloudStatusName,
                                                sizeBytes: sizeBytes)
        return TrackDiagnostics(
            sourceType: source,
            cloudStatus: cloudStatusName,
            kind: track.kind ?? "",
            mediaKind: Self.mediaKindName(track.mediaKind),
            hasLocation: hasFileLocation,
            sizeBytes: sizeBytes,
            address: hasAddress ? address : nil)
    }

    private static func cloudStatusName(_ status: MusicEClS?) -> String {
        switch status {
        case .purchased: return "purchased"
        case .matched: return "matched"
        case .uploaded: return "uploaded"
        case .subscription: return "subscription"
        case .ineligible: return "ineligible"
        case .removed: return "removed"
        case .error: return "error"
        case .duplicate: return "duplicate"
        case .noLongerAvailable: return "noLongerAvailable"
        case .notUploaded: return "notUploaded"
        case .unknown: return "unknown"
        case .none: return "unavailable"
        @unknown default: return "unrecognised(\(Self.fourCC(status?.rawValue ?? 0)))"
        }
    }

    /// Formats a FourCharCode (e.g. a MusicEClS raw value) as a printable tag for logs, so
    /// an unmapped cloud-status value seen in the field can be identified and mapped.
    private static func fourCC(_ code: UInt32) -> String {
        let bytes = [UInt8(truncatingIfNeeded: code >> 24), UInt8(truncatingIfNeeded: code >> 16),
                     UInt8(truncatingIfNeeded: code >> 8), UInt8(truncatingIfNeeded: code)]
        let printable = bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
        let ascii = printable ? "'\(String(bytes: bytes, encoding: .ascii) ?? "")' " : ""
        return "\(ascii)0x\(String(code, radix: 16))"
    }

    private static func mediaKindName(_ kind: MusicEMdK?) -> String {
        switch kind {
        case .song: return "song"
        case .musicVideo: return "musicVideo"
        case .unknown: return "unknown"
        case .none: return "unavailable"
        @unknown default: return "unrecognised"
        }
    }

    /// Snapshot of current app/track state for the exported diagnostics header.
    func currentDiagnostics() -> DiagnosticsReport {
        let bundleID = connectedApp == .spotify ? Constants.Spotify.bundleID : Constants.AppleMusic.bundleID
        let permission = Helper.promptUserForConsent(for: bundleID)
        let trackSource: String
        switch connectedApp {
        case .appleMusic:
            trackSource = makeAppleMusicTrackDiagnostics()?.description ?? "no track"
        case .spotify:
            trackSource = "source=streamed (Spotify)"
        }
        return DiagnosticsReport(
            appVersion: Constants.AppInfo.appVersion ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            connectedApp: name,
            isRunning: isRunning,
            permissionStatus: Self.permissionName(permission),
            debugLoggingEnabled: UserDefaults.standard.bool(forKey: Constants.Logging.enabledKey),
            currentTrackSource: trackSource,
            exportedAt: Date())
    }

    private static func permissionName(_ status: Helper.PermissionStatus) -> String {
        switch status {
        case .closed: return "app not open"
        case .granted: return "granted"
        case .notPrompted: return "not prompted"
        case .denied: return "denied"
        }
    }

    private func updateMenuBarText(isStopped: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let title = self.track.title as String?,
                  let artist = self.track.artist as String? else { return }
            let playbackState: String
            if isStopped {
                playbackState = "stopped"
            } else if self.isPlaying {
                playbackState = "playing"
            } else {
                playbackState = "paused"
            }

            // Query current seeker position for status bar progress indicator
            self.getCurrentSeekerPosition()

            let trackInfo: [String: Any] = [
                "title": title,
                "artist": artist,
                "isPlaying": self.isPlaying,
                "playbackState": playbackState,
                "seekerPosition": self.seekerPosition,
                "trackDuration": self.trackDuration
            ]
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "TrackChanged"), object: nil, userInfo: trackInfo)
        }
    }
    
    func togglePlayPause() {
        switch connectedApp {
        case .spotify:
            spotifyApp?.playpause?()
        case .appleMusic:
            appleMusicApp?.playpause?()
        }
    }
    
    func previousTrack() {
        switch connectedApp {
        case .spotify:
            spotifyApp?.previousTrack?()
        case .appleMusic:
            appleMusicApp?.backTrack?()
        }
    }
    
    func nextTrack() {
        switch connectedApp {
        case .spotify:
            spotifyApp?.nextTrack?()
        case .appleMusic:
            appleMusicApp?.nextTrack?()
        }
    }
    
    func toggleLoveTrack() {
        switch connectedApp {
        case .appleMusic:
            if let isLovedTrack = appleMusicApp?.currentTrack?.loved {
                appleMusicApp?.currentTrack?.setLoved?(!isLovedTrack)
                self.isLoved = !isLovedTrack
            }
        case .spotify:
            Log.playback.notice("Love is not supported for Spotify")
        }
    }
    
    // MARK: - Seeker
    
    func getCurrentSeekerPosition() {
        guard isRunning, !isScrubbing else { return }
        self.seekerPosition = connectedApp == .spotify
        ? Double(spotifyApp?.playerPosition ?? 0)
        : Double(appleMusicApp?.playerPosition ?? 0)
    }

    // MARK: - Menu Bar Progress Poll

    // The menu bar progress line self-advances from a single position snapshot,
    // so it only stays accurate while it is periodically re-anchored to the real
    // player position. Notifications alone are insufficient: Apple Music does NOT
    // post a `playerInfo` notification when the playhead is moved on a local
    // (file) track, so a seek would otherwise go unnoticed until the next track
    // change. This low-frequency poll reconciles position and play state for both
    // apps, independently of whether the popover is open.
    private func startMenuBarProgressUpdates() {
        guard menuBarProgressTimer == nil else { return }
        let timer = Timer(timeInterval: menuBarProgressInterval, repeats: true) { [weak self] _ in
            self?.pollMenuBarProgress()
        }
        RunLoop.main.add(timer, forMode: .common)
        menuBarProgressTimer = timer
    }

    private func stopMenuBarProgressUpdates() {
        menuBarProgressTimer?.invalidate()
        menuBarProgressTimer = nil
    }

    private func pollMenuBarProgress() {
        guard isRunning else {
            stopMenuBarProgressUpdates()
            return
        }

        getCurrentSeekerPosition()

        let stateString: String
        switch connectedApp {
        case .spotify:
            switch spotifyApp?.playerState {
            case .playing: stateString = "playing"
            case .paused: stateString = "paused"
            default: stateString = "stopped"
            }
        case .appleMusic:
            switch appleMusicApp?.playerState {
            case .playing: stateString = "playing"
            case .paused: stateString = "paused"
            default: stateString = "stopped"
            }
        }

        let playing = (stateString == "playing")
        if isPlaying != playing { isPlaying = playing }

        let info: [String: Any] = [
            "playbackState": stateString,
            "seekerPosition": seekerPosition,
            "trackDuration": trackDuration
        ]
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "ProgressUpdate"), object: nil, userInfo: info)
    }
    
    func seek(to seconds: Double) {
        switch connectedApp {
        case .spotify:
            spotifyApp?.setPlayerPosition?(seconds)
        case .appleMusic:
            appleMusicApp?.setPlayerPosition?(seconds)
        }
        seekerPosition = seconds
    }
    
    func startTimer() {
        timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    }
    
    func pauseTimer() {
        timer.upstream.connect().cancel()
    }
    
    @objc private func popoverIsOpening(_ notification: NSNotification) {
        startTimer()
        popoverIsShown = true
    }
    
    @objc private func popoverIsClosing(_ notification: NSNotification) {
        pauseTimer()
        popoverIsShown = false
    }
    
}
