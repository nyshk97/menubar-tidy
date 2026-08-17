//
//  PermissionsWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The window that hosts the permissions decision.
struct PermissionsWindow: Scene {
    let appState: AppState

    var body: some Scene {
        IceWindow(id: .permissions) {
            permissionsContent
                .onWindowChange { window in
                    guard let window else {
                        return
                    }
                    window.standardWindowButton(.closeButton)?.isHidden = true
                    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                    window.standardWindowButton(.zoomButton)?.isHidden = true
                    if let contentView = window.contentView {
                        withMutableCopy(of: contentView.safeAreaInsets) { insets in
                            insets.bottom = -insets.bottom
                            insets.left = -insets.left
                            insets.right = -insets.right
                            insets.top = -insets.top
                            contentView.additionalSafeAreaInsets = insets
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .environment(appState)
    }

    /// Upstream showed a feature tour ahead of this on first launch, and this
    /// screen alone afterwards. This fork dropped the tour, so both occasions
    /// land here.
    ///
    /// Quit is supplied only here: this window hides its close, minimize and
    /// zoom buttons, and Continue is disabled until the required permissions
    /// are granted, so it is the only way out for a user who declines.
    private var permissionsContent: some View {
        PermissionsView(
            onContinue: { appState.completeFirstLaunchSetup() },
            onQuit: { NSApp.terminate(nil) }
        )
        .frame(width: PermissionsWindowMetrics.width, height: PermissionsWindowMetrics.height)
        .environment(appState.permissions)
    }
}
