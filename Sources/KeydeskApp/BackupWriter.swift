import Foundation
import CryptoKit
import KeydeskCore

/// Serializes backup saves and retention so snapshots cannot prune each other's output.
protocol BackupSaving: Sendable {
    func save(_ envelope: VaultEnvelope, key: SymmetricKey, directory: URL) async throws -> URL
}

final class BackupWriter: BackupSaving {
    private let queue = DispatchQueue(label: "com.keydesk.backup-writer", qos: .utility)
    func save(_ envelope: VaultEnvelope, key: SymmetricKey, directory: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try BackupManager.save(envelope, key: key, directory: directory) })
            }
        }
    }
}
