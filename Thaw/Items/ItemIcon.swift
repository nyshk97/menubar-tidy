//
//  ItemIcon.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import AppKit

/// The picture shown next to an item in the list.
///
/// The item's real menu bar glyph cannot be read without the Screen Recording
/// permission, so the owning app's icon stands in for it. Control Center's items
/// all belong to Control Center, so they get an SF Symbol by identifier instead.
enum ItemIcon {
    private static let size = NSSize(width: 16, height: 16)
    private static var appIcons: [pid_t: NSImage] = [:]

    static func image(for info: ItemInfo) -> NSImage? {
        if info.bundleID == ItemRules.controlCenterBundleID,
           let name = ItemRules.symbolName(forControlCenterIdentifier: info.identifier),
           let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        {
            return symbol
        }
        if let cached = appIcons[info.pid] {
            return cached
        }
        guard let icon = NSRunningApplication(processIdentifier: info.pid)?.icon?.copy() as? NSImage else {
            return nil
        }
        icon.size = size
        appIcons[info.pid] = icon
        return icon
    }
}
