//
//  ItemPresser.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import AppKit
import ApplicationServices

/// Opens a menu bar item by sending it `AXPress`.
///
/// The item opens its menu (or panel) at its own position. For an item hidden
/// behind the notch or under the frontmost app's menus, that is just below the
/// menu bar, where the user can see it. Nothing is moved.
enum ItemPresser {
    /// How long to wait before pressing, so this app's own menu has finished
    /// closing and the item's menu does not open underneath it.
    static let delay: TimeInterval = 0.15

    static func press(_ item: MenuBarItem) {
        let target = resolve(item)
        let label = target.info.appName
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            // Pressing an item that opens an `NSMenu` does not return until the
            // menu closes; after the timeout the call gives up with
            // `kAXErrorCannotComplete` while the menu stays open. That is the
            // normal outcome, not a failure — and why this is off the main thread.
            AXUIElementSetMessagingTimeout(target.element, 1.0)
            let error = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
            switch error {
            case .success, .cannotComplete:
                Log.press.debug("Pressed \(label, privacy: .public) (\(error.rawValue))")
            default:
                Log.press.error("Pressing \(label, privacy: .public) failed: \(error.rawValue)")
            }
        }
    }

    /// The item to press: `item` itself if its element still works, otherwise
    /// the same item read again from the app (which may have relaunched with a
    /// new process).
    private static func resolve(_ item: MenuBarItem) -> MenuBarItem {
        AXUIElementSetMessagingTimeout(item.element, ItemScanner.messagingTimeout)
        var role: AnyObject?
        guard AXUIElementCopyAttributeValue(item.element, kAXRoleAttribute as CFString, &role) == .invalidUIElement else {
            return item
        }
        let apps = item.info.bundleID.map(NSRunningApplication.runningApplications(withBundleIdentifier:))
            ?? [NSRunningApplication(processIdentifier: item.info.pid)].compactMap(\.self)
        for app in apps {
            let candidates = ItemScanner.readItems(pid: app.processIdentifier, bundleID: app.bundleIdentifier, appName: item.info.appName)
            if let index = ItemRules.match(item.info, among: candidates.map(\.info)) {
                Log.press.debug("Re-read \(item.info.appName, privacy: .public) before pressing")
                return candidates[index]
            }
        }
        return item
    }
}
