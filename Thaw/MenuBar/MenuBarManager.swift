//
//  MenuBarManager.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Observation
import SwiftUI

/// Manager for the state of the menu bar.
@MainActor
@Observable
final class MenuBarManager {
    /// Information for the menu bar's average color on the active screen.
    private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// Per-screen average colors, so the Thaw Bar matches the menu bar on
    /// whichever display it is shown.
    private(set) var averageColors: [CGDirectDisplayID: MenuBarAverageColorInfo] = [:]

    /// A Boolean value that indicates whether the menu bar is either always hidden
    /// by the system, or automatically hidden and shown by the system based on the
    /// location of the mouse.
    private(set) var isMenuBarHiddenBySystem = false

    /// A Boolean value that indicates whether the menu bar is hidden by the system
    /// according to a value stored in UserDefaults.
    private(set) var isMenuBarHiddenBySystemUserDefaults = false

    /// Timestamp of the last time a section was shown.
    private(set) var lastShowTimestamp: ContinuousClock.Instant?

    /// Reference to the settings window.
    private var settingsWindow: NSWindow?

    /// Diagnostic logger for the menu bar manager.
    @ObservationIgnored
    private let diagLog = DiagLog(category: "MenuBarManager")

    /// The shared app state.
    @ObservationIgnored
    private weak var appState: AppState?

    /// Storage for internal observers.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// Task observing `DisplaySettingsManager.configurations`, which is
    /// `@Observable` rather than a Combine `ObservableObject`.
    private var displayConfigurationsObservationTask: Task<Void, Never>?

    /// Task observing `settingsWindow`'s `isVisible` KVO stream (wave 3),
    /// replacing the old `$settingsWindow.removeNil().map { $0.publisher(for:
    /// \.isVisible) }.switchToLatest()` pipeline. `settingsWindow` is now a
    /// plain `@Observable` property rather than a Combine `@Published` one,
    /// so it no longer has a `$settingsWindow` publisher; the inner KVO
    /// publisher on the resolved `NSWindow` is unrelated to Observation and
    /// stays Combine, manually re-subscribed on each new non-nil window
    /// value (mirroring `switchToLatest`'s behavior).
    private var settingsWindowObservationTask: Task<Void, Never>?

    @MainActor
    deinit {
        displayConfigurationsObservationTask?.cancel()
        settingsWindowObservationTask?.cancel()
        settingsWindowVisibilityCancellable?.cancel()
    }

    /// Cancellable for the periodic average-color refresh, active only while settings is visible.
    private var averageColorRefreshCancellable: AnyCancellable?

    /// Cancellable for `settingsWindow`'s `isVisible` KVO stream, resubscribed
    /// on each new non-nil `settingsWindow` value by `settingsWindowObservationTask`.
    @ObservationIgnored
    private var settingsWindowVisibilityCancellable: AnyCancellable?

    /// A Boolean value that indicates whether the application menus are hidden.
    private var isHidingApplicationMenus = false

    /// A Boolean value that indicates whether the application menus were hidden
    /// by a manual toggle (a `thaw://` URL), rather than automatically by section state.
    private var isManuallyHidingApplicationMenus = false

    /// The panel that contains the Thaw Bar interface.
    let iceBarPanel = IceBarPanel()

    /// The managed sections in the menu bar.
    let sections = [
        MenuBarSection(name: .visible),
        MenuBarSection(name: .hidden),
        MenuBarSection(name: .alwaysHidden),
    ]

    /// A Boolean value that indicates whether at least one of the manager's
    /// sections is visible.
    var hasVisibleSection: Bool {
        sections.contains { !$0.isHidden }
    }

