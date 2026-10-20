//
//  Updates.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Sparkle

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
final class UpdatesManager: NSObject {
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

    /// Tracks whether the updater has been started.
    private var hasStartedUpdater = false

    /// The underlying updater controller.
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    /// Whether the user can check for updates right now.
    var canCheckForUpdates: Bool {
        Self.isSupported && updaterController.updater.canCheckForUpdates
    }

    /// Starts the updater (scheduled checks included). Does nothing in the dev build.
    func startUpdaterIfNeeded() {
        guard Self.isSupported, !hasStartedUpdater else {
            return
        }
        hasStartedUpdater = true
        updaterController.startUpdater()
    }

    /// Checks for app updates, showing Sparkle's progress and result UI.
    @objc func checkForUpdates() {
        guard Self.isSupported else {
            let alert = NSAlert()
            alert.messageText = "dev 版ではアップデートを確認できません。"
            alert.informativeText = "アップデートの確認は配布版（MenuBar Tidy）でのみ動作します。"
            NSApp.activate()
            alert.runModal()
            return
        }
        startUpdaterIfNeeded()
        // Activate the app so Sparkle's alerts come to the front.
        NSApp.activate()
        updaterController.updater.checkForUpdates()
    }
}

// MARK: UpdatesManager: SPUUpdaterDelegate

extension UpdatesManager: SPUUpdaterDelegate {
    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        // `SUEnableAutomaticChecks` in the Info.plist already answers this
        // for every install; never raise Sparkle's own consent dialog.
        false
    }
}
