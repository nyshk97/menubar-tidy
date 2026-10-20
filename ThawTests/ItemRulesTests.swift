//
//  ItemRulesTests.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

// The numbers come from a MacBook Pro 14" (1512×982pt, notch from x=663 to 848)
// measured on 2026-10-20 with scripts/list-ax-items.swift.

private let notched = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notch: 663 ... 848)
private let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), notch: nil)
/// A notched screen placed to the left of the main screen.
private let notchedOnTheLeft = ScreenGeometry(frame: CGRect(x: -1512, y: 458, width: 1512, height: 982), notch: -849 ... -664)

private func item(x: CGFloat, y: CGFloat = 4.5, width: CGFloat = 24, height: CGFloat = 24) -> CGRect {
    CGRect(x: x, y: y, width: width, height: height)
}

private func info(
    pid: pid_t = 100,
    bundleID: String? = "com.example.app",
    appName: String = "Example",
    identifier: String? = nil,
    description: String = "",
    title: String = "",
    frame: CGRect = CGRect(x: 1000, y: 4.5, width: 24, height: 24),
    isEnabled: Bool = true,
    indexInApp: Int = 0
) -> ItemInfo {
    ItemInfo(
        pid: pid, bundleID: bundleID, appName: appName, identifier: identifier,
        axDescription: description, axTitle: title, frame: frame, isEnabled: isEnabled, indexInApp: indexInApp
    )
}

@Suite("Item visibility")
struct ItemVisibilityTests {
    @Test("An item right of the notch is visible")
    func rightOfNotch() {
        #expect(ItemVisibility.classify(item(x: 1208, width: 46), on: notched, appMenusMaxX: 477) == .visible)
    }

    @Test("An item behind the notch is hidden, even partly")
    func behindNotch() {
        #expect(ItemVisibility.classify(item(x: 743), on: notched, appMenusMaxX: 214) == .hidden)
        #expect(ItemVisibility.classify(item(x: 650, width: 20), on: notched, appMenusMaxX: 214) == .hidden)
        #expect(ItemVisibility.classify(item(x: 840, width: 20), on: notched, appMenusMaxX: 214) == .hidden)
    }

    @Test("An item under the frontmost app's menus is hidden")
    func underAppMenus() {
        #expect(ItemVisibility.classify(item(x: 495), on: notched, appMenusMaxX: 646) == .hidden)
        #expect(ItemVisibility.classify(item(x: 495), on: plain, appMenusMaxX: 646) == .hidden)
    }

    @Test("Short app menus leave the items right of them visible")
    func shortAppMenus() {
        #expect(ItemVisibility.classify(item(x: 495), on: notched, appMenusMaxX: 214) == .visible)
        #expect(ItemVisibility.classify(item(x: 495), on: plain, appMenusMaxX: nil) == .visible)
    }

    @Test("An item past the left edge is off screen, even partly, and that wins over the notch")
    func offScreen() {
        #expect(ItemVisibility.classify(item(x: -177), on: notched, appMenusMaxX: 646) == .offScreen)
        #expect(ItemVisibility.classify(item(x: -9, width: 40), on: notched, appMenusMaxX: nil) == .offScreen)
        #expect(ItemVisibility.classify(item(x: -4306), on: plain, appMenusMaxX: nil) == .offScreen)
    }

    @Test("Off screen is judged against the screen's own left edge, not x = 0")
    func screenNotAtOrigin() {
        let y: CGFloat = 462.5
        #expect(ItemVisibility.classify(item(x: -300, y: y), on: notchedOnTheLeft, appMenusMaxX: nil) == .visible)
        #expect(ItemVisibility.classify(item(x: -760, y: y), on: notchedOnTheLeft, appMenusMaxX: nil) == .hidden)
        #expect(ItemVisibility.classify(item(x: -1520, y: y), on: notchedOnTheLeft, appMenusMaxX: nil) == .offScreen)
    }
}

@Suite("Which items are listed")
struct ItemListingTests {
    private let screens = [notched]

