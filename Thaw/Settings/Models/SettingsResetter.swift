//
//  SettingsResetter.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension AppSettings {
    /// Resets all settings to their default values.
    func resetAllSettingsToDefaults() {
        resetGeneral()
        resetAdvanced()
        resetDisplay()
        // Not a setting, but a learned verdict about the user's other apps.
        // A reset is the one moment they explicitly ask for a clean slate,
        // and it is the only way to clear a record from the UI.
        appState?.itemManager.failureLedger.removeAll()
    }

    /// Resets General settings to their default values.
    func resetGeneral() {
        general.showIceIcon = Defaults.DefaultValue.showIceIcon
        general.iceIcon = Defaults.DefaultValue.iceIcon
        general.lastCustomIceIcon = nil
        general.customIceIconIsTemplate = Defaults.DefaultValue.customIceIconIsTemplate
        general.useIceBar = Defaults.DefaultValue.useIceBar
        general.useIceBarOnlyOnNotchedDisplay = Defaults.DefaultValue.useIceBarOnlyOnNotchedDisplay
        general.iceBarLocation = Defaults.DefaultValue.iceBarLocation
        general.iceBarLocationOnHotkey = Defaults.DefaultValue.iceBarLocationOnHotkey
        general.showOnClick = Defaults.DefaultValue.showOnClick
        general.showOnDoubleClick = Defaults.DefaultValue.showOnDoubleClick
        general.autoRehide = Defaults.DefaultValue.autoRehide
        general.rehideStrategy = Defaults.DefaultValue.rehideStrategy
        general.rehideInterval = Defaults.DefaultValue.rehideInterval
    }

    /// Resets Advanced settings to their default values.
    func resetAdvanced() {
        advanced.enableAlwaysHiddenSection = Defaults.DefaultValue.enableAlwaysHiddenSection
        advanced.useOptionClickToShowAlwaysHiddenSection = Defaults.DefaultValue.useOptionClickToShowAlwaysHiddenSection
        advanced.useDoubleClickToShowAlwaysHiddenSection = Defaults.DefaultValue.useDoubleClickToShowAlwaysHiddenSection
        advanced.showAllSectionsOnUserDrag = Defaults.DefaultValue.showAllSectionsOnUserDrag
        appState?.itemManager.updateNewItemsPlacement(section: .hidden, arrangedViews: [])
        advanced.hideApplicationMenus = Defaults.DefaultValue.hideApplicationMenus
        advanced.enableSecondaryContextMenu = Defaults.DefaultValue.enableSecondaryContextMenu
        advanced.enableSecondaryContextMenuQuit = Defaults.DefaultValue.enableSecondaryContextMenuQuit
        advanced.tooltipDelay = Defaults.DefaultValue.tooltipDelay
        advanced.enableDiagnosticLogging = Defaults.DefaultValue.enableDiagnosticLogging
        advanced.useAXClickDelivery = Defaults.DefaultValue.useAXClickDelivery
    }

    /// Resets Display settings to their default values.
    func resetDisplay() {
        displaySettings.configurations = Defaults.DefaultValue.displayIceBarConfigurations
        displaySettings.globalConfiguration = Defaults.DefaultValue.globalDisplayConfiguration
        displaySettings.confirmSpacingRelaunch = Defaults.DefaultValue.confirmSpacingRelaunch
        displaySettings.unconfirmedSpacingProfileScope = Defaults.DefaultValue.unconfirmedSpacingProfileScope
    }
}
