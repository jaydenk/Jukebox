//
//  StatusBarAnimation.swift
//  Jukebox
//
//  Created by Sasindu Jayasinghe on 31/10/21.
//

import Foundation
import AppKit
import QuartzCore

enum PlaybackState {
    case playing
    case paused
    case stopped
}

class StatusBarAnimator {

    var playbackState: PlaybackState = .stopped {
        didSet {
            guard playbackState != oldValue else { return }
            if playbackState == .playing {
                barStartTime = CACurrentMediaTime()
            } else if playbackState == .stopped {
                trackDuration = 0
            }
            updateTimerState()
            renderFrame()
        }
    }

    // MARK: - Public text API

    private(set) var text: String = ""
    private(set) var textWidth: CGFloat = 0

    var totalWidth: CGFloat {
        if text.isEmpty {
            return textAreaStart
        }
        return textAreaStart + min(textWidth - textPadding, Constants.StatusBar.statusBarButtonLimit) + endPadding
    }

    private var needsScrolling: Bool {
        return textWidth - textPadding > Constants.StatusBar.statusBarButtonLimit
    }

    func setText(_ newText: String) {
        text = newText
        if newText.isEmpty {
            textWidth = 0
        } else {
            textWidth = newText.stringWidth(with: font) + textPadding
        }

        scrollStartTime = CACurrentMediaTime()

        scrollDelayTimer?.cancel()
        scrollDelayTimer = nil

        if needsScrolling {
            let workItem = DispatchWorkItem { [weak self] in
                self?.updateTimerState()
            }
            scrollDelayTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollDelay, execute: workItem)
        }

