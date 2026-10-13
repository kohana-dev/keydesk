/// The storage provider chosen for encrypted backup files. Cloud synchronization is handled by
/// the user's installed client; this value does not mean that a file has finished uploading.
public enum BackupDestination: String, Codable, Sendable, CaseIterable {
    case iCloud
    case googleDrive
    case folder
}
