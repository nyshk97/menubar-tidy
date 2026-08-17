//
//  list-menu-bar-items.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Lists every menu bar status item window, left to right, with its bounds.
//
//  Read-only. Answers the questions a screenshot cannot: an item pushed off
//  the bar is still a window at a negative x, and a control item that macOS
//  accepted but is not rendering is still a window one point wide. Both look
//  identical to "the icon is gone".
//
//      swift scripts/list-menu-bar-items.swift
//
//  Reading the output:
//    - Thaw.ControlItem.Hidden with a ~5000pt width and everything to its
//      left at a negative x is the push-out working.
//    - Thaw.ControlItem.Visible at width 1 means the app's own icon was
//      collapsed by hideIceIconCompletely(), i.e. ShowIceIcon is false.
//      Width ~33 is a rendered icon.
//

import AppKit

// optionAll rather than optionOnScreenOnly: items pushed off the bar are the
// ones worth seeing, and they are by definition not on screen.
guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
    print("failed to read the window list")
    exit(1)
}

struct Row {
    let x: CGFloat
    let width: CGFloat
    let owner: String
    let name: String
    let windowID: Int
    let isOnScreen: Bool
}

// Layer 25 is the status item layer. Menus, the menu bar itself and ordinary
// windows all sit elsewhere.
let statusItemLayer = 25

var rows: [Row] = []
for window in raw {
    guard
        let layer = window[kCGWindowLayer as String] as? Int,
        layer == statusItemLayer,
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
    else {
        continue
    }
    rows.append(Row(
        x: bounds["X"] ?? 0,
        width: bounds["Width"] ?? 0,
        owner: (window[kCGWindowOwnerName as String] as? String) ?? "?",
        name: (window[kCGWindowName as String] as? String) ?? "",
        windowID: (window[kCGWindowNumber as String] as? Int) ?? -1,
        isOnScreen: (window[kCGWindowIsOnscreen as String] as? Bool) ?? false
    ))
}

func pad(_ string: String, _ width: Int) -> String {
    string.count >= width ? string : string + String(repeating: " ", count: width - string.count)
}

for screen in NSScreen.screens {
    let id = (screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    print("screen \(id): \(CGDisplayBounds(id))  notchInset=\(screen.safeAreaInsets.top)")
}
print("")
print(pad("wid", 8) + pad("x", 11) + pad("width", 10) + pad("onscreen", 10) + pad("owner", 26) + "name")
for row in rows.sorted(by: { $0.x < $1.x }) {
    print(
        pad(String(row.windowID), 8)
            + pad(String(format: "%.1f", Double(row.x)), 11)
            + pad(String(format: "%.1f", Double(row.width)), 10)
            + pad(row.isOnScreen ? "yes" : "NO", 10)
            + pad(row.owner, 26)
            + row.name
    )
}
print("\ntotal: \(rows.count) status item windows")