    /// Performs the initial setup of the menu bar manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        iceBarPanel.performSetup(with: appState)
        for section in sections {
            section.performSetup(with: appState)
        }
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        averageColorRefreshCancellable?.cancel()
        averageColorRefreshCancellable = nil
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.currentSystemPresentationOptions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] options in
                guard let self else {
                    return
                }
                let hidden = options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
                isMenuBarHiddenBySystem = hidden
            }
            .store(in: &c)

        if
            let hiddenSection = section(withName: .alwaysHidden),
            let window = hiddenSection.controlItem.window
        {
            window.publisher(for: \.frame)
                .map(\.origin.y)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard
                        let self,
                        let isMenuBarHidden = Defaults.globalDomain["_HIHideMenuBar"] as? Bool
                    else {
                        return
                    }
                    isMenuBarHiddenBySystemUserDefaults = isMenuBarHidden
                }
                .store(in: &c)
        }

        // Handle the `focusedApp` and `smart` rehide strategies.
        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didActivateApplicationNotification
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] notification in
            let activatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            guard
                let self,
                let appState,
                appState.settings.general.autoRehide,
                Self.shouldHandleAutoRehideActivation(
                    activatedProcessIdentifier: activatedApplication?.processIdentifier,
                    currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
                )
            else {
                if self?.appState?.settings.general.autoRehide == false {
                    // Auto-rehide is off; no strategy fires. Not an error,
                    // but the user may expect focus/timed to work without
                    // the master toggle.
                }
                return
            }

            let strategy = appState.settings.general.rehideStrategy
            switch strategy {
            case .focusedApp, .smart:
                guard
                    let screen = appState.hidEventManager.bestScreen(appState: appState),
                    !appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen),
                    !appState.hidEventManager.isMouseInsideIceBar(appState: appState)
                else {
                    return
                }
                Task { [weak self] in
                    // Wait for focus to settle and carry an activation
                    // inside the reveal grace period to its end instead
                    // of dropping that activation permanently.
                    let delay = Self.rehideDelay(for: strategy, since: self?.lastShowTimestamp)
                    guard await (try? Task.sleep(for: delay)) != nil else { return }

                    guard let self else { return }
                    guard appState.settings.general.rehideStrategy == strategy else { return }
                    if strategy == .smart, await appState.itemManager.isAnyMenuBarItemMenuOpen() {
                        return
                    }

                    self.hideVisibleSections()
                }
            default:
                break
            }
        }
        .store(in: &c)

        appState?.publisherForWindow(.settings)
            .sink { [weak self] window in
                self?.settingsWindow = window
            }
            .store(in: &c)

        if let appState {
            let displaySettings = appState.settings.displaySettings
            displayConfigurationsObservationTask = Task { [weak self] in
                let changes = Observations { displaySettings.configurations }
                for await _ in changes {
                    guard let self else { return }
                    updateControlItemStates()
                }
            }
        }

        settingsWindowObservationTask = Task { [weak self] in
            let changes = Observations { self?.settingsWindow }
            for await window in changes {
                guard let self else { return }
                guard let window else { continue }
                settingsWindowVisibilityCancellable = window.publisher(for: \.isVisible)
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] isVisible in
                        guard let self else { return }
                        if isVisible {
                            updateAverageColorInfo()
                            // Start a visibility-gated 60s refresh to catch wallpaper changes
                            // (macOS no longer posts a wallpaper change notification).
                            averageColorRefreshCancellable = Timer.publish(every: 60, tolerance: 10, on: .main, in: .default)
                                .autoconnect()
                                .sink { [weak self] _ in
                                    self?.updateAverageColorInfo()
                                }
                        } else {
                            averageColorRefreshCancellable?.cancel()
                            averageColorRefreshCancellable = nil
                        }
                    }
            }
        }

        // Refresh average color when space or screen changes while settings is visible.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                .replace(with: ()),
            NotificationCenter.default
                .publisher(for: NSApplication.didChangeScreenParametersNotification)
                .replace(with: ())
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else { return }
            guard settingsWindow?.isVisible == true else { return }
            updateAverageColorInfo()
        }
        .store(in: &c)

        // Hide application menus when a section is shown (if applicable).
        Publishers.MergeMany(sections.map(\.controlItem.$state))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let appState else {
                    return
                }

                // Don't continue if:
                //   * The "HideApplicationMenus" setting isn't enabled.
                //   * Using the Thaw Bar.
                //   * The menu bar is hidden by the system.
                //   * The active space is fullscreen.
                //   * The settings window is visible.
                guard
                    appState.settings.advanced.hideApplicationMenus,
                    !appState.settings.displaySettings.configurationForActiveDisplay().useIceBar,
                    !isMenuBarHiddenBySystem,
                    !appState.activeSpace.isFullscreen,
                    !appState.navigationState.isSettingsPresented
                else {
                    return
                }

                // Check if hidden or alwaysHidden section is being shown
                let hiddenSection = self.section(withName: .hidden)
                let alwaysHiddenSection = self.section(withName: .alwaysHidden)

                // Use isHidden property - when section is shown, isHidden is false.
                // A section presenting in the Thaw Bar expands nothing inline,
                // so the application menus have no items to make room for. The
                // guard above already covers the display-wide setting; this
                // covers useThawBarForAlwaysHidden, where the always-hidden
                // section is in the panel while the hidden section is inline.
                let panelSection = iceBarPanel.currentSection
                let isShowingHiddenSection = (hiddenSection.map { !$0.isHidden } ?? false)
                    && panelSection != .hidden
                let isShowingAlwaysHiddenSection = (alwaysHiddenSection.map { !$0.isHidden } ?? false)
                    && panelSection != .alwaysHidden

                if isShowingHiddenSection || isShowingAlwaysHiddenSection {
                    // Use the screen with the active menu bar
                    guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
                        return
                    }

                    Task {
                        // The window server needs time to update window positions after expansion.
                        try? await Task.sleep(for: .milliseconds(50))

                        // Get the app menu frame for this screen
                        guard let appMenuFrame = screen.getApplicationMenuFrame() else {
                            return
                        }

                        // Get ALL menu bar items
                        let allItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)

                        // Filter to items on THIS screen by comparing Y coordinate with app menu's Y
                        let menuBarY = appMenuFrame.origin.y
                        let screenItems = allItems.filter { item in
                            abs(item.bounds.origin.y - menuBarY) < 50
                        }

                        // Get the control items for this screen
                        let hiddenControlItem = screenItems.first { $0.tag == .hiddenControlItem }
                        let alwaysHiddenControlItem = screenItems.first { $0.tag == .alwaysHiddenControlItem }

                        // Approximate hidden items width from control item positions.

                        // Get control item bounds and hidden items width
                        var controlBounds: CGRect = .zero
                        var hiddenItemsWidth: CGFloat = 0

                        if isShowingAlwaysHiddenSection, let ahControl = alwaysHiddenControlItem {
                            controlBounds = ahControl.bounds
                            if let appState = self.appState {
                                hiddenItemsWidth = appState.itemManager.itemCache[.alwaysHidden].reduce(0) { $0 + $1.bounds.width }
                            }
                        } else if isShowingHiddenSection, let hControl = hiddenControlItem {
                            controlBounds = hControl.bounds
                            if let appState = self.appState {
                                hiddenItemsWidth = appState.itemManager.itemCache[.hidden].reduce(0) { $0 + $1.bounds.width }
                            }
                        }

                        // The hidden section expands by replacing control item with hidden items
                        // New rightmost = where hidden items end = control.minX + hiddenItemsWidth
                        let newRightmostPos = controlBounds.minX + hiddenItemsWidth

                        // Use the actual app menu frame for needed space
                        let appMenuRightStart = appMenuFrame.maxX

                        // Available space: if app menu extends into notch, add notch width; otherwise use visible frame
                        let spaceAvailableFromAppMenuEnd: CGFloat = if let notch = screen.frameOfNotch {
                            if appMenuRightStart > notch.minX {
                                // App menu extends into notch, items get moved past notch
                                (notch.minX - appMenuRightStart) + (screen.visibleFrame.maxX - notch.maxX)
                            } else {
                                // App menu doesn't extend into notch
                                screen.visibleFrame.maxX - appMenuRightStart
                            }
                        } else {
                            screen.visibleFrame.maxX - appMenuRightStart
                        }

                        let spaceNeededFromAppMenuEnd = newRightmostPos - appMenuRightStart

                        // If items would extend past screen edge, hide the app menu
                        if spaceNeededFromAppMenuEnd > spaceAvailableFromAppMenuEnd {
                            self.hideApplicationMenus()
                        }
                    }
                } else if isHidingApplicationMenus, !isManuallyHidingApplicationMenus {
                    showApplicationMenus()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Updates the ``averageColorInfo`` and ``averageColors`` properties with
    /// the current average color of the menu bar background per screen.
    ///
    /// Fire-and-forget shape preserved for the call sites that don't need to
    /// read averageColors immediately after. Callers that DO need read-after
    /// semantics must use updateAverageColorInfoAsync directly so their read
    /// sees fresh state.
    func updateAverageColorInfo() {
        Task { [weak self] in
            await self?.updateAverageColorInfoAsync()
        }
    }

    /// Awaitable variant of updateAverageColorInfo. Per-screen captures run
    /// concurrently in a TaskGroup; the for-await loop collects results on the
    /// @MainActor context, so all averageColors / averageColorInfo writes are
    /// complete before the await returns.
    func updateAverageColorInfoAsync() async {
        guard let appState else { return }

        // Only update if we really need the color info
        let isSettingsVisible = settingsWindow?.isVisible == true
        let isIceBarVisible = appState.navigationState.isIceBarPresented
        let anyIceBarEnabled = appState.settings.displaySettings.isIceBarEnabledOnAnyDisplay

        guard isSettingsVisible || isIceBarVisible || anyIceBarEnabled else {
            return
        }

        let targetScreens: [NSScreen]
        if isSettingsVisible {
            targetScreens = [settingsWindow?.screen].compactMap(\.self)
        } else {
            guard let screen = NSScreen.screenWithActiveMenuBar else { return }
            targetScreens = [screen]
        }

        guard !targetScreens.isEmpty else { return }

        let windows = WindowInfo.createWindows(option: .onScreen)
        let activeDisplayID = NSScreen.screenWithActiveMenuBar?.displayID

        // Resolve per-screen capture inputs synchronously on MainActor before
        // fanning out; the SCK calls themselves are the only async work.
        var inputs = [(displayID: CGDirectDisplayID, windowIDs: [CGWindowID], bounds: CGRect)]()
        for screen in targetScreens {
            let displayID = screen.displayID
            guard
                let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
                let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
            else {
                continue
            }
            let windowIDs = [menuBarWindow.windowID, wallpaperWindow.windowID]
            let bounds = withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 }
            inputs.append((displayID, windowIDs, bounds))
        }

        await withTaskGroup(of: (CGDirectDisplayID, MenuBarAverageColorInfo)?.self) { group in
            for input in inputs {
                group.addTask {
                    guard
                        let image = await ScreenCapture.captureWindowsAsync(
                            with: input.windowIDs,
                            screenBounds: input.bounds,
                            option: .nominalResolution
                        ),
                        let color = image.averageColor(option: .ignoreAlpha)
                    else {
                        return nil
                    }
                    return (input.displayID, MenuBarAverageColorInfo(color: color, source: .menuBarWindow))
                }
            }

            // Collected on @MainActor (enclosing class isolation), so the
            // averageColors / averageColorInfo writes below are safe and
            // observable to read-after callers as soon as this await returns.
            for await result in group {
                guard let (displayID, info) = result else { continue }
                if averageColors[displayID] != info {
                    averageColors[displayID] = info
                }
                if displayID == activeDisplayID, averageColorInfo != info {
                    averageColorInfo = info
                }
            }
        }
    }

    /// Returns a Boolean value that indicates whether the given display
    /// has a valid menu bar.
    func hasValidMenuBar(in windows: [WindowInfo], for display: CGDirectDisplayID) -> Bool {
        guard
            let window = WindowInfo.menuBarWindow(from: windows, for: display),
            let element = AXHelpers.element(at: window.bounds.origin)
        else {
            return false
        }
        return AXHelpers.role(for: element) == .menuBar
    }

    /// Shows the secondary context menu.
    func showSecondaryContextMenu(at point: CGPoint) {
        let menu = NSMenu(title: "\(Constants.displayName)")

        let editLayoutItem = NSMenuItem(
            title: "メニューバーのレイアウトを編集…",
            action: #selector(showMenuBarLayoutSettings),
            keyEquivalent: ""
        )
        editLayoutItem.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Edit Layout")
        editLayoutItem.target = self
        menu.addItem(editLayoutItem)

        // Profiles submenu.
        if let appState, !appState.profileManager.profiles.isEmpty {
            menu.addItem(.separator())

            let profilesItem = NSMenuItem(
                title: "プロファイル",
                action: nil,
                keyEquivalent: ""
            )
            profilesItem.image = NSImage(
                systemSymbolName: "person.crop.rectangle.stack",
                accessibilityDescription: "Profiles"
            )
            let profilesMenu = NSMenu()
            for meta in appState.profileManager.profiles {
                let item = NSMenuItem(
                    title: meta.name,
                    action: #selector(applyProfileFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = meta.id
                if meta.id == appState.profileManager.activeProfileID {
                    item.state = .on
                }
                profilesMenu.addItem(item)
            }
            profilesItem.submenu = profilesMenu
            menu.addItem(profilesItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "\(Constants.displayName) 設定…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)

        if appState?.settings.advanced.enableSecondaryContextMenuQuit == true {
            menu.addItem(.separator())

            let quitItem = NSMenuItem(
                title: "\(Constants.displayName) を終了",
                action: #selector(quitFromSecondaryContextMenu),
                keyEquivalent: "q"
            )
            quitItem.keyEquivalentModifierMask = .command
            quitItem.target = self
            quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
            menu.addItem(quitItem)

            let restartItem = NSMenuItem(
                title: "\(Constants.displayName) を再起動",
                action: #selector(restartFromSecondaryContextMenu),
                keyEquivalent: "q"
            )
            restartItem.keyEquivalentModifierMask = [.command, .option]
            restartItem.isAlternate = true
            restartItem.target = self
            restartItem.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Restart")
            menu.addItem(restartItem)
        }

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func quitFromSecondaryContextMenu() {
        // Defer NSApp.terminate until the main run loop is back in default mode.
        // The action fires inside popUp's eventTracking-mode nested run loop, and
        // popUp itself was invoked from a Task that is occupying the main actor.
        // Scheduling in .default only ensures the block runs after popUp tracking
        // unwinds and the enclosing Task completes, so terminate's wait loop can
        // drain the restore and timeout Tasks scheduled by applicationShouldTerminate.
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func restartFromSecondaryContextMenu() {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                self?.appState?.restartSelf()
            }
        }
    }

    @objc private func applyProfileFromMenu(_ menuItem: NSMenuItem) {
        guard
            let profileID = menuItem.representedObject as? UUID,
            let appState,
            appState.profileManager.layoutTask == nil,
            profileID != appState.profileManager.activeProfileID
        else { return }
        Task { [weak self] in
            do {
                let profile = try appState.profileManager.loadProfile(id: profileID)
                let previousID = appState.profileManager.activeProfileID
                appState.profileManager.activeProfileID = profileID
                appState.profileManager.applyProfile(profile, to: appState, previousProfileID: previousID)
            } catch {
                self?.diagLog.error("Failed to apply profile \(profileID): \(error)")
            }
        }
    }

    /// Hides the application menus.
    ///
    /// - Important: Uses `.regular` activation policy to hide menus, which briefly shows the app in the Dock.
    func hideApplicationMenus(manual: Bool = false) {
        guard let appState else {
            diagLog.error("Error hiding application menus: Missing app state")
            return
        }

        if isHidingApplicationMenus {
            return
        }

        diagLog.info("Hiding application menus")
        isHidingApplicationMenus = true
        if manual {
            isManuallyHidingApplicationMenus = true
        }

        // Ensure this happens on the main thread
        Task { @MainActor in
            guard isHidingApplicationMenus else { return }

            appState.activate(withPolicy: .regular)

            // Force activation again after a micro-delay.
            // The first activation after policy change can sometimes be ignored by the system.
            try? await Task.sleep(for: .milliseconds(25))
            guard isHidingApplicationMenus else { return }
            appState.activate()
        }
    }

    /// Shows the application menus.
    func showApplicationMenus() {
        guard let appState else {
            diagLog.error("Error showing application menus: Missing app state")
            return
        }
        diagLog.info("Showing application menus")
        appState.deactivate(withPolicy: .accessory)
        isHidingApplicationMenus = false
        isManuallyHidingApplicationMenus = false
    }

    /// Toggles the visibility of the application menus.
    func toggleApplicationMenus() {
        if isHidingApplicationMenus {
            showApplicationMenus()
        } else {
            hideApplicationMenus(manual: true)
        }
    }

    /// Shows the menu bar layout settings pane.
    ///
    /// Upstream selects the pane first, since the settings window opens on
    /// whichever one was last shown. Here it is the only pane.
    @objc private func showMenuBarLayoutSettings() {
        guard let appState else {
            return
        }
        appState.activate(withPolicy: .regular)
        appState.openWindow(.settings)
    }

    /// Updates the ``lastShowTimestamp`` property.
    func updateLastShowTimestamp() {
        lastShowTimestamp = .now
    }

    /// Delay for a focus-change rehide. A focus change during the reveal
    /// grace period is deferred to the end of that period rather than lost.
    /// Smart waits longer for focus to settle than focusedApp because it
    /// re-checks state (open menus) that a fresh activation can still churn.
    static nonisolated func rehideDelay(
        for strategy: RehideStrategy,
        since lastShow: ContinuousClock.Instant?,
        now: ContinuousClock.Instant = .now
    ) -> Duration {
        let focusSettleDelay: Duration = strategy == .smart
            ? .milliseconds(250)
            : .milliseconds(100)
        guard let lastShow else { return focusSettleDelay }
        let remainingGrace = Duration.milliseconds(500) - lastShow.duration(to: now)
        return max(focusSettleDelay, remainingGrace)
    }

    /// Thaw temporarily activates itself when it must hide application menus.
    /// That internal activation is not a user focus change and must not rehide
    /// the section that caused it.
    static nonisolated func shouldHandleAutoRehideActivation(
        activatedProcessIdentifier: pid_t?,
        currentProcessIdentifier: pid_t
    ) -> Bool {
        activatedProcessIdentifier != currentProcessIdentifier
    }

    private func hideVisibleSections() {
        for section in sections where !section.isHidden {
            section.hide()
        }
    }

    /// Updates the control item states for all sections.
    ///
    /// - Parameter screen: The screen to use for the update. If `nil`, the
    ///   best screen is determined automatically.
    func updateControlItemStates(for screen: NSScreen? = nil) {
        for section in sections {
            section.updateControlItemState(for: screen)
        }
    }

    /// Returns the menu bar section with the given name.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }

    /// Returns the control item for the menu bar section with the given name.
    func controlItem(withName name: MenuBarSection.Name) -> ControlItem? {
        section(withName: name)?.controlItem
    }
}

// MARK: - MenuBarAverageColorInfo

/// Information for the average color of the menu bar.
struct MenuBarAverageColorInfo: Hashable {
    /// Sources used to compute the average color of the menu bar.
    enum Source: Hashable {
        case menuBarWindow
        case desktopWallpaper
    }

    /// The average color of the menu bar
    var color: CGColor

    /// The source used to compute the color.
    var source: Source

    /// The brightness of the menu bar's color.
    var brightness: CGFloat {
        color.brightness ?? 0
    }

    /// A Boolean value that indicates whether the menu bar has a
    /// bright color.
    ///
    /// This value is `true` if ``brightness`` is above ``Constants.menuBarBrightnessThreshold``.
    /// At the time of writing, if this value is `true`, the menu bar
    /// draws its items with a darker appearance.
    var isBright: Bool {
        brightness > Constants.menuBarBrightnessThreshold
    }

    /// Returns whether the menu bar has a bright color for the given screen.
    /// Uses a lower threshold for notched displays to bias toward black text.
    /// - Parameter screen: The screen to check for notch presence
    /// - Returns: `true` if the background is bright enough to require dark text
    func isBright(for screen: NSScreen?) -> Bool {
        let activeOrPassed = screen ?? NSScreen.screenWithActiveMenuBar
        let hasNotch = activeOrPassed?.hasNotch == true
        let threshold = hasNotch
            ? Constants.notchedDisplayBrightnessThreshold
            : Constants.menuBarBrightnessThreshold
        return brightness > threshold
    }
}
