import Foundation

public struct CLIEvent: Codable, Sendable {
    public let kind: String
    public let text: String?
    public let exitCode: Int32?
    public let data: Data?
    public init(kind: String, text: String? = nil, exitCode: Int32? = nil, data: Data? = nil) {
        self.kind = kind; self.text = text; self.exitCode = exitCode; self.data = data
    }
}
