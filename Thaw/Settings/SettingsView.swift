//
//  SettingsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The settings window's only screen.
///
/// Upstream puts nine panes behind a `NavigationSplitView` sidebar, with a
/// search field over them and back/forward toolbar buttons to step between
/// them. This fork keeps one pane — the menu bar layout editor — leaving the
/// sidebar, the search and the navigation with a single destination to move
/// between, so they are gone.
struct SettingsView: View {
    let appState: AppState

    var body: some View {
        MenuBarLayoutSettingsPane(
            itemManager: appState.itemManager,
            advancedSettings: appState.settings.advanced
        )
        // No `navigationTitle`: with a single pane, naming the pane says nothing
        // the content does not, and the window falls back to the scene title
        // (`IceWindowIdentifier.title` = the app's display name), which is what
        // identifies the window in Mission Control and the Window menu.
        //
        // The window is the only place the app surfaces itself, so the running
        // version belongs where it is visible without hunting for it.
        .navigationSubtitle("ver \(Constants.versionString)")
    }
}
