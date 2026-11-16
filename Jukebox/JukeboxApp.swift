//
//  JukeboxApp.swift
//  Jukebox
//
//  Created by Sasindu Jayasinghe on 13/10/21.
//

import SwiftUI
import Sparkle
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, NSPopoverDelegate {

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
    @AppStorage("nowPlayingWindowWidth") private var nowPlayingWindowWidth = 240.0
    @AppStorage("nowPlayingWindowHeight") private var nowPlayingWindowHeight = 240.0
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
    private var floatingHostView: SnapHostingView<NowPlayingCompactView>!
    private var preferencesWindow: PreferencesWindow!
    private var onboardingWindow: OnboardingWindow!
    private var pauseTimer: Timer?
    private var isPaused: Bool = false
    // Set while a performClose() is in flight so the several paths that can close the
    // popover (item click, unpin, macOS 27 session end) never double-close it.
    private var popoverCloseRequested = false
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
        let floatingSize = savedNowPlayingWindowSize()

        // Initialize Popover Content
        popoverHostView = NSHostingView(rootView: ContentView(contentViewVM: contentViewVM))
        popoverHostView.frame = NSRect(x: 0, y: 0, width: popoverSize.width, height: popoverSize.height)
        // Frame-driven sizing: on macOS 14+ NSHostingView reports its SwiftUI intrinsic size
        // by default, which lets the popover grow past contentSize on macOS 26 (extra margin
        // around the fixed-size album art). sizingOptions = [] makes it respect the 272x350
        // frame, matching the tighter macOS 15 layout. (Same fix the floating window uses.)
        popoverHostView.sizingOptions = []

        popover = NSPopover()
        popover.delegate = self
        popover.contentSize = popoverSize
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = popoverHostView
        // Force the popover size. On macOS 26 `popover.contentSize` is honoured
        // inconsistently (the popover grows past it); preferredContentSize is the canonical
        // override that NSPopover respects.
        popover.contentViewController?.preferredContentSize = popoverSize

        // Initialize Floating Window Content
        floatingHostView = SnapHostingView(rootView: NowPlayingCompactView(contentViewVM: contentViewVM))
        // Single sizing authority: let the autoresized contentView frame drive
        // size (no intrinsic/min/max Auto Layout constraints from the host), so
        // the centred overlay lays out against an already-final frame each tick.
        floatingHostView.sizingOptions = []
        floatingHostView.translatesAutoresizingMaskIntoConstraints = true
        floatingHostView.autoresizingMask = [.width, .height]
        floatingHostView.frame = NSRect(x: 0, y: 0, width: floatingSize.width, height: floatingSize.height)

        nowPlayingWindow = NowPlayingWindow(
            contentRect: NSRect(x: 0, y: 0, width: floatingSize.width, height: floatingSize.height)
        )
        // The hosting view must NOT be the window's contentView. An NSHostingView that is a
        // window's contentView takes over the window's sizing: on the first display cycle it
        // resets contentMinSize/contentMaxSize to 0/infinity (dropping the 200–360 clamp),
        // and after a live resize it animates the window toward its own preferred size,
        // which fights the square aspect ratio and makes AppKit throw "more Update
        // Constraints in Window passes than there are views in the window". sizingOptions = []
        // does not stop this (verified on macOS 27.2). Hosting it inside a plain container
        // leaves the window, not SwiftUI, as the single sizing authority.
        let floatingContainer = NSView(frame: floatingHostView.frame)
        floatingContainer.autoresizingMask = [.width, .height]
        floatingContainer.addSubview(floatingHostView)
        nowPlayingWindow.contentView = floatingContainer
        nowPlayingWindow.delegate = self
        nowPlayingWindow.onCornerResizeBegan = { [weak self] in self?.floatingResizeDidBegin() }
        nowPlayingWindow.onCornerResizeEnded = { [weak self] in self?.floatingResizeDidEnd() }
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

        // macOS 27 rewrote the menu bar as a single system-owned window. A status item that
        // shows a popover or window (rather than an NSMenu) is expected to drive it through
        // the expanded interface session API instead of toggling it from the button action:
        // the system begins a session on left click or keyboard activation and ends it when
        // the item is clicked again, when the user moves to a neighbouring item (menu
        // tracking) or when the popover closes. Once a delegate is set, left clicks no longer
        // reach the button action; right clicks still do. Verified on macOS 27.0 with a
        // throwaway spike before adoption.
        if #available(macOS 27, *) {
            statusBarItem.expandedInterfaceDelegate = self
        }
    }

    // MARK: - Status Bar Handlers

    // Handle left or right click of Status Bar Item
    @objc func didClickStatusBarItem(_ sender: AnyObject?) {

        guard let event = NSApp.currentEvent else { return }

        switch event.type {
        case .rightMouseUp:
            showStatusBarMenu(with: event)

        default:
            toggleNowPlayingPresentation(statusBarItem.button)
        }

    }

    private func showStatusBarMenu(with event: NSEvent) {
        guard let button = statusBarItem.button else { return }
        if #available(macOS 27, *) {
            // Assigning statusItem.menu and calling performClick starts a second expanded
            // interface session under the delegate, and the system tears the menu down
            // within ~300 ms, so the menu is popped up directly instead. It is anchored to
            // the button's bottom-left corner (in the button's own coordinate space, which
            // popUp(positioning:at:in:) interprets with the view's flippedness) so it drops
            // below the menu bar like a status item menu. popUpContextMenu(_:with:for:) was
            // tried first but places the menu's top-left at the mouse, i.e. over the bar.
            let bounds = button.bounds
            let gap: CGFloat = 5
            let anchor = NSPoint(x: bounds.minX,
                                 y: button.isFlipped ? bounds.maxY + gap : bounds.minY - gap)
            statusBarMenu.popUp(positioning: nil, at: anchor, in: button)
        } else {
            statusBarItem.menu = statusBarMenu
            button.performClick(nil)
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
                contentViewVM.pauseTimer()
                contentViewVM.isResizing = false   // clear any latched live-resize state
            } else {
                showNowPlayingWindow(relativeTo: statusBarItemButton)
            }
        } else {
            if popover.isShown {
                closePopover()
            } else {
                showPopover(relativeTo: statusBarItemButton)
            }
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        guard popover.isShown, !popoverCloseRequested else { return }
        popoverCloseRequested = true
        popover.performClose(nil)
    }

    // NSPopoverDelegate
    func popoverDidClose(_ notification: Notification) {
        popoverCloseRequested = false
        if #available(macOS 27, *) {
            // The popover can close through means the menu bar cannot see (transient
            // dismissal, the pin button). Apple's guidance is to cancel the session in that
            // case; when the system already ended it this is a no-op.
            statusBarItem?.expandedInterfaceSession?.cancel()
        }
    }

    @objc func togglePinnedMode(_ sender: Any?) {
        nowPlayingPinned.toggle()

        if nowPlayingPinned {
            closePopover()
            if let button = statusBarItem.button {
                showNowPlayingWindow(relativeTo: button)
            }
        } else {
            nowPlayingWindow.orderOut(nil)
            contentViewVM.pauseTimer()
            contentViewVM.isResizing = false   // clear any latched live-resize state
        }
    }

    @objc func toggleAlwaysOnTop(_ sender: Any?) {
        nowPlayingAlwaysOnTop.toggle()   // didSet calls applyNowPlayingWindowLevel()
    }

    private func showNowPlayingWindow(relativeTo button: NSStatusBarButton) {
        applyNowPlayingWindowLevel()
        let size = savedNowPlayingWindowSize()
        if let savedOrigin = savedNowPlayingWindowOrigin() {
            nowPlayingWindow.setFrame(NSRect(origin: savedOrigin, size: size), display: true)
        } else {
            nowPlayingWindow.setContentSize(size)
            positionNowPlayingWindow(relativeTo: button)
        }
        nowPlayingWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        contentViewVM.startTimer()
    }

    private func positionNowPlayingWindow(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window, let screen = buttonWindow.screen else { return }

        let windowSize = nowPlayingWindow.frame.size
        let screenFrame = screen.visibleFrame

        var x: CGFloat
        var y: CGFloat
        if buttonWindow.frame.height > 0 {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect)
            x = screenRect.midX - (windowSize.width / 2)
            y = screenRect.minY - windowSize.height - 6
        } else {
            // macOS 27: until the system layout table has given the item a slot, the status
            // bar window reports a zero-height placeholder frame at the screen origin, so a
            // conversion through it would drop the window in the bottom-left corner. Anchor
            // to the top-right of the screen instead.
            x = screenFrame.maxX - windowSize.width - 6
            y = screenFrame.maxY - windowSize.height - 6
        }

        x = min(max(x, screenFrame.minX), screenFrame.maxX - windowSize.width)
        y = min(max(y, screenFrame.minY), screenFrame.maxY - windowSize.height)

        nowPlayingWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// The remembered window size, squared and clamped to the allowed range. Programmatic
    /// setFrame/setContentSize bypass contentMin/MaxSize, and sizes saved while the clamp
    /// was being dropped (see setupContentView) can be out of range, so clamp on restore.
    private func savedNowPlayingWindowSize() -> NSSize {
        let minS = Constants.NowPlaying.minWindowSize
        let maxS = Constants.NowPlaying.maxWindowSize
        let side = min(max(min(nowPlayingWindowWidth, nowPlayingWindowHeight), minS), maxS)
        return NSSize(width: side, height: side)
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

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == nowPlayingWindow else { return }
        floatingResizeDidBegin()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == nowPlayingWindow else { return }
        floatingResizeDidEnd()
    }

    // Shared by AppKit's live resize (the thin native border) and the corner grips'
    // own resize tracking (NowPlayingWindow.trackCornerResize), which produces no
    // live-resize notifications of its own.
    private func floatingResizeDidBegin() {
        // Hide the transient hover overlay (and quiet position updates) during the
        // drag so the only visible content is the edge-pinned album art, which
        // tracks the resize cleanly. The overlay can't wobble if it isn't shown.
        contentViewVM.isResizing = true
        contentViewVM.pauseTimer()
    }

    private func floatingResizeDidEnd() {
        let frame = nowPlayingWindow.frame
        storeNowPlayingWindowOrigin(frame.origin)
        nowPlayingWindowWidth = frame.size.width
        nowPlayingWindowHeight = frame.size.height
        contentViewVM.isResizing = false
        contentViewVM.startTimer()
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
            let hostedPrefView = NSHostingView(rootView: PreferencesView(parentWindow: preferencesWindow, contentViewVM: contentViewVM))
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

// MARK: - macOS 27 expanded interface sessions

@available(macOS 27, *)
extension AppDelegate: NSStatusItemExpandedInterfaceDelegate {

    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        guard let button = statusItem.button else {
            session.cancel()
            return
        }
        if nowPlayingPinned {
            // The floating window is persistent, not a transient expanded interface: toggle
            // it and hand the session straight back so the item is not held "open" in the bar.
            toggleNowPlayingPresentation(button)
            session.cancel()
            return
        }
        // Show only. The second click on the item ends the session (below) rather than
        // re-entering here, so no toggle logic is needed on this path.
        guard !popover.isShown else { return }
        showPopover(relativeTo: button)
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        closePopover()
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

    // MARK: Corner resize

    /// Called when a corner-grip resize starts and ends, standing in for the live-resize
    /// notifications AppKit only sends for its own (native border) resizing.
    var onCornerResizeBegan: (() -> Void)?
    var onCornerResizeEnded: (() -> Void)?

    /// Resizes the window from `corner`, tracking the drag that began with `mouseDown`
    /// until the button is released (anywhere, including outside the window). The
    /// opposite corner stays fixed and the window stays square within the size bounds.
    func trackCornerResize(from corner: WindowCorner, with mouseDown: NSEvent) {
        let startFrame = frame
        let startMouse = NSEvent.mouseLocation   // screen coordinates, same space as frame
        // Begin lazily on the first drag: a plain click on a grip must not flash the hover
        // controls, restart the position timer or persist an unchanged frame.
        var began = false
        defer {
            isTrackingCornerResize = false
            if began { onCornerResizeEnded?() }
        }
        while let event = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp { break }
            if !began {
                began = true
                isTrackingCornerResize = true
                onCornerResizeBegan?()
            }
            let mouse = NSEvent.mouseLocation
            let newFrame = CornerResize.frame(
                start: startFrame,
                corner: corner,
                delta: CGVector(dx: mouse.x - startMouse.x, dy: mouse.y - startMouse.y),
                minSide: Constants.NowPlaying.minWindowSize,
                maxSide: Constants.NowPlaying.maxWindowSize)
            setFrame(newFrame, display: true)
        }
    }

    /// True while trackCornerResize is running. AppKit's `inLiveResize` is only set for its
    /// own border resize, so SnapHostingView checks this as well.
    private(set) var isTrackingCornerResize = false
}

/// NSHostingView that suppresses implicit Core Animation actions on its layer
/// tree during a live window resize, so the hosted SwiftUI content snaps to the
/// new frame each tick instead of tweening (which SwiftUI's Transaction cannot
/// reach because the tween is at the CALayer level).
final class SnapHostingView<Content: View>: NSHostingView<Content> {
    override func layout() {
        let resizing = inLiveResize || (window as? NowPlayingWindow)?.isTrackingCornerResize == true
        if resizing {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            super.layout()
            CATransaction.commit()
        } else {
            super.layout()
        }
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
