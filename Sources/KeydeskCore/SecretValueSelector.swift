import Foundation

public enum SecretValueSelector {
    /// Decode RFC 6901 tokens. This accepts the pointer string form, not URI fragments or percent escapes.
    public static func pointerTokens(_ pointer: String) throws -> [String] {
        guard pointer.utf8.count <= 2_048, !pointer.contains("\0") else { throw VaultError.accessDenied }
        if pointer.isEmpty { return [] }
        guard pointer.first == "/" else { throw VaultError.accessDenied }
        let components = pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard components.count <= 64 else { throw VaultError.accessDenied }
        return try components.map { component in
            let bytes = Array(component.utf8)
            var decoded = [UInt8](), index = 0
            while index < bytes.count {
                if bytes[index] == 126 {
                    guard index + 1 < bytes.count else { throw VaultError.accessDenied }
                    switch bytes[index + 1] {
                    case 48: decoded.append(126)
                    case 49: decoded.append(47)
                    default: throw VaultError.accessDenied
                    }
                    index += 2
                } else { decoded.append(bytes[index]); index += 1 }
            }
            return String(decoding: decoded, as: UTF8.self)
        }
    }

    /// Selects only a scalar from a current key-value or JSON version. No document is returned whole.
    /// Numbers and booleans retain their exact lexical representation for command execution.
    public static func value(in credential: Credential, pointer: String, allowNonStringScalar: Bool = true) throws -> String {
        let tokens = try pointerTokens(pointer)
        guard credential.currentFormat == .keyValue || credential.currentFormat == .json,
              let content = credential.currentText, content.utf8.count <= SecretContent.maximumBytes,
              !content.contains("\0"), JSONSyntaxValidator.isValid(content) else { throw VaultError.accessDenied }
        var reader = Reader(bytes: Array(content.utf8))
        var node = try reader.readValue(depth: 0)
        // A malformed key-value payload must not be treated as arbitrary JSON even if a caller has
        // not validated its snapshot first. The normal vault decoder already enforces this too.
        if credential.currentFormat == .keyValue {
            guard case .object(let entries) = node, !entries.isEmpty,
                  entries.allSatisfy({ entry in
                      if case .string(let value) = entry.1 {
                          return !entry.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !value.contains("\0")
                      }
                      return false
                  }) else { throw VaultError.accessDenied }
        }
        for token in tokens {
            switch node {
            case .object(let entries):
                // Compare UTF-8 bytes, since JSON member matching must not normalize Unicode.
                var keys = Set<Data>()
                for entry in entries {
                    guard keys.insert(Data(entry.0.utf8)).inserted else { throw VaultError.accessDenied }
                }
                guard let match = entries.first(where: { Data($0.0.utf8) == Data(token.utf8) }) else {
                    throw VaultError.accessDenied
                }
                node = match.1
            case .array(let values):
                let digits = Array(token.utf8)
                guard !digits.isEmpty, digits.allSatisfy({ (48...57).contains($0) }),
                      digits.count == 1 || digits[0] != 48, let index = Int(token), index < values.count else {
                    throw VaultError.accessDenied
                }
                node = values[index]
            default: throw VaultError.accessDenied
            }
        }
        let value: String
        switch node {
        case .string(let selected): value = selected
        case .scalar(let selected) where allowNonStringScalar: value = selected
        default: throw VaultError.accessDenied
        }
        guard value.utf8.count <= SecretContent.maximumBytes, !value.contains("\0") else { throw VaultError.accessDenied }
        return value
    }

    private indirect enum Node {
        case object([(String, Node)]), array([Node]), string(String), scalar(String), null
    }

    /// Grammar is checked before this reader runs. Keeping lexical nodes avoids Double/NSNumber
    /// rounding and preserves ambiguity rather than collapsing duplicate object members.
    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        mutating func whitespace() {
            while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func readString() throws -> String {
            whitespace()
            let start = index
            guard index < bytes.count, bytes[index] == 34 else { throw VaultError.accessDenied }
            index += 1
            while index < bytes.count {
                if bytes[index] == 92 { index += 2; continue }
                if bytes[index] == 34 {
                    index += 1
                    guard let value = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) else {
                        throw VaultError.accessDenied
                    }
                    return value
                }
                index += 1
            }
            throw VaultError.accessDenied
        }

        mutating func readValue(depth: Int) throws -> Node {
            whitespace()
            guard index < bytes.count, depth <= JSONSyntaxValidator.maximumDepth else { throw VaultError.accessDenied }
            switch bytes[index] {
            case 123:
                index += 1; whitespace()
                var entries = [(String, Node)]()
                if bytes[index] == 125 { index += 1; return .object(entries) }
                while true {
                    let key = try readString()
                    whitespace(); index += 1 // Colon, already checked by the grammar validator.
                    let value = try readValue(depth: depth + 1)
                    entries.append((key, value)); whitespace()
                    if bytes[index] == 125 { index += 1; return .object(entries) }
                    index += 1
                }
            case 91:
                index += 1; whitespace()
                var values = [Node]()
                if bytes[index] == 93 { index += 1; return .array(values) }
                while true {
                    values.append(try readValue(depth: depth + 1)); whitespace()
                    if bytes[index] == 93 { index += 1; return .array(values) }
                    index += 1
                }
            case 34: return .string(try readString())
            default:
                let start = index
                while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                let lexical = String(decoding: bytes[start..<index], as: UTF8.self)
                return lexical == "null" ? .null : .scalar(lexical)
            }
        }
    }
}
