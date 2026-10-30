import Foundation
import Testing
import KeydeskCore
@testable import KeydeskApp

private final class InspectionGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 5) == .success }
    func read(directory: URL?, statusURL: URL, vaultID: UUID) -> BackupInspection {
        #expect(!Thread.isMainThread, "Cloud backup reads must not block the UI thread")
        entered.signal()
        #expect(resume.wait(timeout: .now() + 5) == .success, "Main actor must remain responsive during backup inspection")
        return BackupInspection(file: directory?.appendingPathComponent("old.keydesk"),
                                status: BackupStatus(vaultID: vaultID, revision: 999, date: .now), cloudUpload: .uploaded)
    }
}

@Suite(.serialized) @MainActor
struct UnlockBackupResponsivenessTests {
    @Test func slowBackupInspectionLeavesUIResponsiveAndCannotRestoreStateAfterLock() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("unlock-inspection-\(UUID())")
        let gate = InspectionGate(), keys = MemoryKeyStore()
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: keys,
                               serve: false, observeSystemEvents: false, inspectBackup: gate.read)
        defer { gate.resume.signal(); model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun(startNew: true)
        model.lock()
        let unlock = Task { await model.unlock() }
        // The wait runs off the main actor; the unlock's backup read must let us resume here.
        let entered = await Task.detached { gate.waitUntilEntered() }.value
        try #require(entered)
        #expect(model.busy && model.snapshot != nil)
        model.lock()
        gate.resume.signal()
        await unlock.value
        #expect(model.snapshot == nil && model.lastBackupFile == nil && model.backedUpRevision == nil)
        #expect(!model.busy && model.error == nil)
    }

    @Test func inspectionFromOldRevisionCannotOverwriteNewBackupSettings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("unlock-settings-\(UUID())")
        let gate = InspectionGate(), keys = MemoryKeyStore()
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: keys,
                               serve: false, observeSystemEvents: false, inspectBackup: gate.read)
        defer { gate.resume.signal(); model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun(startNew: true)
        model.lock()
        let unlock = Task { await model.unlock() }
        try #require(await Task.detached { gate.waitUntilEntered() }.value)
        try model.configureBackup(directory: nil)
        gate.resume.signal()
        await unlock.value
        #expect(model.snapshot != nil && model.backupDirectory == nil)
        #expect(model.lastBackupFile == nil && model.backedUpRevision == nil && !model.busy)
    }
}
