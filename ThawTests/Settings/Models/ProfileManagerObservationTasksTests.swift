//
//  ProfileManagerObservationTasksTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers `ProfileManager.startObservationTasks()`: the notification
/// observation wiring that `performSetup(with:)` runs, extracted so it is
/// exercisable without a live `AppState`.
///
/// The debounced stream mechanics themselves are covered by
/// `DebouncedNotificationTaskTests`; these cases pin the manager-side
/// contract — every observer task is started, and a repeated setup
/// replaces the previous tasks instead of leaking them.
@Suite("Profile manager observation tasks")
@MainActor
struct ProfileManagerObservationTasksTests {
    private func withManager(_ body: (ProfileManager) throws -> Void) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileManagerObservationTasksTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try body(ProfileManager(profilesDirectory: tmp))
    }

    @Test("Starting observation starts the screen-parameters task")
    func startingObservationStartsTheTask() throws {
        try withManager { manager in
            manager.startObservationTasks()

            #expect(manager.screenParametersTask != nil)
        }
    }

    @Test("A repeated setup cancels the previous tasks")
    func repeatedSetupCancelsThePreviousTasks() throws {
        try withManager { manager in
            manager.startObservationTasks()
            let first = try #require(manager.screenParametersTask)

            manager.startObservationTasks()

            #expect(first.isCancelled)
            #expect(manager.screenParametersTask != nil)
        }
    }
}
