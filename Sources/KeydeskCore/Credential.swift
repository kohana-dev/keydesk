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
    public var currentValue: String? { versions.first(where: { $0.id == currentVersionID }).flatMap { $0.file == nil ? $0.value : nil } }

    public var currentFile: SecretFile? { versions.first(where: { $0.id == currentVersionID })?.file }

    public init(id: UUID = UUID(), name: String, value: String, provider: String = "Other", account: String = "", note: String = "") {
        let version = SecretVersion(value: value)
        self.id = id; self.name = name; self.provider = provider; self.account = account; self.note = note
        self.favorite = false; self.versions = [version]; self.currentVersionID = version.id; self.updatedAt = Date()
    }
    public init(id: UUID = UUID(), name: String, file: SecretFile, provider: String = "Other", account: String = "", note: String = "") {
        let version = SecretVersion(file: file)
        self.id = id; self.name = name; self.provider = provider; self.account = account; self.note = note
        favorite = false; versions = [version]; currentVersionID = version.id; updatedAt = Date()
    }
    public mutating func rotate(to file: SecretFile) {
        let version = SecretVersion(file: file); versions.insert(version, at: 0); currentVersionID = version.id; updatedAt = Date()
    }
    public mutating func rotate(to value: String) {
        let version = SecretVersion(value: value)
        versions.insert(version, at: 0); currentVersionID = version.id; updatedAt = Date()
    }
}
