//
//  AppNavigationState.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation

/// The model for app-wide navigation.
@MainActor
@Observable
final class AppNavigationState {
    var isAppFrontmost = false
    var isSettingsPresented = false
    var isIceBarPresented = false
}
