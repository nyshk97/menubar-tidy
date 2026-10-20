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

/// `AppIdentity` derives its answers from the identifier the build settings
/// assign, so these tests catch the two halves drifting apart: a renamed
/// product or a bundle identifier changed in one configuration only. The tests
/// are hosted by the app, so `Bundle.main` here is the app under test.
@Suite("App identity")
struct AppIdentityTests {
    @Test("The identity matches the bundle the tests are hosted by")
    func identityMatchesHostBundle() throws {
        let hostBundleID = try #require(Bundle.main.bundleIdentifier)
        #expect(AppIdentity.bundleID == hostBundleID)
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
