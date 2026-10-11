import Foundation
import CryptoKit
import KeydeskCore

extension VaultModel {
    /// Reads recovery material only inside the signed app after OS authentication.
    /// Restores into a fresh encrypted file and disposable protected Keychain identity.
    func verifyCloudRecovery() async throws -> [String: Bool] {
        guard !isDemo else { throw VaultError.invalidData }
        let token = generation
        let context = try await keys.authenticate(reason: "iCloud 백업을 별도 암호화 금고로 복원 검증합니다. 기존 금고는 바꾸지 않습니다.")
        guard token == generation else { throw VaultError.locked }
        flushBackup()
        guard let directory = backupDirectory ?? Self.iCloudBackupDirectory,
              let latest = BackupManager.latestBackup(in: directory),
              let recovery = keys.loadRecoveryKey(vaultID: latest.envelope.header.vaultID) else { throw VaultError.invalidRecoveryKey }
        let original = try Data(contentsOf: store.vaultURL)
        let current = try store.read()
        guard current.header.vaultID == latest.envelope.header.vaultID, current.header.revision == latest.envelope.header.revision else { throw VaultError.staleRevision }
        let recovered = try VaultCrypto.recover(latest.envelope, code: RecoveryCode.encode(recovery))
        let restored = try VaultCrypto.open(latest.envelope, key: recovered)
        let currentSnapshot = try VaultCrypto.open(current, key: recovered)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard try encoder.encode(restored) == encoder.encode(currentSnapshot) else { throw VaultError.invalidData }
        let root = store.directory.appendingPathComponent("recovery-check-\(UUID())")
        let isolated = VaultFileStore(directory: root)
        var header = VaultHeader(); header.revision = restored.revision
        let isolatedKey = SymmetricKey(size: .bits256), isolatedRecovery = SymmetricKey(size: .bits256)
        defer { keys.removeDeviceKey(id: header.vaultID, epoch: header.keyEpoch); try? FileManager.default.removeItem(at: root) }
        let wrapped = try VaultCrypto.wrap(isolatedKey, recoveryKey: isolatedRecovery, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        let envelope = try VaultCrypto.seal(restored, header: header, wrappedKey: wrapped, key: isolatedKey)
        try isolated.write(envelope, expectedRevision: nil)
        try keys.saveDeviceKey(isolatedKey, id: header.vaultID, epoch: header.keyEpoch)
        let readBack = try isolated.read()
        let keyFromKeychain = try keys.loadDeviceKey(envelope: readBack, context: context)
        let opened = try VaultCrypto.open(readBack, key: keyFromKeychain)
        guard try encoder.encode(opened) == encoder.encode(restored) else { throw VaultError.invalidData }
        let wrongRecoveryRejected = (try? VaultCrypto.recover(latest.envelope, code: RecoveryCode.encode(SymmetricKey(size: .bits256)))) == nil
        var ciphertext = latest.envelope.ciphertext; ciphertext[ciphertext.startIndex] ^= 1
        let altered = VaultEnvelope(header: latest.envelope.header, recoveryWrappedKey: latest.envelope.recoveryWrappedKey, ciphertext: ciphertext)
        let tamperingRejected = (try? VaultCrypto.open(altered, key: recovered)) == nil
        let unchanged = try Data(contentsOf: store.vaultURL) == original
        guard wrongRecoveryRejected, tamperingRejected, unchanged else { throw VaultError.invalidData }
        return ["same_mac_isolated_restore": true, "icloud_keychain_recovery_used": true, "backup_uploaded": BackupLocation.cloudUpload(of: latest.url) == .uploaded, "fresh_protected_keychain_reopen": true, "restored_snapshot_matches_current": true, "wrong_recovery_rejected": true, "tampered_backup_rejected": true, "original_vault_unchanged": unchanged, "cross_mac_sync_verified": false, "secrets_returned": false]
    }
}
