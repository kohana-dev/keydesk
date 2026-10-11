import Foundation

public struct ActivityRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let action: String
    public init(action: String) { id = UUID(); date = Date(); self.action = action }
}
