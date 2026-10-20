import Foundation
import Testing
import CryptoKit
import LocalAuthentication
import Darwin
import KeydeskCore
@testable import KeydeskApp

@MainActor
private final class ContentEditingKeyStore: VaultKeyStore {
    let backing = MemoryKeyStore()
    var suspended = false
    private var continuation: CheckedContinuation<LAContext?, any Error>?
    var waiting: Bool { continuation != nil }

    func authenticate(reason: String) async throws -> LAContext? {
        if suspended { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return try await backing.authenticate(reason: reason)
    }
    func completeAuthentication() { let pending = continuation; continuation = nil; pending?.resume(returning: nil) }
    func saveDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID) throws { try backing.saveDeviceKey(key, id: id, epoch: epoch) }
    func loadDeviceKey(envelope: VaultEnvelope, context: LAContext?) throws -> SymmetricKey { try backing.loadDeviceKey(envelope: envelope, context: context) }
    func removeDeviceKey(id: UUID, epoch: UUID) { backing.removeDeviceKey(id: id, epoch: epoch) }
    func restoreDeviceKey(_ key: SymmetricKey, id: UUID, epoch: UUID, context: LAContext?) throws { try backing.restoreDeviceKey(key, id: id, epoch: epoch, context: context) }
    func saveDepositPublicKey(_ data: Data, vaultID: UUID) throws { try backing.saveDepositPublicKey(data, vaultID: vaultID) }
    func loadDepositPublicKey(vaultID: UUID) throws -> Data { try backing.loadDepositPublicKey(vaultID: vaultID) }
    func saveRecoveryKey(_ key: SymmetricKey, vaultID: UUID) -> Bool { backing.saveRecoveryKey(key, vaultID: vaultID) }
    func loadRecoveryKey(vaultID: UUID) -> SymmetricKey? { backing.loadRecoveryKey(vaultID: vaultID) }
    func knownRecoveryVaults() -> [UUID] { backing.knownRecoveryVaults() }
}

