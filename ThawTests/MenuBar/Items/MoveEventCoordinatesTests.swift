//
//  MoveEventCoordinatesTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Regression tests for the synthetic event coordinates used to move menu bar items.
@Suite("Move event coordinates")
struct MoveEventCoordinatesTests {
    /// Off-screen destinations preserve their horizontal edge while keeping the
    /// event away from the top-left Hot Corner.
    @Test("An off-screen destination keeps its horizontal edge and uses the bounds midpoint")
    func offscreenTargetPointsUseBoundsMidpoint() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let bounds = CGRect(x: -4193, y: 0, width: 22, height: 33)
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 100,
            bounds: bounds,
            isOnScreen: false
        )

        #expect(
            MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.minX, y: bounds.midY)
        )
        #expect(
            MenuBarItemManager.MoveDestination.rightOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.maxX, y: bounds.midY)
        )
    }

    /// #923: dropping onto the exact coordinate of a zero-width section
    /// divider leaves AppKit free to choose either side. The field log showed
    /// `.leftOfItem(AH_ctrl)` repeatedly landing one point to its right.
    @Test("A control-item destination biases the drop into the requested section")
    func controlItemTargetPointUsesRequestedSide() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let bounds = CGRect(x: -9465, y: 0, width: 0, height: 33)
        let target = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 32278,
            bounds: bounds,
            isOnScreen: false
        )

        #expect(
            MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.minX - 1, y: bounds.midY)
        )
        #expect(
            MenuBarItemManager.MoveDestination.rightOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.maxX + 1, y: bounds.midY)
        )
    }

    /// A control item with actual width (e.g. an expanded divider) already
    /// gives AppKit enough hit-test span to disambiguate the side, so the
    /// ±1 bias must not fire and shift the drop point away from the edge.
    @Test("A wide control-item destination gets no section bias")
    func wideControlItemTargetPointGetsNoBias() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let bounds = CGRect(x: -9465, y: 0, width: 10, height: 33)
        let target = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 32279,
            bounds: bounds,
            isOnScreen: false
        )

        #expect(
            MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.minX, y: bounds.midY)
        )
        #expect(
            MenuBarItemManager.MoveDestination.rightOfItem(target).targetPoint(
                in: bounds,
                on: displayBounds
            ) == CGPoint(x: bounds.maxX, y: bounds.midY)
        )
    }

    /// hard-coded primary-display inset.
    @Test("The safe vertical coordinate comes from the target on a vertically offset display")
    func targetPointUsesMidpointOnVerticallyOffsetDisplay() {
        let displayBounds = CGRect(x: 1200, y: -900, width: 1920, height: 1080)
        let bounds = CGRect(x: -4193, y: -900, width: 24, height: 24)
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 101,
            bounds: bounds
        )

        let point = MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
            in: bounds,
            on: displayBounds
        )

        #expect(point == CGPoint(x: bounds.minX, y: bounds.midY))
        #expect(point.y != bounds.minY)
    }

    /// On-screen moves retain their existing top-edge coordinate because those
    /// moves still physically warp the cursor before posting events.
    @Test("An on-screen destination keeps its existing top-edge coordinate")
    func onscreenTargetPointPreservesExistingYCoordinate() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let bounds = CGRect(x: 1100, y: 0, width: 24, height: 33)
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 102,
            bounds: bounds
        )

        let point = MenuBarItemManager.MoveDestination.leftOfItem(target).targetPoint(
            in: bounds,
            on: displayBounds
        )

        #expect(point == CGPoint(x: bounds.minX, y: bounds.minY))
    }

    /// The gap between the notch and the leftmost status item is the widest
    /// stretch of menu bar that reacts to nothing, so it is preferred. Aiming
    /// at the notch instead is what made a notch utility (NotchDrop) open its
    /// panel on every move into the hidden section.
    @Test("An off-screen mouse-down aims at the span between the notch and the leftmost item")
    func offscreenMouseDownPrefersTheSpanRightOfTheNotch() {
        let notchFrameAppKit = CGRect(x: 763, y: 1074, width: 185, height: 33)
        let targetPointCoreGraphics = CGPoint(x: -3714, y: 16.5)

        let point = MenuBarItemManager.offscreenMoveMouseDownPoint(
            notchFrameAppKit: notchFrameAppKit,
            displayBounds: CGRect(x: 0, y: 0, width: 1710, height: 1107),
            applicationMenuMaxX: 400,
            menuBarItemBounds: [
                CGRect(x: 1303, y: 0, width: 35, height: 33),
                CGRect(x: 1382, y: 0, width: 33, height: 33),
            ],
            targetPointCoreGraphics: targetPointCoreGraphics
        )

        // (948 + 8) ... (1303 - 8), midpoint.
        #expect(point == CGPoint(x: 1125.5, y: targetPointCoreGraphics.y))
        // The notch frame comes from AppKit, so only its horizontal position
        // is safe to reuse in a Core Graphics event.
        #expect(point.y != notchFrameAppKit.midY)
    }

    /// A status item parked right against the notch leaves no room on that
    /// side, so the span between the application menu and the notch is used.
    @Test("An off-screen mouse-down falls back to the span left of the notch")
    func offscreenMouseDownFallsBackToTheSpanLeftOfTheNotch() {
        let notchFrameAppKit = CGRect(x: 763, y: 1074, width: 185, height: 33)

        let point = MenuBarItemManager.offscreenMoveMouseDownPoint(
            notchFrameAppKit: notchFrameAppKit,
            displayBounds: CGRect(x: 0, y: 0, width: 1710, height: 1107),
            applicationMenuMaxX: 400,
            menuBarItemBounds: [CGRect(x: 950, y: 0, width: 35, height: 33)],
            targetPointCoreGraphics: CGPoint(x: -3714, y: 16.5)
        )

        // (400 + 8) ... (763 - 8), midpoint.
        #expect(point.x == 581.5)
    }

    /// An item overlapping the notch's edge bounds neither span, so the
    /// candidate it covers has to be rejected on its own.
    @Test("An off-screen mouse-down skips a span covered by an item that overlaps the notch")
    func offscreenMouseDownSkipsASpanCoveredByAnOverlappingItem() {
        let notchFrameAppKit = CGRect(x: 763, y: 1074, width: 185, height: 33)

        let point = MenuBarItemManager.offscreenMoveMouseDownPoint(
            notchFrameAppKit: notchFrameAppKit,
            displayBounds: CGRect(x: 0, y: 0, width: 1710, height: 1107),
            applicationMenuMaxX: 400,
            menuBarItemBounds: [
                CGRect(x: 940, y: 0, width: 300, height: 33),
                CGRect(x: 1303, y: 0, width: 35, height: 33),
            ],
            targetPointCoreGraphics: CGPoint(x: -3714, y: 16.5)
        )

        #expect(point.x == 581.5)
    }

    /// With both spans too narrow the notch remains the last resort: a click
    /// there still hit-tests against nothing in the OS, which is what the
    /// screen-corner fix (#774) needed.
    @Test("An off-screen mouse-down falls back to the notch when no span is wide enough")
    func offscreenMouseDownFallsBackToTheNotch() {
        let notchFrameAppKit = CGRect(x: 763, y: 1074, width: 185, height: 33)

        let point = MenuBarItemManager.offscreenMoveMouseDownPoint(
            notchFrameAppKit: notchFrameAppKit,
            displayBounds: CGRect(x: 0, y: 0, width: 1710, height: 1107),
            applicationMenuMaxX: 760,
            menuBarItemBounds: [CGRect(x: 950, y: 0, width: 35, height: 33)],
            targetPointCoreGraphics: CGPoint(x: -3714, y: 16.5)
        )

        #expect(point.x == notchFrameAppKit.midX)
    }

    /// Without a known application menu frame the left span has no lower
    /// bound to measure from, so it is not a candidate at all.
    @Test("An off-screen mouse-down ignores the left span when the application menu is unknown")
    func offscreenMouseDownIgnoresTheLeftSpanWithoutAnApplicationMenu() {
        let notchFrameAppKit = CGRect(x: 763, y: 1074, width: 185, height: 33)

        let point = MenuBarItemManager.offscreenMoveMouseDownPoint(
            notchFrameAppKit: notchFrameAppKit,
            displayBounds: CGRect(x: 0, y: 0, width: 1710, height: 1107),
            applicationMenuMaxX: nil,
            menuBarItemBounds: [CGRect(x: 950, y: 0, width: 35, height: 33)],
            targetPointCoreGraphics: CGPoint(x: -3714, y: 16.5)
        )

        #expect(point.x == notchFrameAppKit.midX)
    }

    /// The control item that holds a collapsed section off-screen is a window
    /// wider than the display, spanning every candidate span without being
    /// anything a click can land on. Measuring against it would leave no span
    /// at all and send the mouse-down back to the notch.
    @Test("An off-screen mouse-down ignores the control item that parks a collapsed section")
    func offscreenMouseDownIgnoresTheOffscreenParkingControlItem() {
        let notchFrameAppKit = CGRect(x: 763, y: 1074, width: 185, height: 33)

        let point = MenuBarItemManager.offscreenMoveMouseDownPoint(
            notchFrameAppKit: notchFrameAppKit,
            displayBounds: CGRect(x: 0, y: 0, width: 1710, height: 1107),
            applicationMenuMaxX: 400,
            menuBarItemBounds: [
                CGRect(x: -3713, y: 0, width: 5016, height: 33),
                CGRect(x: 1303, y: 0, width: 35, height: 33),
            ],
            targetPointCoreGraphics: CGPoint(x: -3714, y: 16.5)
        )

        #expect(point.x == 1125.5)
    }
}
