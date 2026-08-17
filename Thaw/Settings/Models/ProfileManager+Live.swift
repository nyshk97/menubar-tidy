//
//  ProfileManager+Live.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// The live half of ``ProfileManager``: everything whose substance needs a
/// running `AppState` — pushing snapshots into live managers, the spacing
/// relaunch wave, WindowServer display identity via Bridging, and Focus
/// Filter intents. None of that can run in a unit
/// test, so this file is excluded from coverage in sonar-project.properties.
///
/// The measured half (ProfileManager.swift) keeps the manifest, file CRUD,
/// capture, and every decision rule. New decision logic belongs there, not
/// here; methods in this file should stay thin orchestration over measured
/// primitives, mirroring the MenuBarItemManager / LayoutSolver split.
extension ProfileManager {
    /// Sets up the manager with the app state and configures auto-switch.
    /// If the current display has an associated profile, it is applied
    /// after the menu bar has settled.
    func performSetup(with appState: AppState) {
        self.appState = appState
        lastActiveDisplayUUID = Bridging.getActiveMenuBarDisplayUUID()

        // Before anything can apply a profile. Once per build, because each
        // build is the only thing that can widen what pruning recognizes as
        // unmatchable — repeating it within a build would rewrite the same
        // files to the same bytes on every launch.
        repairPersistedLayoutsIfNeeded()

        startObservationTasks()

        Task { [weak self] in
            guard let self else { return }
            // The spacing apply runs unconditionally; its no-op guard
            // skips the relaunch when on-disk values already match the
            // active profile's offset, but if the user is booting on a
            // display whose profile has a different offset than the last
            // session left on-disk, the relaunch must happen here or the
            // apps will continue rendering with the wrong spacing.
            if let currentUUID = lastActiveDisplayUUID {
                await self.applyProfileForDisplay(uuid: currentUUID)
            }
        }
    }

    // MARK: - AppState-Sourced Capture

    /// Captures the current app state and saves it as a named profile.
    func saveProfile(name: String, from appState: AppState) throws {
        try saveProfile(
            name: name,
            settings: appState.settings,
            itemManager: appState.itemManager
        )
    }

    /// Overwrites an existing profile with the current app state,
    /// keeping its id, name, display association, and creation date.
    func updateProfileWithCurrentState(id: UUID, appState: AppState) throws {
        try updateProfileWithCurrentState(
            id: id,
            settings: appState.settings,
            itemManager: appState.itemManager
        )
    }

    /// Updates a profile with only the specified scope of current state.
    func updateProfile(id: UUID, scope: ProfileUpdateScope, appState: AppState) throws {
        try updateProfile(
            id: id,
            scope: scope,
            settings: appState.settings,
            itemManager: appState.itemManager
        )
    }

    // MARK: - Apply

