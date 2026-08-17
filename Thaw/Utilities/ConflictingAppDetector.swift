//
//  ConflictingAppDetector.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Detects other running menu bar management apps that may conflict with Thaw.
enum ConflictingAppDetector {
    /// Known menu bar management app bundle identifiers and their display names.
    private static let knownConflictingApps: [String: String] = [
        "com.jordanbaird.Ice": "Ice",
        "com.surteesstudios.Bartender": "Bartender",
        "com.dwarvesv.minimalbar": "Hidden Bar",
        "com.macpaw.CleanMyMac-setapp": "CleanMyMac Menu",
        "com.gaosun.BarTender": "iBar",
        "com.HyperartFlow.Barbee": "Barbee",
        "com.sanebar.app": "SaneBar",
    ]

    /// Returns the display names of any conflicting menu bar managers currently running.
    @MainActor
    static func detectConflictingApps() -> [String] {
        let runningApps = NSWorkspace.shared.runningApplications
        var conflicts: [String] = []

        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            if let name = knownConflictingApps[bundleID], !app.isTerminated {
                conflicts.append(name)
            }
        }

        return conflicts
    }

    /// Shows a warning alert listing the conflicting apps. Returns `true` if the user chose to continue.
    @MainActor
    @discardableResult
    static func showWarningIfNeeded() -> Bool {
        let conflicts = detectConflictingApps()
        guard !conflicts.isEmpty else { return true }

        let appList = conflicts.joined(separator: ", ")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "競合するメニューバーマネージャーが検出されました"
        alert.informativeText = """
        \(appList) は現在実行中です。複数のメニューバーマネージャーを同時に実行すると、\
        表示の問題や予期しない動作が発生する可能性があります。\
        \(Constants.displayName) を使用する前に \(appList) を終了することをおすすめします。
        """
        alert.addButton(withTitle: "このまま続ける")
        alert.addButton(withTitle: "\(Constants.displayName) を終了")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSApp.terminate(nil)
            return false
        }
        return true
    }
}
