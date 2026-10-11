import Foundation

public struct BackupSettings: Codable, Sendable {
    public var directory: String?
    public var lastSuccess: Date?
    public var bookmark: Data?
    public init(directory: String? = nil, lastSuccess: Date? = nil, bookmark: Data? = nil) {
        self.directory = directory; self.lastSuccess = lastSuccess; self.bookmark = bookmark
    }
}