@Suite(.serialized) @MainActor
struct SecretContentModelTests {
    private func fixture(keys: (any VaultKeyStore)? = nil, transport: any APITransport = FixtureAPITransport()) async throws -> VaultModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cellar-content-model-\(UUID())")
        let model = VaultModel(directory: root, defaultBackupDirectory: nil, keys: keys ?? MemoryKeyStore(), apiTransport: transport, serve: false, observeSystemEvents: false)
        await model.prepareFirstRun(startNew: true)
        try model.addProject("Synthetic formats")
        model.selectedProject = try #require(model.snapshot?.projects.first?.id)
        return model
    }

    private func cleanup(_ model: VaultModel) { model.shutdown(); try? FileManager.default.removeItem(at: model.store.directory) }

    @discardableResult
    private func add(_ model: VaultModel, value: String, format: SecretFormat, variable: String = "DOCUMENT") throws -> Credential {
        try model.addCredential(name: "Synthetic content", value: value, provider: "Cloudflare", account: "", note: "", variable: variable, format: format)
        return try #require(model.detail)
    }

    @Test func invalidDocumentsNeverMutateTheSnapshotOrVaultFile() async throws {
        let model = try await fixture(); defer { cleanup(model) }
        let before = try #require(model.snapshot)
        let encryptedBefore = try Data(contentsOf: model.store.vaultURL)
        for (value, format) in [("{\"fixture\":", SecretFormat.json), ("{\"A\":1}", SecretFormat.keyValue)] {
            #expect(throws: (any Error).self) { try add(model, value: value, format: format) }
            #expect(model.snapshot?.revision == before.revision)
            #expect(model.snapshot?.credentials.count == before.credentials.count)
            #expect(try Data(contentsOf: model.store.vaultURL) == encryptedBefore)
        }
        #expect(throws: (any Error).self) { try model.addCredential(name: " \r\n\t", value: "fixture", provider: "Other", account: "", note: "", variable: "WHITESPACE_NAME", format: .text) }
        #expect(model.snapshot?.revision == before.revision)
        #expect(try Data(contentsOf: model.store.vaultURL) == encryptedBefore)
    }

    @Test func typedContentSurvivesLockUnlockAndVersionRestoration() async throws {
        let model = try await fixture(); defer { cleanup(model) }
        let raw = " \r\n{ \"fixture\" : \"SYNTHETIC_JSON_ONLY\" }\n\n"
        let credential = try add(model, value: raw, format: .json)
        let original = credential.versions[0]
        try model.rotate(credential.id, value: "SYNTHETIC_TEXT_ONLY\nsecond line", format: .text, expectedVersionID: original.id)
        model.revealID = credential.id; model.revealedValue = "SYNTHETIC_VISIBLE_FIXTURE"
        try model.restoreVersion(credential.id, version: original)
        let restored = try #require(model.snapshot?.credentials.first { $0.id == credential.id })
        #expect(restored.currentFormat == .json && restored.currentText == raw)
        #expect(restored.currentVersionID != original.id && restored.versions.count == 3)
        #expect(model.revealID == nil && model.revealedValue == nil)
        #expect(try model.store.read().header.format == 3)
        model.lock(); await model.unlock()
        let reopened = try #require(model.snapshot?.credentials.first { $0.id == credential.id })
        #expect(reopened.currentFormat == .json && reopened.currentText == raw)
    }

    @Test func staleEditorAndInvalidReplacementCannotOverwriteNewerContent() async throws {
        let model = try await fixture(); defer { cleanup(model) }
        let credential = try add(model, value: "{\"first\":true}", format: .json)
        try model.rotate(credential.id, value: "[1,2]")
        let before = try #require(model.snapshot?.revision)
        #expect(throws: (any Error).self) { try model.rotate(credential.id, value: "{}", expectedVersionID: credential.currentVersionID) }
        #expect(throws: (any Error).self) { try model.rotate(credential.id, value: "not valid JSON") }
        #expect(model.snapshot?.revision == before)
        #expect(model.snapshot?.credentials.first?.currentFormat == .json)
        #expect(model.snapshot?.credentials.first?.currentText == "[1,2]")
    }

    @Test func storedDocumentEditingAlwaysAuthenticatesAndDenialReturnsNoContent() async throws {
        let keys = MemoryKeyStore(), model = try await fixture(keys: keys)
        defer { cleanup(model) }
        let credential = try add(model, value: "SYNTHETIC_DEVELOPMENT_TEXT", format: .text)
        let before = keys.authentications
        let value = try await model.authenticatedContentForEditing(credential.id, versionID: credential.currentVersionID)
        #expect(value == "SYNTHETIC_DEVELOPMENT_TEXT" && keys.authentications == before + 1)
        keys.denyAuthentication = true
        do { _ = try await model.authenticatedContentForEditing(credential.id, versionID: credential.currentVersionID); Issue.record("Expected authentication denial") }
        catch { #expect(!error.localizedDescription.contains("SYNTHETIC_DEVELOPMENT_TEXT")) }
        #expect(keys.authentications == before + 2)
        #expect(model.revealID == nil && model.revealedValue == nil)
    }

    @Test func editorAuthenticationCannotReturnContentAfterLockOrVersionChange() async throws {
        for lockDuringAuthentication in [true, false] {
            let keys = ContentEditingKeyStore(), model = try await fixture(keys: keys)
            defer { keys.completeAuthentication(); cleanup(model) }
            let credential = try add(model, value: "SYNTHETIC_BEFORE_AUTH", format: .text)
            keys.suspended = true
            let editing = Task { @MainActor in try await model.authenticatedContentForEditing(credential.id, versionID: credential.currentVersionID) }
            for _ in 0..<50 { if keys.waiting { break }; try await Task.sleep(for: .milliseconds(2)) }
            try #require(keys.waiting)
            if lockDuringAuthentication { model.lock() }
            else { try model.rotate(credential.id, value: "SYNTHETIC_CHANGED_DURING_AUTH", format: .text) }
            keys.completeAuthentication()
            do { _ = try await editing.value; Issue.record("Expected authentication race to reject content") }
            catch { #expect(!error.localizedDescription.contains("SYNTHETIC_")) }
        }
    }

    @Test func demoDocumentEditingUsesOnlyDemoContentWithoutOSAuthentication() async throws {
        let keys = MemoryKeyStore(); keys.denyAuthentication = true
        let model = VaultModel(demo: true, keys: keys, serve: false, observeSystemEvents: false)
        defer { cleanup(model) }
        let credential = try add(model, value: "{\"fixture\":true}", format: .json, variable: "SYNTHETIC_JSON_DOCUMENT")
        #expect(try await model.authenticatedContentForEditing(credential.id, versionID: credential.currentVersionID) == "{\"fixture\":true}")
        #expect(keys.authentications == 0)
    }

    @Test func documentsCannotAuthenticateAPIRequestsOrReuseAnOldAPIGrant() async throws {
        let transport = FixtureAPITransport(), model = try await fixture(transport: transport)
        defer { cleanup(model) }
        let credential = try add(model, value: "SYNTHETIC_API_ONLY", format: .apiKey, variable: "CLOUDFLARE_API_TOKEN")
        let request = APIRequest(project: "Synthetic formats", environment: .development, variable: "CLOUDFLARE_API_TOKEN", method: "GET", url: "https://api.cloudflare.com/client/v4/user/tokens/verify")
        let helper = APIBrokerTests()
        let (initial, initialClient) = try RunnerTests().sockets(); defer { close(initialClient) }
        model.receiveAPI(request, channel: initial)
        await model.acceptAPI(remember: true); try await helper.awaitCompletion(model)
        #expect(try helper.events(initialClient).contains { $0.kind == "exit" && $0.exitCode == 0 })
        #expect(await transport.calls == 1)
        for (value, format) in [("{\"token\":\"SYNTHETIC_JSON\"}", SecretFormat.json), ("SYNTHETIC_TEXT", SecretFormat.text), ("{\"TOKEN\":\"SYNTHETIC_PAIRS\"}", SecretFormat.keyValue)] {
            try model.rotate(credential.id, value: value, format: format)
            let (channel, client) = try RunnerTests().sockets(); defer { close(client) }
            model.receiveAPI(request, channel: channel)
            #expect(model.apiApproval == nil && model.apiApprovals.active().isEmpty)
            let events = try helper.events(client)
            #expect(events.contains { $0.kind == "error" } && !events.contains { $0.kind == "stdout" })
            #expect(await transport.calls == 1)
        }
    }

    @Test func dotenvImportDoesNotLinkAnIdenticalStoredTextDocument() async throws {
        let model = try await fixture(); defer { cleanup(model) }
        let document = try add(model, value: "SYNTHETIC_SAME_CONTENT", format: .text, variable: "NOTES")
        try model.importRows(DotenvParser.parse("API_TOKEN=SYNTHETIC_SAME_CONTENT"), replace: false)
        let snapshot = try #require(model.snapshot)
        let binding = try #require(snapshot.bindings.first { $0.variable == "API_TOKEN" })
        let imported = try #require(snapshot.credentials.first { $0.id == binding.credentialID })
        #expect(imported.id != document.id && imported.currentFormat == .apiKey)
        #expect(imported.currentAPIKey == "SYNTHETIC_SAME_CONTENT")
    }

    @Test func brokerDescribesTypesWithoutReturningStoredContent() async throws {
        let model = try await fixture(); defer { cleanup(model) }
        _ = try add(model, value: "SYNTHETIC_NEVER_MCP_VALUE", format: .apiKey, variable: "API_TOKEN")
        _ = try add(model, value: "{\"token\":\"SYNTHETIC_NEVER_MCP_VALUE\"}", format: .json, variable: "JSON_DOCUMENT")
        _ = try add(model, value: "SYNTHETIC_NEVER_MCP_VALUE", format: .text, variable: "TEXT_DOCUMENT")
        _ = try add(model, value: "{\"TOKEN\":\"SYNTHETIC_NEVER_MCP_VALUE\"}", format: .keyValue, variable: "PAIRS_DOCUMENT")
        try model.addCredential(name: "Synthetic file", value: "", provider: "Other", account: "", note: "", variable: "FILE_PATH", file: SecretFile(name: "fixture.bin", data: Data([0,255])))
        let project = try #require(model.selectedProject), session = "synthetic-format-session"
        let grant = AccessGrant(session: session, projectID: project, environment: .development, connectionID: nil, operation: "metadata", resource: nil)
        model.grants[grant.id] = grant
        let request = BrokerRequest(session: session, project: project.uuidString, environment: .development, tool: "list_connections", arguments: [:])
        let (channel, client) = try RunnerTests().sockets(); defer { close(client) }
        model.receiveBroker(request, channel: channel)
        let bytes = try #require(try SocketTransport.readLine(from: client))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("SYNTHETIC_NEVER_MCP_VALUE"))
        let response = try JSONDecoder().decode(JSONValue.self, from: bytes)
        let variables = try #require(response["result"]?["variables"])
        guard case .array(let entries) = variables else { Issue.record("Expected metadata array"); return }
        let kinds = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, String)? in
            guard let variable = entry["variable"]?.string, let kind = entry["kind"]?.string else { return nil }
            return (variable, kind)
        })
        #expect(kinds == ["API_TOKEN":"value", "JSON_DOCUMENT":"json", "TEXT_DOCUMENT":"text", "PAIRS_DOCUMENT":"keyValue", "FILE_PATH":"file"])
        #expect(entries.allSatisfy { $0["format"]?.string != nil })
        #expect(response["result"]?["note"]?.string?.contains("not passed to commands or API authentication") == true)
    }
}
