//
//  ItemPositionDriftGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Characterizes the position-drift gate in `cacheItemsIfNeeded`.
///
/// The windowID gate cannot see a move: a layout-editor drag keeps every
/// windowID and only changes where the windows sit. When the recache that
/// follows the drag is discarded (mid expand/collapse, or skipped behind a
/// pass already in flight), the editor kept showing the pre-drag layout until
/// a window happened to appear or vanish. This gate compares positions so the
/// next poll catches up instead.
@Suite("Item position drift gate")
struct ItemPositionDriftGateTests {
    @Test("Identical positions do not fire")
    func unchangedDoesNotFire() {
        #expect(
            MenuBarItemManager.firstDriftedWindowID(
                previous: [10: 1200, 11: 1240],
                current: [10: 1200, 11: 1240]
            ) == nil
        )
    }

    @Test("A window at a new x fires and is reported")
    func movedWindowFires() {
        #expect(
            MenuBarItemManager.firstDriftedWindowID(
                previous: [10: 1200, 11: -3900],
                current: [10: 1200, 11: 1240]
            ) == 11
        )
    }

    /// Additions and removals belong to the windowID gate, and a window whose
    /// bounds failed to read on one side is absent, not moved.
    @Test("Windows present on only one side are ignored")
    func oneSidedWindowsAreIgnored() {
        #expect(
            MenuBarItemManager.firstDriftedWindowID(
                previous: [10: 1200, 12: 900],
                current: [10: 1200, 13: 700]
            ) == nil
        )
    }

    /// Nothing recorded yet (first poll after launch or after a cache reset)
    /// must not read as motion.
    @Test("An empty previous reading does not fire")
    func emptyPreviousDoesNotFire() {
        #expect(
            MenuBarItemManager.firstDriftedWindowID(
                previous: [:],
                current: [10: 1200]
            ) == nil
        )
    }
}
