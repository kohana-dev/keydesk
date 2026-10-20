import Foundation
import Testing
@testable import KeydeskCore

struct SecretFieldSelectionTests {
    private func select(_ value: String, pointer: String, format: SecretFormat = .json, stringsOnly: Bool = false) throws -> String {
        try SecretValueSelector.value(in: Credential(name: "Synthetic document", value: value, format: format),
                                      pointer: pointer, allowNonStringScalar: !stringsOnly)
    }

    private func request(variables: [String]? = nil, files: [String]? = nil, stdin: String? = nil,
                         selections: [SecretFieldSelection]? = nil) -> CLIRequest {
        CLIRequest(project: "Synthetic", environment: .development, command: ["/usr/bin/true"],
                   directory: "/tmp", stdinKey: stdin, variables: variables, fileVariables: files, selections: selections)
    }

    @Test func invocationSyntaxSplitsOnlyTheFirstEqualsAndHash() throws {
        let selection = try SecretFieldSelection.parse("OUTPUT=DOCUMENT#/nested/a=b#c")
        #expect(selection == SecretFieldSelection(variable: "OUTPUT", source: "DOCUMENT", pointer: "/nested/a=b#c"))
        #expect(try SecretFieldSelection.parse("OUTPUT=DOCUMENT#").pointer.isEmpty)
        #expect(try SecretValueSelector.pointerTokens("/a~1b/~0/~01/") == ["a/b", "~", "~1", ""])
        #expect(try SecretValueSelector.pointerTokens("/percent%2Fencoded") == ["percent%2Fencoded"])
        for invalid in ["OUTPUT=DOCUMENT", "OUTPUTDOCUMENT#/token", "=DOCUMENT#/token", "OUTPUT=#/token",
                        "BAD-NAME=DOCUMENT#/token", "OUTPUT=BAD-NAME#/token", "PATH=DOCUMENT#/token",
                        "OUTPUT\n=DOCUMENT#/token", "OUTPUT=DOCUMENT\r\n#/token",
                        "OUTPUT=HOME#/token", "OUTPUT=DOCUMENT#token", "OUTPUT=DOCUMENT#/~", "OUTPUT=DOCUMENT#/~2"] {
            #expect(throws: (any Error).self) { try SecretFieldSelection.parse(invalid) }
        }
    }

