import Foundation
import CryptoKit
import LocalAuthentication
import KeydeskCore

/// Keychain and OS authentication used by the vault model. The system implementation talks to the
/// protected Keychain; tests substitute an in-memory store so the real first-run and restore paths run.
@MainActor
protocol VaultKeyStore: AnyObject {
    func authenticate(reason: String) async throws -> LAContext?
    func saveDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID) throws
    func loadDeviceKey(envelope: VaultEnvelope, context: LAContext?) throws -> SymmetricKey
    func removeDeviceKey(id: UUID, epoch: UUID)
    func restoreDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID, context: LAContext?) throws
    func saveDepositPublicKey(_ data: Data, vaultID: UUID) throws
    func loadDepositPublicKey(vaultID: UUID) throws -> Data
    /// Stores the recovery key in iCloud Keychain. Returns false when the item could not be written.
    func saveRecoveryKey(_ key: SymmetricKey, vaultID: UUID) -> Bool
    func loadRecoveryKey(vaultID: UUID) -> SymmetricKey?
    /// Vault IDs whose recovery keys reached this Mac through iCloud Keychain.
    func knownRecoveryVaults() -> [UUID]
}

@MainActor
final class SystemKeyStore: VaultKeyStore {
    func authenticate(reason: String) async throws -> LAContext? { try await DeviceKeyStore.authenticate(reason: reason) }
    func saveDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID) throws { try DeviceKeyStore.save(key, id: id, epoch: epoch) }
    func loadDeviceKey(envelope: VaultEnvelope, context: LAContext?) throws -> SymmetricKey { try DeviceKeyStore.load(envelope: envelope, context: context) }
    func removeDeviceKey(id: UUID, epoch: UUID) { DeviceKeyStore.remove(id: id, epoch: epoch) }
    func restoreDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID, context: LAContext?) throws { try DeviceKeyStore.restoreDeviceKey(key, id: id, epoch: epoch, context: context) }
    func saveDepositPublicKey(_ data: Data, vaultID: UUID) throws { try DeviceKeyStore.saveDepositPublicKey(data, vaultID: vaultID) }
    func loadDepositPublicKey(vaultID: UUID) throws -> Data { try DeviceKeyStore.loadDepositPublicKey(vaultID: vaultID) }
    func saveRecoveryKey(_ key: SymmetricKey, vaultID: UUID) -> Bool { DeviceKeyStore.saveRecoveryKey(key, vaultID: vaultID) }
    func loadRecoveryKey(vaultID: UUID) -> SymmetricKey? { DeviceKeyStore.loadRecoveryKey(vaultID: vaultID) }
    func knownRecoveryVaults() -> [UUID] { DeviceKeyStore.knownRecoveryVaults() }
}

extension SymmetricKey {
    var rawData: Data { withUnsafeBytes { Data($0) } }
}
