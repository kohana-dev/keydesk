/// Foundation accepts some non-JSON syntax, including trailing commas. Check the grammar before
/// semantic decoding so accepting or formatting content never silently repairs invalid input.
enum JSONSyntaxValidator {
    static let maximumDepth = 512

    static func isValid(_ value: String) -> Bool {
        var parser = Parser(bytes: Array(value.utf8))
        do { try parser.parse(); return true }
        catch { return false }
    }

    private enum SyntaxError: Error { case invalid }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func parse() throws {
            try value(depth: 0)
            whitespace()
            guard index == bytes.count else { throw SyntaxError.invalid }
        }

        mutating func whitespace() {
            while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func consume(_ byte: UInt8) throws {
            guard index < bytes.count, bytes[index] == byte else { throw SyntaxError.invalid }
            index += 1
        }

        mutating func value(depth: Int) throws {
            whitespace()
            guard index < bytes.count else { throw SyntaxError.invalid }
            switch bytes[index] {
            case 123:
                guard depth < JSONSyntaxValidator.maximumDepth else { throw SyntaxError.invalid }
                try object(depth: depth + 1)
            case 91:
                guard depth < JSONSyntaxValidator.maximumDepth else { throw SyntaxError.invalid }
                try array(depth: depth + 1)
            case 34: try string()
            case 45, 48...57: try number()
            case 116: try literal(Array("true".utf8))
            case 102: try literal(Array("false".utf8))
            case 110: try literal(Array("null".utf8))
            default: throw SyntaxError.invalid
            }
        }

        mutating func object(depth: Int) throws {
            try consume(123)
            whitespace()
            if index < bytes.count, bytes[index] == 125 { index += 1; return }
            while true {
                try string()
                whitespace()
                try consume(58)
                try value(depth: depth)
                whitespace()
                guard index < bytes.count else { throw SyntaxError.invalid }
                if bytes[index] == 125 { index += 1; return }
                try consume(44)
                whitespace()
            }
        }

        mutating func array(depth: Int) throws {
            try consume(91)
            whitespace()
            if index < bytes.count, bytes[index] == 93 { index += 1; return }
            while true {
                try value(depth: depth)
                whitespace()
                guard index < bytes.count else { throw SyntaxError.invalid }
                if bytes[index] == 93 { index += 1; return }
                try consume(44)
            }
        }

        mutating func string() throws {
            try consume(34)
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 34 { return }
                guard byte >= 32 else { throw SyntaxError.invalid }
                if byte == 92 {
                    guard index < bytes.count else { throw SyntaxError.invalid }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case 34, 47, 92, 98, 102, 110, 114, 116: break
                    case 117:
                        let scalar = try hexQuad()
                        if (0xD800...0xDBFF).contains(scalar) {
                            try consume(92); try consume(117)
                            let low = try hexQuad()
                            guard (0xDC00...0xDFFF).contains(low) else { throw SyntaxError.invalid }
                        } else if (0xDC00...0xDFFF).contains(scalar) { throw SyntaxError.invalid }
                    default: throw SyntaxError.invalid
                    }
                }
            }
            throw SyntaxError.invalid
        }

        mutating func hexQuad() throws -> UInt16 {
            var result: UInt16 = 0
            for _ in 0..<4 {
                guard index < bytes.count else { throw SyntaxError.invalid }
                let digit: UInt16
                switch bytes[index] {
                case 48...57: digit = UInt16(bytes[index] - 48)
                case 65...70: digit = UInt16(bytes[index] - 65 + 10)
                case 97...102: digit = UInt16(bytes[index] - 97 + 10)
                default: throw SyntaxError.invalid
                }
                result = result * 16 + digit
                index += 1
            }
            return result
        }

        func isDigit(at position: Int) -> Bool { position < bytes.count && (48...57).contains(bytes[position]) }

        mutating func number() throws {
            if bytes[index] == 45 { index += 1 }
            guard index < bytes.count else { throw SyntaxError.invalid }
            if bytes[index] == 48 {
                index += 1
                guard !isDigit(at: index) else { throw SyntaxError.invalid }
            } else {
                guard (49...57).contains(bytes[index]) else { throw SyntaxError.invalid }
                while isDigit(at: index) { index += 1 }
            }
            if index < bytes.count, bytes[index] == 46 {
                index += 1
                guard isDigit(at: index) else { throw SyntaxError.invalid }
                while isDigit(at: index) { index += 1 }
            }
            if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
                index += 1
                if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
                guard isDigit(at: index) else { throw SyntaxError.invalid }
                while isDigit(at: index) { index += 1 }
            }
        }

        mutating func literal(_ literal: [UInt8]) throws {
            for byte in literal { try consume(byte) }
        }
    }
}
