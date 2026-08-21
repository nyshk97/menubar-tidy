//
//  Updates.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Observation
import Sparkle
import SwiftUI

/// Manager for app updates.
///
/// A cut-down return of upstream's Sparkle integration. What is gone, and
/// why: the beta channel (one channel), the consent sheet and the automatic
/// check/download toggles (`SUEnableAutomaticChecks` in the Info.plist
/// answers the question once, for every install), and the gentle-reminder
/// user driver delegate. That last one mattered: upstream answered
/// `standardUserDriverShouldHandleShowingScheduledUpdate` with `false`
/// whenever the app was inactive and relied on a user notification instead.
/// An `LSUIElement` app is inactive nearly always, so without the
/// notification half a scheduled check that found an update ended in
/// silence. Sparkle's standard alert handles it now.
@MainActor
@Observable
final class UpdatesManager: NSObject {
    /// A Boolean value that indicates whether the user can check for updates.
    var canCheckForUpdates = false

    /// The date of the last update check.
    var lastUpdateCheckDate: Date?

    /// Whether this build can update itself at all.
    ///
    /// The dev build carries no `SUFeedURL` (only `Info-Release.plist` has
    /// one), so it has nowhere to look; and even if it did, replacing the
    /// dev bundle with a release download would be the wrong answer.
    static let isSupported: Bool = {
        #if DEBUG
            return false
        #else
            return true
        #endif
    }()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Tracks whether the updater has been started.
    private var hasStartedUpdater = false

    /// Storage for internal observers.
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    /// The underlying updater controller.
    @ObservationIgnored
    private(set) lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    /// The underlying updater.
    var updater: SPUUpdater {
        updaterController.updater
    }

    /// Performs the initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        guard Self.isSupported else {
            return
        }
        _ = updaterController
        configureCancellables()
        startUpdaterIfNeeded()
    }

    /// Starts the updater if it hasn't been started yet.
    func startUpdaterIfNeeded() {
        guard Self.isSupported, !hasStartedUpdater else {
            return
        }
        hasStartedUpdater = true
        updaterController.startUpdater()
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &c)
        updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] value in
                self?.lastUpdateCheckDate = value
            }
            .store(in: &c)
        cancellables = c
    }

    /// Checks for app updates, showing Sparkle's progress and result UI.
    @objc func checkForUpdates() {
        guard Self.isSupported else {
            let alert = NSAlert()
            alert.messageText = "dev 版ではアップデートを確認できません。"
            alert.informativeText = "アップデートの確認は配布版（\(Constants.displayName)）でのみ動作します。"
            alert.runModal()
            return
        }
        guard let appState else {
            return
        }
        startUpdaterIfNeeded()
        // Activate the app so Sparkle's alerts come to the front.
        appState.activate(withPolicy: .regular)
        updater.checkForUpdates()
    }
}

// MARK: UpdatesManager: SPUUpdaterDelegate

extension UpdatesManager: SPUUpdaterDelegate {
    func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        // `SUEnableAutomaticChecks` in the Info.plist already answers this
        // for every install; never raise Sparkle's own consent dialog.
        false
    }
}