    @Test("Items in the menu bar strip are listed, including ones pushed past the edge")
    func inStrip() {
        #expect(ItemRules.isListed(info(frame: item(x: 743)), screens: screens, ownPID: 1))
        #expect(ItemRules.isListed(info(frame: item(x: -4306)), screens: screens, ownPID: 1))
    }

    @Test("Items turned off in System Settings are parked outside the strip and left out")
    func turnedOff() {
        #expect(!ItemRules.isListed(info(frame: CGRect(x: -1, y: 981, width: 31, height: 24)), screens: screens, ownPID: 1))
    }

    @Test("Control Center's empty placeholders, disabled items and this app's own items are left out")
    func leftOut() {
        #expect(!ItemRules.isListed(info(frame: CGRect(x: 0, y: 982, width: 0, height: 0), isEnabled: false), screens: screens, ownPID: 1))
        #expect(!ItemRules.isListed(info(frame: item(x: -3833, width: 5002), isEnabled: false), screens: screens, ownPID: 1))
        #expect(!ItemRules.isListed(info(pid: 1), screens: screens, ownPID: 1))
    }

    @Test("Items on a second screen's menu bar are listed")
    func secondScreen() {
        let above = ScreenGeometry(frame: CGRect(x: 0, y: -1440, width: 2560, height: 1440), notch: nil)
        let onSecond = info(frame: item(x: 2000, y: -1435.5))
        #expect(!ItemRules.isListed(onSecond, screens: screens, ownPID: 1))
        #expect(ItemRules.isListed(onSecond, screens: screens + [above], ownPID: 1))
    }

    @Test("Items of a menu bar tucked away above its screen are listed")
    func tuckedAway() {
        // Studio Display above the built-in screen with a full-screen app: the
        // bar waits above the screen and accessibility reports y = -1499.
        let studio = ScreenGeometry(frame: CGRect(x: -502, y: -1440, width: 2560, height: 1440), notch: nil)
        #expect(ItemRules.isListed(info(frame: item(x: 1752, y: -1499)), screens: [notched, studio], ownPID: 1))
    }
}

@Suite("Which screen the items are on")
struct ItemScreenTests {
    private let studio = ScreenGeometry(frame: CGRect(x: -502, y: -1440, width: 2560, height: 1440), notch: nil)

    @Test("The screen whose strip holds the items wins over the fallback")
    func fromItems() {
        let items = [info(frame: item(x: 1752, y: -1499)), info(frame: item(x: -3841, y: -1498))]
        #expect(ItemRules.screen(for: items, among: [notched, studio], fallback: notched) == studio)
    }

    @Test("Without items in any strip, the fallback is used")
    func fallback() {
        #expect(ItemRules.screen(for: [], among: [notched, studio], fallback: notched) == notched)
        #expect(ItemRules.screen(for: [info(frame: CGRect(x: -1, y: 981, width: 31, height: 24))], among: [notched, studio], fallback: studio) == studio)
    }
}

@Suite("Item titles")
struct ItemTitleTests {
    @Test("Control Center's items use their description")
    func controlCenter() {
        let wifi = info(bundleID: "com.apple.controlcenter", appName: "コントロールセンター", identifier: "com.apple.menuextra.wifi", description: "Wi‑Fi、インターネット共有")
        #expect(ItemRules.title(for: wifi, siblingCount: 6) == "Wi‑Fi、インターネット共有")
    }

    @Test("Other Apple processes use their description instead of the process name")
    func appleAgents() {
        let input = info(bundleID: "com.apple.TextInputMenuAgent", appName: "TextInputMenuAgent", description: "日本語")
        #expect(ItemRules.title(for: input, siblingCount: 1) == "日本語")
        let spotlight = info(bundleID: "com.apple.Spotlight", appName: "Spotlight", description: "検索", title: "Spotlight")
        #expect(ItemRules.title(for: spotlight, siblingCount: 1) == "検索")
        let bare = info(bundleID: "com.apple.Something", appName: "Something")
        #expect(ItemRules.title(for: bare, siblingCount: 1) == "Something")
    }

    @Test("A third-party app with one item shows its app name, ignoring SF Symbol titles")
    func singleItem() {
        let translator = info(appName: "Translator", title: "character.bubble.fill")
        #expect(ItemRules.title(for: translator, siblingCount: 1) == "Translator")
        let todo = info(appName: "TodoMac", description: "Todo")
        #expect(ItemRules.title(for: todo, siblingCount: 1) == "TodoMac")
    }

