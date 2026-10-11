import Foundation

public struct APIResponse: Codable, Sendable {
    public let status: Int
    public let body: String
    public init(status: Int, body: String) { self.status = status; self.body = body }
    public func validated(secret: String) throws -> Self {
        guard (200...599).contains(status), !(300...399).contains(status), body.utf8.count <= 1_048_576 else { throw VaultError.accessDenied }
        // Fail closed on common reflection encodings. This cannot classify every sensitive API field.
        let bytes = Data(secret.utf8)
        let encoded = [secret, bytes.base64EncodedString(), bytes.map { String(format: "%02x", $0) }.joined(),
                       secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? secret,
                       String(decoding: (try? JSONEncoder().encode(secret)) ?? bytes, as: UTF8.self)]
        guard !encoded.filter({ !$0.isEmpty }).contains(where: { body.contains($0) }) else { throw VaultError.accessDenied }
        return self
    }
}
