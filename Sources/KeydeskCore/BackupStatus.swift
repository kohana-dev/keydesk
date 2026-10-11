import Foundation

/// Non-secret record of the last verified automatic backup. Kept outside the encrypted vault so that
/// recording a backup does not itself create a new unbacked revision.
public struct BackupStatus: Codable, Sendable, Equatable {
    public var vaultID: UUID
    public var revision: UInt64
    public var date: Date
    public init(vaultID: UUID, revision: UInt64, date: Date) { self.vaultID = vaultID; self.revision = revision; self.date = date }

    public static func read(at url: URL, vaultID: UUID) -> BackupStatus? {
        guard let data = try? Data(contentsOf: url), data.count < 4096,
              let status = try? JSONDecoder().decode(BackupStatus.self, from: data), status.vaultID == vaultID else { return nil }
        return status
    }
    public func write(to url: URL) throws {
        try VaultFileStore.atomicWrite(JSONEncoder().encode(self), to: url)
    }
}

public enum BackupLocation {
    public enum CloudUpload: Equatable, Sendable {
        /// Not an iCloud Drive file, so there is nothing to upload.
        case notCloud
        case pending
        case uploaded
        /// iCloud reported an upload error, for example an Apple Account that must accept new terms.
        case failed
    }
    /// Writing into the iCloud Drive folder only creates a local copy; this asks iCloud whether it has
    /// reached Apple's servers, which is what makes the backup survive losing the Mac.
    public static func cloudUpload(of url: URL) -> CloudUpload {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey]),
              values.isUbiquitousItem == true else { return .notCloud }
        if values.ubiquitousItemIsUploaded == true { return .uploaded }
        return values.ubiquitousItemUploadingError == nil ? .pending : .failed
    }
    /// True when the folder lives on this Mac's internal disk and is not a cloud-synced folder,
    /// i.e. it would be lost together with the Mac.
    public static func isOnlyOnThisMac(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path.hasPrefix(home + "/Library/Mobile Documents/") || path.hasPrefix(home + "/Library/CloudStorage/") { return false }
        let isInternal = (try? url.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) ?? true
        return isInternal != false
    }
}
