//
//  CoverageSweep4Tests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Coverage sweep, part 4: the settings models whose *load* path — the code
/// that runs once at `init`, before any UI exists — has no dedicated suite.
///
/// Covers:
///
/// - `AutomationHookSettings.init`, which is entirely uncovered today. Its
///   whole reason to exist is the `suppressPersist` latch: without it the
///   two `didSet` observers would echo the freshly loaded hooks straight
///   back to `UserDefaults` on every launch. That is asserted by planting
///   bytes the encoder would never produce and checking they survive.
/// - `AutomationSettings.addCurrentApp`, the "whitelist this app" button.
///
/// Every test routes through ``withScratchDefaults(sourceLocation:_:)``, so
/// nothing here writes to the real `com.nyshk97.Thaw` domain, and the suite
/// is `.serialized` because that store is process-wide.
///
/// Deliberate gap: `AutomationSettings`' whitelist-change notification sink
/// is skipped because it hops through
/// `receive(on: DispatchQueue.main)`, so observing it would mean waiting on
/// a run loop turn.
@MainActor
@Suite("Coverage sweep 4: settings model load paths", .serialized)
struct CoverageSweep4Tests {
    // MARK: - AutomationHookSettings

    @Test("Both global hooks are loaded at init")
    func globalHooksAreLoadedAtInit() throws {
        try withScratchDefaults { _ in
            let pre = HookScript(path: "/tmp/thaw-pre.sh", timeoutSeconds: 7, isEnabled: true)
            let post = HookScript(path: "/tmp/thaw-post.sh", timeoutSeconds: 12, isEnabled: false)
            HookScript.saveGlobal(pre, phase: .pre)
            HookScript.saveGlobal(post, phase: .post)

            let settings = AutomationHookSettings()

            #expect(settings.globalPreHook == pre)
            #expect(settings.globalPostHook == post)
        }
    }

    @Test("Unconfigured global hooks load as nil rather than as empty scripts")
    func unconfiguredGlobalHooksLoadAsNil() throws {
        try withScratchDefaults { _ in
            let settings = AutomationHookSettings()

            #expect(settings.globalPreHook == nil)
            #expect(settings.globalPostHook == nil)
        }
    }

    /// The stored bytes are deliberately in an order and spacing that
    /// `JSONEncoder` would never emit, so an echo from the `didSet`
    /// observers would rewrite them and this comparison would fail.
    @Test("Loading at init does not write the hooks back to defaults")
    func loadingAtInitDoesNotEchoBackToDefaults() throws {
        try withScratchDefaults { _ in
            let planted = Data(#"{ "isEnabled" : true, "timeoutSeconds" : 7, "path" : "/tmp/thaw-pre.sh" }"#.utf8)
            Defaults.set(planted, forKey: .globalPreProfileHook)

            let settings = AutomationHookSettings()

            #expect(settings.globalPreHook?.path == "/tmp/thaw-pre.sh")
            #expect(Defaults.data(forKey: .globalPreProfileHook) == planted)
        }
    }

    /// The contrast that makes the previous test meaningful: once `init` has
    /// returned, an assignment *is* persisted.
    @Test("An assignment after init is persisted")
    func assigningAfterInitPersists() throws {
        try withScratchDefaults { _ in
            let settings = AutomationHookSettings()
            let hook = HookScript(path: "/tmp/thaw-later.sh", timeoutSeconds: 3, isEnabled: true)

            settings.globalPostHook = hook

            #expect(HookScript.loadGlobal(.post) == hook)
            #expect(HookScript.loadGlobal(.pre) == nil)
        }
    }

    @Test("Clearing a hook after init removes it from defaults")
    func clearingAfterInitRemovesTheStoredHook() throws {
        try withScratchDefaults { _ in
            HookScript.saveGlobal(HookScript(path: "/tmp/thaw-pre.sh"), phase: .pre)
            let settings = AutomationHookSettings()
            #expect(settings.globalPreHook != nil)

            settings.globalPreHook = nil

            #expect(Defaults.data(forKey: .globalPreProfileHook) == nil)
            #expect(HookScript.loadGlobal(.pre) == nil)
        }
    }

    // MARK: - AutomationSettings

    @Test("Adding the current app whitelists this bundle")
    func addCurrentAppWhitelistsThisBundle() throws {
        try withScratchDefaults { _ in
            let bundleID = try #require(
                Bundle.main.bundleIdentifier,
                "the test host is an app bundle, so it always has an identifier"
            )
            let settings = AutomationSettings()
            #expect(settings.whitelistedApps.isEmpty)

            settings.addCurrentApp()

            #expect(settings.whitelistedApps.contains { $0.bundleId == bundleID })
            #expect(SettingsURIHandler.getWhitelist().contains(bundleID))
        }
    }

    @Test("Adding the current app twice does not duplicate the entry")
    func addCurrentAppIsIdempotent() throws {
        try withScratchDefaults { _ in
            let settings = AutomationSettings()

            settings.addCurrentApp()
            settings.addCurrentApp()

            #expect(settings.whitelistedApps.count == 1)
        }
    }
}
