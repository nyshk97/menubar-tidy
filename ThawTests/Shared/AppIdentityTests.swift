//
//  AppIdentityTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

// MARK: - AppIdentity Tests

/// `AppIdentity` derives the paths and the service name from the identifier the
/// build settings assign, so these tests exist to catch the two halves drifting
/// apart: a renamed product, a bundle identifier changed in one configuration
/// only, or an XPC service left behind under the old identifier. The tests are
/// hosted by the app, so `Bundle.main` here is the app under test.
@Suite("App identity")
struct AppIdentityTests {
    @Test("The identity matches the bundle the tests are hosted by")
    func identityMatchesHostBundle() throws {
        let hostBundleID = try #require(Bundle.main.bundleIdentifier)

        #expect(AppIdentity.bundleID == hostBundleID)
        #expect(AppIdentity.serviceName == "\(hostBundleID).MenuBarItemService")
    }

    @Test("The support directory is named after the bundle")
    func supportDirectoryMatchesBundleName() {
        // Log and profile directories are named after the app, so a build whose
        // display name says one thing and whose paths say another would write
        // the dev build's state into the release install's directories.
        #expect(AppIdentity.supportDirectoryName == Bundle.main.displayName)
    }

    @Test("The embedded XPC service carries the identifier the app talks to")
    func embeddedServiceIdentifierMatches() throws {
        let serviceURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/XPCServices/MenuBarItemService.xpc")
        let service = try #require(
            Bundle(url: serviceURL),
            "The app bundle has no embedded MenuBarItemService"
        )

        #expect(service.bundleIdentifier == MenuBarItemService.name)
    }

    @Test("Debug builds are the dev build, release builds are not")
    func devBuildTracksTheConfiguration() {
        #if DEBUG
            #expect(AppIdentity.isDevBuild)
            #expect(AppIdentity.bundleID.hasSuffix(".dev"))
        #else
            #expect(!AppIdentity.isDevBuild)
            #expect(AppIdentity.bundleID == "com.nyshk97.MenuBarTidy")
        #endif
    }
}
