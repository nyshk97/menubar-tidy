//
//  AppDelegate.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    func applicationDidFinishLaunching(_: Notification) {
        statusItem.autosaveName = "Thaw.ControlItem.Visible"
        let image = NSImage(named: "TidyBarFill")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "\(Constants.displayName) を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
