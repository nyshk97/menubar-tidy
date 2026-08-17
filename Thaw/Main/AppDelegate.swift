//
//  AppDelegate.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import LaunchAtLogin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The shared app state.
    let appState = AppState()
    private var isPreparingForTermination = false
    private var hasRepliedToTerminationRequest = false
    private var terminationAttemptID = UUID()
    private var terminationTimeoutTask: Task<Void, Never>?

    #if DEBUG
        /// Whether the app is running as an Xcode preview/playground.
        ///
        /// Xcode sets one of these environment variables depending on the
        /// Tools version and execution mode (newer versions report
        /// `XCODE_RUNNING_FOR_PLAYGROUNDS` for SwiftUI previews). Checking
        /// both keeps the guard working across versions.
        private var isRunningForPreviews: Bool {
            let environment = ProcessInfo.processInfo.environment
            return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
        }
    #endif

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_: Notification) {
        #if DEBUG
            // Don't perform setup if running as a preview.
            if isRunningForPreviews {
                return
            }
        #endif

        // Bound accessibility messaging before anything can create an element.
        // Every AX call is synchronous IPC tied to the target's event loop, so an
        // app that stops pumping it blocks us for the system default of six
        // seconds — the delay behind #767. Healthy calls return in well under
        // 100 ms, so a one second ceiling costs nothing and lets the fallback
        // paths run while the user is still watching. Override with:
        //   defaults write com.nyshk97.Thaw axMessagingTimeout -float <seconds>
        UIElement.defaultMessagingTimeout = Float(
            max(0, (Defaults.object(forKey: .axMessagingTimeout) as? Double) ?? Defaults.DefaultValue.axMessagingTimeout)
        )

        // A direct launch (for example from Xcode) can bypass the usual
        // single-instance behavior. Two live Thaw instances each register
        // control items and then fight to restore their own saved layouts.
        // Let the newly launched instance win so restart and update flows
        // remain reliable.
        terminateOtherInstances()

        // Initial chore work.
        NSSplitViewItem.swizzle()
        MigrationManager().migrateAll()

    }

    func applicationDidFinishLaunching(_: Notification) {
        // Hide the main menu's items to add additional space to the
        // menu bar when we are the focused app.
        for item in NSApp.mainMenu?.items ?? [] {
            item.isHidden = true
        }

        // Allow hiding the mouse while the app is in the background
        // to make menu bar item movement less jarring.
        Bridging.setConnectionProperty(true, forKey: "SetsCursorInBackground")

        #if DEBUG
            // Don't perform setup if running as a preview.
            if isRunningForPreviews {
                return
            }
        #endif

        registerForLaunchAtLogin()

        // Warn if another menu bar manager is running.
        ConflictingAppDetector.showWarningIfNeeded()

        // Check if this is the first launch
        let isFirstLaunch = !Defaults.bool(forKey: .hasCompletedFirstLaunch)

        // Depending on the permissions state, either perform setup
        // or prompt to grant permissions.
        switch appState.permissions.permissionsState {
        case .hasAll:
            appState.permissions.diagLog.debug("Passed all permissions checks")
            appState.performSetup(hasPermissions: true)
        case .missing:
            appState.permissions.diagLog.debug("Failed permissions checks")
            appState.performSetup(hasPermissions: false)
        }

        // Surface the permissions window on first launch, and afterwards only
        // when required permissions are missing (e.g. they were revoked).
        // Upstream fronted this with a feature tour on first launch; this fork
        // dropped it, so both occasions show the permissions screen directly.
        if isFirstLaunch || appState.permissions.permissionsState == .missing {
            appState.openWindow(.permissions)
        }
    }

    /// Registers the app to start at login.
    ///
    /// Upstream exposed this as a toggle in the General settings pane; that
    /// pane was cut down to the layout editor, taking the toggle with it and
    /// leaving the app unable to register itself at all. A menu bar manager
    /// that has to be launched by hand after every restart is not much of a
    /// menu bar manager, so registration is unconditional here.
    ///
    /// - Important: This re-registers on every launch, so removing the app
    ///   from System Settings' login items does not stick. There is no UI to
    ///   turn it off — stop launching the app, or delete this call.
    ///
    /// `SMAppService` registers whatever bundle is running, so a debug build
    /// registers its path inside `Build/`. Wiping that directory leaves a
    /// login item pointing at nothing; re-register by launching a fresh build.
    private func registerForLaunchAtLogin() {
        guard !LaunchAtLogin.isEnabled else { return }
        LaunchAtLogin.isEnabled = true
        appState.diagLog.debug("Registered for launch at login")
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        appState.diagLog.debug("Handling reopen from app icon click")
        openSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if sender.isActive, sender.activationPolicy() != .accessory, appState.navigationState.isAppFrontmost {
            appState.diagLog.debug("All windows closed - deactivating with accessory activation policy")
            appState.deactivate(withPolicy: .accessory)
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isPreparingForTermination else {
            return .terminateLater
        }

        let attemptID = UUID()
        terminationAttemptID = attemptID
        terminationTimeoutTask?.cancel()
        isPreparingForTermination = true
        hasRepliedToTerminationRequest = false
        appState.diagLog.info("Application asked to terminate - restoring blocked items asynchronously")

        Task { @MainActor in
            _ = await appState.itemManager.restoreBlockedItemsToVisible()
            guard terminationAttemptID == attemptID else {
                return
            }
            terminationTimeoutTask?.cancel()
            replyToTerminationRequest(sender, timedOut: false)
        }

        terminationTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard terminationAttemptID == attemptID else {
                return
            }
            replyToTerminationRequest(sender, timedOut: true)
        }

        return .terminateLater
    }

    func applicationWillTerminate(_: Notification) {
        appState.diagLog.info("Application will terminate")
    }

    // MARK: Other Methods

    /// Asks any other live copy of this bundle to terminate, escalating after
    /// a short grace period if it does not respond. XCTest hosts are exempt so
    /// parallel test processes never terminate one another.
    private func terminateOtherInstances() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier

        for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            where other.processIdentifier != currentPID
        {
            appState.diagLog.warning(
                "Another instance is already running (PID \(other.processIdentifier)); terminating it"
            )
            if !other.terminate() {
                other.forceTerminate()
                continue
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if !other.isTerminated {
                    self.appState.diagLog.warning(
                        "Other instance (PID \(other.processIdentifier)) did not terminate; force-terminating"
                    )
                    other.forceTerminate()
                }
            }
        }
    }

    /// Answers a deferred `applicationShouldTerminate`, once.
    ///
    /// Both the restore task and its timeout race to call this, and whichever
    /// arrives second must not reply again — `reply(toApplicationShouldTerminate:)`
    /// is not idempotent.
    private func replyToTerminationRequest(
        _ sender: NSApplication,
        timedOut: Bool
    ) {
        guard !hasRepliedToTerminationRequest else {
            return
        }

        hasRepliedToTerminationRequest = true
        isPreparingForTermination = false
        terminationTimeoutTask?.cancel()
        terminationTimeoutTask = nil

        if timedOut {
            appState.diagLog.warning("Blocked item restore operation timed out during app termination")
        } else {
            appState.diagLog.info("Blocked item restore operation completed during app termination")
        }

        sender.reply(toApplicationShouldTerminate: true)
    }

    /// Opens the settings window and activates the app.
    @objc func openSettingsWindow() {
        // Always allow opening settings window from menu item clicks
        // This ensures clicking app icon, dock icon or menu bar item works correctly
        appState.diagLog.debug("Opening settings window from app icon/dock/menu click")

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }
}
