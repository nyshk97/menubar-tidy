//
//  MacOSCompatibilityWarning.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

enum MacOSCompatibilityWarning {
    static nonisolated func shouldShow(for version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= 27
    }

    @MainActor
    static func showIfNeeded() {
        guard shouldShow(for: ProcessInfo.processInfo.operatingSystemVersion) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "macOS 27 は未対応です"
        alert.informativeText = """
        このバージョンの Thaw は macOS 27 にまだ対応していません。\
        プレビュービルドは GitHub Releases で公開されており、\
        macOS 27 対応は alpha アップデートチャンネルで配信されます。
        """
        alert.addButton(withTitle: "プレビュービルドを見る")
        alert.addButton(withTitle: "続ける")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Constants.releasesURL)
        }
    }
}
