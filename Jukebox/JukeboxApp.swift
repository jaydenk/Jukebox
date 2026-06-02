//
//  JukeboxApp.swift
//  Jukebox
//
//  Created by Sasindu Jayasinghe on 13/10/21.
//

import SwiftUI
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {

    @AppStorage("viewedOnboarding") var viewedOnboarding: Bool = false
    @AppStorage("nowPlayingPinned") private var nowPlayingPinned = false
    @AppStorage("nowPlayingAlwaysOnTop") private var nowPlayingAlwaysOnTop = false {
        didSet {
            applyNowPlayingWindowLevel()
        }
    }
    @AppStorage("nowPlayingWindowHasPosition") private var nowPlayingWindowHasPosition = false
    @AppStorage("nowPlayingWindowX") private var nowPlayingWindowX = 0.0
    @AppStorage("nowPlayingWindowY") private var nowPlayingWindowY = 0.0
    // Owned (not @StateObject): AppDelegate is not a SwiftUI View, so @StateObject's
    // autoclosure was being evaluated twice here, creating a second ContentViewModel
    // (with duplicate distributed observers and timers). A plain stored property gives
    // exactly one instance, which the views observe via @ObservedObject.
    let contentViewVM = ContentViewModel()
    private var statusBarItem: NSStatusItem!
    private var statusBarMenu: NSMenu!
    private var popover: NSPopover!
    private var nowPlayingWindow: NowPlayingWindow!
    private var popoverHostView: NSHostingView<ContentView>!
    private var floatingHostView: NSHostingView<NowPlayingCompactView>!
    private var preferencesWindow: PreferencesWindow!
    private var onboardingWindow: OnboardingWindow!
    private var pauseTimer: Timer?
    private var isPaused: Bool = false
    private var barAnimator: StatusBarAnimator!
    private var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {

        // Initialise Sparkle updater
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)

        // Add observer to listen to when track changes to update the title in the menu bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusBarItemTitle),
            name: NSNotification.Name("TrackChanged"),
            object: nil)

        // Add observer for lightweight progress re-anchoring (position/state only)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateProgress),
            name: NSNotification.Name("ProgressUpdate"),
            object: nil)

        // Onboarding
        guard viewedOnboarding else {
            showOnboarding()
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        // Setup
        setupContentView()
        setupStatusBar()
        applyNowPlayingWindowLevel()

    }

    // MARK: - Setup

    private func setupContentView() {
        let popoverSize = NSSize(width: 272, height: 350)
        let floatingSize = Constants.NowPlaying.windowSize

        // Initialize Popover Content
        popoverHostView = NSHostingView(rootView: ContentView(contentViewVM: contentViewVM))
        popoverHostView.frame = NSRect(x: 0, y: 0, width: popoverSize.width, height: popoverSize.height)

        popover = NSPopover()
        popover.contentSize = popoverSize
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = popoverHostView

        // Initialize Floating Window Content
        floatingHostView = NSHostingView(rootView: NowPlayingCompactView(contentViewVM: contentViewVM))
        floatingHostView.frame = NSRect(x: 0, y: 0, width: floatingSize.width, height: floatingSize.height)

        nowPlayingWindow = NowPlayingWindow(
            contentRect: NSRect(x: 0, y: 0, width: floatingSize.width, height: floatingSize.height)
        )
        nowPlayingWindow.contentView = floatingHostView
        nowPlayingWindow.delegate = self
    }

    private func setupStatusBar() {
        // Initialize Status Bar Menu
        statusBarMenu = NSMenu()
        statusBarMenu.delegate = self
        let hostedAboutView = NSHostingView(rootView: AboutView())
        hostedAboutView.frame = NSRect(x: 0, y: 0, width: 220, height: 70)
        let aboutMenuItem = NSMenuItem()
        aboutMenuItem.view = hostedAboutView
        statusBarMenu.addItem(aboutMenuItem)
        statusBarMenu.addItem(NSMenuItem.separator())
        let checkForUpdates = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: "")
        checkForUpdates.target = updaterController
        statusBarMenu.addItem(checkForUpdates)
        statusBarMenu.addItem(
            withTitle: "Preferences...",
            action: #selector(showPreferences),
            keyEquivalent: "")
        statusBarMenu.addItem(
            withTitle: "Quit Jukebox",
            action: #selector(NSApplication.terminate),
            keyEquivalent: "")

        // Initialize Status Bar Item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Initialize the Status Bar Item Button properties
        if let statusBarItemButton = statusBarItem.button {
            // Initialize bar animator (renders full status bar content as template image)
            barAnimator = StatusBarAnimator(button: statusBarItemButton)
            statusBarItem.length = barAnimator.totalWidth

            // Set Status Bar Item Button click action
            statusBarItemButton.action = #selector(didClickStatusBarItem)
            statusBarItemButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - Status Bar Handlers

    // Handle left or right click of Status Bar Item
    @objc func didClickStatusBarItem(_ sender: AnyObject?) {

        guard let event = NSApp.currentEvent else { return }

        switch event.type {
        case .rightMouseUp:
            statusBarItem.menu = statusBarMenu
            statusBarItem.button?.performClick(nil)

        default:
            toggleNowPlayingPresentation(statusBarItem.button)
        }

    }

    // Set menu to nil when closed so popover is re-enabled
    func menuDidClose(_: NSMenu) {
        statusBarItem.menu = nil
    }

    // Toggle open and close of popover or floating window
    @objc func toggleNowPlayingPresentation(_ sender: NSStatusBarButton?) {
        guard let statusBarItemButton = sender else { return }

        if nowPlayingPinned {
            if nowPlayingWindow.isVisible {
                nowPlayingWindow.orderOut(nil)
            } else {
                showNowPlayingWindow(relativeTo: statusBarItemButton)
            }
        } else {
            if popover.isShown {
                popover.performClose(statusBarItemButton)
            } else {
                popover.show(relativeTo: statusBarItemButton.bounds, of: statusBarItemButton, preferredEdge: .minY)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc func togglePinnedMode(_ sender: Any?) {
        nowPlayingPinned.toggle()

        if nowPlayingPinned {
            if popover.isShown, let button = statusBarItem.button {
                popover.performClose(button)
            }
            if let button = statusBarItem.button {
                showNowPlayingWindow(relativeTo: button)
            }
        } else {
            nowPlayingWindow.orderOut(nil)
        }
    }

    private func showNowPlayingWindow(relativeTo button: NSStatusBarButton) {
        applyNowPlayingWindowLevel()
        if let savedOrigin = savedNowPlayingWindowOrigin() {
            nowPlayingWindow.setFrameOrigin(savedOrigin)
        } else {
            positionNowPlayingWindow(relativeTo: button)
        }
        nowPlayingWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func positionNowPlayingWindow(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window, let screen = buttonWindow.screen else { return }

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let windowSize = nowPlayingWindow.frame.size
        let screenFrame = screen.visibleFrame

        var x = screenRect.midX - (windowSize.width / 2)
        var y = screenRect.minY - windowSize.height - 6

        x = min(max(x, screenFrame.minX), screenFrame.maxX - windowSize.width)
        y = min(max(y, screenFrame.minY), screenFrame.maxY - windowSize.height)

        nowPlayingWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func savedNowPlayingWindowOrigin() -> NSPoint? {
        guard nowPlayingWindowHasPosition else { return nil }
        return NSPoint(x: nowPlayingWindowX, y: nowPlayingWindowY)
    }

    private func storeNowPlayingWindowOrigin(_ origin: NSPoint) {
        nowPlayingWindowX = origin.x
        nowPlayingWindowY = origin.y
        nowPlayingWindowHasPosition = true
    }

    private func applyNowPlayingWindowLevel() {
        if nowPlayingWindow == nil {
            return
        }
        nowPlayingWindow.level = nowPlayingAlwaysOnTop ? .floating : .normal
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == nowPlayingWindow else { return }
        storeNowPlayingWindowOrigin(window.frame.origin)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == nowPlayingWindow else { return }
        storeNowPlayingWindowOrigin(window.frame.origin)
    }

    private func updateStatusBarText(_ text: String) {
        barAnimator.setText(text)
        statusBarItem.length = barAnimator.totalWidth
    }

    // Updates the title of the status bar with the currently playing track
    @objc func updateStatusBarItemTitle(_ notification: NSNotification) {

        // Get track data from notification
        guard let trackTitle = notification.userInfo?["title"] as? String else { return }
        guard let trackArtist = notification.userInfo?["artist"] as? String else { return }
        guard let isPlaying = notification.userInfo?["isPlaying"] as? Bool else { return }
        let playbackStateString = notification.userInfo?["playbackState"] as? String ?? "stopped"
        let titleAndArtist = trackTitle.isEmpty && trackArtist.isEmpty ? "" : "\(trackTitle) • \(trackArtist)"

        // Update playback state animation
        let playbackState: PlaybackState
        switch playbackStateString {
        case "playing": playbackState = .playing
        case "paused": playbackState = .paused
        default: playbackState = .stopped
        }
        barAnimator.playbackState = playbackState

        // Update progress indicator
        let seekerPosition = notification.userInfo?["seekerPosition"] as? Double ?? 0
        let trackDuration = notification.userInfo?["trackDuration"] as? Double ?? 0
        barAnimator.setTrackProgress(position: seekerPosition, duration: trackDuration)

        // Handle empty track info case
        if titleAndArtist.isEmpty {
            updateStatusBarText("")
            return
        }

        // Handle playback state changes
        if isPlaying {
            pauseTimer?.invalidate()
            pauseTimer = nil
            isPaused = false

            updateStatusBarText(titleAndArtist)
        } else {
            isPaused = true

            updateStatusBarText(titleAndArtist)

            pauseTimer?.invalidate()
            pauseTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                guard let self = self, self.isPaused else { return }
                self.updateStatusBarText("")
            }
        }
    }

    // Lightweight progress re-anchor driven by the ContentViewModel poll. Updates
    // only the playback state and progress snapshot — it deliberately does NOT
    // call setText(), so the marquee scroll position and album art are left
    // untouched while the menu bar progress line is kept in sync with seeks.
    @objc func updateProgress(_ notification: NSNotification) {
        guard let barAnimator else { return }

        let playbackStateString = notification.userInfo?["playbackState"] as? String ?? "stopped"
        let playbackState: PlaybackState
        switch playbackStateString {
        case "playing": playbackState = .playing
        case "paused": playbackState = .paused
        default: playbackState = .stopped
        }
        barAnimator.playbackState = playbackState

        let seekerPosition = notification.userInfo?["seekerPosition"] as? Double ?? 0
        let trackDuration = notification.userInfo?["trackDuration"] as? Double ?? 0
        barAnimator.setTrackProgress(position: seekerPosition, duration: trackDuration)
    }

    func applicationWillTerminate(_ notification: Notification) {
        pauseTimer?.invalidate()
        pauseTimer = nil
    }

    // MARK: - Window Handlers

    // Open the preferences window
    @objc func showPreferences(_ sender: AnyObject?) {

        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
            let hostedPrefView = NSHostingView(rootView: PreferencesView(parentWindow: preferencesWindow))
            preferencesWindow.contentView = hostedPrefView
        }

        preferencesWindow.center()
        preferencesWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

    }

    // Open the onboarding window
    private func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindow()
            let hostedOnboardingView = NSHostingView(rootView: OnboardingView())
            onboardingWindow.contentView = hostedOnboardingView
        }

        onboardingWindow.center()
        onboardingWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // Close the onboarding window
    @objc func finishOnboarding(_ sender: AnyObject) {
        setupContentView()
        setupStatusBar()
        onboardingWindow.close()
        self.onboardingWindow = nil
    }

}

final class NowPlayingWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Resize: locked square, bounded so the album art never upscales noticeably
        aspectRatio = NSSize(width: 1, height: 1)
        let minS = Constants.NowPlaying.minWindowSize
        let maxS = Constants.NowPlaying.maxWindowSize
        contentMinSize = NSSize(width: minS, height: minS)
        contentMaxSize = NSSize(width: maxS, height: maxS)
    }
}

// MARK: - SwiftUI App Entry Point

@main
struct JukeboxApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {

        // Required to hide window
        Settings {
            EmptyView()
        }

    }

}
