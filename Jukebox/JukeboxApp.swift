//
//  JukeboxApp.swift
//  Jukebox
//
//  Created by Sasindu Jayasinghe on 13/10/21.
//

import SwiftUI
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    
    @AppStorage("viewedOnboarding") var viewedOnboarding: Bool = false
    @StateObject var contentViewVM = ContentViewModel()
    private var statusBarItem: NSStatusItem!
    private var statusBarMenu: NSMenu!
    private var popover: NSPopover!
    private var preferencesWindow: PreferencesWindow!
    private var onboardingWindow: OnboardingWindow!
    
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
        
    }
    
    // MARK: - Setup
    
    private func setupContentView() {
        let frameSize = NSSize(width: 272, height: 350)
        
        // Initialize ContentView
        let hostedContentView = NSHostingView(rootView: ContentView(contentViewVM: contentViewVM))
        hostedContentView.frame = NSRect(x: 0, y: 0, width: frameSize.width, height: frameSize.height)
        
        // Initialize Popover
        popover = NSPopover()
        popover.contentSize = frameSize
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = hostedContentView
        popover.contentViewController?.view.window?.makeKey()
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
        let updates = NSMenuItem(
            title: "Check for updates...",
            action: #selector(SUUpdater.checkForUpdates(_:)),
            keyEquivalent: "")
        updates.target = SUUpdater.shared()
        statusBarMenu.addItem(updates)
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
            togglePopover(statusBarItem.button)
        }
        
    }
    
    // Set menu to nil when closed so popover is re-enabled
    func menuDidClose(_: NSMenu) {
        statusBarItem.menu = nil
    }
    
    // Toggle open and close of popover
    @objc func togglePopover(_ sender: NSStatusBarButton?) {
        
        guard let statusBarItemButton = sender else { return }
        
        if popover.isShown {
            popover.performClose(statusBarItemButton)
        } else {
            popover.show(relativeTo: statusBarItemButton.bounds, of: statusBarItemButton, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        
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
        
        // Calculate string width
        let font = Constants.StatusBar.marqueeFont
        let stringWidth = titleAndArtist.stringWidth(with: font)
        
        // Set Marquee text with new track data
        marqueeText.text = titleAndArtist
        
        // Hide the track data when paused
        if !isPlaying {
            marqueeText.text = ""
            button.frame = NSRect(x: 0, y: 0, width: barAnimation.bounds.width + 16, height: button.bounds.height)
            barAnimation.isPlaying = false
            return
        }
        
        let limit = Constants.StatusBar.statusBarButtonLimit
        let animWidth = Constants.StatusBar.barAnimationWidth
        let padding = Constants.StatusBar.statusBarButtonPadding
        
        if titleAndArtist.isEmpty {
            barAnimation.isPlaying = false
            button.frame = NSRect(x: 0, y: 0, width: barAnimation.bounds.width + 16, height: button.bounds.height)
            return
        }
        
        // Set button frame
        button.frame = NSRect(
            x: 0,
            y: 0,
            width: stringWidth < limit ? stringWidth + animWidth + 3*padding : limit + animWidth + 3*padding,
            height: button.bounds.height)
        barAnimation.isPlaying = isPlaying
        marqueeText.menubarBounds = button.bounds

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
