//
//  IceBarLocation.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Locations where the Thaw Bar can appear.
nonisolated enum IceBarLocation: Int, CaseIterable, Codable, Identifiable {
    /// The Thaw Bar will appear in different locations based on context.
    case dynamic = 0

    /// The Thaw Bar will appear centered below the mouse pointer.
    case mousePointer = 1

    /// The Thaw Bar will appear centered below the Ice icon.
    case iceIcon = 2

    /// The Thaw Bar will appear aligned to the left edge of the display.
    case leftAligned = 3

    /// The Thaw Bar will appear aligned to the right edge of the display.
    case rightAligned = 4

    var id: Int {
        rawValue
    }

    /// The name as shown in the UI.
    var localized: String {
        switch self {
        case .dynamic: "ダイナミック"
        case .mousePointer: "マウスポインター"
        case .iceIcon: "\(Constants.displayName) アイコン"
        case .leftAligned: "左揃え"
        case .rightAligned: "右揃え"
        }
    }

    /// Parses an IceBarLocation from a string value.
    /// Supports exact case names: "dynamic", "mousePointer", "iceIcon"
    /// Or raw integer values: "0", "1", "2"
    static func fromString(_ value: String) -> IceBarLocation? {
        switch value {
        case "dynamic", "0":
            return .dynamic
        case "mousePointer", "1":
            return .mousePointer
        case "iceIcon", "2":
            return .iceIcon
        case "leftAligned", "3":
            return .leftAligned
        case "rightAligned", "4":
            return .rightAligned
        default:
            return nil
        }
    }
}
