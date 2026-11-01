import Foundation
import CryptoKit
import LocalAuthentication
import KeydeskCore

/// Keychain and OS authentication used by the vault model. The system implementation talks to the
/// protected Keychain; tests substitute an in-memory store so the real first-run and restore paths run.
@MainActor
protocol VaultKeyStore: AnyObject {
    func authenticate(reason: String) async throws -> LAContext?
    func saveDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID) async throws
    func loadDeviceKey(envelope: VaultEnvelope, context: LAContext?) async throws -> SymmetricKey
    func removeDeviceKey(id: UUID, epoch: UUID) async
    func restoreDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID, context: LAContext?) async throws
    func saveDepositPublicKey(_ data: Data, vaultID: UUID) async throws
    func loadDepositPublicKey(vaultID: UUID) async throws -> Data
    /// Stores the recovery key in iCloud Keychain. Returns false when the item could not be written.
    func saveRecoveryKey(_ key: SymmetricKey, vaultID: UUID) async -> Bool
    func loadRecoveryKey(vaultID: UUID) async -> SymmetricKey?
    /// Vault IDs whose recovery keys reached this Mac through iCloud Keychain.
    func knownRecoveryVaults() async -> [UUID]
}

@MainActor
final class SystemKeyStore: VaultKeyStore {
    private let worker = KeychainWorker()
    func authenticate(reason: String) async throws -> LAContext? { try await DeviceKeyStore.authenticate(reason: reason) }
    func saveDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID) async throws {
        try await worker.runThrowing { try DeviceKeyStore.save(key, id: id, epoch: epoch) }
    }
    func loadDeviceKey(envelope: VaultEnvelope, context: LAContext?) async throws -> SymmetricKey {
        let transferred = KeychainAuthenticationContext(context)
        return try await worker.runThrowing { try DeviceKeyStore.load(envelope: envelope, context: transferred.context) }
    }
    func removeDeviceKey(id: UUID, epoch: UUID) async {
        await worker.run { DeviceKeyStore.remove(id: id, epoch: epoch) }
    }
    func restoreDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID, context: LAContext?) async throws {
        let transferred = KeychainAuthenticationContext(context)
        try await worker.runThrowing { try DeviceKeyStore.restoreDeviceKey(key, id: id, epoch: epoch, context: transferred.context) }
    }
    func saveDepositPublicKey(_ data: Data, vaultID: UUID) async throws {
        try await worker.runThrowing { try DeviceKeyStore.saveDepositPublicKey(data, vaultID: vaultID) }
    }
    func loadDepositPublicKey(vaultID: UUID) async throws -> Data {
        try await worker.runThrowing { try DeviceKeyStore.loadDepositPublicKey(vaultID: vaultID) }
    }
    func saveRecoveryKey(_ key: SymmetricKey, vaultID: UUID) async -> Bool {
        await worker.run { DeviceKeyStore.saveRecoveryKey(key, vaultID: vaultID) }
    }
    func loadRecoveryKey(vaultID: UUID) async -> SymmetricKey? {
        await worker.run { DeviceKeyStore.loadRecoveryKey(vaultID: vaultID) }
    }
    func knownRecoveryVaults() async -> [UUID] {
        await worker.run { DeviceKeyStore.knownRecoveryVaults() }
    }
}

extension SymmetricKey {
    var rawData: Data { withUnsafeBytes { Data($0) } }
}
