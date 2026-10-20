//
//  Log.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import OSLog

/// Unified logging. Read with:
///
///     log stream --predicate 'subsystem == "com.nyshk97.MenuBarTidy.dev"' --level debug
///
/// (the release build's subsystem is `com.nyshk97.MenuBarTidy`).
nonisolated enum Log {
    static let scanner = Logger(subsystem: AppIdentity.bundleID, category: "Scanner")
    static let press = Logger(subsystem: AppIdentity.bundleID, category: "Press")
    static let app = Logger(subsystem: AppIdentity.bundleID, category: "App")
}
