//
//  AdvancedSettingsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``AdvancedSettings``' setup surface: the `Defaults` load performed by
/// `performSetup(with:)` and the Settings-URI notification it subscribes to.
///
/// The load reads whatever is in `UserDefaults` — possibly written by an older
/// build, a hand-edited plist, or a partially failed import — so an
/// unrecognized divider style or a search-section order that is short,
/// duplicated, or full of unknown names has to resolve to something usable
/// rather than leave the search panel with a missing or repeated section.
/// The notification arrives on behalf of a *third-party app* that sent a
/// `thaw://` URL, so a key this model does not own, or a payload of the wrong
/// type, must be dropped.
///
/// `SettingsURIHandlerApplyTests` covers the sending side of the same
/// notification; the two suites have to agree on the `userInfo` shape.
///
/// The model persists through `didSet`, so every test body runs inside
/// `withScratchDefaults`: writes land in a throwaway store rather than the
/// developer's own settings, and each test starts from the empty store of a
/// first launch. That also keeps `enableDiagnosticLogging` at its compiled-in
/// default, so the model never runs the `didSet` that reaches into the shared
/// ``DiagnosticLogger``.
@MainActor
@Suite("Advanced settings", .serialized)
struct AdvancedSettingsTests {
    /// Returns a model that has run its setup against the current `Defaults`.
    ///
    /// The app state is unused by this model, so setup runs without one.
    private func makeSettings() -> AdvancedSettings {
        let settings = AdvancedSettings()
        settings.performSetup()
        return settings
    }

    // MARK: Initial load

    @Test("Stored values are loaded into the model")
    func storedValuesAreLoaded() throws {
        try withScratchDefaults { _ in
            Defaults.set(true, forKey: .enableAlwaysHiddenSection)
            Defaults.set(true, forKey: .useOptionClickToShowAlwaysHiddenSection)
            Defaults.set(true, forKey: .useDoubleClickToShowAlwaysHiddenSection)
            Defaults.set(false, forKey: .showAllSectionsOnUserDrag)
            Defaults.set(false, forKey: .hideApplicationMenus)
            Defaults.set(false, forKey: .enableSecondaryContextMenu)
            Defaults.set(true, forKey: .enableSecondaryContextMenuQuit)
            Defaults.set(2.5, forKey: .tooltipDelay)
            Defaults.set(true, forKey: .useAXClickDelivery)

            let settings = makeSettings()

            #expect(settings.enableAlwaysHiddenSection)
            #expect(settings.useOptionClickToShowAlwaysHiddenSection)
            #expect(settings.useDoubleClickToShowAlwaysHiddenSection)
            #expect(!settings.showAllSectionsOnUserDrag)
            #expect(!settings.hideApplicationMenus)
            #expect(!settings.enableSecondaryContextMenu)
            #expect(settings.enableSecondaryContextMenuQuit)
            #expect(settings.tooltipDelay == 2.5)
            #expect(settings.useAXClickDelivery)
        }
    }

    @Test("Absent keys leave the shipped defaults in place")
    func absentKeysLeaveTheDefaults() throws {
        try withScratchDefaults { _ in
            let settings = makeSettings()

            #expect(settings.enableAlwaysHiddenSection == Defaults.DefaultValue.enableAlwaysHiddenSection)
            #expect(settings.showAllSectionsOnUserDrag == Defaults.DefaultValue.showAllSectionsOnUserDrag)
            #expect(settings.hideApplicationMenus == Defaults.DefaultValue.hideApplicationMenus)
            #expect(settings.tooltipDelay == Defaults.DefaultValue.tooltipDelay)
            #expect(settings.useAXClickDelivery == Defaults.DefaultValue.useAXClickDelivery)
        }
    }

    // MARK: Persistence

    @Test("A property change is written straight through to Defaults")
    func propertyChangesArePersisted() throws {
        try withScratchDefaults { _ in
            let settings = makeSettings()

            settings.enableAlwaysHiddenSection = true
            settings.tooltipDelay = 1.25

            #expect(Defaults.bool(forKey: .enableAlwaysHiddenSection))
            #expect(Defaults.double(forKey: .tooltipDelay) == 1.25)
        }
    }

    @Test("Stored values survive a reload")
    func storedValuesRoundTrip() throws {
        try withScratchDefaults { _ in
            let settings = makeSettings()
            settings.enableAlwaysHiddenSection = true
            settings.tooltipDelay = 3.5

            let reloaded = makeSettings()

            #expect(reloaded.enableAlwaysHiddenSection)
            #expect(reloaded.tooltipDelay == 3.5)
        }
    }
}