    /// Applies a profile's settings to the running app state.
    ///
    /// The menu bar item spacing offset is applied after the snapshot is
    /// pushed, driving the per-profile spacing behaviour. The no-op guard
    /// inside applyOffset skips the relaunch when the on-disk values
    /// already match, so identical-offset switches cost nothing.
    ///
    /// previousProfileID is the active profile ID before this apply was
    /// initiated. Callers capture it before they overwrite
    /// self.activeProfileID, so it can be surfaced to hooks via the
    /// THAW_PREVIOUS_PROFILE_ID env var.
    func applyProfile(
        _ profile: Profile,
        to appState: AppState,
        previousProfileID _: UUID? = nil
    ) {
        diagLog.debug(
            "applyProfile entered: name=\(profile.name)"
        )

        // Cancel any in-flight layout task before starting a new one.
        // Prevents two profile applies from fighting over item positions.
        layoutTask?.cancel()
        layoutGeneration &+= 1
        let generation = layoutGeneration

        let pinnedHidden = Set(profile.menuBarLayout.pinnedHiddenBundleIDs)
        let pinnedAlwaysHidden = Set(profile.menuBarLayout.pinnedAlwaysHiddenBundleIDs)
        let sectionOrder = profile.menuBarLayout.savedSectionOrder
        let itemSectionMap = profile.menuBarLayout.resolvedItemSectionMap
        let itemOrder = profile.menuBarLayout.resolvedItemOrder

        layoutTask = Task { [weak self] in
            if Task.isCancelled {
                return
            }

            // 2. Snapshot apply: push profile settings into the running
            //    app state.
            self?.applySnapshot(profile, to: appState)

            // Take the offset from the configuration the snapshot just
            // installed, rather than trusting whatever spacingManager
            // happens to be holding. The push that normally keeps it in
            // sync lives in configurations.didSet, which guards on
            // oldValue != configurations, so applying a profile whose
            // display configurations already match the live ones — the
            // usual case, since the profile is where they came from —
            // leaves the offset at its launch value of 0. applyOffset()
            // below would then write the system default over the user's
            // spacing and relaunch every menu bar app to do it.
            appState.spacingManager.offset = appState.settings.displaySettings
                .activeDisplaySpacingOffset

            // Run the spacing apply BEFORE the layout pass. Otherwise the
            // two race: applyOffset() kills and relaunches every menu bar
            // app, so any positioning the layout task did up to that
            // point is wiped when items reappear at the OS default
            // insertion point. The no-op guard inside applyOffset()
            // returns immediately when the on-disk values already match,
            // so identical-offset switches add no latency.
            //
            // After the relaunch wave, restart a settling period so
            // applyProfileLayout's wait-for-settling loop blocks until
            // items have actually re-attached. Without this, the settling
            // flag is false (no performSetup to set it), the wait passes
            // through, and applyProfileLayout positions items that
            // haven't come back yet, leaving them at OS-default positions.

            // Preflight settling: flip isInStartupSettling on BEFORE the
            // wave so cacheItemsRegardless skips late-arriver detection
            // and scheduleProfileResort short-circuits while apps are
            // dying and respawning. Without this, on a notch display
            // each intermediate cache cycle triggers a partial full-sort
            // that gets cancelled by the next; only the run after the
            // wave settles produces the correct layout.
            appState.itemManager.startSettlingPeriod(reason: "spacingRelaunch:preflight")

            let didRelaunch: Bool
            let recovered: Set<String>
            do {
                let outcome = try await appState.spacingManager.applyOffset()
                didRelaunch = outcome.didRelaunch
                recovered = outcome.recoveredBundleIDs
            } catch is CancellationError {
                // The task was cancelled, typically because a newer
                // layoutTask is taking over. Drop the preflight settling
                // and bail out so we don't apply a stale layout pass on
                // top of the new task's work.
                appState.itemManager.cancelSettlingPeriod(reason: "spacingRelaunch:cancelled")
                return
            } catch {
                self?.diagLog.error("spacingRelaunch: applyOffset failed: \(error)")
                didRelaunch = false
                recovered = []
            }
            if didRelaunch {
                appState.itemManager.startSettlingPeriod(
                    reason: "spacingRelaunch",
                    expectedBundleIDs: recovered
                )
            } else {
                // No-op apply: nothing churned, drop the preflight so the
                // following applyProfileLayout proceeds without waiting.
                appState.itemManager.cancelSettlingPeriod(reason: "spacingRelaunch:noOp")
            }
            await appState.itemManager.applyProfileLayout(
                pinnedHidden: pinnedHidden,
                pinnedAlwaysHidden: pinnedAlwaysHidden,
                sectionOrder: sectionOrder,
                itemSectionMap: itemSectionMap,
                itemOrder: itemOrder
            )

            // 3. Post-hooks. Profile runs first (mirror of the pre order),
            //    then global teardown. Cancellation skips both, since a
            //    newer apply is taking over.
            if Task.isCancelled {
                if self?.layoutGeneration == generation {
                    self?.layoutTask = nil
                }
                return
            }

            if self?.layoutGeneration == generation {
                self?.layoutTask = nil
            }
        }
    }

