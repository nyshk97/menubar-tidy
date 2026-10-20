//
//  AppDelegate.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import AppKit
import LaunchAtLogin

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The status item's save name. Kept from 1.x, where this was the
    /// "visible" control item, so AppKit restores the icon to the position the
    /// user dragged it to (`NSStatusItem Preferred Position <name>` in defaults).
    private static let statusItemAutosaveName = "Thaw.ControlItem.Visible"

    private let scanner = ItemScanner()
    private let updates = UpdatesManager()
    private var statusItem: NSStatusItem?
    private var menuController: StatusMenuController?

    /// Whether this process is hosting the unit tests. The tests only need the
    /// module loaded; a status item, a permission prompt and a login-item change
    /// on every test run would land on the developer's real menu bar.
    private static let isHostingTests = NSClassFromString("XCTestCase") != nil

    func applicationDidFinishLaunching(_: Notification) {
        guard !Self.isHostingTests else {
            return
        }
        terminateOtherInstances()
        registerForLaunchAtLogin()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.statusItemAutosaveName
        statusItem.button?.image = Self.makeStatusIcon()
        statusItem.button?.toolTip = Constants.displayName
        self.statusItem = statusItem
        menuController = StatusMenuController(statusItem: statusItem, scanner: scanner, updates: updates)

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }
        scanner.start()
        updates.startUpdaterIfNeeded()
        Log.app.info("Launched \(Constants.versionString, privacy: .public) (\(Constants.gitCommitSHA ?? "-", privacy: .public))")
    }

    /// The menu bar glyph, scaled to fit 25×17pt like 1.x drew it.
    private static func makeStatusIcon() -> NSImage? {
        guard let original = NSImage(named: "TidyBarFill") else {
            return nil
        }
        let ratio = max(original.size.width / 25, original.size.height / 17)
        let size = NSSize(width: original.size.width / ratio, height: original.size.height / ratio)
        let image = NSImage(size: size, flipped: false) { rect in
            original.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Registers the app to start at login. There is no setting for it: a menu
    /// bar helper that has to be launched by hand after every restart is not much
    /// of one. Removing the app from System Settings' login items does not stick,
    /// since this re-registers on every launch.
    ///
    /// The dev build is excluded. `SMAppService` registers whatever bundle is
    /// running, so a dev build would register its path inside `Build/` and come
    /// back at every login next to the release install. A dev build that finds
    /// itself registered (from an older build) unregisters.
    private func registerForLaunchAtLogin() {
        if AppIdentity.isDevBuild {
            if LaunchAtLogin.isEnabled {
                LaunchAtLogin.isEnabled = false
                Log.app.info("Dev build: removed stale launch-at-login registration")
            }
            return
        }
        if !LaunchAtLogin.isEnabled {
            LaunchAtLogin.isEnabled = true
        }
    }

    /// Asks any other live copy of this bundle to quit, so a direct launch (from
    /// Xcode or `open`) does not leave two icons in the menu bar.
    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return
        }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            where other.processIdentifier != currentPID
        {
            Log.app.info("Another instance is running (PID \(other.processIdentifier)); terminating it")
            if !other.terminate() {
                other.forceTerminate()
            }
        }
    }
}
