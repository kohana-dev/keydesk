import Foundation
import CryptoKit
import LocalAuthentication
import Testing
import KeydeskCore
@testable import KeydeskApp

private final class KeychainTestGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 5) == .success }
    func block() -> Bool {
        entered.signal()
        return resume.wait(timeout: .now() + 5) == .success
    }
}

@MainActor
private final class SlowDeviceKeyStore: VaultKeyStore {
    let backing = MemoryKeyStore()
    let worker = KeychainWorker()
    let gate = KeychainTestGate()
    var slowRead = false
    func authenticate(reason: String) async throws -> LAContext? { try await backing.authenticate(reason: reason) }
    func saveDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID) throws { try backing.saveDeviceKey(key, id: id, epoch: epoch) }
    func loadDeviceKey(envelope: VaultEnvelope, context: LAContext?) async throws -> SymmetricKey {
        let key = try backing.loadDeviceKey(envelope: envelope, context: context)
        guard slowRead else { return key }
        let gate = gate
        return await worker.run {
            #expect(!Thread.isMainThread)
            #expect(gate.block(), "The main actor must run while Keychain waits")
            return key
        }
    }
    func removeDeviceKey(id: UUID, epoch: UUID) { backing.removeDeviceKey(id: id, epoch: epoch) }
    func restoreDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID, context: LAContext?) throws { try backing.restoreDeviceKey(key, id: id, epoch: epoch, context: context) }
    func saveDepositPublicKey(_ data: Data, vaultID: UUID) throws { try backing.saveDepositPublicKey(data, vaultID: vaultID) }
    func loadDepositPublicKey(vaultID: UUID) throws -> Data { try backing.loadDepositPublicKey(vaultID: vaultID) }
    func saveRecoveryKey(_ key: SymmetricKey, vaultID: UUID) -> Bool { backing.saveRecoveryKey(key, vaultID: vaultID) }
    func loadRecoveryKey(vaultID: UUID) -> SymmetricKey? { backing.loadRecoveryKey(vaultID: vaultID) }
    func knownRecoveryVaults() -> [UUID] { backing.knownRecoveryVaults() }
}

@Suite(.serialized) @MainActor
struct KeychainResponsivenessTests {
    @Test func blockedKeychainReadKeepsMainActorResponsiveAndCannotReopenLockedVault() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-keychain-worker-\(UUID())")
        let keys = SlowDeviceKeyStore()
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: keys, serve: false, observeSystemEvents: false)
        defer { keys.gate.resume.signal(); model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun(startNew: true)
        try #require(model.snapshot != nil)
        model.lock()
        keys.slowRead = true
        let unlock = Task { await model.unlock() }
        let gate = keys.gate
        try #require(await Task.detached { gate.waitUntilEntered() }.value)
        #expect(model.busy && model.snapshot == nil)
        model.lock()
        gate.resume.signal()
        await unlock.value
        #expect(model.snapshot == nil && !model.busy && model.error == nil)
    }

    @Test func recoveringDeviceAccessCannotOverwriteEditsMadeDuringKeychainWait() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-recovery-race-\(UUID())")
        let keys = SlowDeviceKeyStore()
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: keys, serve: false, observeSystemEvents: false)
        defer { keys.gate.resume.signal(); model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.prepareFirstRun(startNew: true)
        let backup = root.appendingPathComponent("synthetic-backup.keydesk")
        try await model.backup(to: backup)
        let code = try #require(model.snapshot?.recoveryCode)
        keys.slowRead = true
        let recovery = Task { try await model.recoverDeviceAccess(at: backup, code: code) }
        let gate = keys.gate
        try #require(await Task.detached { gate.waitUntilEntered() }.value)
        try model.addProject("Keep newer edit")
        let revision = model.snapshot?.revision
        gate.resume.signal()
        do { try await recovery.value } catch VaultError.staleRevision {} catch { throw error }
        #expect(model.snapshot?.revision == revision)
        #expect(model.snapshot?.projects.contains { $0.name == "Keep newer edit" } == true)
        #expect(try model.store.read().header.revision == revision)
    }

    @Test func keychainWorkerKeepsSerializationAndPropagatesFailures() async throws {
        let worker = KeychainWorker(), gate = KeychainTestGate()
        let first = Task { await worker.run { gate.block() } }
        try #require(await Task.detached { gate.waitUntilEntered() }.value)
        let second = Task { await worker.run { !Thread.isMainThread } }
        gate.resume.signal()
        #expect(await first.value)
        #expect(await second.value)
        do {
            let _: Bool = try await worker.runThrowing { throw VaultError.accessDenied }
            Issue.record("A failed Keychain operation must remain failed")
        } catch VaultError.accessDenied {
        } catch { Issue.record("Unexpected error from Keychain worker") }
    }
}