    /// Pushes the profile snapshot into the live app state. Split out so
    /// applyProfile's task body stays readable.
    private func applySnapshot(_ profile: Profile, to appState: AppState) {
        profile.generalSettings.apply(to: appState.settings.general)
        profile.advancedSettings.apply(to: appState.settings.advanced)

        // configurations.didSet derives active-display spacing synchronously,
        // so install its global fallback before the per-display overrides.
        appState.settings.displaySettings.globalConfiguration = profile.globalDisplayConfiguration

        // Apply display configurations.
        appState.settings.displaySettings.configurations = profile.displayConfigurations

        // Apply the spacing-relaunch confirmation preferences
        appState.settings.displaySettings.confirmSpacingRelaunch = profile.confirmSpacingRelaunch
        appState.settings.displaySettings.unconfirmedSpacingProfileScope = profile.unconfirmedSpacingProfileScope

        // Apply custom names to UserDefaults.
        Defaults.set(
            profile.menuBarLayout.customNames,
            forKey: .menuBarItemCustomNames
        )

        // Apply the New Items badge placement before starting the layout
        // task, so late-arriving items land in the profile-defined spot.
        if let placement = profile.menuBarLayout.newItemsPlacement {
            appState.itemManager.applyNewItemsPlacement(placement)
        }
    }

    // MARK: - Auto-Switch

    /// Called when the active menu bar display changes. Finds a profile
    /// associated with the new active display and applies it.
    /// Skipped when a Focus Filter profile is currently active.
    ///
    /// Internal rather than private because `startObservationTasks()` — which
    /// stays in the measured file so its wiring remains testable — installs
    /// the closure that calls it.
    func checkDisplayAndAutoSwitch() async {
        guard let currentUUID = Bridging.getActiveMenuBarDisplayUUID() else { return }
        guard currentUUID != lastActiveDisplayUUID else { return }
        lastActiveDisplayUUID = currentUUID

        await applyProfileForDisplay(uuid: currentUUID)
    }

    /// Re-applies the currently active profile, driving its layout pass
    /// without changing which profile is active.
    ///
    /// Used by DisplaySettingsManager.applyActiveDisplaySpacing after it
    /// fires a relaunch wave whose menu bar items reattach at OS-default
    /// positions: the auto-switch path doesn't fire when the active display
    /// keeps the same associated profile, so without an explicit re-apply
    /// the layout would never run and the items would stay where macOS put
    /// them. The applyOffset inside layoutTask no-ops (the on-disk values
    /// were just written), and the subsequent applyProfileLayout awaits
    /// the in-flight expected-set settling before running.
    func reapplyActiveProfile() {
        guard let appState else { return }
        guard let activeID = activeProfileID else { return }
        do {
            let profile = try loadProfile(id: activeID)
            // No previous-vs-new transition here; pass the active id as
            // both previous and current so a hook can see the apply was a
            // refresh of the same profile rather than a switch.
            applyProfile(profile, to: appState, previousProfileID: activeID)
        } catch {
            diagLog.error("reapplyActiveProfile failed: \(error)")
        }
    }

    /// Applies the profile associated with the given display UUID, if any.
    private func applyProfileForDisplay(uuid: String) async {
        guard let meta = profiles.first(where: { $0.associatedDisplayUUID == uuid }) else {
            return
        }
        guard meta.id != activeProfileID else { return }
        guard let appState else { return }

        diagLog.info("Auto-switching to profile \(meta.name) for display \(uuid)")
        do {
            let profile = try loadProfile(id: meta.id)
            let previousID = activeProfileID
            activeProfileID = meta.id
            applyProfile(profile, to: appState, previousProfileID: previousID)
        } catch {
            diagLog.error("Auto-switch failed: \(error)")
        }
    }
}
