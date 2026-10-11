import Foundation
import CryptoKit
import LocalAuthentication
import KeydeskCore

/// Disposable demos never touch the user's protected or synchronizing Keychain.
@MainActor
final class DemoKeyStore: VaultKeyStore {
    private var devices: [String: SymmetricKey] = [:]
    private var deposits: [UUID: Data] = [:]
    func authenticate(reason: String) async throws -> LAContext? { nil }
    func saveDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID) throws { devices["\(id):\(epoch)"] = key }
    func loadDeviceKey(envelope: VaultEnvelope, context: LAContext?) throws -> SymmetricKey {
        guard let key = devices["\(envelope.header.vaultID):\(envelope.header.keyEpoch)"] else { throw VaultError.locked }
        return key
    }
    func removeDeviceKey(id: UUID, epoch: UUID) { devices.removeValue(forKey: "\(id):\(epoch)") }
    func restoreDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID, context: LAContext?) throws { try saveDeviceKey(key, id: id, epoch: epoch) }
    func saveDepositPublicKey(_ data: Data, vaultID: UUID) throws { deposits[vaultID] = data }
    func loadDepositPublicKey(vaultID: UUID) throws -> Data {
        guard let data = deposits[vaultID] else { throw VaultError.locked }; return data
    }
    func saveRecoveryKey(_ key: SymmetricKey, vaultID: UUID) -> Bool { false }
    func loadRecoveryKey(vaultID: UUID) -> SymmetricKey? { nil }
    func knownRecoveryVaults() -> [UUID] { [] }
}
