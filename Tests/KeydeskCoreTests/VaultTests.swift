import Testing
import Foundation
import CryptoKit
@testable import KeydeskCore

struct VaultTests {
    private func fixture() throws -> (VaultSnapshot, VaultEnvelope, SymmetricKey, String) {
        let key = SymmetricKey(size: .bits256), recovery = SymmetricKey(size: .bits256), header = VaultHeader()
        var snapshot = VaultSnapshot()
        let project = Project(name: "Fixture")
        let credential = Credential(name: "Fixture key", value: "SENTINEL_SECRET_NEVER_ON_DISK", provider: "Fixture")
        snapshot.projects = [project]; snapshot.credentials = [credential]
        snapshot.bindings = [BindingRecord(projectID: project.id, environment: .development, variable: "FIXTURE_API_KEY", credentialID: credential.id)]
        let wrapped = try VaultCrypto.wrap(key, recoveryKey: recovery, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        return (snapshot, try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key), key, RecoveryCode.encode(recovery))
    }
    @Test func encryptedRoundTripAndIndependentRecovery() throws {
        let (snapshot, envelope, key, code) = try fixture()
        #expect(try VaultCrypto.open(envelope, key: key).credentials[0].currentValue == snapshot.credentials[0].currentValue)
        let restored = try VaultCrypto.recover(envelope, code: code)
        #expect(try VaultCrypto.open(envelope, key: restored).credentials[0].currentValue == snapshot.credentials[0].currentValue)
        let data = try JSONEncoder().encode(envelope)
        #expect(!String(decoding: data, as: UTF8.self).contains("SENTINEL_SECRET"))
        #expect(!String(decoding: data, as: UTF8.self).contains("Fixture"))
    }
    @Test func incorrectRecoveryAndKeyFail() throws {
        let (_, envelope, _, _) = try fixture()
        #expect(throws: (any Error).self) { try VaultCrypto.recover(envelope, code: RecoveryCode.encode(SymmetricKey(size: .bits256))) }
        #expect(throws: (any Error).self) { try VaultCrypto.open(envelope, key: SymmetricKey(size: .bits256)) }
    }
    @Test func recoveryChecksumAndWhitespace() throws {
        let key = SymmetricKey(size: .bits256), code = RecoveryCode.encode(key)
        #expect(try RecoveryCode.encode(RecoveryCode.decode("  " + code.lowercased() + "\n")) == code)
        let altered = (code.first == "0" ? "1" : "0") + code.dropFirst()
        #expect(throws: (any Error).self) { try RecoveryCode.decode(altered) }
    }
    @Test func headerAndCiphertextTamperFail() throws {
        let (_, envelope, key, _) = try fixture()
        var altered = envelope
        altered.header.revision += 1
        #expect(throws: (any Error).self) { try VaultCrypto.open(altered, key: key) }
        var bytes = envelope.ciphertext; bytes[bytes.count - 1] ^= 1
        let corrupted = VaultEnvelope(header: envelope.header, recoveryWrappedKey: envelope.recoveryWrappedKey, ciphertext: bytes)
        #expect(throws: (any Error).self) { try VaultCrypto.open(corrupted, key: key) }
    }
    @Test func wrappingBoundToVaultIdentity() throws {
        let (_, envelope, _, code) = try fixture()
        let other = VaultEnvelope(header: VaultHeader(), recoveryWrappedKey: envelope.recoveryWrappedKey, ciphertext: envelope.ciphertext)
        #expect(throws: (any Error).self) { try VaultCrypto.recover(other, code: code) }
    }
    @Test func damagedRecoveryWrapperRejectedDuringNormalUnlock() throws {
        let (_, envelope, key, _) = try fixture()
        var wrapper = envelope.recoveryWrappedKey; wrapper[0] ^= 1
        let corrupted = VaultEnvelope(header: envelope.header, recoveryWrappedKey: wrapper, ciphertext: envelope.ciphertext)
        #expect(throws: (any Error).self) { try VaultCrypto.open(corrupted, key: key) }
    }
    @Test func atomicWritePreviousAndStaleWriter() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VaultFileStore(directory: root)
        let (original, envelope, key, _) = try fixture()
        try store.write(envelope, expectedRevision: nil)
        var next = original; next.revision += 1; next.credentials[0].rotate(to: "SECOND_SENTINEL")
        var header = envelope.header; header.revision = next.revision
        let updated = try VaultCrypto.seal(next, header: header, wrappedKey: envelope.recoveryWrappedKey, key: key)
        try store.write(updated, expectedRevision: 0)
        #expect(try store.read().header.revision == 1)
        #expect(try VaultCrypto.open(VaultFileStore.read(at: store.previousURL), key: key).credentials[0].currentValue == "SENTINEL_SECRET_NEVER_ON_DISK")
        #expect(throws: (any Error).self) { try store.write(envelope, expectedRevision: 0) }
        #expect(try store.read().header.revision == 1)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        #expect(!files.contains { $0.pathExtension == "tmp" })
        for file in files {
            #expect(!String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("SENTINEL"))
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }
    @Test func duplicateBindingsAndDanglingIDsRejected() throws {
        var (snapshot, _, _, _) = try fixture()
        snapshot.bindings.append(snapshot.bindings[0])
        #expect(throws: (any Error).self) { try snapshot.validated() }
        snapshot.bindings.removeLast(); snapshot.credentials.removeAll()
        #expect(throws: (any Error).self) { try snapshot.validated() }
    }
    @Test func failedBackupWritePreservesCurrentVault() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keydesk-write-failure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VaultFileStore(directory: root)
        let (original, envelope, key, _) = try fixture()
        try store.write(envelope, expectedRevision: nil)
        // A directory at the previous-file destination forces atomic rename failure.
        try FileManager.default.createDirectory(at: store.previousURL, withIntermediateDirectories: false)
        var next = original; next.revision = 1
        var header = envelope.header; header.revision = 1
        let updated = try VaultCrypto.seal(next, header: header, wrappedKey: envelope.recoveryWrappedKey, key: key)
        #expect(throws: (any Error).self) { try store.write(updated, expectedRevision: 0) }
        #expect(try VaultCrypto.open(store.read(), key: key).revision == 0)
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: root.path)).contains { $0.hasSuffix(".tmp") })
    }
    @Test func reservedEnvironmentAndNulRejected() throws {
        var (snapshot, _, _, _) = try fixture()
        let project = snapshot.projects[0].id
        snapshot.bindings[0].variable = "DYLD_INSERT_LIBRARIES"
        #expect(throws: (any Error).self) { try snapshot.environment(projectID: project, environment: .development) }
        snapshot.bindings[0].variable = "FIXTURE_API_KEY"
        snapshot.credentials[0].rotate(to: "abc\0def")
        #expect(throws: (any Error).self) { try snapshot.environment(projectID: project, environment: .development) }
        #expect(throws: (any Error).self) { try snapshot.validated() }
    }
    @Test func environmentSeparationAndSharedRotation() throws {
        var (snapshot, _, _, _) = try fixture()
        let project = snapshot.projects[0].id
        #expect(try snapshot.environment(projectID: project, environment: .production).isEmpty)
        snapshot.credentials[0].rotate(to: "rotated")
        #expect(try snapshot.environment(projectID: project, environment: .development)["FIXTURE_API_KEY"] == "rotated")
        #expect(snapshot.credentials[0].versions.count == 2)
    }
}
