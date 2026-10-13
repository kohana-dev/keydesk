import Testing
import Foundation
import KeydeskCore
@testable import KeydeskApp

@Suite(.serialized) @MainActor
struct GoogleDriveBackupTests {
    final class Folders {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cellar-google-backup-tests-\(UUID())", isDirectory: true)
        var vault: URL { root.appendingPathComponent("first-mac", isDirectory: true) }
        var drive: URL { root.appendingPathComponent("synthetic-google-drive", isDirectory: true) }
        var folder: URL { root.appendingPathComponent("external-backups", isDirectory: true) }
        deinit { try? FileManager.default.removeItem(at: root) }

        func create(_ url: URL) throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func model(directory: URL, keys: MemoryKeyStore = MemoryKeyStore(), defaultBackupDirectory: URL? = nil) -> VaultModel {
        VaultModel(directory: directory, defaultBackupDirectory: defaultBackupDirectory,
                   keys: keys, serve: false, observeSystemEvents: false)
    }

    func backups(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "keydesk" }
    }

    @Test func googleDriveChoiceImmediatelyCreatesRecoverableEncryptedBackup() async throws {
        let folders = Folders()
        try folders.create(folders.drive)
        let app = model(directory: folders.vault)
        defer { app.shutdown() }
        await app.prepareFirstRun(startNew: true)
        try app.addProject("Synthetic Google Project 732")
        try app.addCredential(name: "Synthetic Credential 732", value: "synthetic-credential-value-732",
                              provider: "Synthetic Provider", account: "", note: "", variable: "TEST_TOKEN")
        let code = try #require(app.snapshot?.recoveryCode)

        try app.configureBackup(directory: folders.drive, destination: .googleDrive)

        #expect(app.backupDestination == .googleDrive)
        #expect(app.snapshot?.backup?.destination == .googleDrive)
        #expect(app.backedUpRevision == app.snapshot?.revision)
        #expect(app.lastBackupAt != nil && app.backupFailure == nil && !app.hasUnbackedChanges)
        #expect(app.cloudUpload == .notCloud)
        let url = try #require(app.lastBackupFile)
        #expect(url.deletingLastPathComponent().standardizedFileURL == folders.drive.standardizedFileURL)
        let bytes = try Data(contentsOf: url)
        for plaintext in ["Synthetic Google Project 732", "Synthetic Credential 732", "synthetic-credential-value-732"] {
            #expect(bytes.range(of: Data(plaintext.utf8)) == nil)
        }
        let envelope = try VaultFileStore.read(at: url)
        let restored = try VaultCrypto.open(envelope, key: VaultCrypto.recover(envelope, code: code))
        #expect(restored.projects.map(\.name) == ["Synthetic Google Project 732"])
        #expect(restored.credentials.first?.currentValue == "synthetic-credential-value-732")
        #expect(restored.backup?.destination == .googleDrive)
    }

    @Test func selectedProviderAndFolderSurviveLockAndReopen() async throws {
        let folders = Folders(), keys = MemoryKeyStore()
        try folders.create(folders.drive)
        let app = model(directory: folders.vault, keys: keys)
        defer { app.shutdown() }
        await app.prepareFirstRun(startNew: true)
        try app.configureBackup(directory: folders.drive, destination: .googleDrive)
        let revision = app.snapshot?.revision
        app.lock()
        await app.unlock()
        #expect(app.backupDestination == .googleDrive)
        #expect(app.backupDirectory?.standardizedFileURL == folders.drive.standardizedFileURL)
        #expect(app.backedUpRevision == revision && !app.hasUnbackedChanges)
        app.shutdown()

        let reopened = model(directory: folders.vault, keys: keys)
        defer { reopened.shutdown() }
        await reopened.unlock()
        #expect(reopened.snapshot?.backup?.destination == .googleDrive)
        #expect(reopened.backupDirectory?.standardizedFileURL == folders.drive.standardizedFileURL)
        #expect(reopened.backedUpRevision == revision && !reopened.hasUnbackedChanges)
        #expect(reopened.cloudUpload == .notCloud)
    }

