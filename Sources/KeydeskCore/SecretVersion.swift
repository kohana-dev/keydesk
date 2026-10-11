import Foundation

public struct SecretVersion: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let value: String
    public init(value: String) { id = UUID(); createdAt = Date(); self.value = value }
}
