//
//  MenuBarAppearanceConfigurationTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Menu bar appearance configuration")
struct MenuBarAppearanceConfigurationTests {
    @Suite("MenuBarAppearanceConfigurationV2")
    struct MenuBarAppearanceConfigurationV2Tests {
        // MARK: - Default Configuration Tests

        @Test("The default configuration ships the documented values")
        func defaultConfiguration() {
            let config = MenuBarAppearanceConfigurationV2.defaultConfiguration

            #expect(config.shapeKind == .noShape)
            #expect(config.isInset)
            #expect(config.leftMargin == 0)
            #expect(config.rightMargin == 0)
            #expect(!config.isDynamic)
        }

        // MARK: - Has Rounded Shape Tests

        @Test("A configuration with no shape has no rounded shape")
        func hasRoundedShapeNoShape() {
            var config = MenuBarAppearanceConfigurationV2.defaultConfiguration
            config.shapeKind = .noShape

            #expect(!config.hasRoundedShape)
        }

        // MARK: - Codable Tests

        @Test("The default configuration survives a round trip")
        func encodeDecode() throws {
            let original = MenuBarAppearanceConfigurationV2.defaultConfiguration

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)

            #expect(decoded.shapeKind == original.shapeKind)
            #expect(decoded.isInset == original.isInset)
            #expect(decoded.leftMargin == original.leftMargin)
            #expect(decoded.rightMargin == original.rightMargin)
            #expect(decoded.isDynamic == original.isDynamic)
        }

        @Test("An empty payload decodes to the defaults")
        func decodeWithMissingFields() throws {
            // Test forward compatibility - decode with minimal JSON
            let json = "{}".data(using: .utf8)!

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: json)

            // Should use default values for missing fields
            let defaultConfig = MenuBarAppearanceConfigurationV2.defaultConfiguration
            #expect(decoded.shapeKind == defaultConfig.shapeKind)
            #expect(decoded.isInset == defaultConfig.isInset)
        }

        @Test("A partial payload decodes its own fields and defaults the rest")
        func decodeWithPartialFields() throws {
            let json = """
            {
                "isDynamic": true,
                "leftMargin": 10.0,
                "rightMargin": 5.0
            }
            """.data(using: .utf8)!

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: json)

            #expect(decoded.isDynamic)
            #expect(decoded.leftMargin == 10.0)
            #expect(decoded.rightMargin == 5.0)
            // Other fields should have defaults
            #expect(decoded.shapeKind == .noShape)
        }

        // MARK: - Hashable Tests

        @Test("Two default configurations hash alike")
        func hashableIdentical() {
            let config1 = MenuBarAppearanceConfigurationV2.defaultConfiguration
            let config2 = MenuBarAppearanceConfigurationV2.defaultConfiguration

            #expect(config1.hashValue == config2.hashValue)
        }
    }

    // MARK: - MenuBarAppearanceBorderTests

    /// Tests for the border flags on ``MenuBarAppearancePartialConfiguration``,
    /// which the menu bar and the Thaw Bar read separately.
    @Suite("Border flags")
    struct MenuBarAppearanceBorderTests {
        private func partialConfiguration(
            borderOnMenuBar: Bool,
            borderOnThawBar: Bool
        ) -> MenuBarAppearancePartialConfiguration {
            var partial = MenuBarAppearancePartialConfiguration.defaultConfiguration
            partial.borderOnMenuBar = borderOnMenuBar
            partial.borderOnThawBar = borderOnThawBar
            return partial
        }

        @Test(
            "hasBorder is on when either place draws one",
            arguments: [
                (false, false, false),
                (true, false, true),
                (false, true, true),
                (true, true, true),
            ]
        )
        func hasBorderReflectsBothFlags(menuBar: Bool, thawBar: Bool, expected: Bool) {
            let partial = partialConfiguration(borderOnMenuBar: menuBar, borderOnThawBar: thawBar)

            #expect(partial.hasBorder == expected)
        }

        @Test("Setting hasBorder writes both flags", arguments: [true, false])
        func settingHasBorderWritesBothFlags(newValue: Bool) {
            var partial = MenuBarAppearancePartialConfiguration.defaultConfiguration
            partial.hasBorder = newValue

            #expect(partial.borderOnMenuBar == newValue)
            #expect(partial.borderOnThawBar == newValue)
        }

        @Test("Both flags survive a round trip")
        func encodeDecode() throws {
            let original = partialConfiguration(borderOnMenuBar: false, borderOnThawBar: true)

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(MenuBarAppearancePartialConfiguration.self, from: data)

            #expect(!decoded.borderOnMenuBar)
            #expect(decoded.borderOnThawBar)
        }

        /// Settings saved before the split carry only `hasBorder`, which drew a
        /// border in both places, so it has to seed both flags.
        @Test("A pre-split payload turns the border on in both places", arguments: [true, false])
        func decodeLegacyPayload(legacyHasBorder: Bool) throws {
            let json = Data("{\"hasBorder\": \(legacyHasBorder)}".utf8)

            let decoded = try JSONDecoder().decode(MenuBarAppearancePartialConfiguration.self, from: json)

            #expect(decoded.borderOnMenuBar == legacyHasBorder)
            #expect(decoded.borderOnThawBar == legacyHasBorder)
        }

        /// The new keys win over the legacy one, which is written on every encode
        /// so that older builds still see a border.
        @Test("The split keys take precedence over the legacy one")
        func decodePayloadWithBothKeys() throws {
            let json = Data("""
            {
                "hasBorder": true,
                "borderOnMenuBar": false,
                "borderOnThawBar": true
            }
            """.utf8)

            let decoded = try JSONDecoder().decode(MenuBarAppearancePartialConfiguration.self, from: json)

            #expect(!decoded.borderOnMenuBar)
            #expect(decoded.borderOnThawBar)
        }

        /// Downgrade safety: a build that only knows `hasBorder` has to keep
        /// showing a border for someone who enabled it on just one of the two.
        @Test("Encoding keeps the legacy key for older builds")
        func encodeKeepsLegacyKey() throws {
            let original = partialConfiguration(borderOnMenuBar: false, borderOnThawBar: true)

            let data = try JSONEncoder().encode(original)
            let object = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any]
            )

            #expect(object["hasBorder"] as? Bool == true)
        }
    }
}
