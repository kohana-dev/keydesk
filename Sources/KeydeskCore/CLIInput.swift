import Foundation

public struct CLIInput: Codable, Sendable {
    public let kind: String
    public let data: Data?
    public let columns: UInt16?
    public let rows: UInt16?
    public init(kind: String, data: Data? = nil, columns: UInt16? = nil, rows: UInt16? = nil) {
        self.kind = kind; self.data = data; self.columns = columns; self.rows = rows
    }
}