    @Test func pointerAndSelectionBoundsAreCheckedForBothParsedAndDecodedRequests() throws {
        let longPointer = "/" + String(repeating: "가", count: 683)
        #expect(throws: (any Error).self) { try SecretValueSelector.pointerTokens(longPointer) }
        #expect(try SecretValueSelector.pointerTokens(String(repeating: "/x", count: 64)).count == 64)
        #expect(throws: (any Error).self) { try SecretValueSelector.pointerTokens(String(repeating: "/x", count: 65)) }
        #expect(throws: (any Error).self) { try SecretValueSelector.pointerTokens("/token\0") }
        let hundred = (0..<100).map { SecretFieldSelection(variable: "OUT_\($0)", source: "DOCUMENT", pointer: "/token") }
        try SecretFieldSelection.validate(hundred)
        #expect(throws: (any Error).self) {
            try SecretFieldSelection.validate(hundred + [SecretFieldSelection(variable: "EXTRA", source: "DOCUMENT", pointer: "/token")])
        }
        #expect(throws: (any Error).self) { try SecretFieldSelection.validate([hundred[0], hundred[0]]) }
        let invalid = SecretFieldSelection(variable: "NODE_OPTIONS", source: "DOCUMENT", pointer: "/token")
        let decoded = try JSONDecoder().decode(CLIRequest.self, from: JSONEncoder().encode(request(selections: [invalid])))
        #expect(throws: (any Error).self) { try decoded.selectedSecrets(from: ["NODE_OPTIONS": "synthetic"]) }
    }

    @Test func escapedNestedKeysArraysAndEmptyMembersResolveExactly() throws {
        let document = #"{"a/b":{"~":{"": ["zero", {"token":"line one\nline two\r\n\uD83D\uDE00"}]}},"literal%2F":"percent","~1":"tilde-slash","":"empty key"}"#
        #expect(try select(document, pointer: "/a~1b/~0//1/token") == "line one\nline two\r\n😀")
        #expect(try select(document, pointer: "/a~1b/~0//0") == "zero")
        #expect(try select(document, pointer: "/literal%2F") == "percent")
        #expect(try select(document, pointer: "/~01") == "tilde-slash")
        #expect(try select(document, pointer: "/") == "empty key")
        #expect(try select(#"{"TOKEN":"","OTHER":"unused"}"#, pointer: "/TOKEN", format: .keyValue) == "")
        #expect(try select(#""root string""#, pointer: "", stringsOnly: true) == "root string")
    }

    @Test func numericAndBooleanScalarsKeepLexicalPrecisionButAPIRequiresStrings() throws {
        let values = ["0", "-0", "12345678901234567890123456789012345678901234567890", "-123.4500e+067", "1E-3", "1e999", "true", "false"]
        for lexical in values {
            #expect(try select("{\"value\":\(lexical)}", pointer: "/value") == lexical)
            #expect(try select(" \n\(lexical)\t", pointer: "") == lexical)
            #expect(throws: (any Error).self) { try select("{\"value\":\(lexical)}", pointer: "/value", stringsOnly: true) }
        }
        #expect(try select(#"{"value":"123.4500"}"#, pointer: "/value", stringsOnly: true) == "123.4500")
    }

    @Test func arrayIndicesMustBeCanonicalAndSelectedValueMustBeAScalar() throws {
        let document = #"{"array":["zero", "one"],"object":{"token":"synthetic"},"nil":null,"empty":[]}"#
        for pointer in ["/array/01", "/array/-", "/array/-1", "/array/+1", "/array/2", "/array/1.0", "/array/999999999999999999999999999999", "/array/", "/object", "/array", "/nil", "/empty", "/missing", "/array/0/missing", ""] {
            #expect(throws: (any Error).self) { try select(document, pointer: pointer) }
        }
        // A numeric object key is not an array index and may retain leading zeroes.
        #expect(try select(#"{"01":"object key"}"#, pointer: "/01") == "object key")
    }

    @Test func duplicateKeysInEveryTraversedObjectFailClosedWithoutNormalizingNames() throws {
        for document in [#"{"token":"first","token":"second"}"#,
                         #"{"token":"first","\u0074oken":"second"}"#,
                         #"{"token":"selected","unrelated":1,"unrelated":2}"#,
                         #"{"nested":{"token":"one","token":"two"}}"#] {
            let pointer = document.contains("nested") ? "/nested/token" : "/token"
            #expect(throws: (any Error).self) { try select(document, pointer: pointer) }
        }
        #expect(try select(#"{"token":"selected","unvisited":{"duplicate":1,"duplicate":2}}"#, pointer: "/token") == "selected")
        let composed = "é", decomposed = "e\u{301}"
        let exactDocument = "{\"\(composed)\":\"composed\",\"\(decomposed)\":\"decomposed\"}"
        #expect(try select(exactDocument, pointer: "/" + composed) == "composed")
        #expect(try select(exactDocument, pointer: "/" + decomposed) == "decomposed")
    }

    @Test func malformedDocumentsUnsafeStringsAndWrongFormatsAreRejectedWithGenericErrors() throws {
        let sentinel = "SYNTHETIC_DO_NOT_INCLUDE_IN_ERROR"
        for document in ["{\"token\":\"\(sentinel)\",}", "[1,]", "01", "NaN", "\"\\uD800\"", "true false", "{\"token\":\"\\u0000\"}"] {
            do { _ = try select(document, pointer: document.first == "{" ? "/token" : ""); Issue.record("Invalid document accepted") }
            catch { #expect(!error.localizedDescription.contains(sentinel)) }
        }
        for format in [SecretFormat.apiKey, .text] {
            #expect(throws: (any Error).self) { try select(#"{"token":"synthetic"}"#, pointer: "/token", format: format) }
        }
        let file = try SecretFile(name: "fixture.json", data: Data(#"{"token":"synthetic"}"#.utf8))
        #expect(throws: (any Error).self) { try SecretValueSelector.value(in: Credential(name: "File", file: file), pointer: "/token") }
        #expect(throws: (any Error).self) { try select(#"{"token":1}"#, pointer: "/token", format: .keyValue) }
        #expect(throws: (any Error).self) { try select("\"" + String(repeating: "x", count: SecretContent.maximumBytes) + "\"", pointer: "") }
        #expect(try select("\"" + String(repeating: "x", count: SecretContent.maximumBytes - 2) + "\"", pointer: "").utf8.count == SecretContent.maximumBytes - 2)
    }

    @Test func selectionUsesOnlyTheCurrentVersion() throws {
        var credential = Credential(name: "Synthetic", value: #"{"token":"old"}"#, format: .json)
        credential.rotate(to: #"{"token":"new"}"#)
        #expect(try SecretValueSelector.value(in: credential, pointer: "/token") == "new")
        credential.rotate(to: "new API key", format: .apiKey)
        #expect(throws: (any Error).self) { try SecretValueSelector.value(in: credential, pointer: "/token") }
    }

    @Test func CLISelectionIncludesOnlyExplicitOutputsAndCanRouteOneToStdin() throws {
        let selected = SecretFieldSelection(variable: "TOKEN", source: "DOCUMENT", pointer: "/token")
        let available = ["TOKEN": "selected synthetic", "OTHER_KEY": "unselected synthetic", "DOCUMENT": "never select whole document"]
        #expect(try request(selections: [selected]).selectedSecrets(from: available) == ["TOKEN": "selected synthetic"])
        #expect(try request(variables: ["OTHER_KEY"], selections: [selected]).selectedSecrets(from: available) == ["TOKEN": "selected synthetic", "OTHER_KEY": "unselected synthetic"])
        #expect(try request(stdin: "TOKEN", selections: [selected]).selectedSecrets(from: available) == ["TOKEN": "selected synthetic"])
        #expect(throws: (any Error).self) { try request(selections: [selected]).selectedSecrets(from: ["OTHER_KEY": "synthetic"]) }
        let stdinRequest = CLIRequest(project: "Synthetic", environment: .development, command: ["/usr/bin/true"], directory: "/tmp", stdinKey: "TOKEN", interactive: true, selections: [selected])
        #expect(throws: (any Error).self) { try stdinRequest.selectedSecrets(from: available) }
    }

    @Test func CLIOutputCollisionsAndExecutionControlNamesFailForBothSelectionMethods() throws {
        let selected = SecretFieldSelection(variable: "TOKEN", source: "DOCUMENT", pointer: "/token")
        let file = try SecretFile(name: "fixture.bin", data: Data())
        for invalid in [request(variables: ["TOKEN"], selections: [selected]), request(files: ["TOKEN"], selections: [selected]), request(selections: [selected, selected])] {
            #expect(throws: (any Error).self) { try invalid.selectedSecrets(from: ["TOKEN": "synthetic"]) }
            #expect(throws: (any Error).self) { try invalid.selectedFiles(from: ["TOKEN": file]) }
        }
        for name in ["PATH", "HOME", "DYLD_INSERT_LIBRARIES", "LD_PRELOAD", "NODE_OPTIONS", "TMPDIR", "USER", "TERM", "PERL5LIB"] {
            let unsafe = request(selections: [SecretFieldSelection(variable: name, source: "DOCUMENT", pointer: "/token")])
            #expect(throws: (any Error).self) { try unsafe.selectedSecrets(from: [name: "synthetic"]) }
            #expect(throws: (any Error).self) { try unsafe.selectedFiles(from: [:]) }
        }
        let many = (0..<100).map { SecretFieldSelection(variable: "OUT_\($0)", source: "DOCUMENT", pointer: "/token") }
        let available = Dictionary(uniqueKeysWithValues: many.map { ($0.variable, "synthetic") })
        #expect(try request(selections: many).selectedSecrets(from: available).count == 100)
        #expect(throws: (any Error).self) { try request(variables: ["EXTRA"], selections: many).selectedSecrets(from: available.merging(["EXTRA": "synthetic"]) { _, new in new }) }
    }

    @Test func legacyCLIRequestsDecodeAndNewSelectorsRoundTripWithoutChangingInvocationIdentity() throws {
        let original = request(variables: ["LEGACY_KEY"])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "selections")
        let legacy = try JSONDecoder().decode(CLIRequest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.selections == nil)
        #expect(try legacy.selectedSecrets(from: ["LEGACY_KEY": "synthetic"]) == ["LEGACY_KEY": "synthetic"])
        let first = request(selections: [SecretFieldSelection(variable: "TOKEN", source: "DOCUMENT", pointer: "/first")])
        let second = request(selections: [SecretFieldSelection(variable: "TOKEN", source: "DOCUMENT", pointer: "/second")])
        #expect(try JSONDecoder().decode(CLIRequest.self, from: JSONEncoder().encode(first)) == first)
        #expect(first != second)
    }

    @Test func vaultResolutionIsExplicitAndBoundToTheExactProjectAndEnvironment() throws {
        let project = Project(name: "Synthetic"), other = Project(name: "Other synthetic")
        let api = Credential(name: "API", value: "synthetic API")
        let doc = Credential(name: "Document", value: #"{"token":"development synthetic","number":123456789012345678901234567890}"#, format: .json)
        let production = Credential(name: "Production", value: #"{"token":"production synthetic"}"#, format: .keyValue)
        let unrelated = Credential(name: "Unrelated", value: "malformed unselected JSON", format: .json)
        var snapshot = VaultSnapshot()
        snapshot.projects = [project, other]; snapshot.credentials = [api, doc, production, unrelated]
        snapshot.bindings = [BindingRecord(projectID: project.id, environment: .development, variable: "API_KEY", credentialID: api.id),
                             BindingRecord(projectID: project.id, environment: .development, variable: "DOCUMENT", credentialID: doc.id),
                             BindingRecord(projectID: project.id, environment: .production, variable: "DOCUMENT", credentialID: production.id),
                             BindingRecord(projectID: other.id, environment: .development, variable: "OTHER_DOCUMENT", credentialID: doc.id),
                             BindingRecord(projectID: project.id, environment: .development, variable: "UNSELECTED", credentialID: unrelated.id)]
        let selection = SecretFieldSelection(variable: "TOKEN", source: "DOCUMENT", pointer: "/token")
        #expect(try snapshot.environment(projectID: project.id, environment: .development) == ["API_KEY": "synthetic API"])
        #expect(try snapshot.environment(projectID: project.id, environment: .development, selections: [selection]) == ["API_KEY": "synthetic API", "TOKEN": "development synthetic"])
        #expect(try snapshot.environment(projectID: project.id, environment: .production, selections: [selection]) == ["TOKEN": "production synthetic"])
        #expect(throws: (any Error).self) { try snapshot.environment(projectID: other.id, environment: .development, selections: [selection]) }
        #expect(throws: (any Error).self) { try snapshot.environment(projectID: project.id, environment: .development, selections: [SecretFieldSelection(variable: "TOKEN", source: "OTHER_DOCUMENT", pointer: "/token")]) }
        #expect(throws: (any Error).self) { try snapshot.environment(projectID: project.id, environment: .development, selections: [SecretFieldSelection(variable: "TOKEN", source: "API_KEY", pointer: "")]) }
        #expect(throws: (any Error).self) { try snapshot.environment(projectID: project.id, environment: .development, selections: [SecretFieldSelection(variable: "API_KEY", source: "DOCUMENT", pointer: "/token")]) }
        snapshot.bindings.append(BindingRecord(projectID: project.id, environment: .development, variable: "DOCUMENT", credentialID: doc.id))
        #expect(throws: (any Error).self) { try snapshot.environment(projectID: project.id, environment: .development, selections: [selection]) }
    }
}
