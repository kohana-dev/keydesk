import Foundation
import CryptoKit

public enum VaultCrypto {
    public static func headerData(_ header: VaultHeader) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(header)
    }
    public static func seal(_ snapshot: VaultSnapshot, header: VaultHeader, wrappedKey: Data, key: SymmetricKey) throws -> VaultEnvelope {
        guard key.bitCount == 256 else { throw VaultError.invalidData }
        let checked = try snapshot.validated()
        guard checked.revision == header.revision else { throw VaultError.invalidData }
        var header = header
        guard [1, 2, 3].contains(header.format) else { throw VaultError.unsupportedFormat }
        if checked.credentials.contains(where: { $0.versions.contains(where: { $0.format.requiresTypedVault }) }) { header.format = 3 }
        else if checked.credentials.contains(where: { $0.versions.contains(where: { $0.file != nil }) }) { header.format = max(2, header.format) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        let bytes = try encoder.encode(checked)
        guard bytes.count <= 16 * 1024 * 1024 else { throw VaultError.invalidData }
        let box = try AES.GCM.seal(bytes, using: key, authenticating: headerData(header) + wrappedKey)
        guard let ciphertext = box.combined else { throw VaultError.invalidData }
        return VaultEnvelope(header: header, recoveryWrappedKey: wrappedKey, ciphertext: ciphertext)
    }
    public static func open(_ envelope: VaultEnvelope, key: SymmetricKey) throws -> VaultSnapshot {
        guard key.bitCount == 256 else { throw VaultError.invalidData }
        guard [1, 2, 3].contains(envelope.header.format), envelope.header.algorithm == "AES-256-GCM" else { throw VaultError.unsupportedFormat }
        let bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.ciphertext), using: key, authenticating: headerData(envelope.header) + envelope.recoveryWrappedKey)
        let snapshot = try JSONDecoder().decode(VaultSnapshot.self, from: bytes).validated()
        guard snapshot.revision == envelope.header.revision else { throw VaultError.invalidData }
        if envelope.header.format < 3,
           snapshot.credentials.contains(where: { $0.versions.contains(where: { $0.format.requiresTypedVault }) }) { throw VaultError.unsupportedFormat }
        return snapshot
    }
    public static func wrap(_ key: SymmetricKey, recoveryKey: SymmetricKey, vaultID: UUID, keyEpoch: UUID) throws -> Data {
        let data = key.withUnsafeBytes { Data($0) }
        guard let combined = try AES.GCM.seal(data, using: recoveryKey, authenticating: Data("Keydesk/recovery/\(vaultID)/\(keyEpoch)".utf8)).combined else { throw VaultError.invalidData }
        return combined
    }
    public static func recover(_ envelope: VaultEnvelope, code: String) throws -> SymmetricKey {
        do {
            let recovery = try RecoveryCode.decode(code)
            let data = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.recoveryWrappedKey), using: recovery, authenticating: Data("Keydesk/recovery/\(envelope.header.vaultID)/\(envelope.header.keyEpoch)".utf8))
            guard data.count == 32 else { throw VaultError.invalidRecoveryKey }
            let key = SymmetricKey(data: data)
            _ = try open(envelope, key: key)
            return key
        } catch { throw VaultError.invalidRecoveryKey }
    }
}
