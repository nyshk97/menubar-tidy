//
//  AppIdentity.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The identity of the build that is running: its bundle identifier, the name
/// of its XPC service, and the directory its support files live under.
///
/// Debug builds ship as a separate app — `MenuBarTidy-dev`, bundle identifier
/// `com.nyshk97.MenuBarTidy.dev`, DEV-ribboned icon — so the build under
/// development never shares TCC approvals, defaults, profiles or logs with the
/// release install. The names come from the build settings; everything here is
/// derived from the identifier at runtime, so a build renamed in the project
/// file cannot drift away from the paths the code uses.
nonisolated enum AppIdentity {
    /// The main app's bundle identifier.
    ///
    /// In `MenuBarItemService`, `Bundle.main` is the `.xpc` bundle, so the
    /// service component is trimmed to get back to the app that hosts it. Both
    /// processes have to agree on this value: the service validates the log
    /// path the app hands it against a directory derived from it.
    static let bundleID: String = {
        let mainBundleID = Bundle.main.bundleIdentifier ?? releaseBundleID
        let suffix = ".\(serviceComponent)"
        return mainBundleID.hasSuffix(suffix)
            ? String(mainBundleID.dropLast(suffix.count))
            : mainBundleID
    }()

    /// Whether this build is the dev build rather than the release install.
    static let isDevBuild = bundleID.hasSuffix(devSuffix)

    /// The XPC service's name, which is also its bundle identifier.
    static let serviceName = "\(bundleID).\(serviceComponent)"

    /// The name of the directories this build keeps its support files in:
    /// `~/Library/Logs/<name>/` and
    /// `~/Library/Application Support/<name>/Profiles/`. Matches the bundle
    /// name so the two builds never write to each other's files.
    static let supportDirectoryName = isDevBuild ? devBundleName : releaseBundleName

    private static let releaseBundleID = "com.nyshk97.MenuBarTidy"
    private static let releaseBundleName = "MenuBar Tidy"
    private static let devBundleName = "MenuBarTidy-dev"
    private static let devSuffix = ".dev"
    private static let serviceComponent = "MenuBarItemService"
}
