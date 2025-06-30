//
//  UnplugApp.swift
//  Unplug
//
//  Created by Thameem Hassan on 28-6-25.
//

import SwiftUI
import AppKit

@main
struct UnplugApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var headphoneDetector: HeadphoneDetector?
    private var menu: NSMenu?
    private var swiftUIMenuItem: NSMenuItem?
    private var hostingController: NSHostingController<MenuRowView>?
    private var updateTimer: Timer?
    private var menuUpdateTimer: Timer?
    private var isMenuOpen = false
    private var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHeadphoneDetector()
        startUpdateTimer()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: 62)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Unplug")
            button.image?.isTemplate = true
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        menu = NSMenu()
        menu?.delegate = self
        
        // Create SwiftUI menu item
        swiftUIMenuItem = NSMenuItem()
        swiftUIMenuItem?.isEnabled = false // Disable interaction since it's just a display
        menu?.addItem(swiftUIMenuItem!)
        
        // Add separator
        menu?.addItem(NSMenuItem.separator())
        
        // Add reset timer item (hidden by default)
        let resetItem = NSMenuItem(title: "Reset Timer", action: #selector(resetTimer), keyEquivalent: "")
        resetItem.target = self
        resetItem.tag = 3
        resetItem.isHidden = true
        menu?.addItem(resetItem)
        
        // Add separator
        menu?.addItem(NSMenuItem.separator())
        
        // Add settings item
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu?.addItem(settingsItem)
        
        // Add separator
        menu?.addItem(NSMenuItem.separator())
        
        // Add quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu?.addItem(quitItem)
        
        statusItem?.menu = menu
        
        // Setup the SwiftUI view for the first menu item
        setupSwiftUIMenuItem()
    }
    
    private func setupSwiftUIMenuItem() {
        guard let detector = headphoneDetector else { return }
        
        let menuRowView = MenuRowView(headphoneDetector: detector)
        hostingController = NSHostingController(rootView: menuRowView)
        hostingController?.view.frame = NSRect(x: 0, y: 0, width: 250, height: 70)
        
        swiftUIMenuItem?.view = hostingController?.view
    }
    
    private func setupHeadphoneDetector() {
        headphoneDetector = HeadphoneDetector()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(headphoneStatusChanged),
            name: NSNotification.Name("HeadphoneStatusChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(usageTimeChanged),
            name: NSNotification.Name("UsageTimeChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fatigueChanged),
            name: NSNotification.Name("FatigueChanged"),
            object: nil
        )
        
        setupSwiftUIMenuItem()
        updateStatusBarIcon()
        updateMenuItems()
    }
    
    @objc private func headphoneStatusChanged() {
        updateStatusBarIcon()
        updateTooltip()
        updateMenuItems()
    }
    
    @objc private func usageTimeChanged() {
        updateTooltip()
        forceMenuViewUpdate()
    }
    
    @objc private func fatigueChanged() {
        updateStatusBarIcon()
        forceMenuViewUpdate()
        updateMenuItems()
    }
    
    private func updateStatusBarIcon() {
        guard let detector = headphoneDetector else { return }
        
        DispatchQueue.main.async {
            if let button = self.statusItem?.button {
                let customIcon = self.createIconWithProgress(
                    isConnected: detector.headphonesConnected,
                    fatigueLevel: detector.fatigueLevel
                )
                button.image = customIcon
                button.image?.isTemplate = detector.fatigueLevel == 0
            }
        }
    }
    
    private func createIconWithProgress(isConnected: Bool, fatigueLevel: Double) -> NSImage {
        let iconSize = NSSize(width: 60, height: 18)
        let image = NSImage(size: iconSize)
        
        image.lockFocus()
        
        // Get the base system icon
        let baseIconName = isConnected ? "headphones" : "speaker.wave.2"
        if let baseIcon = NSImage(systemSymbolName: baseIconName, accessibilityDescription: "Unplug") {
            let baseIconRect = NSRect(x: 0, y: 3, width: 12, height: 12)
            baseIcon.draw(in: baseIconRect)
        }
        
        // Draw horizontal progress bar to the right of the icon if has fatigue (connected or recovering)
        if fatigueLevel > 0 {
            drawProgressBar(fatigueLevel: fatigueLevel, rect: NSRect(x: 22, y: 4, width: 36, height: 10))
        }
        
        image.unlockFocus()
        return image
    }
    
    private func drawProgressBar(fatigueLevel: Double, rect: NSRect) {
        // Background bar
        NSColor.systemGray.withAlphaComponent(0.3).setFill()
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        backgroundPath.fill()
        
        // Progress fill
        let progressWidth = rect.width * fatigueLevel
        let progressRect = NSRect(x: rect.origin.x, y: rect.origin.y, width: progressWidth, height: rect.height)
        
        // Color based on fatigue level
        let progressColor: NSColor
        switch fatigueLevel {
        case 0.0..<0.5:
            progressColor = NSColor.systemGreen
        case 0.5..<0.8:
            progressColor = NSColor.systemYellow
        default:
            progressColor = NSColor.systemRed
        }
        
        progressColor.setFill()
        let progressPath = NSBezierPath(roundedRect: progressRect, xRadius: 3, yRadius: 3)
        progressPath.fill()
    }
    
    private func updateTooltip() {
        guard let detector = headphoneDetector else { return }
        
        DispatchQueue.main.async {
            if let button = self.statusItem?.button {
                if detector.headphonesConnected {
                    let formattedTime = self.formatDuration(detector.usageDuration)
                    button.toolTip = "Headphones connected - Usage: \(formattedTime)"
                } else {
                    button.toolTip = "No headphones connected"
                }
            }
        }
    }
    
    private func updateMenuItems() {
        guard let detector = headphoneDetector else { return }
        
        DispatchQueue.main.async {
            // Update the height of the SwiftUI menu item based on headphone status and fatigue
            let newHeight: CGFloat
            if detector.headphonesConnected {
                newHeight = 70 // Connected with usage time and fatigue bar
            } else if detector.fatigueLevel > 0 {
                newHeight = 50 // Disconnected but showing recovery
            } else {
                newHeight = 28 // Just status text
            }
            
            self.hostingController?.view.frame = NSRect(x: 0, y: 0, width: 250, height: newHeight)
            
            // Show/hide reset timer menu item
            if let resetItem = self.menu?.item(withTag: 3) {
                resetItem.isHidden = !detector.headphonesConnected
            }
        }
    }
    
    private func forceMenuViewUpdate() {
        guard let detector = headphoneDetector else { return }
        
        DispatchQueue.main.async {
            // Recreate the SwiftUI view to force updates
            let menuRowView = MenuRowView(headphoneDetector: detector)
            self.hostingController?.rootView = menuRowView
            
            // Update frame size based on current state
            let newHeight: CGFloat
            if detector.headphonesConnected {
                newHeight = 70 // Connected with usage time and fatigue bar
            } else if detector.fatigueLevel > 0 {
                newHeight = 50 // Disconnected but showing recovery
            } else {
                newHeight = 28 // Just status text
            }
            
            self.hostingController?.view.frame = NSRect(x: 0, y: 0, width: 250, height: newHeight)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    @objc private func resetTimer() {
        headphoneDetector?.resetUsageTracking()
    }
    
    @objc private func openSettings() {
        // Close existing window if it exists
        settingsWindow?.close()
        
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        settingsWindow?.title = "Unplug Settings"
        settingsWindow?.contentViewController = hostingController
        settingsWindow?.center()
        settingsWindow?.setFrameAutosaveName("Settings")
        settingsWindow?.isReleasedWhenClosed = false
        
        // Set up window delegate to handle close events
        settingsWindow?.delegate = self
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        updateTimer?.invalidate()
        menuUpdateTimer?.invalidate()
        settingsWindow?.close()
        NSApplication.shared.terminate(nil)
    }
    
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateTooltip()
        }
    }
    
    private func startMenuUpdateTimer() {
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if self.isMenuOpen {
                self.updateTooltip()
                self.updateMenuItems()
                self.forceMenuViewUpdate()
            }
        }
    }
    
    private func stopMenuUpdateTimer() {
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = nil
    }
    
    // MARK: - NSMenuDelegate
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        updateMenuItems()
        updateTooltip()
        startMenuUpdateTimer()
    }
    
    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        stopMenuUpdateTimer()
    }
    
    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindow {
            settingsWindow = nil
        }
    }
}
