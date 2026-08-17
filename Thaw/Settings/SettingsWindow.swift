//
//  SettingsWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsWindow

struct SettingsWindow: Scene {
    @Bindable var appState: AppState

    var body: some Scene {
        IceWindow(id: .settings) {
            SettingsView(appState: appState, navigationState: appState.navigationState)
                .frame(minWidth: 850, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 950, height: 650)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .environment(appState)
    }
}
