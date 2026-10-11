import Testing
import Foundation
@testable import KeydeskCore

struct ParserAndTransportTests {
    @Test func dotenvLiteralsAndMultiline() {
        let rows = DotenvParser.parse("# comment\nexport API_KEY='  preserve  '\nTEXT=\"line1\nline2\"\nESCAPED=\"a\\n\\\"b\"\nRAW=$(touch /tmp/keydesk-must-not-execute)\nREF=${API_KEY}\nEMPTY=\nHASH=abc#def # comment")
        #expect(rows.count == 7)
        #expect(rows.allSatisfy { $0.error == nil })
        #expect(rows[0].value == "  preserve  ")
        #expect(rows[1].value == "line1\nline2")
        #expect(rows[2].value == "a\n\"b")
        #expect(rows[3].value == "$(touch /tmp/keydesk-must-not-execute)")
        #expect(rows[4].value == "${API_KEY}")
        #expect(rows[5].value == "")
        #expect(rows[6].value == "abc#def")
    }
    @Test func dotenvMalformedAndDuplicates() {
        let rows = DotenvParser.parse("A=one\nA=two\nBAD-NAME=value\nmissing\nQ=\"unclosed")
        #expect(rows.count == 5)
        #expect(rows[0].error == nil)
        #expect(rows.dropFirst().allSatisfy { $0.error != nil })
    }
    @Test func redactionAcrossEveryByteBoundary() {
        let source = Data("prefix UNIQUE_SECRET suffix 한글".utf8)
        for split in 0...source.count {
            var redactor = StreamingRedactor(secrets: ["UNIQUE_SECRET"])
            let first = redactor.push(source.prefix(split))
            let second = redactor.push(source.suffix(source.count - split), final: true)
            #expect(String(decoding: first + second, as: UTF8.self) == "prefix [REDACTED] suffix 한글")
        }
    }
    @Test func redactionOneByteChunksAndOverlappingValues() {
        var redactor = StreamingRedactor(secrets: ["abc", "abcdef", "", "bc"])
        var output = Data()
        for byte in Data("abcdef and abc".utf8) { output += redactor.push(Data([byte])) }
        output += redactor.push(Data(), final: true)
        #expect(String(decoding: output, as: UTF8.self) == "[REDACTED] and [REDACTED]")
    }
    @Test func protocolRoundTripNoKeysInRequest() throws {
        let request = CLIRequest(project: "Fixture", environment: .development, command: ["/bin/echo", "hello"], directory: "/tmp", stdinKey: "API_KEY")
        let encoded = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(CLIRequest.self, from: encoded).stdinKey == "API_KEY")
        let binary = Data([0, 10, 255])
        let event = CLIEvent(kind: "stdout", data: binary)
        #expect(try JSONDecoder().decode(CLIEvent.self, from: JSONEncoder().encode(event)).data == binary)
        #expect(throws: (any Error).self) { try SocketTransport.address(String(repeating: "x", count: 200)) }
    }
}
