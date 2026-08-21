//
//  MenuBarLayoutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @Environment(AppState.self) var appState: AppState
    let itemManager: MenuBarItemManager
    @Bindable var advancedSettings: AdvancedSettings

    @State private var loadDeadlineReached = false
    @State private var isResettingLayout = false
    @State private var resetStatus: ResetStatus?
    @State private var isConfirmingReset = false

    /// Bumped whenever the screen the editor reflects may have changed, so
    /// the display title above the bars re-evaluates. Screen parameters cover
    /// displays arriving, leaving or being rearranged; app activation covers
    /// the menu bar moving to another screen without the layout changing.
    @State private var displayTitleRefreshToken = 0

    private let diagLog = DiagLog(category: "MenuBarLayoutPane")

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty
    }

    private var areControlItemsDisabledBySystem: Bool {
        itemManager.areControlItemsMissing
    }

    var body: some View {
        if !ScreenCapture.cachedCheckPermissions() {
            missingScreenRecordingPermissions
        } else if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            IceForm {
                layoutBarsSection
                resetControls
            }
            .onAppear {
                // Enable background cache prewarming while the layout settings
                // pane is open.
                appState.imageCache.markSettingsPaneOpened()
            }
            .onDisappear {
                // Disable background cache prewarming once the layout settings
                // pane is no longer visible, bounding how long perpetual
                // background captures (including the leaking SkyLight offscreen
                // path) can run (#759).
                appState.imageCache.markSettingsPaneClosed()
            }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: NSApplication.didChangeScreenParametersNotification)
            ) { _ in
                displayTitleRefreshToken &+= 1
            }
            .onReceive(
                NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.didActivateApplicationNotification)
            ) { _ in
                displayTitleRefreshToken &+= 1
            }
        }
    }

    /// The name of the display whose layout the bars below are showing.
    ///
    /// The editor has no display picker: it always reflects the screen that
    /// currently owns the menu bar, which is what `LayoutBarContainer` and
    /// `LayoutBarPaddingView` both read. On a single Mac that is invisible,
    /// but with an external display as the primary the editor silently
    /// describes a different screen than the user is picturing — and the
    /// notch placeholder correctly disappearing is the symptom people
    /// actually notice (#886). Naming the display makes the existing
    /// behaviour legible instead of changing it.
    private var editingDisplayName: String? {
        guard NSScreen.screens.count > 1 else {
            return nil
        }
        let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        let name = screen?.localizedName.trimmingCharacters(in: .whitespaces)
        return (name?.isEmpty ?? true) ? nil : name
    }

    private var layoutBarsSection: some View {
        IceSection {
            if let editingDisplayName {
                Text("使用中のディスプレイ: \(editingDisplayName)")
                    // Redrawn on the same signals LayoutBarPaddingView uses to
                    // re-evaluate the notch indicator, so the title and the
                    // bars below it can never disagree about which screen
                    // they are describing.
                    .id(displayTitleRefreshToken)
            }
        } content: {
            layoutBars
        }
    }

    private var layoutBars: some View {
        VStack(spacing: 20) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
        .opacity(hasItems ? 1 : 0.75)
        .blur(radius: hasItems ? 0 : 5)
        .allowsHitTesting(hasItems)
        .overlay {
            if !hasItems {
                VStack(spacing: 8) {
                    if loadDeadlineReached {
                        VStack(spacing: 4) {
                            if areControlItemsDisabledBySystem {
                                Text("1つ以上のセクション区切りが macOS によって非表示にされています")
                                Text("システム設定 > メニューバー を確認して \(Constants.displayName) を有効にしてください")
                                    .font(.callout.bold())
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("メニューバー項目を読み込めません")
                            }
                        }
                    } else {
                        Text("メニューバー項目を読み込んでいます…")
                        ProgressView()
                    }
                }
            }
        }
        .task(id: hasItems) {
            loadDeadlineReached = false

            guard !hasItems, ScreenCapture.cachedCheckPermissions() else {
                return
            }

            diagLog.debug("Preloading menu bar layout caches (hasItems=\(self.hasItems), screenRecording=\(ScreenCapture.cachedCheckPermissions()))")

            async let preloadCaches: Void = preloadLayoutCaches()

            try? await Task.sleep(for: .seconds(3))

            if !Task.isCancelled, !hasItems {
                loadDeadlineReached = true
                diagLog.error("Menu bar layout failed to load items after 3s timeout. cacheItems: \(itemManager.itemCache.managedItems.count), images: \(appState.imageCache.images.count), displayID: \(self.itemManager.itemCache.displayID.map { "\($0)" } ?? "nil")")
            }

            await preloadCaches
        }
    }

    private var resetControls: some View {
        IceSection {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("メニューバーのレイアウトをリセット")
                        .font(.headline)
                    Text("仕切りをリセットし、\(Constants.displayName) のアイコンを除く移動可能なすべての項目を選択したセクションへ移動します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    isConfirmingReset = true
                } label: {
                    if isResettingLayout {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("レイアウトをリセット…")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isResettingLayout || areControlItemsDisabledBySystem)
            }

            if isConfirmingReset {
                resetTargetControls
            }

            if let resetStatus {
                Text(resetStatus.message)
                    .font(.footnote)
                    .foregroundStyle(resetStatus.isError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            versionFooter
        }
    }

    private var resetTargetControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("メニューバー項目の移動先を選択:")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("表示") { resetMenuBarLayout(to: .visible) }
                Button("非表示") { resetMenuBarLayout(to: .hidden) }
                if appState.settings.advanced.enableAlwaysHiddenSection {
                    Button("常に非表示") { resetMenuBarLayout(to: .alwaysHidden) }
                }
                Button("キャンセル", role: .cancel) {
                    isConfirmingReset = false
                }
            }
            .buttonStyle(.bordered)
        }
    }

    /// The running build, spelled out at the bottom of the pane.
    ///
    /// The title bar carries the marketing version; this repeats it with the
    /// build number and commit so a dev build (which also renames itself) can
    /// be told apart from the release one, and so the string can be copied
    /// into a bug report. It rides the last section's footer rather than a
    /// section of its own: a footer draws outside the grouped card, which is
    /// what a version line should look like.
    private var versionFooter: some View {
        HStack(spacing: 12) {
            Text(versionFooterText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            checkForUpdatesButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    /// Sits next to the version line: "this is what you have" and "is there
    /// a newer one" belong side by side. Sparkle drives the rest (progress,
    /// "up to date", the install prompt) in its own windows.
    private var checkForUpdatesButton: some View {
        Button("アップデートを確認") {
            appState.updatesManager.checkForUpdates()
        }
        .controlSize(.small)
        .disabled(!UpdatesManager.isSupported || !appState.updatesManager.canCheckForUpdates)
        .help(
            UpdatesManager.isSupported
                ? "最新バージョンがあるか確認します"
                : "dev 版ではアップデートを確認できません"
        )
    }

    private var versionFooterText: String {
        let base = "\(Constants.displayName) \(Constants.versionString) (\(Constants.buildString))"
        guard let sha = Constants.gitCommitSHA else {
            return base
        }
        return "\(base) · \(sha)"
    }

    private var cannotArrange: some View {
        Text("\(Constants.displayName) は自動的に非表示になるメニューバーではメニューバー項目を整理できません。")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var missingScreenRecordingPermissions: some View {
        VStack {
            Text("メニューバーのレイアウトには画面収録の権限が必要です。")
                .font(.title2)

            // Upstream links to its Advanced pane, which lists the permission
            // and a button to request it. That pane is gone, so send the user
            // where the grant actually happens.
            Button {
                appState.permissions.screenRecording.performRequest()
            } label: {
                Text("システム設定を開く")
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: name),
            section.isEnabled
        {
            VStack(alignment: .leading) {
                Text(name.localized)
                    .font(.headline)
                    .padding(.leading, 8)

                LayoutBar(imageCache: appState.imageCache, section: name)
            }
        }
    }

    private func resetMenuBarLayout(to target: MenuBarItemManager.LayoutResetTarget) {
        isConfirmingReset = false
        isResettingLayout = true
        resetStatus = nil

        let manager = itemManager

        Task { @MainActor in
            do {
                let failedMoves = switch target {
                case .visible:
                    try await manager.resetLayoutToVisible()
                case .hidden:
                    try await manager.resetLayoutToFreshState()
                case .alwaysHidden:
                    try await manager.resetLayoutToAlwaysHidden()
                }
                if failedMoves == 0 {
                    resetStatus = .success(target)
                } else {
                    resetStatus = .partialFailure(failedMoves)
                }
                isResettingLayout = false

                // The manager rebuilds both caches before returning.
            } catch {
                resetStatus = .failure(error.localizedDescription)
                isResettingLayout = false
            }
        }
    }

    private func preloadLayoutCaches() async {
        await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        guard !Task.isCancelled else {
            return
        }

        diagLog.debug("Preload: itemCache after cacheItemsRegardless: managedItems=\(self.itemManager.itemCache.managedItems.count), visible=\(self.itemManager.itemCache[.visible].count), hidden=\(self.itemManager.itemCache[.hidden].count), alwaysHidden=\(self.itemManager.itemCache[.alwaysHidden].count)")

        await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        guard !Task.isCancelled else {
            return
        }

        diagLog.debug("Preload: imageCache after update: \(self.appState.imageCache.images.count) images")
    }

    private enum ResetStatus {
        case success(MenuBarItemManager.LayoutResetTarget)
        case partialFailure(Int)
        case failure(String)

        var message: String {
            switch self {
            case .success(.visible):
                "項目を表示セクションへ移動しました。"
            case .success(.hidden):
                "レイアウトをリセットしました。項目は非表示セクションに移動されました。"
            case .success(.alwaysHidden):
                "レイアウトをリセットしました。項目を常に非表示セクションへ移動しました。"
            case let .partialFailure(count):
                "リセットが完了しましたが、\(count) 個の項目を移動できませんでした。必要に応じてメニューバーを確認し、再試行してください。"
            case let .failure(message):
                "リセットに失敗しました: \(message)"
            }
        }

        var isError: Bool {
            switch self {
            case .failure, .partialFailure:
                true
            case .success:
                false
            }
        }
    }
}
