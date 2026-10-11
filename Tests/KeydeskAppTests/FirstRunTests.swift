import Testing
import Foundation
import CryptoKit
import LocalAuthentication
import KeydeskCore
@testable import KeydeskApp

/// Stands in for the protected Keychain. `recovery` plays the role of iCloud Keychain and can be shared
/// between two instances to simulate a second Mac signed in to the same Apple Account.
@MainActor
final class MemoryKeyStore: VaultKeyStore {
    final class Cloud { var recovery: [UUID: Data] = [:] }
    var device: [String: Data] = [:]
    var depositPublic: [UUID: Data] = [:]
    let cloud: Cloud
    var authentications = 0
    var denyAuthentication = false
    var recoveryWritable = true
    init(cloud: Cloud = Cloud()) { self.cloud = cloud }
    func authenticate(reason: String) async throws -> LAContext? {
        authentications += 1
        if denyAuthentication { throw VaultError.locked }
        return nil
    }
    func saveDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID) throws { device["\(id)/\(epoch)"] = key.rawData }
    func loadDeviceKey(envelope: VaultEnvelope, context: LAContext?) throws -> SymmetricKey {
        guard let data = device["\(envelope.header.vaultID)/\(envelope.header.keyEpoch)"] else { throw VaultError.accessDenied }
        return SymmetricKey(data: data)
    }
    func removeDeviceKey(id: UUID, epoch: UUID) { device.removeValue(forKey: "\(id)/\(epoch)") }
    func restoreDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID, context: LAContext?) throws { try saveDeviceKey(key, id: id, epoch: epoch) }
    func saveDepositPublicKey(_ data: Data, vaultID: UUID) throws { depositPublic[vaultID] = data }
    func loadDepositPublicKey(vaultID: UUID) throws -> Data {
        guard let data = depositPublic[vaultID] else { throw VaultError.accessDenied }; return data
    }
    func saveRecoveryKey(_ key: SymmetricKey, vaultID: UUID) -> Bool {
        guard recoveryWritable else { return false }
        cloud.recovery[vaultID] = key.rawData; return true
    }
    func loadRecoveryKey(vaultID: UUID) -> SymmetricKey? { cloud.recovery[vaultID].map(SymmetricKey.init(data:)) }
    func knownRecoveryVaults() -> [UUID] { Array(cloud.recovery.keys) }
}

