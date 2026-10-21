import AppKit
import Foundation
import Testing
import KeydeskCore
@testable import KeydeskApp

@MainActor
struct SystemLockTests {
    @Test func workspaceSleepAndSessionNotificationsEndTimedApprovalAndDoNotUnlockOnWake() async throws {
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Keydesk-system-lock-test-\(UUID())")
            let model = VaultModel(demo: true, directory: directory, defaultBackupDirectory: nil,
                                   keys: MemoryKeyStore(), serve: false, observeSystemEvents: true)
            defer { model.shutdown(); try? FileManager.default.removeItem(at: directory) }
            await model.startTimedApproval(minutes: 480)
            try #require(model.snapshot != nil && model.timedApprovalIsActive)
            let generation = model.generation
            // NSWorkspace's in-process center exercises the actual observers. Do not post the
            // distributed screen-lock notification: that would also reach other running apps.
            NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
            for _ in 0..<100 where model.snapshot != nil {
                await Task.yield()
            }
            #expect(model.snapshot == nil)
            #expect(model.generation != generation)
            #expect(!model.timedApprovalIsActive && model.timedApprovalExpiresAt == nil)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            await Task.yield()
            #expect(model.snapshot == nil && !model.timedApprovalIsActive)
        }
    }

    @Test func manualLockOverridesTimedApprovalAndScreenLockOnlyIdlePolicy() async throws {
        for minutes in [0, 30] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Keydesk-manual-lock-test-\(UUID())")
            let model = VaultModel(demo: true, directory: directory, defaultBackupDirectory: nil,
                                   keys: MemoryKeyStore(), serve: false, observeSystemEvents: false)
            defer { model.shutdown(); try? FileManager.default.removeItem(at: directory) }
            model.autoLockMinutes = minutes // Demo mode does not write user preferences.
            await model.startTimedApproval(minutes: 480)
            try #require(model.snapshot != nil && model.timedApprovalIsActive)
            let generation = model.generation

            model.lock()

            #expect(model.snapshot == nil && model.generation != generation)
            #expect(model.timedApprovalExpiresAt == nil && !model.timedApprovalIsActive)
            #expect(model.autoLockMinutes == minutes)
        }
    }
}
