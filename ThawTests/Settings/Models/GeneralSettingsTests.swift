//
//  GeneralSettingsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``GeneralSettings``' setup surface: the `Defaults` load performed by
/// `performSetup(with:)` and the Settings-URI notification it subscribes to.
///
/// Both halves are trust boundaries of a sort. The load reads whatever is in
/// `UserDefaults` — possibly written by an older build, a hand-edited plist, or
/// a partially failed import — so an unrecognized enum raw value or undecodable
/// icon payload has to leave the shipped default standing rather than crash or
/// blank the icon. The notification arrives on behalf of a *third-party app*
/// that sent a `thaw://` URL, so a key this model does not own, or a payload of
/// the wrong type, must be dropped.
///
/// `SettingsURIHandlerApplyTests` covers the sending side of the same
/// notification; the two suites have to agree on the `userInfo` shape.
///
/// The model persists through `didSet` and `Defaults` is hardcoded to
/// `.standard`, so the suite snapshots the keys it touches and restores them
/// afterwards.
///
/// Snapshotting the *keys* rather than the whole persistent domain is
/// deliberate: suites run concurrently, so a whole-domain snapshot taken while
/// another suite holds scratch values captures them, and restoring it writes
/// them back over the developer's own settings. Restoring one model's keys
/// cannot reach anything this suite did not write.
@MainActor
@Suite("General settings", .serialized)
final class GeneralSettingsTests {
    /// The keys this suite reads and writes.
    private static let touchedKeys: [Defaults.Key] = [
        .showIceIcon,
        .iceIcon,
        .customIceIconIsTemplate,
        .useIceBar,
        .useIceBarOnlyOnNotchedDisplay,
        .iceBarLocation,
        .iceBarLocationOnHotkey,
        .showOnClick,
        .showOnDoubleClick,
        .autoRehide,
        .rehideStrategy,
        .rehideInterval,
    ]

    private let savedDefaults: [Defaults.Key: Any?]

    init() {
        savedDefaults = Dictionary(
            uniqueKeysWithValues: Self.touchedKeys.map { ($0, Defaults.object(forKey: $0)) }
        )
    }

    /// Isolated so the non-Sendable snapshot is reachable here; the suite is
    /// already `@MainActor`.
    @MainActor
    deinit {
        for (key, value) in savedDefaults {
            if let value {
                Defaults.set(value, forKey: key)
            } else {
                Defaults.removeObject(forKey: key)
            }
        }
    }

    /// Returns a model that has run its setup against the current `Defaults`.
    ///
    /// The app state is unused by this model, so setup runs without one.
    private func makeSettings() -> GeneralSettings {
        let settings = GeneralSettings()
        settings.performSetup()
        return settings
    }

    /// Removes every key the model loads, so a test starts from the state of a
    /// first launch rather than from the developer's own settings.
    private func clearStoredSettings() {
        for key in Self.touchedKeys {
            Defaults.removeObject(forKey: key)
        }
    }

    // MARK: Initial load

    @Test("Stored values are loaded into the model")
    func storedValuesAreLoaded() {
        clearStoredSettings()
        Defaults.set(false, forKey: .showIceIcon)
        Defaults.set(true, forKey: .customIceIconIsTemplate)
        Defaults.set(true, forKey: .useIceBar)
        Defaults.set(true, forKey: .useIceBarOnlyOnNotchedDisplay)
        Defaults.set(true, forKey: .iceBarLocationOnHotkey)
        Defaults.set(false, forKey: .showOnClick)
        Defaults.set(false, forKey: .showOnDoubleClick)
        Defaults.set(false, forKey: .autoRehide)
        Defaults.set(42.5, forKey: .rehideInterval)

        let settings = makeSettings()

        #expect(!settings.showIceIcon)
        #expect(settings.customIceIconIsTemplate)
        #expect(settings.useIceBar)
        #expect(settings.useIceBarOnlyOnNotchedDisplay)
        #expect(settings.iceBarLocationOnHotkey)
        #expect(!settings.showOnClick)
        #expect(!settings.showOnDoubleClick)
        #expect(!settings.autoRehide)
        #expect(settings.rehideInterval == 42.5)
    }

