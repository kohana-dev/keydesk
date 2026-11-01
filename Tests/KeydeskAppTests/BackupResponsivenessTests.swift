import Foundation
import CryptoKit
import Testing
import KeydeskCore
@testable import KeydeskApp

private actor PausedBackupWriter: BackupSaving {
    private(set) var revisions: [UInt64] = []
    private var completions: [CheckedContinuation<Void, Never>] = []
    private var entered: [CheckedContinuation<Void, Never>] = []
    func save(_ envelope: VaultEnvelope, key: SymmetricKey, directory: URL) async throws -> URL {
        revisions.append(envelope.header.revision)
        let waiters = entered; entered.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { completions.append($0) }
        return directory.appendingPathComponent("synthetic-\(envelope.header.revision).keydesk")
    }
    func waitForEntry() async {
        if !completions.isEmpty { return }
        await withCheckedContinuation { entered.append($0) }
    }
    func complete() {
        let pending = completions; completions.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@Suite(.serialized) @MainActor
struct BackupResponsivenessTests {
    @Test func lockingDoesNotWaitForCloudSaveAndOldCompletionCannotPublish() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-responsive-\(UUID())")
        let folder = root.appendingPathComponent("cloud"), writer = PausedBackupWriter()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = VaultModel(directory: root.appendingPathComponent("vault"), defaultBackupDirectory: nil,
                               keys: MemoryKeyStore(), serve: false, observeSystemEvents: false, backupWriter: writer)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun(startNew: true)
        let configuration = Task { try await model.configureBackup(directory: folder, destination: .googleDrive) }
        await writer.waitForEntry()
        #expect(model.backupInProgress && model.backedUpRevision == nil)
        model.lock()
        #expect(model.snapshot == nil && model.backedUpRevision == nil)
        await writer.complete()
        do { try await configuration.value; Issue.record("Old backup configuration must not succeed after lock") }
        catch VaultError.locked {} catch { Issue.record("Unexpected error: \(error)") }
        await model.waitForBackups()
        #expect(!model.backupInProgress && model.lastBackupFile == nil && model.backedUpRevision == nil)
    }

    @Test func realBackupWriterCompletesBeforeReportingVerified() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-verified-\(UUID())")
        let folder = root.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = VaultModel(directory: root.appendingPathComponent("vault"), defaultBackupDirectory: nil,
                               keys: MemoryKeyStore(), serve: false, observeSystemEvents: false)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun(startNew: true)
        try await model.configureBackup(directory: folder)
        try model.addProject("Synthetic background save")
        model.flushBackup()
        await model.waitForBackups()
        let file = try #require(model.lastBackupFile)
        #expect(try VaultFileStore.read(at: file).header.revision == model.snapshot?.revision)
        #expect(!model.backupInProgress && !model.hasUnbackedChanges)
    }
}