@Suite(.serialized) @MainActor
struct FirstRunTests {
    final class Folders {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-firstrun-\(UUID())")
        var iCloud: URL { root.appendingPathComponent("iCloud Drive/Keydesk") }
        func mac(_ name: String) -> URL { root.appendingPathComponent(name) }
        deinit { try? FileManager.default.removeItem(at: root) }
    }
    func model(_ folders: Folders, _ mac: String, _ keys: MemoryKeyStore) -> VaultModel {
        VaultModel(directory: folders.mac(mac), defaultBackupDirectory: folders.iCloud, keys: keys, serve: false)
    }
    func backups(_ folders: Folders) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folders.iCloud, includingPropertiesForKeys: nil).filter { $0.pathExtension == "keydesk" }
    }

    @Test func firstLaunchCreatesVaultWithoutQuestionsAndBacksUpToICloud() async throws {
        let folders = Folders(), keys = MemoryKeyStore()
        let app = model(folders, "mac-a", keys); defer { app.shutdown() }
        await app.prepareFirstRun()
        #expect(app.exists && app.snapshot != nil && app.firstRun == nil)
        #expect(keys.authentications == 0)
        #expect(app.recoveryKeySaved && keys.cloud.recovery.count == 1)
        #expect(!app.hasUnbackedChanges && app.backupDirectory?.standardizedFileURL == folders.iCloud.standardizedFileURL)
        // The iCloud backup opens with the recovery key from iCloud Keychain alone.
        let backup = try VaultFileStore.read(at: #require(try backups(folders).first))
        let recovery = try #require(keys.cloud.recovery[backup.header.vaultID])
        #expect(try VaultCrypto.open(backup, key: VaultCrypto.recover(backup, code: RecoveryCode.encode(SymmetricKey(data: recovery)))).recoveryCode != nil)
    }

    @Test func secondMacRestoresLatestBackupAutomatically() async throws {
        let folders = Folders(), cloud = MemoryKeyStore.Cloud()
        let first = model(folders, "mac-a", MemoryKeyStore(cloud: cloud))
        await first.prepareFirstRun()
        try first.addProject("Studio Notes"); try first.addProject("Daylight")
        first.lock(); first.shutdown()

        let keys = MemoryKeyStore(cloud: cloud)
        let second = model(folders, "mac-b", keys); defer { second.shutdown() }
        await second.prepareFirstRun()
        #expect(second.firstRun == nil)
        #expect(second.snapshot?.projects.map(\.name) == ["Studio Notes", "Daylight"])
        #expect(keys.authentications == 1)
        // The restored vault gets its own identity and recovery entry, and keeps backing up to iCloud Drive.
        #expect(cloud.recovery.count == 2 && second.recoveryKeySaved && !second.hasUnbackedChanges)
        second.lock(); await second.unlock()
        #expect(second.snapshot?.projects.count == 2)
    }

    @Test func cancelledAuthenticationDoesNotCreateEmptyVault() async throws {
        let folders = Folders(), cloud = MemoryKeyStore.Cloud()
        let first = model(folders, "mac-a", MemoryKeyStore(cloud: cloud))
        await first.prepareFirstRun(); try first.addProject("Keep"); first.lock(); first.shutdown()
        let keys = MemoryKeyStore(cloud: cloud); keys.denyAuthentication = true
        let second = model(folders, "mac-b", keys); defer { second.shutdown() }
        await second.prepareFirstRun()
        guard case .restoreStopped = second.firstRun else { Issue.record("expected restoreStopped, got \(String(describing: second.firstRun))"); return }
        #expect(!second.exists)
        keys.denyAuthentication = false
        await second.prepareFirstRun()
        #expect(second.snapshot?.projects.map(\.name) == ["Keep"])
    }

    @Test func backupWithoutSyncedRecoveryKeyWaitsForCode() async throws {
        let folders = Folders(), firstKeys = MemoryKeyStore()
        let first = model(folders, "mac-a", firstKeys)
        await first.prepareFirstRun(); try first.addProject("Manual"); first.lock(); first.shutdown()
        let code = try RecoveryCode.encode(SymmetricKey(data: #require(firstKeys.cloud.recovery.values.first)))

        let second = model(folders, "mac-b", MemoryKeyStore()); defer { second.shutdown() }
        await second.prepareFirstRun()
        guard case .needsRecoveryCode(let url) = second.firstRun else { Issue.record("expected needsRecoveryCode"); return }
        #expect(!second.exists)
        try await second.restore(at: url, code: code)
        #expect(second.snapshot?.projects.map(\.name) == ["Manual"] && second.firstRun == nil)
    }

    @Test func knownVaultWithoutBackupWaitsInsteadOfCreatingEmptyVault() async throws {
        let folders = Folders(), keys = MemoryKeyStore()
        keys.cloud.recovery[UUID()] = SymmetricKey(size: .bits256).rawData
        let app = model(folders, "mac-b", keys); defer { app.shutdown() }
        await app.prepareFirstRun()
        #expect(app.firstRun == .waitingForBackup && !app.exists)
        await app.prepareFirstRun(startNew: true)
        #expect(app.exists && app.snapshot != nil)
    }

    @Test func missingICloudKeychainItemIsRepairedOrReported() async throws {
        let folders = Folders(), keys = MemoryKeyStore()
        let app = model(folders, "mac-a", keys); defer { app.shutdown() }
        await app.prepareFirstRun()
        let code = try #require(app.snapshot?.recoveryCode)
        keys.cloud.recovery.removeAll()
        app.lock(); await app.unlock()
        #expect(app.recoveryKeySaved && keys.cloud.recovery.values.first.map { SymmetricKey(data: $0) }.map(RecoveryCode.encode) == code)
        keys.cloud.recovery.removeAll(); keys.recoveryWritable = false
        app.lock(); await app.unlock()
        #expect(!app.recoveryKeySaved)
        #expect(try await app.authenticatedRecoveryCode() == code)
    }

    @Test func rotationUpdatesICloudKeychainAndBackup() async throws {
        let folders = Folders(), keys = MemoryKeyStore()
        let app = model(folders, "mac-a", keys); defer { app.shutdown() }
        await app.prepareFirstRun()
        let vaultID = try #require(keys.cloud.recovery.keys.first)
        let newCode = RecoveryCode.encode(SymmetricKey(size: .bits256))
        try await app.rotateVaultKeys(code: newCode, dataKey: true)
        #expect(keys.cloud.recovery[vaultID].map { RecoveryCode.encode(SymmetricKey(data: $0)) } == newCode)
        let latest = try #require(BackupManager.latestBackup(in: folders.iCloud))
        #expect(try VaultCrypto.open(latest.envelope, key: VaultCrypto.recover(latest.envelope, code: newCode)).recoveryCode == newCode)
        #expect(!app.hasUnbackedChanges)
        app.lock(); await app.unlock(); #expect(app.snapshot != nil)
    }
}
