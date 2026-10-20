//
//  MenuBarItem.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import ApplicationServices
import CoreGraphics

/// What we know about one menu bar item, read from the owning app's
/// `AXExtrasMenuBar`. Plain values only, so the rules that decide how an item is
/// listed can be tested without a live accessibility element.
nonisolated struct ItemInfo: Equatable, Sendable {
    /// The process that owns the item (for Control Center's items, Control Center).
    var pid: pid_t
    var bundleID: String?
    var appName: String
    /// `AXIdentifier`. Control Center's items have one (`com.apple.menuextra.wifi`
    /// and so on); third-party items usually do not.
    var identifier: String?
    /// `AXDescription`. The app name, empty, or something specific like `Wi‑Fi`.
    var axDescription: String
    /// `AXTitle`. Sometimes an SF Symbol name (`character.bubble.fill`).
    var axTitle: String
    /// The item's frame in global CG coordinates (main screen's top-left is the
    /// origin, y grows downward), the same space `CGWindowList` uses.
    var frame: CGRect
    var isEnabled: Bool
    /// The item's position among its app's items, as the app reports them.
    var indexInApp: Int
}

/// A menu bar item together with the accessibility element that presses it.
///
/// `AXUIElement` is not `Sendable`, but the accessibility API is safe to call
/// from any thread, and the press has to happen off the main thread (a press
/// that opens an `NSMenu` blocks until the menu closes).
nonisolated struct MenuBarItem: @unchecked Sendable {
    let info: ItemInfo
    let element: AXUIElement
}
