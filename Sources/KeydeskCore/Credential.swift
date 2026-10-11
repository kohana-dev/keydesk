import Foundation

public struct Credential: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var provider: String
    public var account: String
    public var note: String
    public var favorite: Bool
    public var versions: [SecretVersion]
    public var currentVersionID: UUID
    public var updatedAt: Date
    public var currentValue: String? { versions.first(where: { $0.id == currentVersionID })?.value }

    public init(id: UUID = UUID(), name: String, value: String, provider: String = "Other", account: String = "", note: String = "") {
        let version = SecretVersion(value: value)
        self.id = id; self.name = name; self.provider = provider; self.account = account; self.note = note
        self.favorite = false; self.versions = [version]; self.currentVersionID = version.id; self.updatedAt = Date()
    }
    public mutating func rotate(to value: String) {
        let version = SecretVersion(value: value)
        versions.insert(version, at: 0); currentVersionID = version.id; updatedAt = Date()
    }
}
