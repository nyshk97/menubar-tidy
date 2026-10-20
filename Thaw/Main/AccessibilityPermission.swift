//
//  AccessibilityPermission.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import AppKit
import ApplicationServices

/// The one permission this app needs: Accessibility, to read menu bar items and
/// press them.
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system's prompt (which offers to open System Settings) if the
    /// permission has not been granted.
    static func request() {
        // The literal value of `kAXTrustedCheckOptionPrompt`; the imported
        // global is a mutable C variable that strict concurrency rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings › Privacy & Security › Accessibility.
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
