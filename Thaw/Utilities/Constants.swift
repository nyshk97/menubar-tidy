//
//  Constants.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// App-specific constants read from the bundle.
nonisolated enum Constants {
    /// The version string in the app's bundle (`CFBundleShortVersionString`).
    static let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    /// The build string in the app's bundle (`CFBundleVersion`).
    static let buildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

    /// The short git SHA stamped into the bundle by the "Stamp Git SHA" build
    /// phase, with a `-dirty` suffix when the tree was not clean at build time.
    ///
    /// `nil` when the phase did not run, which is the signal that the binary
    /// cannot be tied back to a commit.
    static let gitCommitSHA = Bundle.main.object(forInfoDictionaryKey: "GitCommitSHA") as? String

    /// The app's display name (`CFBundleDisplayName`, then `CFBundleName`).
    static let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "MenuBar Tidy"
}
