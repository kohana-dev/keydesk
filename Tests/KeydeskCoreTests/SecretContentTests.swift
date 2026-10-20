import Foundation
import Testing
import CryptoKit
@testable import KeydeskCore

struct SecretContentTests {
    private func withoutFormat(_ version: SecretVersion) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(version)) as? [String: Any])
        object.removeValue(forKey: "format")
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func authenticatedEnvelope(_ snapshot: VaultSnapshot, format: Int, key: SymmetricKey) throws -> VaultEnvelope {
        var header = VaultHeader(); header.format = format; header.revision = snapshot.revision
        let wrapped = try VaultCrypto.wrap(key, recoveryKey: SymmetricKey(size: .bits256), vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        let plaintext = try JSONEncoder().encode(snapshot)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: VaultCrypto.headerData(header) + wrapped)
        return VaultEnvelope(header: header, recoveryWrappedKey: wrapped, ciphertext: try #require(box.combined))
    }

    @Test func legacyStringsAndFilesInferFormatWithoutChangingContent() throws {
        let value = "LEGACY_SYNTHETIC_VALUE\r\n\n"
        let legacy = try JSONDecoder().decode(SecretVersion.self, from: withoutFormat(SecretVersion(value: value)))
        #expect(legacy.format == .apiKey && legacy.value == value && legacy.file == nil)
        let file = try SecretFile(name: "fixture.bin", data: Data([0, 255, 10, 13, 0]))
        let legacyFile = try JSONDecoder().decode(SecretVersion.self, from: withoutFormat(SecretVersion(file: file)))
        #expect(legacyFile.format == .file && legacyFile.file == file && legacyFile.value.isEmpty)
        _ = try legacy.validated(); _ = try legacyFile.validated()
    }

    @Test func invalidOrAmbiguousVersionMetadataIsRejected() throws {
        let version = SecretVersion(value: "SYNTHETIC_TYPED_FIXTURE")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(version)) as? [String: Any])
        for invalid in [NSNull(), "unknown-format"] as [Any] {
            object["format"] = invalid
            let encoded = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(SecretVersion.self, from: encoded) }
        }
        #expect(throws: (any Error).self) { try SecretVersion(value: "", format: .file).validated() }
        let file = try SecretFile(name: "fixture.json", data: Data("{}".utf8))
        object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(SecretVersion(file: file))) as? [String: Any])
        object["format"] = "apiKey"
        let malformed = try JSONDecoder().decode(SecretVersion.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(throws: (any Error).self) { try malformed.validated() }
    }

    @Test func validJSONFragmentsAndExactWhitespaceAreAccepted() throws {
        for value in ["null", "true", "42", "\"synthetic value\"", "[1,\"two\",null]", "{\"nested\":{\"value\":false}}", " \r\n{ \"가\": \"value\" }\n\n"] {
            try SecretContent.validate(value, format: .json)
            let credential = Credential(name: "Fixture", value: value, format: .json)
            #expect(credential.currentText == value && credential.currentValue == value)
            #expect(credential.currentAPIKey == nil)
        }
    }

    @Test func JSONErrorsNeverContainSubmittedContent() throws {
        let secret = "SYNTHETIC_SECRET_DO_NOT_INCLUDE_IN_ERROR"
        for value in ["{\"token\":\"\(secret)\",}", "\(secret)", "[\"\(secret)\""] {
            do { try SecretContent.validate(value, format: .json); Issue.record("Expected invalid JSON") }
            catch { #expect(!error.localizedDescription.contains(secret)) }
        }
    }

    @Test func strictJSONRejectsTrailingCommasAndMalformedGrammarAcrossAllEntryPoints() throws {
        let malformed = ["{\"token\":\"fixture\",}", "[1,]", "[1,,2]", "{\"A\":\"x\" \"B\":\"y\"}", "{\"A\" \"x\"}", "01", "-01", "+1", ".1", "1.", "1e", "1e+", "NaN", "Infinity", "TRUE", "true false", "{}[]", "\"bad\\xescape\"", "\"bad\ncontrol\"", "\"\\uD800\"", "\"\\uDC00\"", "\"\\uD800\\u0041\"", "\"\\uZZZZ\"", "/* comment */{}", "{\"A\":\"x\"}//comment", "\u{00A0}{}"]
        for value in malformed {
            #expect(!JSONSyntaxValidator.isValid(value))
            #expect(throws: (any Error).self) { try SecretContent.validate(value, format: .json) }
            #expect(throws: (any Error).self) { try SecretContent.formattedJSON(value) }
        }
        #expect(throws: (any Error).self) { try SecretContent.fields(from: "{\"A\":\"fixture\",}") }
    }

    @Test func strictJSONAcceptsValidNumbersEscapesAndSurrogatePairsWithBoundedDepth() throws {
        for value in ["0", "-0", "10", "-123.45e+67", "1E-3", "[{}, [], null, false]", "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"", "\"\\uD83D\\uDE00\"", "\"가😀\"", "\t\r\n{\"A\":\"x\"} "] {
            #expect(JSONSyntaxValidator.isValid(value))
            try SecretContent.validate(value, format: .json)
        }
        let bounded = String(repeating: "[", count: JSONSyntaxValidator.maximumDepth) + "0" + String(repeating: "]", count: JSONSyntaxValidator.maximumDepth)
        #expect(JSONSyntaxValidator.isValid(bounded))
        #expect(!JSONSyntaxValidator.isValid("[" + bounded + "]"))
    }

    @Test func keyValueRowsRoundTripInOrderWithUnicodeEscapesAndEmptyValues() throws {
        let fields = [SecretField(key: "서비스", value: "line one\nline two\r\n"), SecretField(key: "QUOTED\"KEY", value: ""), SecretField(key: "URL", value: "https://example.invalid/a")]
        let encoded = try SecretContent.encode(fields: fields)
        let decoded = try SecretContent.fields(from: encoded)
        #expect(decoded.map(\.key) == fields.map(\.key))
        #expect(decoded.map(\.value) == fields.map(\.value))
        try SecretContent.validate(encoded, format: .keyValue)
    }

    @Test func keyValueRejectsDuplicateBlankAndNonStringFields() throws {
        let duplicate = [SecretField(key: "TOKEN", value: "one"), SecretField(key: "TOKEN", value: "two")]
        #expect(throws: (any Error).self) { try SecretContent.encode(fields: duplicate) }
        #expect(throws: (any Error).self) { try SecretContent.encode(fields: []) }
        #expect(throws: (any Error).self) { try SecretContent.encode(fields: [SecretField(key: " \t\n", value: "")]) }
        for value in ["{}", "[]", "{\"A\":1}", "{\"A\":null}", "{\"A\":{}}", "{\"A\":\"one\",\"A\":\"two\"}", "{\"TOKEN\":\"one\",\"\\u0054OKEN\":\"two\"}", "{\"\":\"value\"}", "{\"A\":\"\\u0000\"}"] {
            #expect(throws: (any Error).self) { try SecretContent.validate(value, format: .keyValue) }
        }
    }

    @Test func UTF8LimitsAndNulValidationApplyBeforeSaving() throws {
        let exact = String(repeating: "x", count: SecretContent.maximumBytes)
        try SecretContent.validate(exact, format: .text)
        #expect(throws: (any Error).self) { try SecretContent.validate(exact + "x", format: .text) }
        let multibyte = String(repeating: "가", count: 21_845)
        try SecretContent.validate(multibyte, format: .text)
        #expect(throws: (any Error).self) { try SecretContent.validate(multibyte + "ab", format: .text) }
        for format in [SecretFormat.apiKey, .text, .json, .keyValue] {
            #expect(throws: (any Error).self) { try SecretContent.validate("prefix\0suffix", format: format) }
        }
        #expect(throws: (any Error).self) { try SecretContent.encode(fields: [SecretField(key: "A", value: exact)]) }
    }

    @Test func JSONFormattingIsExplicitAndProducesValidJSON() throws {
        let raw = " { \"fixture\" : [1, true], \"unicode\" : \"가\" } \r\n"
        let version = SecretVersion(value: raw, format: .json)
        _ = try version.validated()
        #expect(version.value == raw)
        let formatted = try SecretContent.formattedJSON(raw)
        try SecretContent.validate(formatted, format: .json)
        #expect(formatted.contains("\n"))
        #expect(try SecretContent.formattedJSON("null") == "null")
        let precise = "{\"large\":12345678901234567890123456789012345678901234567890,\"escaped\":\"\\u0061\",\"same\":1,\"same\":2}"
        let preciseFormatted = try SecretContent.formattedJSON(precise)
        #expect(preciseFormatted.contains("12345678901234567890123456789012345678901234567890"))
        #expect(preciseFormatted.contains("\\u0061"))
        #expect(preciseFormatted.components(separatedBy: "\"same\"").count == 3)
    }

    @Test func rotationKeepsFormatAndRestoringCanSpecifyTheOriginalType() throws {
        var credential = Credential(name: "Fixture", value: "{\"old\":true}", format: .json)
        let original = credential.versions[0]
        credential.rotate(to: "[1,2]")
        #expect(credential.currentFormat == .json)
        credential.rotate(to: "multiline\ntext", format: .text)
        #expect(credential.currentFormat == .text)
        credential.rotate(to: original.value, format: original.format)
        #expect(credential.currentFormat == .json && credential.currentText == original.value)
        credential.rotate(to: try SecretFile(name: "fixture.bin", data: Data([0,255])))
        #expect(credential.currentFormat == .file && credential.currentText == nil && credential.currentAPIKey == nil)
        credential.rotate(to: "SYNTHETIC_NEW_KEY")
        #expect(credential.currentFormat == .apiKey && credential.currentAPIKey == "SYNTHETIC_NEW_KEY")
    }

    @Test func mixedProjectsExposeOnlyAPIKeysToEnvironmentExecution() throws {
        var snapshot = VaultSnapshot()
        let project = Project(name: "Synthetic formats")
        snapshot.projects = [project]
        snapshot.credentials = [Credential(name: "API", value: "SYNTHETIC_API_KEY"), Credential(name: "JSON", value: "{\"token\":\"fixture\"}", format: .json), Credential(name: "Text", value: "fixture\nnotes", format: .text), Credential(name: "Pairs", value: "{\"TOKEN\":\"fixture\"}", format: .keyValue), Credential(name: "File", file: try SecretFile(name: "fixture.bin", data: Data([0,255])))]
        let variables = ["API_KEY", "JSON_DOCUMENT", "TEXT_DOCUMENT", "KEY_VALUE_DOCUMENT", "FILE_PATH"]
        snapshot.bindings = zip(snapshot.credentials, variables).map { credential, variable in BindingRecord(projectID: project.id, environment: .development, variable: variable, credentialID: credential.id) }
        _ = try snapshot.validated()
        let environment = try snapshot.environment(projectID: project.id, environment: .development)
        #expect(environment == ["API_KEY": "SYNTHETIC_API_KEY"])
        let request = CLIRequest(project: project.id.uuidString, environment: .development, command: ["/usr/bin/true"], directory: "/tmp", stdinKey: nil, variables: ["JSON_DOCUMENT"])
        #expect(throws: (any Error).self) { try request.selectedSecrets(from: environment) }
        #expect(try snapshot.files(projectID: project.id, environment: .development).keys.sorted() == ["FILE_PATH"])
        #expect(snapshot.credentials.filter { $0.currentAPIKey != nil }.map(\.name) == ["API"])
    }

    @Test func typedVersionsEncryptRecoverAndBackUpWithoutLosingRawContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-format-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var snapshot = VaultSnapshot()
        let json = " \r\n{ \"fixture-token\": \"SYNTHETIC_JSON_SECRET\" }\n\n"
        let text = "SYNTHETIC_TEXT_SECRET\r\nsecond line\n\n"
        snapshot.credentials = [Credential(name: "JSON", value: json, format: .json), Credential(name: "Text", value: text, format: .text), Credential(name: "Pairs", value: "{\"A\":\"\"}", format: .keyValue)]
        let key = SymmetricKey(size: .bits256), recovery = SymmetricKey(size: .bits256), header = VaultHeader()
        let wrapped = try VaultCrypto.wrap(key, recoveryKey: recovery, vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        let sealed = try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key)
        #expect(sealed.header.format == 3)
        #expect(sealed.ciphertext.range(of: Data("SYNTHETIC_JSON_SECRET".utf8)) == nil)
        let store = VaultFileStore(directory: root)
        try store.write(sealed, expectedRevision: nil)
        let backup = try store.read()
        let restored = try VaultCrypto.open(backup, key: VaultCrypto.recover(backup, code: RecoveryCode.encode(recovery)))
        #expect(restored.credentials.map(\.currentText) == [json, text, "{\"A\":\"\"}"])
        #expect(restored.credentials.map(\.currentFormat) == [.json, .text, .keyValue])
    }

    @Test func historicalTypedVersionsRequireFormatThreeAndNeverDowngrade() throws {
        var snapshot = VaultSnapshot()
        var credential = Credential(name: "Fixture", value: "{\"old\":true}", format: .json)
        credential.rotate(to: "SYNTHETIC_CURRENT_KEY", format: .apiKey)
        snapshot.credentials = [credential]
        let key = SymmetricKey(size: .bits256), header = VaultHeader()
        let wrapped = try VaultCrypto.wrap(key, recoveryKey: SymmetricKey(size: .bits256), vaultID: header.vaultID, keyEpoch: header.keyEpoch)
        let sealed = try VaultCrypto.seal(snapshot, header: header, wrappedKey: wrapped, key: key)
        #expect(sealed.header.format == 3)
        snapshot.credentials = [Credential(name: "Legacy", value: "SYNTHETIC_VALUE")]
        let resealed = try VaultCrypto.seal(snapshot, header: sealed.header, wrappedKey: wrapped, key: key)
        #expect(resealed.header.format == 3)
    }

    @Test func lowerEnvelopeFormatsRejectEvenAuthenticatedTypedPayloads() throws {
        let key = SymmetricKey(size: .bits256)
        var snapshot = VaultSnapshot()
        snapshot.credentials = [Credential(name: "JSON", value: "{}", format: .json)]
        for format in [1, 2] {
            let envelope = try authenticatedEnvelope(snapshot, format: format, key: key)
            #expect(throws: (any Error).self) { try VaultCrypto.open(envelope, key: key) }
        }
        snapshot.credentials = [Credential(name: "Legacy", value: "SYNTHETIC_VALUE")]
        for format in [1, 2, 3] {
            let envelope = try authenticatedEnvelope(snapshot, format: format, key: key)
            #expect(try VaultCrypto.open(envelope, key: key).credentials.first?.currentAPIKey == "SYNTHETIC_VALUE")
        }
    }

    @Test func validationChecksHistoricalVersionsToo() throws {
        var snapshot = VaultSnapshot()
        var credential = Credential(name: "Fixture", value: "not valid JSON", format: .json)
        credential.rotate(to: "SYNTHETIC_VALID_KEY", format: .apiKey)
        snapshot.credentials = [credential]
        #expect(throws: (any Error).self) { try snapshot.validated() }
    }
}
