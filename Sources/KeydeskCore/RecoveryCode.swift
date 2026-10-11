import Foundation
import CryptoKit

public enum RecoveryCode {
    public static func encode(_ key: SymmetricKey) -> String {
        let bytes = key.withUnsafeBytes { Data($0) }
        let all = bytes + Data(SHA256.hash(data: bytes).prefix(4))
        let hex = all.map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 8).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return String(hex[start..<hex.index(start, offsetBy: 8)])
        }.joined(separator: "-")
    }
    public static func decode(_ code: String) throws -> SymmetricKey {
        let text = code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard text.count == 72, text.allSatisfy({ "0123456789ABCDEF".contains($0) }) else { throw VaultError.invalidRecoveryKey }
        var bytes = Data()
        for offset in stride(from: 0, to: 72, by: 2) {
            let start = text.index(text.startIndex, offsetBy: offset)
            guard let byte = UInt8(text[start..<text.index(start, offsetBy: 2)], radix: 16) else { throw VaultError.invalidRecoveryKey }
            bytes.append(byte)
        }
        let raw = bytes.prefix(32)
        guard Data(SHA256.hash(data: raw).prefix(4)) == bytes.suffix(4) else { throw VaultError.invalidRecoveryKey }
        return SymmetricKey(data: raw)
    }
}
