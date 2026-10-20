//
//  StatusMenuController.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import AppKit

/// The menu behind this app's status icon: every menu bar item, split into the
/// ones that are hidden (behind the notch, under the frontmost app's menus, or
/// off screen) and the ones that are visible. Choosing one presses it.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let scanner: ItemScanner
    private let updates: UpdatesManager
    private let menu = NSMenu()
    private var isMenuOpen = false

    init(statusItem: NSStatusItem, scanner: ItemScanner, updates: UpdatesManager) {
        self.statusItem = statusItem
        self.scanner = scanner
        self.updates = updates
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        scanner.onKnownPIDsChanged = { [weak self] in
            // A scan that finishes while the list is open (the first one after
            // the permission was granted, or an app that just added an item)
            // fills in the open menu.
            guard let self, isMenuOpen else {
                return
            }
            rebuild()
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_: NSMenu) {
        rebuild()
    }

    func menuWillOpen(_: NSMenu) {
        isMenuOpen = true
        // Pick up apps that added an item since the last scan, for next time
        // (or for this time, through `onKnownPIDsChanged`).
        scanner.startFullScan()
    }

    func menuDidClose(_: NSMenu) {
        isMenuOpen = false
    }

    // MARK: Building

    private func rebuild() {
        menu.removeAllItems()
        if AccessibilityPermission.isGranted {
            addItemSections()
        } else {
            addPermissionItems()
        }
        addFooter()
    }

    private func addItemSections() {
        let screens = ScreenGeometry.current()
        let items = scanner.readItems().filter {
            ItemRules.isListed($0.info, screens: screens, ownPID: ProcessInfo.processInfo.processIdentifier)
        }
        guard !items.isEmpty else {
            let title = scanner.hasCompletedScan ? "メニューバーの項目が見つかりません" : "読み込み中…"
            menu.addItem(disabledItem(title))
            return
        }

        let screen = ItemRules.screen(for: items.map(\.info), among: screens, fallback: screenOfStatusItem(among: screens))
        let appMenusMaxX = NSWorkspace.shared.frontmostApplication.flatMap {
            AXHelper.menusMaxX(of: $0.processIdentifier, within: screen.frame)
        }
        let siblingCounts = Dictionary(grouping: items, by: \.info.pid).mapValues(\.count)

        var hidden: [NSMenuItem] = []
        var visible: [NSMenuItem] = []
        for item in items {
            let menuItem = makeMenuItem(for: item, siblingCount: siblingCounts[item.info.pid] ?? 1)
            switch ItemVisibility.classify(item.info.frame, on: screen, appMenusMaxX: appMenusMaxX) {
            case .visible:
                visible.append(menuItem)
            case .hidden:
                hidden.append(menuItem)
            case .offScreen:
                menuItem.isEnabled = false
                menuItem.subtitle = "画面外のため開けません"
                hidden.append(menuItem)
            }
        }

        if !hidden.isEmpty {
            menu.addItem(.sectionHeader(title: "隠れている"))
            hidden.forEach(menu.addItem)
        }
        if !visible.isEmpty {
            if !hidden.isEmpty {
                menu.addItem(.separator())
            }
            menu.addItem(.sectionHeader(title: "見えている"))
            visible.forEach(menu.addItem)
        }
    }

    private func makeMenuItem(for item: MenuBarItem, siblingCount: Int) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: ItemRules.title(for: item.info, siblingCount: siblingCount),
            action: #selector(pressItem(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.image = ItemIcon.image(for: item.info)
        menuItem.representedObject = ItemBox(item)
        return menuItem
    }

    private func addPermissionItems() {
        menu.addItem(disabledItem("アクセシビリティの許可が必要です"))
        let grant = NSMenuItem(title: "アクセシビリティを許可…", action: #selector(grantAccessibility), keyEquivalent: "")
        grant.target = self
        menu.addItem(grant)
    }

    private func addFooter() {
        menu.addItem(.separator())
        var version = "\(Constants.displayName) \(Constants.versionString)"
        if let sha = Constants.gitCommitSHA {
            version += "（\(sha)）"
        }
        menu.addItem(disabledItem(version))
        let update = NSMenuItem(title: "アップデートを確認…", action: #selector(UpdatesManager.checkForUpdates), keyEquivalent: "")
        update.target = updates
        update.isEnabled = !UpdatesManager.isSupported || updates.canCheckForUpdates
        menu.addItem(update)
        menu.addItem(NSMenuItem(
            title: "\(Constants.displayName) を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// The screen this app's icon is on (the fallback when the items do not say
    /// which screen they are on).
    private func screenOfStatusItem(among screens: [ScreenGeometry]) -> ScreenGeometry {
        if let screen = statusItem.button?.window?.screen {
            return ScreenGeometry(screen: screen)
        }
        return screens.first ?? ScreenGeometry(frame: .zero, notch: nil)
    }

    // MARK: Actions

    @objc private func pressItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ItemBox else {
            return
        }
        ItemPresser.press(box.item)
    }

    @objc private func grantAccessibility() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
    }
}

/// Carries a ``MenuBarItem`` through `NSMenuItem.representedObject`.
private final class ItemBox {
    let item: MenuBarItem

    init(_ item: MenuBarItem) {
        self.item = item
    }
}
