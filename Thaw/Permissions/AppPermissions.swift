//
//  AppPermissions.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation

/// An abstraction over ``AppPermissions`` that lets views depend on just the
/// pieces they read, so previews can supply lightweight stand-ins instead of
/// the real manager and its associated app machinery.
@MainActor
protocol PermissionsManaging: AnyObject, Observable {
    /// The state of the app's granted permissions.
    var permissionsState: AppPermissions.PermissionsState { get }

    /// The permissions required for full app functionality.
    var allPermissions: [Permission] { get }
}

/// A type that manages the permissions of the app.
@MainActor
@Observable
final class AppPermissions: PermissionsManaging {
    /// Keys to access individual permissions.
    enum PermissionKey {
        /// Identifies ``AppPermissions/accessibility``.
        case accessibility
        /// Identifies ``AppPermissions/screenRecording``.
        case screenRecording
    }

    /// The state of the app's granted permissions.
    ///
    /// Both permissions are required, so there is no partial state. Upstream
    /// had a `hasRequired` "limited mode" for a granted Accessibility with a
    /// missing Screen Recording; here that combination leaves the Thaw Bar
    /// unable to draw a single item, which is not a mode worth offering.
    enum PermissionsState {
        /// At least one permission hasn't been granted.
        case missing
        /// Every permission has been granted.
        case hasAll
    }

    /// The manager's logger.
    let diagLog = DiagLog(category: "Permissions")

    /// The permission for Accessibility features.
    let accessibility = AccessibilityPermission()

    /// The permission for Screen Recording features.
    let screenRecording = ScreenRecordingPermission()

    /// The state of the app's granted permissions.
    private(set) var permissionsState: PermissionsState = .missing

    /// The permissions required for full app functionality.
    var allPermissions: [Permission] {
        [accessibility, screenRecording]
    }

    /// Creates a new permissions manager.
    init() {
        self.updatePermissionsState()
        for permission in allPermissions {
            permission.onChange = { [weak self] in
                self?.updatePermissionsState()
            }
        }
    }

    /// Updates the current permissions state.
    private func updatePermissionsState() {
        permissionsState = allPermissions.allSatisfy(\.hasPermission) ? .hasAll : .missing
    }

    /// Stops running all permissions checks.
    func stopAllChecks() {
        diagLog.info("Stopping all permissions checks")
        for permission in allPermissions {
            permission.stopCheck()
        }
    }
}