    @Test("An app with several items adds a detail, or the position when it has none")
    func severalItems() {
        let cpu = info(appName: "Stats", description: "CPU", indexInApp: 0)
        let bare = info(appName: "Stats", title: "chart.bar.fill", indexInApp: 1)
        #expect(ItemRules.title(for: cpu, siblingCount: 2) == "Stats（CPU）")
        #expect(ItemRules.title(for: bare, siblingCount: 2) == "Stats（2）")
    }

    @Test("SF Symbol names are recognised")
    func symbolNames() {
        #expect(ItemRules.isSymbolName("character.bubble.fill"))
        #expect(!ItemRules.isSymbolName("Wi‑Fi、インターネット共有"))
        #expect(!ItemRules.isSymbolName("Todo"))
    }

    @Test("Control Center identifiers map to SF Symbols")
    func controlCenterSymbols() {
        #expect(ItemRules.symbolName(forControlCenterIdentifier: "com.apple.menuextra.wifi") == "wifi")
        #expect(ItemRules.symbolName(forControlCenterIdentifier: "com.apple.menuextra.unknown") == nil)
        #expect(ItemRules.symbolName(forControlCenterIdentifier: nil) == nil)
    }
}

@Suite("Finding an item again")
struct ItemMatchTests {
    @Test("By identifier first")
    func byIdentifier() {
        let original = info(identifier: "com.apple.menuextra.wifi", indexInApp: 3)
        let candidates = [info(identifier: "com.apple.menuextra.battery", indexInApp: 3), info(identifier: "com.apple.menuextra.wifi", indexInApp: 0)]
        #expect(ItemRules.match(original, among: candidates) == 1)
    }

    @Test("Then by description and title")
    func byDescription() {
        let original = info(description: "CPU", indexInApp: 0)
        let candidates = [info(description: "Memory", indexInApp: 0), info(description: "CPU", indexInApp: 1)]
        #expect(ItemRules.match(original, among: candidates) == 1)
    }

    @Test("Then by position")
    func byPosition() {
        let original = info(indexInApp: 1)
        #expect(ItemRules.match(original, among: [info(indexInApp: 0), info(indexInApp: 1)]) == 1)
        #expect(ItemRules.match(original, among: [info(indexInApp: 0)]) == nil)
    }
}

@Suite("Screen geometry")
struct ScreenGeometryTests {
    @Test("NSScreen frames convert to top-left-origin coordinates")
    func conversion() {
        let main = ScreenGeometry.cgRect(fromScreenRect: CGRect(x: 0, y: 0, width: 1512, height: 982), mainScreenHeight: 982)
        #expect(main == CGRect(x: 0, y: 0, width: 1512, height: 982))
        let above = ScreenGeometry.cgRect(fromScreenRect: CGRect(x: 0, y: 982, width: 2560, height: 1440), mainScreenHeight: 982)
        #expect(above == CGRect(x: 0, y: -1440, width: 2560, height: 1440))
    }

    @Test("The notch range is read from the areas either side of it")
    func notchAtOrigin() {
        let range = ScreenGeometry.notchRange(
            leftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
            rightArea: CGRect(x: 848, y: 950, width: 664, height: 32),
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        )
        #expect(range == 663 ... 848)
    }

    @Test("The notch range lands on the screen whether the areas are global or screen-relative")
    func notchOffOrigin() {
        let screenFrame = CGRect(x: -1512, y: 0, width: 1512, height: 982)
        let global = ScreenGeometry.notchRange(
            leftArea: CGRect(x: -1512, y: 950, width: 663, height: 32),
            rightArea: CGRect(x: -664, y: 950, width: 664, height: 32),
            screenFrame: screenFrame
        )
        let relative = ScreenGeometry.notchRange(
            leftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
            rightArea: CGRect(x: 848, y: 950, width: 664, height: 32),
            screenFrame: screenFrame
        )
        #expect(global == -849 ... -664)
        #expect(relative == -849 ... -664)
    }
}
