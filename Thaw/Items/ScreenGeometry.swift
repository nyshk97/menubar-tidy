//
//  ScreenGeometry.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import AppKit

/// A screen's frame and notch in the coordinate space accessibility frames use:
/// global CG coordinates, with the main screen's top-left corner as the origin
/// and y growing downward.
nonisolated struct ScreenGeometry: Equatable, Sendable {
    /// How far below a screen's top edge its menu bar strip reaches. Items are
    /// about 24pt tall and sit a few points from the top; a notched screen's
    /// menu bar is the tallest at about 37pt.
    static let menuBarBandBelowTop: CGFloat = 40

    /// How far above a screen's top edge the strip reaches. When a screen's menu
    /// bar is tucked away (a full-screen app on a second display), accessibility
    /// reports its items about 60pt above the screen, where the bar waits to
    /// slide down.
    static let menuBarBandAboveTop: CGFloat = 80

    /// The screen's frame in global CG coordinates.
    var frame: CGRect

    /// The notch's horizontal extent in global coordinates, or `nil` if the
    /// screen has no notch.
    var notch: ClosedRange<CGFloat>?

    /// The strip along the top of the screen where its menu bar items can be,
    /// whether the menu bar is showing or tucked away above the screen.
    var menuBarBand: CGRect {
        CGRect(
            x: frame.minX,
            y: frame.minY - Self.menuBarBandAboveTop,
            width: frame.width,
            height: Self.menuBarBandAboveTop + Self.menuBarBandBelowTop
        )
    }

    /// Whether a frame sits in this screen's menu bar strip. Only the vertical
    /// position counts: items past a screen's edge are still in its strip.
    func isInMenuBarBand(_ rect: CGRect) -> Bool {
        let band = menuBarBand
        return band.minY <= rect.midY && rect.midY <= band.maxY
    }

    /// Converts an `NSScreen` frame (bottom-left origin, y up) to global CG
    /// coordinates, given the height of the main screen (the first screen).
    static func cgRect(fromScreenRect rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The notch's horizontal extent in global coordinates.
    ///
    /// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are the unobscured
    /// corners either side of the notch. Upstream Thaw read their x values as
    /// global coordinates; whether they are global or relative to the screen
    /// only matters when the notched screen is not at x = 0, so take them as
    /// global when they lie within the screen and as screen-relative otherwise.
    static func notchRange(leftArea: CGRect, rightArea: CGRect, screenFrame: CGRect) -> ClosedRange<CGFloat>? {
        let lower = leftArea.maxX
        let upper = rightArea.minX
        guard upper > lower else {
            return nil
        }
        let isGlobal = lower >= screenFrame.minX && upper <= screenFrame.maxX
        let offset = isGlobal ? 0 : screenFrame.minX
        return (lower + offset) ... (upper + offset)
    }
}

extension ScreenGeometry {
    /// The geometry of every connected screen, in `NSScreen.screens` order.
    static func current() -> [ScreenGeometry] {
        NSScreen.screens.map(ScreenGeometry.init(screen:))
    }

    init(screen: NSScreen) {
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let frame = Self.cgRect(fromScreenRect: screen.frame, mainScreenHeight: mainHeight)
        var notch: ClosedRange<CGFloat>?
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = Self.notchRange(leftArea: left, rightArea: right, screenFrame: screen.frame)
        }
        self.init(frame: frame, notch: notch)
    }
}
