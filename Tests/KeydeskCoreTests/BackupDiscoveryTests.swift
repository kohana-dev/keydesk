import Testing
import Foundation
import CryptoKit
@testable import KeydeskCore

struct BackupDiscoveryTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-backup-discovery-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func fixture(revision: UInt64 = 0, vaultID: UUID = UUID(), key: SymmetricKey = SymmetricKey(size: .bits256)) throws -> (VaultEnvelope, SymmetricKey) {
        var snapshot = VaultSnapshot(); snapshot.revision = revision
        var header = VaultHeader(vaultID: vaultID); header.revision = revision
        let recovery = SymmetricKey(size: .bits256)
        let wrapped = try VaultCrypto.wrap(key, recoveryKey: recovery, vaultID: vaultID, keyEpoch: header.keyEpoch)
        return (try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key), key)
    }

    private func write(_ envelope: VaultEnvelope, named name: String, in directory: URL, at date: Date) throws -> URL {
        let url = directory.appendingPathComponent("Keydesk-\(envelope.header.vaultID)-\(name).keydesk")
        try VaultFileStore.atomicWrite(JSONEncoder().encode(envelope), to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    @Test func discoveryReadsOnlyTheNewestReadableLocalBackup() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (envelope, _) = try fixture(), now = Date(timeIntervalSince1970: 1_750_000_000)
        let older = try write(envelope, named: "older", in: root, at: now.addingTimeInterval(-10))
        let newest = try write(envelope, named: "newest", in: root, at: now)
        var reads: [URL] = []
        let result = BackupManager.latestBackup(in: root, locallyAvailable: BackupManager.isLocallyAvailable) { url in
            reads.append(url); return try VaultFileStore.read(at: url)
        }
        #expect(result?.url.lastPathComponent == newest.lastPathComponent)
        #expect(reads.map(\.lastPathComponent) == [newest.lastPathComponent] && !reads.map(\.lastPathComponent).contains(older.lastPathComponent))
    }

    @Test func unreadableNewestBackupFallsBackToOlderLocalCopy() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (envelope, _) = try fixture(), now = Date(timeIntervalSince1970: 1_750_000_000)
        let older = try write(envelope, named: "older", in: root, at: now)
        let invalid = root.appendingPathComponent("Keydesk-invalid.keydesk")
        try Data("corrupt fixture".utf8).write(to: invalid)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(10)], ofItemAtPath: invalid.path)
        #expect(BackupManager.latestBackup(in: root)?.url.lastPathComponent == older.lastPathComponent)
    }

    @Test func discoveryDoesNotReadCloudPlaceholdersAndManualReadStillWorks() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (envelope, _) = try fixture(), now = Date(timeIntervalSince1970: 1_750_000_000)
        let local = try write(envelope, named: "local", in: root, at: now)
        let placeholder = try write(envelope, named: "placeholder", in: root, at: now.addingTimeInterval(10))
        var reads: [URL] = []
        let result = BackupManager.latestBackup(in: root, locallyAvailable: { $0.lastPathComponent != placeholder.lastPathComponent }) { url in
            reads.append(url); return try VaultFileStore.read(at: url)
        }
        #expect(result?.url.lastPathComponent == local.lastPathComponent && reads.map(\.lastPathComponent) == [local.lastPathComponent])
        #expect(try VaultFileStore.read(at: placeholder).header.vaultID == envelope.header.vaultID)
    }

    @Test func equalModificationDatesStillSelectTheHigherRevision() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), key = SymmetricKey(size: .bits256), now = Date(timeIntervalSince1970: 1_750_000_000)
        let (old, _) = try fixture(revision: 1, vaultID: id, key: key)
        let (new, _) = try fixture(revision: 2, vaultID: id, key: key)
        _ = try write(old, named: "old", in: root, at: now)
        let newest = try write(new, named: "new", in: root, at: now)
        #expect(BackupManager.latestBackup(in: root)?.url.lastPathComponent == newest.lastPathComponent)
    }

    @Test func pruningNeverReadsOrDeletesAnUnavailableCloudBackup() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (envelope, key) = try fixture(), now = Date(timeIntervalSince1970: 1_750_000_000)
        let obsolete = try write(envelope, named: "obsolete", in: root, at: now.addingTimeInterval(-10))
        let newest = try write(envelope, named: "newest", in: root, at: now)
        let placeholder = try write(envelope, named: "placeholder", in: root, at: now.addingTimeInterval(-20))
        var reads: [URL] = []
        try BackupManager.prune(directory: root, vaultID: envelope.header.vaultID, key: key, now: now,
                                locallyAvailable: { $0.lastPathComponent != placeholder.lastPathComponent }) { url in
            reads.append(url); return try VaultFileStore.read(at: url)
        }
        #expect(!reads.map(\.lastPathComponent).contains(placeholder.lastPathComponent))
        #expect(FileManager.default.fileExists(atPath: placeholder.path))
        #expect(FileManager.default.fileExists(atPath: newest.path))
        #expect(!FileManager.default.fileExists(atPath: obsolete.path))
    }

    @Test func automaticDiscoveryRejectsSymlinksAndNonRegularFiles() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let (envelope, _) = try fixture()
        let regular = try write(envelope, named: "local", in: root, at: Date())
        let symbolic = root.appendingPathComponent("Keydesk-link.keydesk")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: regular)
        let folder = root.appendingPathComponent("Keydesk-directory.keydesk")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(BackupManager.isLocallyAvailable(regular))
        #expect(!BackupManager.isLocallyAvailable(symbolic))
        #expect(!BackupManager.isLocallyAvailable(folder))
    }
}
