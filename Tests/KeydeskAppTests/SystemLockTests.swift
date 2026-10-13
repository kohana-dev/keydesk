import AppKit
import Foundation
import Testing
import KeydeskCore
@testable import KeydeskApp

@MainActor
struct SystemLockTests {
    @Test func workspaceSleepAndSessionNotificationsLockWithoutUnlockingOnWake() async throws {
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Keydesk-system-lock-test-\(UUID())")
            let model = VaultModel(directory: directory, defaultBackupDirectory: nil,
                                   keys: MemoryKeyStore(), serve: false, observeSystemEvents: true)
            defer { model.shutdown(); try? FileManager.default.removeItem(at: directory) }
            await model.prepareFirstRun(startNew: true)
            #expect(model.snapshot != nil)
            let generation = model.generation
            NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
            for _ in 0..<100 where model.snapshot != nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.snapshot == nil)
            #expect(model.generation != generation)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            await Task.yield()
            #expect(model.snapshot == nil)
        }
    }
}
