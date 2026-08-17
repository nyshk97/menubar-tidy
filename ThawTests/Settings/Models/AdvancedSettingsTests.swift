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
            Defaults.set(1.5, forKey: .showOnHoverDelay)
            Defaults.set(2.5, forKey: .tooltipDelay)
            Defaults.set(true, forKey: .showMenuBarTooltips)
            Defaults.set(true, forKey: .useAXClickDelivery)
            Defaults.set(false, forKey: .searchIncludeVisible)
            Defaults.set(false, forKey: .searchIncludeHidden)
            Defaults.set(false, forKey: .searchIncludeAlwaysHidden)
            Defaults.set(true, forKey: .moveCursorToRevealedItem)

            let settings = makeSettings()

            #expect(settings.enableAlwaysHiddenSection)
            #expect(settings.useOptionClickToShowAlwaysHiddenSection)
            #expect(settings.useDoubleClickToShowAlwaysHiddenSection)
            #expect(!settings.showAllSectionsOnUserDrag)
            #expect(!settings.hideApplicationMenus)
            #expect(!settings.enableSecondaryContextMenu)
            #expect(settings.enableSecondaryContextMenuQuit)
            #expect(settings.showOnHoverDelay == 1.5)
            #expect(settings.tooltipDelay == 2.5)
            #expect(settings.showMenuBarTooltips)
            #expect(settings.useAXClickDelivery)
            #expect(!settings.searchIncludeVisible)
            #expect(!settings.searchIncludeHidden)
            #expect(!settings.searchIncludeAlwaysHidden)
            #expect(settings.moveCursorToRevealedItem)
        }
    }

    @Test("Absent keys leave the shipped defaults in place")
    func absentKeysLeaveTheDefaults() throws {
        try withScratchDefaults { _ in
            let settings = makeSettings()

            #expect(settings.enableAlwaysHiddenSection == Defaults.DefaultValue.enableAlwaysHiddenSection)
            #expect(settings.showAllSectionsOnUserDrag == Defaults.DefaultValue.showAllSectionsOnUserDrag)
            #expect(settings.hideApplicationMenus == Defaults.DefaultValue.hideApplicationMenus)
            #expect(settings.showOnHoverDelay == Defaults.DefaultValue.showOnHoverDelay)
            #expect(settings.tooltipDelay == Defaults.DefaultValue.tooltipDelay)
            #expect(settings.useAXClickDelivery == Defaults.DefaultValue.useAXClickDelivery)
            #expect(settings.searchSectionOrder.map(\.rawValue) == Defaults.DefaultValue.searchSectionOrder)
        }
    }



    // MARK: Search section order

    @Test("A stored search order is loaded in the order it was written")
    func storedSearchOrderIsLoaded() throws {
        try withScratchDefaults { _ in
            Defaults.set(["alwaysHidden", "hidden", "visible"], forKey: .searchSectionOrder)

            #expect(makeSettings().searchSectionOrder == [.alwaysHidden, .hidden, .visible])
        }
    }

    @Test("A short stored search order is filled out with the missing sections")
    func shortSearchOrderIsFilledOut() throws {
        try withScratchDefaults { _ in
            Defaults.set(["alwaysHidden"], forKey: .searchSectionOrder)

            let order = makeSettings().searchSectionOrder

            #expect(order.first == .alwaysHidden)
            #expect(Set(order) == Set(MenuBarSection.Name.allCases), "every section has to be listed exactly once")
            #expect(order.count == MenuBarSection.Name.allCases.count)
        }
    }

    @Test("Duplicate and unknown section names are dropped from a stored order")
    func malformedSearchOrderIsSanitized() throws {
        try withScratchDefaults { _ in
            Defaults.set(["hidden", "hidden", "sideways", "", "visible"], forKey: .searchSectionOrder)

            let order = makeSettings().searchSectionOrder

            #expect(order == [.hidden, .visible, .alwaysHidden])
        }
    }

    @Test("An empty stored search order falls back to the full set")
    func emptySearchOrderFallsBack() throws {
        try withScratchDefaults { _ in
            Defaults.set([String](), forKey: .searchSectionOrder)

            #expect(makeSettings().searchSectionOrder == MenuBarSection.Name.allCases)
        }
    }

    // MARK: Persistence

    @Test("A property change is written straight through to Defaults")
    func propertyChangesArePersisted() throws {
        try withScratchDefaults { _ in
            let settings = makeSettings()

            settings.enableAlwaysHiddenSection = true
            settings.tooltipDelay = 1.25
            settings.searchSectionOrder = [.alwaysHidden, .hidden, .visible]
            settings.moveCursorToRevealedItem = true

            #expect(Defaults.bool(forKey: .moveCursorToRevealedItem))
            #expect(Defaults.bool(forKey: .enableAlwaysHiddenSection))
            #expect(Defaults.double(forKey: .tooltipDelay) == 1.25)
            #expect(Defaults.stringArray(forKey: .searchSectionOrder) == ["alwaysHidden", "hidden", "visible"])
        }
    }

    @Test("Stored values survive a reload")
    func storedValuesRoundTrip() throws {
        try withScratchDefaults { _ in
            let settings = makeSettings()
            settings.enableAlwaysHiddenSection = true
            settings.searchSectionOrder = [.hidden, .alwaysHidden, .visible]

            let reloaded = makeSettings()

            #expect(reloaded.enableAlwaysHiddenSection)
            #expect(reloaded.searchSectionOrder == [.hidden, .alwaysHidden, .visible])
        }
    }
}
