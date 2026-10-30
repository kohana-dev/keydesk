import Foundation
import KeydeskCore

/// Read-only backup inspection. Cloud filesystem access must run outside the main actor.
struct BackupInspection: Sendable {
    let file: URL?
    let status: BackupStatus?
    let cloudUpload: BackupLocation.CloudUpload

    static func read(directory: URL?, statusURL: URL, vaultID: UUID) -> Self {
        let latest = directory.flatMap { BackupManager.latestBackup(in: $0) }
        let stored = BackupStatus.read(at: statusURL, vaultID: vaultID)
        let verified = stored.flatMap { status in
            latest?.envelope.header.vaultID == status.vaultID && latest?.envelope.header.revision == status.revision ? status : nil
        }
        return Self(file: latest?.url, status: verified,
                    cloudUpload: latest.map { BackupLocation.cloudUpload(of: $0.url) } ?? .notCloud)
    }
}
