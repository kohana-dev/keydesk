import Foundation

public struct SecretVersion: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let value: String
    public let file: SecretFile?
    public let format: SecretFormat
    public init(value: String, format: SecretFormat = .apiKey) { id = UUID(); createdAt = Date(); self.value = value; file = nil; self.format = format }
    public init(file: SecretFile) { id = UUID(); createdAt = Date(); value = ""; self.file = file; format = .file }

    private enum CodingKeys: String, CodingKey { case id, createdAt, value, file, format }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        value = try values.decode(String.self, forKey: .value)
        file = try values.decodeIfPresent(SecretFile.self, forKey: .file)
        if values.contains(.format) { format = try values.decode(SecretFormat.self, forKey: .format) }
        else { format = file == nil ? .apiKey : .file }
    }

    public func validated() throws -> Self {
        if let file {
            guard format == .file, value.isEmpty else { throw VaultError.invalidData }
            _ = try file.validated()
        } else {
            guard format != .file else { throw VaultError.invalidData }
            try SecretContent.validate(value, format: format)
        }
        return self
    }
}