    @Test func deletedBackupCanBeRecreatedWithoutChangesAndIsDetectedOnReopen() async throws {
        let folders = Folders(), keys = MemoryKeyStore()
        try folders.create(folders.drive)
        let app = model(directory: folders.vault, keys: keys)
        defer { app.shutdown() }
        await app.prepareFirstRun(startNew: true)
        try app.configureBackup(directory: folders.drive, destination: .googleDrive)
        let revision = try #require(app.snapshot?.revision)
        let deletedFile = try #require(app.lastBackupFile)
        try FileManager.default.removeItem(at: deletedFile)

        // The user's Back Up Now action must write again even when the vault has not changed.
        app.flushBackup(force: true)
        let recreatedFile = try #require(app.lastBackupFile)
        #expect(recreatedFile != deletedFile && FileManager.default.fileExists(atPath: recreatedFile.path))
        #expect(try VaultFileStore.read(at: recreatedFile).header.revision == revision)
        #expect(app.snapshot?.revision == revision && app.backedUpRevision == revision)
        #expect(app.backupFailure == nil && !app.hasUnbackedChanges)
        app.shutdown()
        try FileManager.default.removeItem(at: recreatedFile)
        try FileManager.default.removeItem(at: folders.drive)

        let reopened = model(directory: folders.vault, keys: keys)
        defer { reopened.shutdown() }
        await reopened.unlock()
        // The old status record alone cannot prove that a removed backup still exists.
        #expect(reopened.snapshot?.revision == revision && reopened.backupDestination == .googleDrive)
        #expect(reopened.backedUpRevision == nil && reopened.lastBackupAt == nil)
        #expect(reopened.lastBackupFile == nil && reopened.hasUnbackedChanges)
        #expect(reopened.backupFailure != nil && !FileManager.default.fileExists(atPath: folders.drive.path))
        try folders.create(folders.drive)
        reopened.flushBackup()
        #expect(reopened.backedUpRevision == revision && !reopened.hasUnbackedChanges)
        let latest = try #require(BackupManager.latestBackup(in: folders.drive))
        #expect(latest.envelope.header.revision == revision && reopened.cloudUpload == .notCloud)
    }

    @Test func invalidDirectoryCannotChangeBackupSelectionOrVaultRevision() async throws {
        let folders = Folders()
        try folders.create(folders.drive)
        let app = model(directory: folders.vault)
        defer { app.shutdown() }
        await app.prepareFirstRun(startNew: true)
        try app.configureBackup(directory: folders.drive, destination: .googleDrive)
        let baseline = try Data(contentsOf: app.store.vaultURL)
        let revision = app.snapshot?.revision, backedUpRevision = app.backedUpRevision
        let originalBackups = try Set(backups(in: folders.drive))
        let child = folders.vault.appendingPathComponent("nested-backups", isDirectory: true)
        try folders.create(child)
        let file = folders.root.appendingPathComponent("not-a-directory")
        try Data("synthetic fixture".utf8).write(to: file)
        let link = folders.root.appendingPathComponent("vault-directory-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folders.vault)

        for invalid in [folders.root.appendingPathComponent("missing-directory", isDirectory: true),
                        file, folders.vault, child, link] {
            #expect(throws: (any Error).self) {
                try app.configureBackup(directory: invalid, destination: .folder)
            }
            #expect(app.snapshot?.revision == revision && app.backedUpRevision == backedUpRevision)
            #expect(app.backupDestination == .googleDrive)
            #expect(app.backupDirectory?.standardizedFileURL == folders.drive.standardizedFileURL)
            #expect(try Data(contentsOf: app.store.vaultURL) == baseline)
            #expect(try Set(backups(in: folders.drive)) == originalBackups)
        }
    }

    @Test func switchingAndDisablingLeavesExistingBackupsIntact() async throws {
        let folders = Folders()
        try folders.create(folders.drive)
        try folders.create(folders.folder)
        let app = model(directory: folders.vault)
        defer { app.shutdown() }
        await app.prepareFirstRun(startNew: true)
        try app.configureBackup(directory: folders.drive, destination: .googleDrive)
        let googleBackups = try Set(backups(in: folders.drive))
        #expect(!googleBackups.isEmpty)

        try app.configureBackup(directory: folders.folder, destination: .folder)
        #expect(app.backupDestination == .folder && !app.hasUnbackedChanges)
        #expect(try Set(backups(in: folders.drive)) == googleBackups)
        let folderBackups = try Set(backups(in: folders.folder))
        #expect(!folderBackups.isEmpty)

        try app.configureBackup(directory: nil)
        #expect(app.snapshot?.backup == nil && app.backupDestination == nil && app.backupDirectory == nil)
        #expect(app.backedUpRevision == nil && app.lastBackupAt == nil && app.hasUnbackedChanges)
        #expect(try Set(backups(in: folders.drive)) == googleBackups)
        #expect(try Set(backups(in: folders.folder)) == folderBackups)
        try app.addProject("Synthetic offline change")
        app.flushBackup()
        #expect(try Set(backups(in: folders.drive)) == googleBackups)
        #expect(try Set(backups(in: folders.folder)) == folderBackups)
    }

