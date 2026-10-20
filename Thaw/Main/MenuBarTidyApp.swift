//
//  MenuBarTidyApp.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import AppKit

/// The process entry point. A plain AppKit app: one status item and its menu,
/// no windows (`LSUIElement`).
@main
enum MenuBarTidyApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // `NSApplication.delegate` is weak; keep the delegate alive for the run.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
