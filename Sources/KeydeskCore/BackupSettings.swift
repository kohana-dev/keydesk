import Foundation

public struct BackupSettings: Codable, Sendable {
    public var directory: String?
    public var lastSuccess: Date?
    public var bookmark: Data?
    /// Optional so vaults created before provider selection remain readable. An absent value is
    /// inferred from a recognized cloud folder, or treated as an ordinary folder.
    public var destination: BackupDestination?
    public init(directory: String? = nil, lastSuccess: Date? = nil, bookmark: Data? = nil, destination: BackupDestination? = nil) {
        self.directory = directory; self.lastSuccess = lastSuccess; self.bookmark = bookmark
        self.destination = destination
    }
}
