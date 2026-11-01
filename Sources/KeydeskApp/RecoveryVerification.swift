import Foundation
import CryptoKit
import KeydeskCore

extension VaultModel {
    /// Restores a backup into a disposable identity without changing the current vault.
    func verifyCloudRecovery() async throws -> [String: Bool] {
        guard !isDemo else { throw VaultError.invalidData }
        let token = generation, revision = snapshot?.revision
        let context = try await keys.authenticate(reason: L10n.tr("iCloud 백업을 별도 암호화 금고로 복원 검증합니다. 기존 금고는 바꾸지 않습니다.", "Authenticate to verify recovery of the iCloud backup in a separate encrypted vault. The existing vault will not be changed."))
        guard token == generation, snapshot?.revision == revision else { throw VaultError.locked }
        await flushBackupAndWait()
        guard token == generation, snapshot?.revision == revision else { throw VaultError.locked }
        guard let directory = backupDirectory ?? Self.iCloudBackupDirectory else { throw VaultError.invalidRecoveryKey }
        let store = store
        let input = try await BackgroundIO.run {
            guard let latest = BackupManager.latestBackup(in: directory) else { throw VaultError.invalidRecoveryKey }
            let original = try Data(contentsOf: store.vaultURL), current = try store.read()
            guard current.header.vaultID == latest.envelope.header.vaultID,
                  current.header.revision == latest.envelope.header.revision else { throw VaultError.staleRevision }
            return (latest: latest.envelope, url: latest.url, original: original, current: current)
        }
        guard token == generation, snapshot?.revision == revision else { throw VaultError.locked }
        guard let recovery = await keys.loadRecoveryKey(vaultID: input.latest.header.vaultID) else { throw VaultError.invalidRecoveryKey }
        guard token == generation, snapshot?.revision == revision else { throw VaultError.locked }
        let root = store.directory.appendingPathComponent("recovery-check-\(UUID())")
        let isolated = VaultFileStore(directory: root)
        let verificationHeader = VaultHeader()
        let id = verificationHeader.vaultID, epoch = verificationHeader.keyEpoch
        do {
            let fixture = try await BackgroundIO.run {
                let recovered = try VaultCrypto.recover(input.latest, code: RecoveryCode.encode(recovery))
                let restored = try VaultCrypto.open(input.latest, key: recovered)
                let currentSnapshot = try VaultCrypto.open(input.current, key: recovered)
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                let expected = try encoder.encode(restored)
                guard try expected == encoder.encode(currentSnapshot) else { throw VaultError.invalidData }
                var header = verificationHeader; header.revision = restored.revision
                let isolatedKey = SymmetricKey(size: .bits256), isolatedRecovery = SymmetricKey(size: .bits256)
                let wrapped = try VaultCrypto.wrap(isolatedKey, recoveryKey: isolatedRecovery, vaultID: id, keyEpoch: epoch)
                let envelope = try VaultCrypto.seal(restored, header: header, wrappedKey: wrapped, key: isolatedKey)
                try isolated.write(envelope, expectedRevision: nil)
                return (key: isolatedKey, recovered: recovered, envelope: try isolated.read(), expected: expected)
            }
            guard token == generation, snapshot?.revision == revision else { throw VaultError.locked }
            try await keys.saveDeviceKey(fixture.key, id: id, epoch: epoch)
            guard token == generation, snapshot?.revision == revision else { throw VaultError.locked }
            let keyFromKeychain = try await keys.loadDeviceKey(envelope: fixture.envelope, context: context)
            guard token == generation, snapshot?.revision == revision else { throw VaultError.locked }
            let report = try await BackgroundIO.run {
                let opened = try VaultCrypto.open(fixture.envelope, key: keyFromKeychain)
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                guard try encoder.encode(opened) == fixture.expected else { throw VaultError.invalidData }
                let wrongRecoveryRejected = (try? VaultCrypto.recover(input.latest, code: RecoveryCode.encode(SymmetricKey(size: .bits256)))) == nil
                var ciphertext = input.latest.ciphertext; ciphertext[ciphertext.startIndex] ^= 1
                let altered = VaultEnvelope(header: input.latest.header, recoveryWrappedKey: input.latest.recoveryWrappedKey, ciphertext: ciphertext)
                let tamperingRejected = (try? VaultCrypto.open(altered, key: fixture.recovered)) == nil
                let unchanged = try Data(contentsOf: store.vaultURL) == input.original
                guard wrongRecoveryRejected, tamperingRejected, unchanged else { throw VaultError.invalidData }
                return ["same_mac_isolated_restore": true, "icloud_keychain_recovery_used": true, "backup_uploaded": BackupLocation.cloudUpload(of: input.url) == .uploaded, "fresh_protected_keychain_reopen": true, "restored_snapshot_matches_current": true, "wrong_recovery_rejected": true, "tampered_backup_rejected": true, "original_vault_unchanged": true, "cross_mac_sync_verified": false, "secrets_returned": false]
            }
            await keys.removeDeviceKey(id: id, epoch: epoch)
            _ = try? await BackgroundIO.run { try FileManager.default.removeItem(at: root) }
            guard token == generation, snapshot?.revision == revision else { throw VaultError.locked }
            return report
        } catch {
            await keys.removeDeviceKey(id: id, epoch: epoch)
            _ = try? await BackgroundIO.run { try FileManager.default.removeItem(at: root) }
            throw error
        }
    }
}
