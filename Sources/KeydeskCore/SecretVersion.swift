import Foundation

public struct SecretVersion: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let value: String
    public let file: SecretFile?
    public init(value: String) { id = UUID(); createdAt = Date(); self.value = value; file = nil }
    public init(file: SecretFile) { id = UUID(); createdAt = Date(); value = ""; self.file = file }
}
