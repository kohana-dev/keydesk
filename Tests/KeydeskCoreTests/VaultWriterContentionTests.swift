import Testing
import Foundation
import CryptoKit
import Darwin
@testable import KeydeskCore

struct VaultWriterContentionTests {
    @Test func competingWriterFailsWithoutChangingVaultAndRetrySucceedsAfterUnlock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-writer-contention-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VaultFileStore(directory: root)
        let key = SymmetricKey(size: .bits256), recovery = SymmetricKey(size: .bits256)
        var snapshot = VaultSnapshot(), header = VaultHeader()
        let wrapped = try VaultCrypto.wrap(key, recoveryKey: recovery, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        let original = try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key)
        try store.write(original, expectedRevision: nil)
        let before = try Data(contentsOf: store.vaultURL)
        let lockURL = root.appendingPathComponent("writer.lock")
        let holder = Darwin.open(lockURL.path, O_RDWR | O_CLOEXEC)
        try #require(holder >= 0)
        defer { _ = flock(holder, LOCK_UN); close(holder) }
        try #require(flock(holder, LOCK_EX | LOCK_NB) == 0)

        snapshot.revision = 1; header.revision = 1
        let changed = try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key)
        // A regression to blocking LOCK_EX still fails safely instead of hanging the test runner.
        let releaseBackstop = DispatchWorkItem { _ = flock(holder, LOCK_UN) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1, execute: releaseBackstop)
        defer { releaseBackstop.cancel() }
        var contention: POSIXError?
        do { try store.write(changed, expectedRevision: 0) }
        catch let error as POSIXError { contention = error }
        #expect(contention?.code.rawValue == EWOULDBLOCK)
        #expect(try Data(contentsOf: store.vaultURL) == before)
        #expect(!FileManager.default.fileExists(atPath: store.previousURL.path))
        #expect(FileManager.default.fileExists(atPath: lockURL.path))

        _ = flock(holder, LOCK_UN)
        releaseBackstop.cancel()
        try store.write(changed, expectedRevision: 0)
        #expect(try store.read().header.revision == 1)
        #expect(try Data(contentsOf: store.previousURL) == before)
        // The expected-revision check remains authoritative after the write lock is acquired.
        #expect(throws: VaultError.self) { try store.write(original, expectedRevision: 0) }
        #expect(try store.read().header.revision == 1)
    }
}