        updateTimerState()
        renderFrame()
    }

    // MARK: - Private properties

    private weak var button: NSStatusBarButton?
    private var animationTimer: Timer?
    private var barStartTime: CFTimeInterval = 0
    private var scrollStartTime: CFTimeInterval = 0
    private var scrollDelayTimer: DispatchWorkItem?

    private let font = Constants.StatusBar.marqueeFont
    private let textPadding: CGFloat = 16
    private let scrollDelay: Double = 5.0
    private let textAreaStart: CGFloat = 30  // 8 padding + 14 bars + 8 gap
    private let endPadding: CGFloat = 8

    private let barHeights = [7.0, 6.0, 9.0, 8.0]
    private let barDurations = [0.6, 0.3, 0.5, 0.7]
    private let buttonHeight: CGFloat

    // Progress indicator
    private var trackDuration: Double = 0
    private var trackPositionAtCapture: Double = 0
    private var positionCaptureTime: CFTimeInterval = 0
    private let progressLineHeight: CGFloat = 2.5
    private let progressLineGap: CGFloat = 1.5
    private var showPlaybackProgress: Bool = true

    private var isActivelyScrolling: Bool {
        guard needsScrolling else { return false }
        let elapsed = CACurrentMediaTime() - scrollStartTime
        return elapsed >= scrollDelay
    }

    // MARK: - Progress

    private var progressFraction: CGFloat {
        guard trackDuration > 0,
              playbackState == .playing || playbackState == .paused else { return 0 }

        let currentPosition: Double
        if playbackState == .playing {
            let elapsed = CACurrentMediaTime() - positionCaptureTime
            currentPosition = trackPositionAtCapture + elapsed
        } else {
            currentPosition = trackPositionAtCapture
        }

        return CGFloat(min(max(currentPosition / trackDuration, 0), 1))
    }

    func setTrackProgress(position: Double, duration: Double) {
        trackPositionAtCapture = position
        trackDuration = duration
        positionCaptureTime = CACurrentMediaTime()
    }

    // MARK: - Init

    private var defaultsObserver: NSObjectProtocol?

    init(button: NSStatusBarButton) {
        self.button = button
        self.buttonHeight = button.bounds.height
        self.showPlaybackProgress = UserDefaults.standard.object(forKey: "showPlaybackProgress") as? Bool ?? true

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let newValue = UserDefaults.standard.object(forKey: "showPlaybackProgress") as? Bool ?? true
            if self.showPlaybackProgress != newValue {
                self.showPlaybackProgress = newValue
                self.renderFrame()
            }
        }

        renderFrame()
    }

    // MARK: - Timer management

    private func updateTimerState() {
        let needsTimer = playbackState == .playing || isActivelyScrolling

        if needsTimer {
            guard animationTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.renderFrame()
            }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    // MARK: - Rendering

    private func renderFrame() {
        button?.image = renderTemplateImage()
    }

    private func renderTemplateImage() -> NSImage {
        let state = playbackState
        let height = buttonHeight
        let imageWidth = totalWidth
        let padding = Constants.StatusBar.statusBarButtonPadding

        // Pre-compute progress values
        let progress = progressFraction
        let showProgress = showPlaybackProgress
            && (state == .playing || state == .paused) && trackDuration > 0

        // Compute midY: the Y where the main icon starts, centring the full
        // element (icon + optional progress line below) in the button
        let iconHeight: CGFloat = state == .playing ? 9 : 10  // bars vs pause/stop
        let progressExtra = showProgress ? progressLineGap + progressLineHeight : 0
        let totalElementHeight = iconHeight + progressExtra
        let midY = (height - totalElementHeight) / 2 + progressExtra
        let capturedProgressLineHeight = progressLineHeight
        let capturedProgressLineGap = progressLineGap

        // Pre-compute bar heights for playing state
        var currentHeights = [CGFloat]()
        if state == .playing {
            let now = CACurrentMediaTime()
            let capturedBarStartTime = barStartTime
            for i in 0..<barHeights.count {
                let period = barDurations[i] * 2
                let phase = ((now - capturedBarStartTime + Double(i)) / period)
                    .truncatingRemainder(dividingBy: 1.0)
                let t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
                currentHeights.append(CGFloat(2 + (barHeights[i] - 2) * t))
            }
        }

        // Capture text rendering values
        let currentText = text
        let hasText = !currentText.isEmpty
        let capturedTextAreaStart = textAreaStart
        let capturedEndPadding = endPadding
        let capturedFont = font
        let capturedTextWidth = textWidth
        let capturedNeedsScrolling = needsScrolling

        var scrollOffset: CGFloat = 0
        if capturedNeedsScrolling {
            let elapsed = CACurrentMediaTime() - scrollStartTime
            if elapsed >= scrollDelay {
                let scrollDuration = capturedTextWidth / 30
                let phase = fmod(elapsed - scrollDelay, scrollDuration)
                scrollOffset = (phase / scrollDuration) * capturedTextWidth
            }
        }

        let imageSize = NSSize(width: imageWidth, height: height)

        let image = NSImage(size: imageSize, flipped: false) { _ in
            NSColor.black.setFill()

            // Draw bars at x = padding (8pt)
            switch state {
            case .stopped:
                NSBezierPath(roundedRect: NSRect(x: padding + 2, y: midY, width: 10, height: 10),
                             xRadius: 2, yRadius: 2).fill()

            case .paused:
                for i in 0..<2 {
                    NSBezierPath(roundedRect: NSRect(x: padding + CGFloat(i) * 8, y: midY, width: 6, height: 10),
                                 xRadius: 2, yRadius: 2).fill()
                }

            case .playing:
                for i in 0..<currentHeights.count {
                    NSBezierPath(roundedRect: NSRect(x: padding + CGFloat(i) * 3.5, y: midY, width: 2, height: currentHeights[i]),
                                 xRadius: 1, yRadius: 1).fill()
                }
            }

            // Draw progress line below bars
            if showProgress {
                let lineY = midY - capturedProgressLineGap - capturedProgressLineHeight
                let trackWidth = Constants.StatusBar.barAnimationWidth

                // Track (dim background)
                NSColor.black.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: NSRect(x: padding, y: lineY, width: trackWidth, height: capturedProgressLineHeight),
                             xRadius: capturedProgressLineHeight / 2, yRadius: capturedProgressLineHeight / 2).fill()

                // Fill (elapsed portion)
                let fillWidth = trackWidth * progress
                if fillWidth > 0 {
                    NSColor.black.setFill()
                    NSBezierPath(roundedRect: NSRect(x: padding, y: lineY, width: fillWidth, height: capturedProgressLineHeight),
                                 xRadius: capturedProgressLineHeight / 2, yRadius: capturedProgressLineHeight / 2).fill()
                }
            }

            // Draw text if present
            if hasText {
                let textClipWidth = imageWidth - capturedTextAreaStart - capturedEndPadding
                let textClipRect = NSRect(x: capturedTextAreaStart, y: 0, width: textClipWidth, height: height)

                let stringHeight = currentText.stringHeight(with: capturedFont)
                let textY = (height - stringHeight) / 2

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: capturedFont,
                    .foregroundColor: NSColor.black
                ]

                NSGraphicsContext.current?.saveGraphicsState()
                NSBezierPath(rect: textClipRect).addClip()

                if capturedNeedsScrolling && scrollOffset > 0 {
                    // Two copies for seamless scroll loop
                    (currentText as NSString).draw(
                        at: NSPoint(x: capturedTextAreaStart - scrollOffset, y: textY),
                        withAttributes: attributes)
                    (currentText as NSString).draw(
                        at: NSPoint(x: capturedTextAreaStart - scrollOffset + capturedTextWidth, y: textY),
                        withAttributes: attributes)
                } else {
                    (currentText as NSString).draw(
                        at: NSPoint(x: capturedTextAreaStart, y: textY),
                        withAttributes: attributes)
                }

                NSGraphicsContext.current?.restoreGraphicsState()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    deinit {
        animationTimer?.invalidate()
        scrollDelayTimer?.cancel()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }
}
