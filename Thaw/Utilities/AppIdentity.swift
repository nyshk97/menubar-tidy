//
//  AppIdentity.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The identity of the build that is running: its bundle identifier and whether
/// it is the dev build.
///
/// Debug builds ship as a separate app — `MenuBarTidy-dev`, bundle identifier
/// `com.nyshk97.MenuBarTidy.dev`, DEV-ribboned icon — so the build under
/// development never shares TCC approvals, defaults or logs with the release
/// install. The names come from the build settings; everything here is derived
/// from the identifier at runtime.
nonisolated enum AppIdentity {
    /// The app's bundle identifier.
    static let bundleID = Bundle.main.bundleIdentifier ?? releaseBundleID

    /// Whether this build is the dev build rather than the release install.
    static let isDevBuild = bundleID.hasSuffix(devSuffix)

    private static let releaseBundleID = "com.nyshk97.MenuBarTidy"
    private static let devSuffix = ".dev"
}
