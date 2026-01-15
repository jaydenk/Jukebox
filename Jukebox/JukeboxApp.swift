//
//  JukeboxApp.swift
//  Jukebox
//
//  Created by Sasindu Jayasinghe on 13/10/21.
//

import SwiftUI

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
    @StateObject var contentViewVM = ContentViewModel()
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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
                
        // Add observer to listen to when track changes to update the title in the menu bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusBarItemTitle),
            name: NSNotification.Name("TrackChanged"),
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
            
            // Add bar animation to Status Bar Item Button
            let barAnimation = StatusBarAnimation(
                menubarAppearance: statusBarItemButton.effectiveAppearance,
                menubarHeight: statusBarItemButton.bounds.height, isPlaying: false)
            statusBarItemButton.addSubview(barAnimation)
            
            // Add default marquee text
            let marqueeText = MenuMarqueeText(
                text: "",
                menubarBounds: statusBarItemButton.bounds,
                menubarAppearance: statusBarItemButton.effectiveAppearance)
            statusBarItemButton.addSubview(marqueeText)
            
            statusBarItemButton.frame = NSRect(x: 0, y: 0, width: barAnimation.bounds.width + 16, height: statusBarItemButton.bounds.height)
            marqueeText.menubarBounds = statusBarItemButton.bounds
            
            // Set Status Bar Item Button click action
            statusBarItemButton.action = #selector(didClickStatusBarItem)
            statusBarItemButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            
        }
        
        // Add observer to listen for status bar appearance changes
        statusBarItem.addObserver(
            self,
            forKeyPath: "button.effectiveAppearance.name",
            options: [ .new, .initial ],
            context: nil)
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
    
    // Updates the title of the status bar with the currently playing track
    @objc func updateStatusBarItemTitle(_ notification: NSNotification) {

        // Get track data from notification
        guard let trackTitle = notification.userInfo?["title"] as? String else { return }
        guard let trackArtist = notification.userInfo?["artist"] as? String else { return }
        guard let isPlaying = notification.userInfo?["isPlaying"] as? Bool  else { return }
        let titleAndArtist = trackTitle.isEmpty && trackArtist.isEmpty ? "" : "\(trackTitle) • \(trackArtist)"

        // Get status item button and marquee text view from button
        guard let button = statusBarItem.button else { return }
        guard let barAnimation = button.subviews[0] as? StatusBarAnimation else { return }
        guard let marqueeText = button.subviews[1] as? MenuMarqueeText else { return }
        
        // Playback state has changed
        barAnimation.isPlaying = isPlaying
        
        // Calculate menu bar item dimensions
        let font = Constants.StatusBar.marqueeFont
        let stringWidth = titleAndArtist.stringWidth(with: font)
        let limit = Constants.StatusBar.statusBarButtonLimit
        let animWidth = Constants.StatusBar.barAnimationWidth
        let padding = Constants.StatusBar.statusBarButtonPadding
        
        // Set Marquee text with new track data
        marqueeText.text = titleAndArtist
        
        // Handle empty track info case
        if titleAndArtist.isEmpty {
            marqueeText.text = ""
            button.frame = NSRect(x: 0, y: 0, width: barAnimation.bounds.width + 16, height: button.bounds.height)
            return
        }
        
        // Handle playback state changes
        if isPlaying {
            // Cancel any existing timers
            pauseTimer?.invalidate()
            pauseTimer = nil
            isPaused = false
            
            // Show track info immediately when playback resumes
            marqueeText.text = titleAndArtist
            button.frame = NSRect(
                x: 0,
                y: 0,
                width: stringWidth < limit ? stringWidth + animWidth + 3*padding : limit + animWidth + 3*padding,
                height: button.bounds.height)
            marqueeText.menubarBounds = button.bounds
        } else {
            // Track is paused
            isPaused = true
            
            // Show track info when first paused
            marqueeText.text = titleAndArtist
            button.frame = NSRect(
                x: 0,
                y: 0,
                width: stringWidth < limit ? stringWidth + animWidth + 3*padding : limit + animWidth + 3*padding,
                height: button.bounds.height)
            marqueeText.menubarBounds = button.bounds
            
            // Cancel any existing timer first
            pauseTimer?.invalidate()
            
            // Create new timer to hide track info after 30 seconds
            pauseTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                guard let self = self, self.isPaused else { return }
                
                //Hide text and resize after 30 seconds
                marqueeText.text = ""
                button.frame = NSRect(x: 0, y: 0, width: barAnimation.bounds.width + 16, height: button.bounds.height)
            }
        }
        
        // Make sure to invalidate the timer when app terminates
        func applicationWillTerminate(_ notification: Notification) {
            pauseTimer?.invalidate()
            pauseTimer = nil
        }
    }
    
    // Called when the status bar appearance is changed to update bar animation color and marquee text color
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if (keyPath == "button.effectiveAppearance.name") {
            
            // Get bar animation and marquee from status item button
            guard let barAnimation = statusBarItem.button?.subviews[0] as? StatusBarAnimation else { return }
            guard let marquee = statusBarItem.button?.subviews[1] as? MenuMarqueeText else { return }
            
            let appearance = statusBarItem.button?.effectiveAppearance.name
            
            // Update based on current menu bar appearance
            switch appearance {
            case NSAppearance.Name.vibrantDark:
                barAnimation.menubarIsDarkAppearance = true
                marquee.menubarIsDarkAppearance = true
            default:
                barAnimation.menubarIsDarkAppearance = false
                marquee.menubarIsDarkAppearance = false
            }
            
        }
        
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
            styleMask: [.borderless],
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
