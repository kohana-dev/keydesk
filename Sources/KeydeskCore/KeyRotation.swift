import CryptoKit

public enum KeyRotation {
    public static func rotate(_ snapshot: VaultSnapshot, current: VaultEnvelope, newRecoveryCode: String, rotateDataKey: Bool, currentKey: SymmetricKey) throws -> (VaultEnvelope, SymmetricKey) {
        let key = rotateDataKey ? SymmetricKey(size: .bits256) : currentKey
        var header = rotateDataKey ? VaultHeader(vaultID: current.header.vaultID) : current.header
        var snapshot = snapshot; snapshot.revision += 1; header.revision = snapshot.revision
        snapshot.record(rotateDataKey ? "데이터 키 교체" : "복구 키 교체")
        let recovery = try RecoveryCode.decode(newRecoveryCode)
        let wrapped = try VaultCrypto.wrap(key, recoveryKey: recovery, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        return (try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key), key)
    }
}
