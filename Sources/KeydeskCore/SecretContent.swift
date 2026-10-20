import Foundation

public enum SecretContentError: Error, LocalizedError {
    case tooLarge, invalidText, invalidJSON, invalidKeyValue, emptyKey, duplicateKey, fileRequired

    public var errorDescription: String? {
        switch self {
        case .tooLarge: L10n.tr("내용은 UTF-8 기준 64KiB 이하여야 합니다.", "Content must be 64KiB or smaller in UTF-8.")
        case .invalidText: L10n.tr("내용에 NUL 문자를 넣을 수 없습니다.", "Content cannot contain a NUL character.")
        case .invalidJSON: L10n.tr("유효한 JSON을 입력하세요.", "Enter valid JSON.")
        case .invalidKeyValue: L10n.tr("키·값 묶음에는 하나 이상의 문자열 키와 문자열 값이 필요합니다.", "Key-value pairs need at least one string key and string value.")
        case .emptyKey: L10n.tr("키 이름을 입력하세요.", "Enter a name for every key.")
        case .duplicateKey: L10n.tr("같은 이름의 키가 중복되어 있습니다.", "Each key must have a unique name.")
        case .fileRequired: L10n.tr("파일 형식은 파일을 선택해 저장하세요.", "Choose a file to save file content.")
        }
    }
}

public enum SecretContent {
    public static let maximumBytes = 65_536

    /// Validation never normalizes input. JSON and text keep the exact supplied string.
    public static func validate(_ value: String, format: SecretFormat) throws {
        try validateText(value)
        switch format {
        case .apiKey, .text: break
        case .json: _ = try jsonObject(value)
        case .keyValue: _ = try fields(from: value)
        case .file: throw SecretContentError.fileRequired
        }
    }

    public static func fields(from value: String) throws -> [SecretField] {
        try validateText(value)
        guard JSONSyntaxValidator.isValid(value),
              let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)),
              let dictionary = object as? [String: String], !dictionary.isEmpty else {
            throw SecretContentError.invalidKeyValue
        }
        // Foundation collapses duplicate object keys. Read the already validated flat object
        // again to preserve field order and reject duplicates, including escaped spellings.
        var reader = FieldReader(bytes: Array(value.utf8))
        let fields = try reader.read()
        try validateFields(fields)
        return fields
    }

    public static func encode(fields: [SecretField]) throws -> String {
        try validateFields(fields)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let lines = try fields.map { field in
            let key = String(decoding: try encoder.encode(field.key), as: UTF8.self)
            let value = String(decoding: try encoder.encode(field.value), as: UTF8.self)
            return "  \(key): \(value)"
        }
        let encoded = "{\n" + lines.joined(separator: ",\n") + "\n}"
        try validateText(encoded)
        return encoded
    }

    public static func formattedJSON(_ value: String) throws -> String {
        try validateText(value)
        _ = try jsonObject(value)
        // Reformat lexical tokens rather than serializing Foundation objects: reserialization
        // can round large numbers, rewrite escape sequences, or collapse duplicate JSON keys.
        let bytes = Array(value.utf8)
        var output = [UInt8](), index = 0, depth = 0
        func whitespace(_ byte: UInt8) -> Bool { [9, 10, 13, 32].contains(byte) }
        func newline() { output.append(10); output.append(contentsOf: repeatElement(UInt8(32), count: depth * 2)) }
        while index < bytes.count {
            let byte = bytes[index]
            if whitespace(byte) { index += 1; continue }
            if byte == 34 {
                output.append(byte); index += 1
                while index < bytes.count {
                    let next = bytes[index]
                    output.append(next); index += 1
                    if next == 92, index < bytes.count { output.append(bytes[index]); index += 1 }
                    else if next == 34 { break }
                }
                continue
            }
            switch byte {
            case 123, 91:
                output.append(byte); depth += 1
                var next = index + 1
                while next < bytes.count && whitespace(bytes[next]) { next += 1 }
                if next < bytes.count && bytes[next] != (byte == 123 ? 125 : 93) { newline() }
            case 125, 93:
                depth -= 1
                if output.last != (byte == 125 ? 123 : 91) { newline() }
                output.append(byte)
            case 44: output.append(byte); newline()
            case 58: output.append(contentsOf: [58, 32])
            default: output.append(byte)
            }
            index += 1
        }
        let formatted = String(decoding: output, as: UTF8.self)
        try validateText(formatted)
        return formatted
    }

    private static func validateText(_ value: String) throws {
        guard value.utf8.count <= maximumBytes else { throw SecretContentError.tooLarge }
        guard !value.contains("\0") else { throw SecretContentError.invalidText }
    }

    private static func validateFields(_ fields: [SecretField]) throws {
        guard !fields.isEmpty else { throw SecretContentError.invalidKeyValue }
        var names = Set<String>()
        for field in fields {
            guard !field.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SecretContentError.emptyKey }
            try validateText(field.key); try validateText(field.value)
            guard names.insert(field.key).inserted else { throw SecretContentError.duplicateKey }
        }
    }

    private static func jsonObject(_ value: String) throws -> Any {
        guard JSONSyntaxValidator.isValid(value),
              let object = try? JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed]) else {
            throw SecretContentError.invalidJSON
        }
        return object
    }

    private struct FieldReader {
        let bytes: [UInt8]
        var index = 0

        mutating func read() throws -> [SecretField] {
            try consume(123)
            var result = [SecretField]()
            while true {
                let key = try string()
                try consume(58)
                let value = try string()
                result.append(SecretField(key: key, value: value))
                skipWhitespace()
                guard index < bytes.count else { throw SecretContentError.invalidKeyValue }
                if bytes[index] == 125 { index += 1; break }
                try consume(44)
            }
            skipWhitespace()
            guard index == bytes.count else { throw SecretContentError.invalidKeyValue }
            return result
        }

        mutating func skipWhitespace() {
            while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func consume(_ expected: UInt8) throws {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == expected else { throw SecretContentError.invalidKeyValue }
            index += 1
        }

        mutating func string() throws -> String {
            skipWhitespace()
            let start = index
            try consume(34)
            while index < bytes.count {
                if bytes[index] == 92 { index += 2; continue }
                if bytes[index] == 34 {
                    index += 1
                    guard let value = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) else {
                        throw SecretContentError.invalidKeyValue
                    }
                    return value
                }
                index += 1
            }
            throw SecretContentError.invalidKeyValue
        }
    }
}
