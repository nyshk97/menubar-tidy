//
//  ItemRules.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Whether an item can be seen in the menu bar, and if not, whether pressing it
/// can still open something the user can see.
///
/// macOS lays status items out right to left without gaps, whether they fit or
/// not. An item that does not fit keeps a real position: behind the notch or
/// under the frontmost app's menus, where it is hidden but where its menu still
/// opens visibly when pressed. Only an item pushed past the screen's left edge
/// opens its menu off screen.
nonisolated enum ItemVisibility: Equatable, Sendable {
    /// Not covered by anything. The user can click it directly.
    case visible
    /// Covered by the notch or by the frontmost app's menus. Its menu still
    /// opens on screen when pressed.
    case hidden
    /// Past the screen's left edge. Pressing it opens its menu off screen.
    case offScreen

    /// Classifies an item, checking off-screen first.
    ///
    /// - Parameters:
    ///   - frame: The item's frame in global CG coordinates.
    ///   - screen: The screen whose menu bar the list was opened from.
    ///   - appMenusMaxX: The right edge of the frontmost app's menus on that
    ///     screen, if known.
    static func classify(_ frame: CGRect, on screen: ScreenGeometry, appMenusMaxX: CGFloat?) -> ItemVisibility {
        // An item even partly past the left edge opens its menu at least
        // partly off screen.
        if frame.minX < screen.frame.minX || frame.minX >= screen.frame.maxX {
            return .offScreen
        }
        if let notch = screen.notch, frame.maxX > notch.lowerBound, frame.minX < notch.upperBound {
            return .hidden
        }
        if let appMenusMaxX, frame.minX < appMenusMaxX {
            return .hidden
        }
        return .visible
    }
}

/// Which items go in the list, and what they are called.
nonisolated enum ItemRules {
    static let controlCenterBundleID = "com.apple.controlcenter"

    /// Whether an item belongs in the list.
    ///
    /// Left out: this app's own items, disabled items (an old divider, Control
    /// Center's empty placeholders), zero-size items, and items outside every
    /// screen's menu bar strip. The last are the ones the user turned off in
    /// System Settings › Menu Bar; accessibility parks them at (-1, 981).
    static func isListed(_ info: ItemInfo, screens: [ScreenGeometry], ownPID: pid_t) -> Bool {
        guard info.pid != ownPID, info.isEnabled, info.frame.width > 0, info.frame.height > 0 else {
            return false
        }
        return screens.contains { $0.isInMenuBarBand(info.frame) }
    }

    /// The screen whose menu bar the items are on.
    ///
    /// Accessibility reports the items of one menu bar only — the active one,
    /// on the screen with keyboard focus — so the items, not this app's icon,
    /// say which screen to judge them against. Falls back to `fallback` (the
    /// screen this app's icon is on) when no item sits in any screen's strip.
    static func screen(for items: [ItemInfo], among screens: [ScreenGeometry], fallback: ScreenGeometry) -> ScreenGeometry {
        let counts = screens.map { screen in items.count { screen.isInMenuBarBand($0.frame) } }
        guard let best = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[best] > 0 else {
            return fallback
        }
        return screens[best]
    }

    /// The name shown for an item.
    ///
    /// - Control Center's items and other Apple processes: the item's own
    ///   description (`Wi‑Fi、インターネット共有`, `日本語`), since their process
    ///   names (`コントロールセンター`, `TextInputMenuAgent`) say nothing.
    /// - Everyone else: the app's name, plus a detail when the app shows more
    ///   than one item.
    static func title(for info: ItemInfo, siblingCount: Int) -> String {
        if info.bundleID?.hasPrefix("com.apple.") == true {
            return usableDetail(info) ?? info.appName
        }
        guard siblingCount > 1 else {
            return info.appName
        }
        let detail = usableDetail(info) ?? "\(info.indexInApp + 1)"
        return "\(info.appName)（\(detail)）"
    }

    /// The description, else the title, as long as it says something the app
    /// name does not and is not an SF Symbol name.
    private static func usableDetail(_ info: ItemInfo) -> String? {
        for candidate in [info.axDescription, info.axTitle] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != info.appName, !isSymbolName(trimmed) {
                return trimmed
            }
        }
        return nil
    }

    /// Whether a string looks like an SF Symbol name (`character.bubble.fill`),
    /// which some apps put in their item's title.
    static func isSymbolName(_ string: String) -> Bool {
        string.range(of: #"^[a-z0-9]+(\.[a-z0-9]+)+$"#, options: .regularExpression) != nil
    }

    /// Finds the item that is `original` again among an app's freshly read
    /// items (after the app relaunched, for example). Tries the identifier, then
    /// the description and title, then the position.
    static func match(_ original: ItemInfo, among candidates: [ItemInfo]) -> Int? {
        if let identifier = original.identifier,
           let index = candidates.firstIndex(where: { $0.identifier == identifier })
        {
            return index
        }
        if !(original.axDescription.isEmpty && original.axTitle.isEmpty),
           let index = candidates.firstIndex(where: {
               $0.axDescription == original.axDescription && $0.axTitle == original.axTitle
           })
        {
            return index
        }
        return candidates.firstIndex { $0.indexInApp == original.indexInApp }
    }

    /// An SF Symbol for a Control Center item, by its `AXIdentifier`.
    static func symbolName(forControlCenterIdentifier identifier: String?) -> String? {
        guard let identifier, identifier.hasPrefix("com.apple.menuextra.") else {
            return nil
        }
        switch identifier.dropFirst("com.apple.menuextra.".count) {
        case "battery": return "battery.100"
        case "wifi": return "wifi"
        case "bluetooth": return "antenna.radiowaves.left.and.right"
        case "now-playing": return "play.circle"
        case "controlcenter": return "switch.2"
        case "clock": return "clock"
        case "focusmodes", "focus", "dnd": return "moon"
        case "sound", "volume": return "speaker.wave.2"
        case "display": return "display"
        case "airdrop": return "airplayaudio"
        case "screenmirroring": return "rectangle.on.rectangle"
        case "keyboardbrightness": return "light.max"
        case "user", "fastuserswitching": return "person.crop.circle"
        default: return nil
        }
    }
}
