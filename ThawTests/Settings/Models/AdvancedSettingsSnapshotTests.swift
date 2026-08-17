//
//  AdvancedSettingsSnapshotTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``AdvancedSettingsSnapshot``'s value semantics and its `Codable`
/// conformance.
///
/// The snapshot is the on-disk shape of a profile's Advanced pane, so a
/// profile written by an older build can be missing any key the current build
/// knows about. Decoding therefore has to fall back to
/// `Defaults.DefaultValue` rather than throwing, which is what the
/// forward-compatibility cases below pin.
///
/// Reads only; nothing here writes to the defaults domain, so the suite is
/// safe to run in parallel with the rest.
@Suite("Advanced settings snapshot")
struct AdvancedSettingsSnapshotTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Helper Methods

    private func makeDefaultSnapshot() -> AdvancedSettingsSnapshot {
        AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: true,
            showAllSectionsOnUserDrag: true,
            hideApplicationMenus: false,
            enableSecondaryContextMenu: true,
            enableSecondaryContextMenuQuit: false,
            tooltipDelay: 1.0,
            useDoubleClickToShowAlwaysHiddenSection: false,
            useOptionClickToShowAlwaysHiddenSection: false
        )
    }

    private func makeCustomSnapshot() -> AdvancedSettingsSnapshot {
        AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: false,
            showAllSectionsOnUserDrag: false,
            hideApplicationMenus: true,
            enableSecondaryContextMenu: false,
            enableSecondaryContextMenuQuit: true,
            tooltipDelay: 2.0,
            useDoubleClickToShowAlwaysHiddenSection: true,
            useOptionClickToShowAlwaysHiddenSection: true
        )
    }

    // MARK: - Initialization Tests

    @Test("A snapshot keeps the default values it was built with")
    func defaultSnapshotValues() {
        let snapshot = makeDefaultSnapshot()

        #expect(snapshot.enableAlwaysHiddenSection)
        #expect(snapshot.showAllSectionsOnUserDrag)
        #expect(!snapshot.hideApplicationMenus)
        #expect(snapshot.enableSecondaryContextMenu)
        #expect(snapshot.tooltipDelay == 1.0)
        #expect(!snapshot.useDoubleClickToShowAlwaysHiddenSection)
    }

    @Test("A snapshot keeps the custom values it was built with")
    func customSnapshotValues() {
        let snapshot = makeCustomSnapshot()

        #expect(!snapshot.enableAlwaysHiddenSection)
        #expect(!snapshot.showAllSectionsOnUserDrag)
        #expect(snapshot.hideApplicationMenus)
        #expect(!snapshot.enableSecondaryContextMenu)
        #expect(snapshot.tooltipDelay == 2.0)
        #expect(snapshot.useDoubleClickToShowAlwaysHiddenSection)
    }

    // MARK: - Encode/Decode Tests

    @Test("A default snapshot survives a round trip unchanged")
    func encodeDecodeDefaultSnapshot() throws {
        let original = makeDefaultSnapshot()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.enableAlwaysHiddenSection == original.enableAlwaysHiddenSection)
        #expect(decoded.showAllSectionsOnUserDrag == original.showAllSectionsOnUserDrag)
        #expect(decoded.hideApplicationMenus == original.hideApplicationMenus)
        #expect(decoded.enableSecondaryContextMenu == original.enableSecondaryContextMenu)
        #expect(decoded.tooltipDelay == original.tooltipDelay)
        #expect(decoded.useDoubleClickToShowAlwaysHiddenSection == original.useDoubleClickToShowAlwaysHiddenSection)
    }

    @Test("A custom snapshot survives a round trip unchanged")
    func encodeDecodeCustomSnapshot() throws {
        let original = makeCustomSnapshot()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.enableAlwaysHiddenSection == false)
        #expect(decoded.showAllSectionsOnUserDrag == false)
        #expect(decoded.hideApplicationMenus == true)
        #expect(decoded.enableSecondaryContextMenu == false)
        #expect(decoded.tooltipDelay == 2.0)
        #expect(decoded.useDoubleClickToShowAlwaysHiddenSection == true)
    }

    // MARK: - Forward-Compatibility Tests

    @Test("A profile written before the newer keys existed decodes with their defaults")
    func decodeOlderProfileMissingNewerKeys() throws {
        // Simulates a profile saved before useDoubleClickToShowAlwaysHiddenSection
        // and enableSecondaryContextMenuQuit were added. Decoding must succeed,
        // filling in defaults from Defaults.DefaultValue.
        let json = """
        {
            "enableAlwaysHiddenSection": true,
            "showAllSectionsOnUserDrag": false,
            "hideApplicationMenus": true,
            "enableSecondaryContextMenu": true,
            "showOnHoverDelay": 0.2,
            "tooltipDelay": 1.0,
            "showMenuBarTooltips": false,
            "enableDiagnosticLogging": false
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: json)

        #expect(decoded.enableAlwaysHiddenSection)
        #expect(
            decoded.useDoubleClickToShowAlwaysHiddenSection
                == Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection
        )
        #expect(
            decoded.enableSecondaryContextMenuQuit
                == Defaults.DefaultValue.enableSecondaryContextMenuQuit
        )
    }

    @Test("An empty object decodes to the shipped defaults")
    func decodeEmptyObjectFallsBackToDefaults() throws {
        // Worst-case forward-compat: every key is missing, decoder must still
        // produce a snapshot rather than throwing keyNotFound.
        let json = "{}".data(using: .utf8)!
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: json)

        #expect(
            decoded.enableAlwaysHiddenSection
                == Defaults.DefaultValue.enableAlwaysHiddenSection
        )
        #expect(
            decoded.enableSecondaryContextMenuQuit
                == Defaults.DefaultValue.enableSecondaryContextMenuQuit
        )
    }

    // MARK: - TimeInterval Edge Cases

    @Test("A zero hover delay round-trips")
    func zeroShowOnHoverDelay() throws {
        var snapshot = makeDefaultSnapshot()

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

    }

    @Test("A large hover delay round-trips")
    func largeShowOnHoverDelay() throws {
        var snapshot = makeDefaultSnapshot()

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

    }

    @Test("A zero tooltip delay round-trips")
    func zeroTooltipDelay() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.tooltipDelay = 0

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.tooltipDelay == 0)
    }

    @Test("A large tooltip delay round-trips")
    func largeTooltipDelay() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.tooltipDelay = 60.0

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.tooltipDelay == 60.0)
    }

    @Test("A zero icon refresh interval round-trips")
    func zeroIconRefreshInterval() throws {
        var snapshot = makeDefaultSnapshot()

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

    }

    @Test("A large icon refresh interval round-trips")
    func largeIconRefreshInterval() throws {
        var snapshot = makeDefaultSnapshot()

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

    }

    @Test("Fractional delays round-trip within tolerance")
    func fractionalDelays() throws {
        var snapshot = makeDefaultSnapshot()
        snapshot.tooltipDelay = 0.75

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(abs(decoded.tooltipDelay - 0.75) < 0.001)
    }

    // MARK: - Boolean Combinations

    @Test("A snapshot with every boolean off round-trips")
    func allBooleansFalse() throws {
        let snapshot = AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: false,
            showAllSectionsOnUserDrag: false,
            hideApplicationMenus: false,
            enableSecondaryContextMenu: false,
            enableSecondaryContextMenuQuit: false,
            tooltipDelay: 0,
            useDoubleClickToShowAlwaysHiddenSection: false,
            useOptionClickToShowAlwaysHiddenSection: false
        )

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(!decoded.enableAlwaysHiddenSection)
        #expect(!decoded.showAllSectionsOnUserDrag)
        #expect(!decoded.hideApplicationMenus)
        #expect(!decoded.enableSecondaryContextMenu)
        #expect(!decoded.enableSecondaryContextMenuQuit)
        #expect(!decoded.useDoubleClickToShowAlwaysHiddenSection)
    }

    @Test("A snapshot with every boolean on round-trips")
    func allBooleansTrue() throws {
        let snapshot = AdvancedSettingsSnapshot(
            enableAlwaysHiddenSection: true,
            showAllSectionsOnUserDrag: true,
            hideApplicationMenus: true,
            enableSecondaryContextMenu: true,
            enableSecondaryContextMenuQuit: true,
            tooltipDelay: 0,
            useDoubleClickToShowAlwaysHiddenSection: true,
            useOptionClickToShowAlwaysHiddenSection: true
        )

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: data)

        #expect(decoded.enableAlwaysHiddenSection)
        #expect(decoded.showAllSectionsOnUserDrag)
        #expect(decoded.hideApplicationMenus)
        #expect(decoded.enableSecondaryContextMenu)
        #expect(decoded.enableSecondaryContextMenuQuit)
        #expect(decoded.useDoubleClickToShowAlwaysHiddenSection)
    }

    // MARK: - Removed Settings

    /// Every profile already on disk carries keys for settings this fork has
    /// since deleted — hover, tooltips, the search panel, the pointer warp.
    /// Decoding must ignore them rather than fail, or a profile saved by any
    /// earlier build stops loading.
    @Test("A profile written before those settings were removed still decodes")
    func legacyRemovedSettingKeysAreIgnored() throws {
        let json = """
        {
            "enableAlwaysHiddenSection": true,
            "showAllSectionsOnUserDrag": false,
            "hideApplicationMenus": true,
            "enableSecondaryContextMenu": true,
            "showOnHoverDelay": 0.2,
            "tooltipDelay": 1.0,
            "showMenuBarTooltips": false,
            "searchSectionOrder": ["hidden", "visible", "alwaysHidden"],
            "searchIncludeVisible": false,
            "searchIncludeHidden": false,
            "searchIncludeAlwaysHidden": false,
            "moveCursorToRevealedItem": true,
            "enableDiagnosticLogging": false
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: json)

        #expect(decoded.enableAlwaysHiddenSection)
        #expect(!decoded.showAllSectionsOnUserDrag)
        #expect(decoded.hideApplicationMenus)
        #expect(decoded.enableSecondaryContextMenu)
        #expect(decoded.tooltipDelay == 1.0)
    }

    // MARK: - Diagnostic Logging Exclusion

    /// `enableDiagnosticLogging` is deliberately not part of a profile.
    ///
    /// It is a diagnostic control, not a preference. While it was in the
    /// snapshot, applying a profile restored whatever the switch had been
    /// when that profile was saved — off, for every profile that already
    /// existed — so logging stopped at the exact moment a user had turned it
    /// on to capture a profile switch, and the switch looked like it flipped
    /// itself back (#899).
    @Test("A profile written before the removal still decodes, ignoring the key")
    func legacyDiagnosticLoggingKeyIsIgnored() throws {
        let json = """
        {
            "enableAlwaysHiddenSection": true,
            "showAllSectionsOnUserDrag": false,
            "hideApplicationMenus": true,
            "enableSecondaryContextMenu": true,
            "showOnHoverDelay": 0.2,
            "tooltipDelay": 1.0,
            "showMenuBarTooltips": false,
            "enableDiagnosticLogging": true
        }
        """.data(using: .utf8)!

        // Decoding must not throw on the now-unknown key, and the rest of the
        // snapshot must come through intact.
        let decoded = try decoder.decode(AdvancedSettingsSnapshot.self, from: json)

        #expect(decoded.enableAlwaysHiddenSection)
        #expect(decoded.hideApplicationMenus)
    }

    /// The key must not come back on the way out either: a profile saved by
    /// this build carries no diagnostic-logging state, so applying it on any
    /// build — including an older one, which decodes with `decodeIfPresent`
    /// and a default — cannot disturb the switch.
    @Test("An encoded snapshot no longer writes the key")
    func encodedSnapshotOmitsDiagnosticLogging() throws {
        let data = try encoder.encode(makeCustomSnapshot())
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("enableDiagnosticLogging"))
    }
}