    @Test("Absent keys leave the shipped defaults in place")
    func absentKeysLeaveTheDefaults() {
        clearStoredSettings()

        let settings = makeSettings()

        #expect(settings.showIceIcon == Defaults.DefaultValue.showIceIcon)
        #expect(settings.iceIcon == Defaults.DefaultValue.iceIcon)
        #expect(settings.customIceIconIsTemplate == Defaults.DefaultValue.customIceIconIsTemplate)
        #expect(settings.useIceBar == Defaults.DefaultValue.useIceBar)
        #expect(settings.iceBarLocation == Defaults.DefaultValue.iceBarLocation)
        #expect(settings.showOnClick == Defaults.DefaultValue.showOnClick)
        #expect(settings.autoRehide == Defaults.DefaultValue.autoRehide)
        #expect(settings.rehideStrategy == Defaults.DefaultValue.rehideStrategy)
        #expect(settings.rehideInterval == Defaults.DefaultValue.rehideInterval)
        #expect(settings.lastCustomIceIcon == nil)
    }

    @Test("Stored enum raw values are loaded")
    func storedEnumRawValuesAreLoaded() {
        clearStoredSettings()
        Defaults.set(IceBarLocation.leftAligned.rawValue, forKey: .iceBarLocation)
        Defaults.set(RehideStrategy.focusedApp.rawValue, forKey: .rehideStrategy)

        let settings = makeSettings()

        #expect(settings.iceBarLocation == .leftAligned)
        #expect(settings.rehideStrategy == .focusedApp)
    }

    @Test("An unrecognized enum raw value leaves the default in place")
    func unrecognizedEnumRawValueIsIgnored() {
        clearStoredSettings()
        Defaults.set(99, forKey: .iceBarLocation)
        Defaults.set(-1, forKey: .rehideStrategy)

        let settings = makeSettings()

        #expect(settings.iceBarLocation == Defaults.DefaultValue.iceBarLocation)
        #expect(settings.rehideStrategy == Defaults.DefaultValue.rehideStrategy)
    }

    @Test("A stored custom icon is loaded and remembered as the last custom icon")
    func storedCustomIconIsLoaded() throws {
        clearStoredSettings()
        let custom = ControlItemImageSet(name: .custom, image: .symbol("star"))
        let data = try JSONEncoder().encode(custom)
        Defaults.set(data, forKey: .iceIcon)

        let settings = makeSettings()

        #expect(settings.iceIcon == custom)
        #expect(settings.lastCustomIceIcon == custom)
    }

    @Test("A stored built-in icon is loaded without becoming the last custom icon")
    func storedBuiltInIconIsNotRemembered() throws {
        clearStoredSettings()
        let builtIn = ControlItemImageSet(name: .dot, image: .symbol("circle.fill"))
        let data = try JSONEncoder().encode(builtIn)
        Defaults.set(data, forKey: .iceIcon)

        let settings = makeSettings()

        #expect(settings.iceIcon == builtIn)
        #expect(settings.lastCustomIceIcon == nil)
    }

    @Test("Undecodable icon data leaves the default icon in place")
    func undecodableIconDataIsIgnored() {
        clearStoredSettings()
        Defaults.set(Data("not an icon".utf8), forKey: .iceIcon)

        let settings = makeSettings()

        #expect(settings.iceIcon == Defaults.DefaultValue.iceIcon)
        #expect(settings.lastCustomIceIcon == nil)
    }

    // MARK: Persistence

    @Test("A property change is written straight through to Defaults")
    func propertyChangesArePersisted() {
        clearStoredSettings()
        let settings = makeSettings()

        settings.customIceIconIsTemplate = true
        settings.rehideInterval = 77
        settings.rehideStrategy = .timed
        settings.iceBarLocation = .mousePointer

        #expect(Defaults.bool(forKey: .customIceIconIsTemplate))
        #expect(Defaults.double(forKey: .rehideInterval) == 77)
        #expect(Defaults.integer(forKey: .rehideStrategy) == RehideStrategy.timed.rawValue)
        #expect(Defaults.integer(forKey: .iceBarLocation) == IceBarLocation.mousePointer.rawValue)
    }

    @Test("Stored values survive a reload")
    func storedValuesRoundTrip() {
        clearStoredSettings()
        let settings = makeSettings()
        settings.customIceIconIsTemplate = true
        settings.rehideStrategy = .timed

        let reloaded = makeSettings()

        #expect(reloaded.customIceIconIsTemplate)
        #expect(reloaded.rehideStrategy == .timed)
    }
}
