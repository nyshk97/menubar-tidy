//
//  Permission.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import SwiftUI

// MARK: - Permission

/// An object that encapsulates the behavior of checking for and requesting
/// a specific permission for the app.
@MainActor
@Observable
class Permission: Identifiable {
    /// A Boolean value that indicates whether the app has this permission.
    private(set) var hasPermission = false {
        didSet {
            // `configureCancellables` re-assigns this every 3 seconds while
            // the permission is still missing, so fire only on an actual
            // transition rather than on every poll.
            guard oldValue != hasPermission else { return }
            onChange?()
        }
    }

    /// Callback invoked after ``hasPermission`` changes, with the new value
    /// already stored. Set by owners (e.g. AppPermissions) that need to
    /// react to updates.
    @ObservationIgnored
    var onChange: (() -> Void)?

    /// The title of the permission.
    let title: String

    /// The name of the system symbol image to display next to the title.
    let iconName: String

    /// The color of the icon displayed next to the title.
    let iconColor: Color

    /// Descriptive details for the permission.
    let details: [String]

    /// A Boolean value that indicates if the app can work without this permission.
    let isRequired: Bool

    /// The URL of the settings pane to open.
    private let settingsURL: URL?

    /// The function that checks permissions.
    private let check: () -> Bool

    /// The function that requests permissions.
    private let request: () -> Void

    /// The function that opens a System Settings URL.
    private let openSettings: (URL) -> Bool

    /// Observer that runs on a timer to check permissions.
    private var timerCancellable: AnyCancellable?

    /// Creates a permission.
    ///
    /// - Parameters:
    ///   - title: The title of the permission.
    ///   - details: Descriptive details for the permission.
    ///   - isRequired: A Boolean value that indicates if the app can work without this permission.
    ///   - settingsURL: The URL of the settings pane to open.
    ///   - check: A function that checks permissions.
    ///   - request: A function that requests permissions.
    ///   - openSettings: A function that opens the settings URL.
    init(
        title: String,
        iconName: String,
        iconColor: Color,
        details: [String],
        isRequired: Bool,
        settingsURL: URL?,
        check: @escaping () -> Bool,
        request: @escaping () -> Void,
        openSettings: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.title = title
        self.iconName = iconName
        self.iconColor = iconColor
        self.details = details
        self.isRequired = isRequired
        self.settingsURL = settingsURL
        self.check = check
        self.request = request
        self.openSettings = openSettings
        self.hasPermission = check()
        configureCancellables()
    }

    /// Sets up the internal observers for the permission.
    ///
    /// Polls ``check`` on a timer until the permission is granted, at which
    /// point the timer cancels itself — there's no need to keep checking once
    /// the app already has what it needs.
    private func configureCancellables() {
        timerCancellable = Timer.publish(every: 3, tolerance: 0.5, on: .main, in: .default)
            .autoconnect()
            .merge(with: Just(.now))
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                let granted = check()
                hasPermission = granted
                if granted {
                    timerCancellable?.cancel()
                    timerCancellable = nil
                }
            }
    }

    /// Performs the request and opens the System Settings app to the appropriate pane.
    func performRequest() {
        // Setup stops background permission polling once the app is running.
        // Restart it for every explicit request so later grants are observed.
        configureCancellables()
        request()
        if let settingsURL {
            _ = openSettings(settingsURL)
        }
    }

    /// Stops running the permission check.
    func stopCheck() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}

// MARK: - AccessibilityPermission

/// The Accessibility permission, required for Thaw to detect, move, and
/// interact with menu bar items on the user's behalf.
final class AccessibilityPermission: Permission {
    init() {
        super.init(
            title: "アクセシビリティ",
            iconName: "accessibility",
            iconColor: .blue,
            details: [
                "Mac 上のメニューバー項目と、その配置を検出します。",
                "メニューバー項目を移動して、並べ替えたり隠したりします。",
                "\(Constants.displayName) バーの項目を押したときなど、あなたの代わりにメニューバー項目をクリックします。",
            ],
            isRequired: true,
            // Keep an explicit settings URL so every click can recover the
            // flow if the user closes System Settings before granting access.
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            check: {
                AXHelpers.isProcessTrusted()
            },
            request: {
                AXHelpers.isProcessTrusted(prompt: true)
            }
        )
    }
}

// MARK: - ScreenRecordingPermission

/// The Screen Recording permission.
///
/// Upstream treated this as optional because most of what it fed — the
/// appearance overlay's adaptive tint, visual search — was optional. What is
/// left in this fork is the capture of the menu bar items' own icons, which
/// the Thaw Bar and the layout editor draw. Without it both show a
/// "grant this permission" placeholder instead of any items, so revealing a
/// hidden item becomes impossible. Required.
final class ScreenRecordingPermission: Permission {
    init() {
        super.init(
            title: "画面収録",
            iconName: "record.circle",
            iconColor: .red,
            details: [
                "メニューバー項目のアイコンを取得して、\(Constants.displayName) バーとレイアウト画面に表示します。",
                "メニューバーの色を読み取り、\(Constants.displayName) バーの背景をメニューバーに合わせます。",
            ],
            isRequired: true,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            check: {
                ScreenCapture.checkPermissions()
            },
            request: {
                ScreenCapture.requestPermissions()
            }
        )
    }
}
