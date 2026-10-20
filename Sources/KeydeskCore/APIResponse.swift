import Foundation

public struct APIResponse: Codable, Sendable {
    public let status: Int
    public let body: String
    public init(status: Int, body: String) { self.status = status; self.body = body }
    public func validated(secret: String) throws -> Self {
        guard (200...599).contains(status), !(300...399).contains(status), body.utf8.count <= 1_048_576 else { throw VaultError.accessDenied }
        // Fail closed on common reflection encodings. This cannot classify every sensitive API field.
        let bytes = Data(secret.utf8)
        let querySafe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = [secret, bytes.base64EncodedString(), bytes.map { String(format: "%02x", $0) }.joined(),
                       secret.addingPercentEncoding(withAllowedCharacters: querySafe) ?? secret,
                       secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? secret,
                       String(decoding: (try? JSONEncoder().encode(secret)) ?? bytes, as: UTF8.self)]
        let normalizedBody = Self.normalizedPercentEscapes(body)
        guard !encoded.filter({ !$0.isEmpty }).contains(where: { body.contains($0) || normalizedBody.contains(Self.normalizedPercentEscapes($0)) }) else { throw VaultError.accessDenied }
        return self
    }
    private static func normalizedPercentEscapes(_ value: String) -> String {
        var bytes = Array(value.utf8), index = 0
        func isHex(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) }
        while index + 2 < bytes.count {
            if bytes[index] == 37, isHex(bytes[index + 1]), isHex(bytes[index + 2]) {
                for offset in 1...2 where (97...102).contains(bytes[index + offset]) { bytes[index + offset] -= 32 }
                index += 3
            } else { index += 1 }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