    @Test(arguments: [false, true])
    func inaccessibleGoogleFolderDoesNotAdvanceBackupAndRetryRecovers(replaceWithFile: Bool) async throws {
        let folders = Folders()
        try folders.create(folders.drive)
        let app = model(directory: folders.vault)
        defer { app.shutdown() }
        await app.prepareFirstRun(startNew: true)
        try app.configureBackup(directory: folders.drive, destination: .googleDrive)
        let successfulRevision = app.backedUpRevision
        try FileManager.default.removeItem(at: folders.drive)
        if replaceWithFile {
            try Data("synthetic unmounted-drive fixture".utf8).write(to: URL(fileURLWithPath: folders.drive.path))
        }
        try app.addProject("Synthetic change while Drive unavailable")
        app.flushBackup()

        #expect(app.backupFailure != nil && app.hasUnbackedChanges)
        #expect(app.backedUpRevision == successfulRevision)
        #expect(app.backupDestination == .googleDrive && app.cloudUpload == .notCloud)
        if !replaceWithFile { #expect(!FileManager.default.fileExists(atPath: folders.drive.path)) }
        else { try FileManager.default.removeItem(at: folders.drive) }
        try folders.create(folders.drive)
        app.flushBackup()

        #expect(app.backupFailure == nil && !app.hasUnbackedChanges)
        #expect(app.backedUpRevision == app.snapshot?.revision)
        let latest = try #require(BackupManager.latestBackup(in: folders.drive))
        #expect(latest.envelope.header.revision == app.snapshot?.revision)
    }

    @Test(arguments: [false, true])
    func restoringGoogleBackupClearsPreviousMacDestinationAndAllowsNewChoice(hasICloudDefault: Bool) async throws {
        let folders = Folders()
        try folders.create(folders.drive)
        let first = model(directory: folders.vault)
        defer { first.shutdown() }
        await first.prepareFirstRun(startNew: true)
        try first.addProject("Synthetic restored Google project")
        try first.configureBackup(directory: folders.drive, destination: .googleDrive)
        let code = try #require(first.snapshot?.recoveryCode)
        let url = try #require(first.lastBackupFile)
        let originalBackups = try Set(backups(in: folders.drive))
        let secondMac = folders.root.appendingPathComponent("second-mac", isDirectory: true)
        let newICloudDefault = folders.root.appendingPathComponent("second-mac-iCloud", isDirectory: true)
        let restored = model(directory: secondMac, defaultBackupDirectory: hasICloudDefault ? newICloudDefault : nil)
        defer { restored.shutdown() }

        // A new Mac must keep the restore choice available instead of creating an empty vault first.
        await restored.prepareFirstRun()
        #expect(!restored.exists && restored.snapshot == nil && restored.firstRun != nil)
        try await restored.restore(at: url, code: code)

        #expect(restored.snapshot?.projects.map(\.name) == ["Synthetic restored Google project"])
        #expect(restored.snapshot?.backup == nil && restored.backupDestination == nil)
        #expect(restored.backupDirectory == nil && restored.lastBackupAt == nil && restored.hasUnbackedChanges)
        #expect(!FileManager.default.fileExists(atPath: newICloudDefault.path))
        #expect(try Set(backups(in: folders.drive)) == originalBackups)
        let newDrive = folders.root.appendingPathComponent("second-mac-google-drive", isDirectory: true)
        try folders.create(newDrive)
        try restored.configureBackup(directory: newDrive, destination: .googleDrive)
        #expect(restored.backupDestination == .googleDrive && !restored.hasUnbackedChanges)
        #expect(restored.backupDirectory?.standardizedFileURL == newDrive.standardizedFileURL)
        #expect(try !backups(in: newDrive).isEmpty)
        #expect(try Set(backups(in: folders.drive)) == originalBackups)
    }
}
